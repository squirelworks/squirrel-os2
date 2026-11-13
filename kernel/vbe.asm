; Squirrel-OS/2 — VBE linear framebuffer (2.1)
; Included from pm.asm after vm.asm. Original code.
;
; Sets Bochs/QEMU DISPI linear modes from protected mode (no BIOS call):
; ports 0x01CE/0x01CF on QEMU's standard VGA (PCI 1234:1111). The linear
; framebuffer is BAR0; vm_map_range makes it reachable. Double buffering
; draws to a second LFB page; vbe_flip blits dirty rectangles (or the whole
; page when none / overflow / full-screen) onto the visible page. Clip
; regions and gfx_blit (same-buffer copy rect) live in gfx.asm; blit marks
; dirty when double buffering is armed.
; Mode 13h stays the fallback when DISPI or the VGA BAR is absent.
; See documentation/kernel/graphics.md.

VBE_DIRTY_MAX   equ 8           ; fixed dirty-rect slots before full-page

VBE_INDEX       equ 0x01CE
VBE_DATA        equ 0x01CF
DISPI_ID        equ 0
DISPI_XRES      equ 1
DISPI_YRES      equ 2
DISPI_BPP       equ 3
DISPI_ENABLE    equ 4
DISPI_VWIDTH    equ 6
DISPI_VHEIGHT   equ 7
DISPI_XOFF      equ 8
DISPI_YOFF      equ 9
DISPI_ON        equ 0x01
DISPI_LFB       equ 0x40
DISPI_ID_MAGIC  equ 0xB0C0

PCI_ADDR        equ 0x0CF8
PCI_DATA        equ 0x0CFC
PCI_BAR0        equ 0x10
VBE_VGA_ID      equ 0x11111234      ; QEMU std VGA: device 1111, vendor 1234

; Largest mode we offer: map two pages once so mode switches and double
; buffering (second LFB page + blit present) stay cheap.
VBE_MAX_W       equ 1024
VBE_MAX_H       equ 768
VBE_MAX_BPP     equ 32
VBE_MAX_BYTES   equ (VBE_MAX_W * VBE_MAX_H * (VBE_MAX_BPP / 8))
VBE_MAP_BYTES   equ (VBE_MAX_BYTES * 2)

; CF clear if DISPI answers. Keeps every register.
vbe_present:
    push eax
    push edx
    mov dx, VBE_INDEX
    mov ax, DISPI_ID
    out dx, ax
    mov dx, VBE_DATA
    in ax, dx
    and ax, 0xFFF0
    cmp ax, DISPI_ID_MAGIC
    pop edx
    pop eax
    je .yes
    stc
    ret
.yes:
    clc
    ret

; al = DISPI index -> ax = value (zx in eax). Keeps every other register.
vbe_read:
    push edx
    mov dx, VBE_INDEX
    movzx eax, al
    out dx, ax
    mov dx, VBE_DATA
    in ax, dx
    movzx eax, ax
    pop edx
    ret

; al = DISPI index, bx = value. Clobbers ax, dx.
vbe_write:
    push eax
    push edx
    mov dx, VBE_INDEX
    movzx ax, al
    out dx, ax
    mov dx, VBE_DATA
    mov ax, bx
    out dx, ax
    pop edx
    pop eax
    ret

; EAX = BAR0 of QEMU's standard VGA, or 0. Stores the BAR size in
; vbe_vram (0 if not found). Clobbers ebx, ecx, edx.
; Scans each bus/dev at function 0 first; only probes functions 1–7 when
; function 0 exists (no device → 0xFFFFFFFF), so a missing VGA is not a
; full 65,536-slot walk.
vbe_lfb:
    push esi
    mov dword [vbe_vram], 0
    xor ebx, ebx                ; bus
.bus:
    xor ecx, ecx                ; device
