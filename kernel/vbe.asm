; Squirrel-OS/2 — VBE linear framebuffer (2.1)
; Included from pm.asm after vm.asm. Original code.
;
; Sets Bochs/QEMU DISPI linear modes from protected mode (no BIOS call):
; ports 0x01CE/0x01CF on QEMU's standard VGA (PCI 1234:1111). The linear
; framebuffer is BAR0; vm_map_range makes it reachable. Double buffering
; draws to a second LFB page and blits it onto the visible page on flip.
; Mode 13h stays the fallback when DISPI or the VGA BAR is absent.
; See documentation/kernel/graphics.md.

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

; Clear double-buffer state (single page at LFB base). Keeps registers.
vbe_dbl_clear:
    push eax
    mov byte [vbe_dbl], 0
    mov eax, [vbe_fb]
    mov [vbe_front], eax
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
.ok:
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; Present the back buffer: copy it onto the visible front page.
; CF set if double buffering is off. gfx_base stays on the back.
vbe_flip:
    pushad
    cmp byte [vbe_dbl], 0
    je .fail
    mov esi, [gfx_base]
    mov edi, [vbe_front]
    mov ecx, [gfx_pitch]
    imul ecx, [gfx_height]
    shr ecx, 2                  ; dwords
    rep movsd
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
; gets a pixel write/read, then a double-buffer self-check (draw on the back,
; front unchanged, flip, front matches). If VBE setup fails, fall back to
; mode 13h once (no double buffering there).
VBET_X equ 100
VBET_Y equ 100
VBET_DBL_COLOUR equ 0x3C        ; distinct from the single-buffer colours

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
vbe_ready db 0
vbe_dbl db 0
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