.dev:
    mov eax, ebx
    shl eax, 8
    mov edx, ecx
    shl edx, 3
    or eax, edx                 ; (bus<<8)|(dev<<3)|fn0
    mov edx, eax                ; slot without enable bit
    shl eax, 8
    or eax, 0x80000000
    push edx
    mov dx, PCI_ADDR
    out dx, eax
    mov dx, PCI_DATA
    in eax, dx
    pop edx
    cmp eax, 0xFFFFFFFF
    je .next_dev                ; empty: skip fn 1–7
    cmp eax, VBE_VGA_ID
    je .found
    mov esi, 1                  ; probe other functions on a live device
.fn:
    mov eax, edx
    or eax, esi                 ; same bus/dev, this fn
    shl eax, 8
    or eax, 0x80000000
    push edx
    push esi
    mov dx, PCI_ADDR
    out dx, eax
    mov dx, PCI_DATA
    in eax, dx
    pop esi
    pop edx
    cmp eax, VBE_VGA_ID
    je .found_fn
    inc esi
    cmp esi, 8
    jb .fn
.next_dev:
    inc ecx
    cmp ecx, 32
    jb .dev
    inc ebx
    cmp ebx, 256
    jb .bus
    pop esi
    xor eax, eax
    ret
.found_fn:
    or edx, esi
.found:
    mov eax, edx
    shl eax, 8
    or eax, 0x80000000 | PCI_BAR0
    mov esi, eax                ; PCI config address of BAR0
    mov dx, PCI_ADDR
    out dx, eax
    mov dx, PCI_DATA
    in eax, dx
    push eax                    ; original BAR (flags + address)
    mov eax, esi
    mov dx, PCI_ADDR
    out dx, eax
    mov eax, 0xFFFFFFFF         ; size probe
    mov dx, PCI_DATA
    out dx, eax
    mov eax, esi
    mov dx, PCI_ADDR
    out dx, eax
    mov dx, PCI_DATA
    in eax, dx
    and eax, 0xFFFFFFF0         ; drop flag bits
    not eax
    inc eax                     ; BAR decode size in bytes
    mov [vbe_vram], eax
    mov eax, esi
    mov dx, PCI_ADDR
    out dx, eax
    pop eax                     ; restore original BAR value
    mov dx, PCI_DATA
    out dx, eax
    and eax, 0xFFFFFFF0         ; drop the flag bits → LFB base
    pop esi
    ret

; Clear the dirty-rectangle set (empty = next flip does a full page).
; Keeps registers.
vbe_dirty_clear:
    push eax
    mov byte [vbe_dirty_n], 0
    mov byte [vbe_dirty_full], 0
    pop eax
    ret

; Clear double-buffer state (single page at LFB base). Keeps registers.
vbe_dbl_clear:
    push eax
    mov byte [vbe_dbl], 0
    mov eax, [vbe_fb]
    mov [vbe_front], eax
    call vbe_dirty_clear
    pop eax
    ret

; Turn DISPI off. Keeps registers.
vbe_disable:
    push eax
    push ebx
    push edx
    xor ebx, ebx
    mov al, DISPI_ENABLE
    call vbe_write
    mov byte [gfx_vbe], 0
    mov byte [vbe_ready], 0     ; next enter must save the text again
    call vbe_dbl_clear
    pop edx
    pop ebx
    pop eax
    ret

; After a failed enter that already saved the text screen: leave DISPI,
; reload text registers, and restore the screen/font (frees the pages).
; Clears vbe_ready. Clobbers as gfx_load_regs / gfx_restore.
vbe_abort_saved:
    xor ebx, ebx
    mov al, DISPI_ENABLE
    call vbe_write
    mov byte [gfx_vbe], 0
    mov byte [vbe_ready], 0
    call vbe_dbl_clear
    mov esi, gfx_regs_text
    call gfx_load_regs
    call gfx_restore
    ret

; One-time prepare: DISPI present, BAR0 found, max LFB mapped, text saved.
; CF set on failure (mode unchanged). Idempotent while vbe_ready is 1.
vbe_setup:
    pushad
    cmp byte [vbe_ready], 0
    jne .ok
    call vbe_present
    jc .fail
    call vbe_lfb
    test eax, eax
    jz .fail
    mov [vbe_fb], eax
    cmp dword [vbe_vram], 0
    je .fail
    mov ecx, VBE_MAP_BYTES      ; two pages for double buffering
    cmp ecx, [vbe_vram]
    jbe .map
    mov ecx, [vbe_vram]         ; smaller adapter: map only what fits
.map:
    call vm_map_range
    jc .fail
    call gfx_save               ; DISPI enable clears VGA memory
    jc .fail
    call vbe_dbl_clear
    mov byte [vbe_ready], 1
.ok:
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; eax = width, ebx = height, cl = bpp (8, 16 or 32).
; Programs DISPI for that linear mode. Calls vbe_setup if needed.
; CF set if setup fails or the adapter refuses the mode; text restored then.
vbe_mode:
    pushad
    cmp cl, 8
    je .bpp_ok
    cmp cl, 16
    je .bpp_ok
    cmp cl, 32
    jne .bad
.bpp_ok:
    mov [vbe_req_w], eax
    mov [vbe_req_h], ebx
    mov [vbe_req_bpp], cl
    call vbe_setup
    jc .fail
    xor ebx, ebx
    mov al, DISPI_ENABLE
    call vbe_write
    mov bx, DISPI_ID_MAGIC
    mov al, DISPI_ID
    call vbe_write
    mov ebx, [vbe_req_w]
    mov al, DISPI_XRES
    call vbe_write
    mov al, DISPI_VWIDTH
    call vbe_write
    mov ebx, [vbe_req_h]
    mov al, DISPI_YRES
    call vbe_write
    mov al, DISPI_VHEIGHT
    call vbe_write
    movzx ebx, byte [vbe_req_bpp]
    mov al, DISPI_BPP
    call vbe_write
    xor ebx, ebx
    mov al, DISPI_XOFF
    call vbe_write
    mov al, DISPI_YOFF
    call vbe_write
    mov bx, DISPI_ON | DISPI_LFB
    mov al, DISPI_ENABLE
    call vbe_write
    ; Confirm the adapter accepted the mode before claiming success.
    mov al, DISPI_XRES
    call vbe_read
    cmp eax, [vbe_req_w]
    jne .refuse
    mov al, DISPI_YRES
    call vbe_read
    cmp eax, [vbe_req_h]
    jne .refuse
    mov al, DISPI_BPP
    call vbe_read
    movzx ebx, byte [vbe_req_bpp]
    cmp eax, ebx
    jne .refuse
    mov eax, [vbe_fb]
    mov [gfx_base], eax
    mov [vbe_front], eax
    mov eax, [vbe_req_w]
    mov [gfx_width], eax
    mov ebx, [vbe_req_h]
    mov [gfx_height], ebx
    movzx ecx, byte [vbe_req_bpp]
    mov [gfx_bpp], cl
    shr ecx, 3                  ; bytes per pixel
    imul eax, ecx               ; pitch
    mov [gfx_pitch], eax
    mov byte [gfx_vbe], 1
    mov byte [vbe_dbl], 0
    call vbe_dirty_clear
    call gfx_resetclip
    popad
    clc
    ret
.refuse:
    call vbe_abort_saved
    mov byte [vbe_ready], 0
.bad:
.fail:
    popad
    stc
    ret

; Enter 640×480×32 (kept for callers). CF set on failure.
gfx_vbe_640_32:
    mov eax, 640
    mov ebx, 480
    mov cl, 32
    jmp vbe_mode

; Double buffering on the current VBE mode (2.1-dblbuf). Uses the second
; LFB page (already mapped) as a back buffer; vbe_flip blits it onto the
; visible page. Drawing (gfx_base) targets the back once armed. Copies the
; front onto the back so the first frame starts from the visible image.
; CF set if not in a VBE mode, or if two pages do not fit in VRAM.
vbe_dblbuf:
    pushad
    cmp byte [gfx_vbe], 0
    je .fail
    cmp byte [vbe_dbl], 0
    jne .ok                     ; already armed
    mov ebx, [gfx_pitch]
    imul ebx, [gfx_height]      ; bytes per page
    mov ecx, ebx
    add ecx, ebx                ; two pages
    cmp ecx, [vbe_vram]
    ja .fail                    ; smaller adapter: refuse double buffering
    mov eax, [vbe_fb]
    mov [vbe_front], eax        ; visible page (DISPI shows this)
    lea edi, [eax+ebx]          ; back page
    mov esi, eax
    mov ecx, ebx
    shr ecx, 2                  ; dwords
    rep movsd                   ; back starts as a copy of the front
    lea eax, [eax+ebx]
    mov [gfx_base], eax         ; draw on the hidden page in VRAM
    mov byte [vbe_dbl], 1
    call vbe_dirty_clear        ; first flip without marks = full page
.ok:
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; Mark a rectangle dirty for the next vbe_flip (2.1-dirty).
; eax = x, ebx = y, ecx = width, edx = height (signed; clipped to the screen).
; No effect when double buffering is off. Overflow of the fixed slot list, or
; a rect that covers the whole screen, forces a full-page flip next time.
vbe_dirty:
    pushad
    cmp byte [vbe_dbl], 0
    je .done
    cmp byte [vbe_dirty_full], 0
    jne .done
    ; Reject non-positive size before clip (ecx/edx are signed widths).
    test ecx, ecx
    jle .done
    test edx, edx
    jle .done
    ; Clip left/top: if x < 0, shrink width and set x = 0.
    test eax, eax
    jns .x_ok
    add ecx, eax                ; w += x (x is negative)
    xor eax, eax
    test ecx, ecx
    jle .done
.x_ok:
    test ebx, ebx
    jns .y_ok
    add edx, ebx
    xor ebx, ebx
    test edx, edx
    jle .done
.y_ok:
    cmp eax, [gfx_width]
    jae .done
    cmp ebx, [gfx_height]
    jae .done
    ; Clip right/bottom against the live mode size.
    mov esi, eax
    add esi, ecx
    cmp esi, [gfx_width]
    jbe .w_ok
    mov ecx, [gfx_width]
    sub ecx, eax
.w_ok:
    mov esi, ebx
    add esi, edx
    cmp esi, [gfx_height]
    jbe .h_ok
    mov edx, [gfx_height]
    sub edx, ebx
.h_ok:
    test ecx, ecx
    jle .done
    test edx, edx
    jle .done
    ; Whole-screen rect → full flip (cheaper than listing it).
    cmp eax, 0
    jne .store
    cmp ebx, 0
    jne .store
    cmp ecx, [gfx_width]
    jne .store
    cmp edx, [gfx_height]
    jne .store
    mov byte [vbe_dirty_full], 1
    jmp .done
.store:
    movzx esi, byte [vbe_dirty_n]
    cmp esi, VBE_DIRTY_MAX
    jae .overflow
    mov [vbe_dx+esi*4], eax
    mov [vbe_dy+esi*4], ebx
    mov [vbe_dw+esi*4], ecx
    mov [vbe_dh+esi*4], edx
    inc byte [vbe_dirty_n]
    jmp .done
.overflow:
    mov byte [vbe_dirty_full], 1
.done:
    popad
    ret

; Copy one clipped rect from the back buffer onto the front.
; eax = x, ebx = y, ecx = width, edx = height. Clobbers as pushad frame.
vbe_blit_rect:
    pushad
    movzx ebp, byte [gfx_bpp]
    shr ebp, 3                  ; bytes per pixel
    imul ecx, ebp               ; bytes per row of the rect
    mov esi, [gfx_base]
    mov edi, [vbe_front]
    imul ebx, [gfx_pitch]
    add esi, ebx
    add edi, ebx
    imul eax, ebp               ; x offset in bytes
    add esi, eax
    add edi, eax
    mov ebx, [gfx_pitch]
.row:
    push ecx
    push esi
    push edi
    mov eax, ecx
    shr ecx, 2
    rep movsd
    mov ecx, eax
    and ecx, 3
    rep movsb
    pop edi
    pop esi
    pop ecx
    add esi, ebx
    add edi, ebx
    dec edx
    jnz .row
    popad
    ret

; Present the back buffer onto the visible front page.
; With no dirty marks, an overflow, or a full-screen mark: copy the whole
; page (same as 2.1-dblbuf). Otherwise copy only the dirty rectangles, then
; clear the dirty set. CF set if double buffering is off. gfx_base stays
; on the back.
vbe_flip:
    pushad
    cmp byte [vbe_dbl], 0
    je .fail
    cmp byte [vbe_dirty_full], 0
    jne .full
    cmp byte [vbe_dirty_n], 0
    je .full                    ; unset → full page (callers that skip marks)
    xor esi, esi
.rects:
    movzx eax, byte [vbe_dirty_n]
    cmp esi, eax
    jae .cleared
    mov eax, [vbe_dx+esi*4]
    mov ebx, [vbe_dy+esi*4]
    mov ecx, [vbe_dw+esi*4]
    mov edx, [vbe_dh+esi*4]
    push esi
    call vbe_blit_rect
    pop esi
    inc esi
    jmp .rects
.full:
    mov esi, [gfx_base]
    mov edi, [vbe_front]
    mov ecx, [gfx_pitch]
    imul ecx, [gfx_height]
    shr ecx, 2                  ; dwords
    rep movsd
.cleared:
    call vbe_dirty_clear
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; Like gfx_getpixel but reads the visible (front) page while double
; buffering. eax = x, ebx = y -> cl = colour (0 off screen).
vbe_front_getpixel:
    push eax
    push ebx
    push edx
    push esi
    xor ecx, ecx
    cmp eax, [gfx_width]
    jae .done
    cmp ebx, [gfx_height]
    jae .done
    mov esi, [vbe_front]
    imul ebx, [gfx_pitch]
    add esi, ebx
    cmp byte [gfx_bpp], 32
    je .b32
    cmp byte [gfx_bpp], 16
    je .b16
    mov cl, [esi+eax]
    jmp .done
.b16:
    mov cx, [esi+eax*2]
    movzx ecx, cl
    jmp .done
.b32:
    mov ecx, [esi+eax*4]
    movzx ecx, cl
.done:
    pop esi
    pop edx
    pop ebx
    pop eax
    ret

; vbetest: walk 640×480 / 800×600 / 1024×768 at 8, 16 and 32 bpp. Each mode
; gets a pixel write/read, a double-buffer self-check, a dirty-rectangle flip,
; then a blit+clip self-check. If VBE setup fails, fall back to mode 13h once
; (clip+blit still run; no double buffering there).
VBET_X equ 100
VBET_Y equ 100
VBET_DBL_COLOUR equ 0x3C        ; distinct from the single-buffer colours
; Dirty-rect probe points (inside every offered mode; away from VBET_X/Y).
VBET_D1_X equ 40
VBET_D1_Y equ 40
VBET_D1_COLOUR equ 0x55
VBET_D2_X equ 200
VBET_D2_Y equ 80
VBET_D2_COLOUR equ 0x66
VBET_OUT_X equ 150
VBET_OUT_Y equ 150
VBET_OUT_COLOUR equ 0x77        ; drawn on the back but not marked dirty
; Blit+clip probes (2.1-blit-clip).
VBET_BG_COLOUR equ 0x11
VBET_FILL_COLOUR equ 0x22
VBET_SRC_COLOUR equ 0x44

cmd_vbetest_run:
    mov byte [vbet_ok], 1
    mov byte [vbet_fb], 0       ; 0 = VBE path, 1 = 13h fallback
    call vbe_setup
    jc .fallback
    mov esi, vbe_modes
.walk:
    mov eax, [esi]
    test eax, eax
    jz .done_modes
    mov ebx, [esi+4]
    mov cl, [esi+8]
    push esi
    call vbe_mode
    pop esi
    jc .mode_fail
    mov cl, 0x2A
    call .one
    mov cl, 0x15
    call .one
    call .dbl
    call .dirty
    call .blit_clip
    add esi, 12
    jmp .walk
.mode_fail:
    mov byte [vbet_ok], 0
.done_modes:
    call gfx_text
    mov byte [vbe_ready], 0
    cmp byte [vbet_ok], 1
    jne .fail
    mov esi, vbet_pass
    jmp .say
.fallback:
    mov byte [vbet_fb], 1
    call gfx_mode13
    jc .fail_mode
    mov cl, 0x2A
    call .one
    mov cl, 0x15
    call .one
    call .blit_clip
    call gfx_text
    cmp byte [vbet_ok], 1
    jne .fail
    mov esi, vbet_13h
    jmp .say
.fail_mode:
    mov esi, vbet_fail
    jmp .say
.fail:
    call gfx_text
    mov byte [vbe_ready], 0
    mov esi, vbet_fail
.say:
    jmp puts
.one:
    mov dl, cl
    mov eax, VBET_X
    mov ebx, VBET_Y
    call gfx_putpixel
    call gfx_getpixel
    cmp cl, dl
    je .same
    mov byte [vbet_ok], 0
.same:
    ret
; Arm double buffering (back starts as a copy of the front), confirm the
; back already has the last single-buffer colour (0x15), draw off-screen,
; confirm the front is still 0x15, flip, and read the new front pixel.
.dbl:
    call vbe_dblbuf
    jc .dbl_bad
    mov eax, VBET_X
    mov ebx, VBET_Y
    call gfx_getpixel           ; back copied from front on arm
    cmp cl, 0x15
    jne .dbl_bad
    call vbe_front_getpixel
    cmp cl, 0x15
    jne .dbl_bad
    mov cl, VBET_DBL_COLOUR
    call gfx_putpixel
    call gfx_getpixel
    cmp cl, VBET_DBL_COLOUR
    jne .dbl_bad
    call vbe_front_getpixel
    cmp cl, 0x15                ; front still unchanged
    jne .dbl_bad
    call vbe_flip
    jc .dbl_bad
    call vbe_front_getpixel
    cmp cl, VBET_DBL_COLOUR
    jne .dbl_bad
    ret
.dbl_bad:
    mov byte [vbet_ok], 0
    ret
; Dirty rectangles (2.1-dirty): draw three pixels on the back, mark only two,
; flip, and confirm the front matches the marked ones while the third stays
; at its pre-flip front colour. Relies on dblbuf already armed from .dbl.
.dirty:
    cmp byte [vbet_ok], 0
    je .dirty_bad
    cmp byte [vbe_dbl], 0
    je .dirty_bad
    ; Remember the front colour at the unmarked probe (must survive flip).
    mov eax, VBET_OUT_X
    mov ebx, VBET_OUT_Y
    call vbe_front_getpixel
    mov [vbet_out_front], cl
    ; Two dirty 1×1 rects.
    mov eax, VBET_D1_X
    mov ebx, VBET_D1_Y
    mov cl, VBET_D1_COLOUR
    call gfx_putpixel
    mov eax, VBET_D1_X
    mov ebx, VBET_D1_Y
    mov ecx, 1
    mov edx, 1
    call vbe_dirty
    mov eax, VBET_D2_X
    mov ebx, VBET_D2_Y
    mov cl, VBET_D2_COLOUR
    call gfx_putpixel
    mov eax, VBET_D2_X
    mov ebx, VBET_D2_Y
    mov ecx, 1
    mov edx, 1
    call vbe_dirty
    ; Third draw on the back, not marked.
    mov eax, VBET_OUT_X
    mov ebx, VBET_OUT_Y
    mov cl, VBET_OUT_COLOUR
    call gfx_putpixel
    call gfx_getpixel
    cmp cl, VBET_OUT_COLOUR
    jne .dirty_bad
    call vbe_front_getpixel
    cmp cl, [vbet_out_front]    ; front still old at the unmarked point
    jne .dirty_bad
    call vbe_flip
    jc .dirty_bad
    mov eax, VBET_D1_X
    mov ebx, VBET_D1_Y
    call vbe_front_getpixel
    cmp cl, VBET_D1_COLOUR
    jne .dirty_bad
    mov eax, VBET_D2_X
    mov ebx, VBET_D2_Y
    call vbe_front_getpixel
    cmp cl, VBET_D2_COLOUR
    jne .dirty_bad
    mov eax, VBET_OUT_X
    mov ebx, VBET_OUT_Y
    call vbe_front_getpixel
    cmp cl, [vbet_out_front]    ; unmarked region not copied
    jne .dirty_bad
    ; Back still has the unmarked colour (flip does not touch the back).
    call gfx_getpixel
    cmp cl, VBET_OUT_COLOUR
    jne .dirty_bad
    ret
.dirty_bad:
    mov byte [vbet_ok], 0
    ret
; Blit + clip (2.1-blit-clip). Preserves ESI for the mode walk.
.blit_clip:
    cmp byte [vbet_ok], 0
    je .blit_bad
    call gfx_resetclip
    mov byte [gfx_colour], VBET_BG_COLOUR
    mov eax, 50
    mov ebx, 50
    mov ecx, 40
    mov edx, 40
    call gfx_fillrect
    mov eax, 60
    mov ebx, 60
    mov ecx, 20
    mov edx, 20
    call gfx_setclip
    mov byte [gfx_colour], VBET_FILL_COLOUR
    mov eax, 50
    mov ebx, 50
    mov ecx, 40
    mov edx, 40
    call gfx_fillrect
    mov eax, 70
    mov ebx, 70
    call gfx_getpixel
    cmp cl, VBET_FILL_COLOUR
    jne .blit_bad
    mov eax, 55
    mov ebx, 55
    call gfx_getpixel
    cmp cl, VBET_BG_COLOUR
    jne .blit_bad
    call gfx_resetclip
    mov byte [gfx_colour], VBET_SRC_COLOUR
    mov eax, 300
    mov ebx, 50
    mov ecx, 20
    mov edx, 20
    call gfx_fillrect
    mov byte [gfx_colour], 0
    mov eax, 100
    mov ebx, 50
    mov ecx, 20
    mov edx, 20
    call gfx_fillrect
    mov eax, 105
    mov ebx, 55
    mov ecx, 10
    mov edx, 10
    call gfx_setclip
    mov dword [gfx_blit_sx], 300
    mov dword [gfx_blit_sy], 50
    mov eax, 100
    mov ebx, 50
    mov ecx, 20
    mov edx, 20
    call gfx_blit
    mov eax, 110
    mov ebx, 60
    call gfx_getpixel
    cmp cl, VBET_SRC_COLOUR
    jne .blit_bad
    mov eax, 102
    mov ebx, 52
    call gfx_getpixel
    test cl, cl
    jnz .blit_bad
    cmp byte [vbe_dbl], 0
    je .blit_ok
    call vbe_flip
    jc .blit_bad
    mov eax, 110
    mov ebx, 60
    call vbe_front_getpixel
    cmp cl, VBET_SRC_COLOUR
    jne .blit_bad
.blit_ok:
    call gfx_resetclip
    ret
.blit_bad:
    mov byte [vbet_ok], 0
    call gfx_resetclip
    ret

; Each record: width dd, height dd, bpp dd (low byte); 0 width ends the list.
align 4
vbe_modes:
    dd 640, 480, 8
    dd 640, 480, 16
    dd 640, 480, 32
    dd 800, 600, 8
    dd 800, 600, 16
    dd 800, 600, 32
    dd 1024, 768, 8
    dd 1024, 768, 16
    dd 1024, 768, 32
    dd 0

vbet_ok db 0
vbet_fb db 0
vbet_out_front db 0
vbe_ready db 0
vbe_dbl db 0
vbe_dirty_n db 0                ; count of stored rects (0 = unset)
vbe_dirty_full db 0             ; 1 → next flip copies the whole page
vbet_pass db 'vbe: PASS', 10, 0
vbet_13h  db 'vbe: 13h', 10, 0
vbet_fail db 'vbe: FAIL', 10, 0

align 4
vbe_fb dd 0
vbe_front dd 0
vbe_vram dd 0                   ; PCI BAR0 decode size (bytes)
vbe_req_w dd 0
vbe_req_h dd 0
vbe_req_bpp db 0
    db 0, 0, 0
vbe_dx times VBE_DIRTY_MAX dd 0
vbe_dy times VBE_DIRTY_MAX dd 0
vbe_dw times VBE_DIRTY_MAX dd 0
vbe_dh times VBE_DIRTY_MAX dd 0
