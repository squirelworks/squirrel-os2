; Squirrel-OS/2 — VBE linear framebuffer (2.1)
; Included from pm.asm after vm.asm. Original code.
;
; Sets a Bochs/QEMU DISPI linear mode from protected mode (no BIOS call):
; ports 0x01CE/0x01CF on QEMU's standard VGA (PCI 1234:1111). The linear
; framebuffer is BAR0; vm_map_range makes it reachable. Mode 13h stays the
; fallback when DISPI or the VGA BAR is absent.
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

VBE_W           equ 640
VBE_H           equ 480
VBE_BPP         equ 32
VBE_PITCH       equ (VBE_W * (VBE_BPP / 8))
VBE_BYTES       equ (VBE_PITCH * VBE_H)

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

; al = DISPI index -> ax = value. Clobbers dx.
vbe_read:
    push edx
    mov dx, VBE_INDEX
    movzx ax, al
    out dx, ax
    mov dx, VBE_DATA
    in ax, dx
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

; EAX = BAR0 of QEMU's standard VGA, or 0. Clobbers ebx, ecx, edx.
vbe_lfb:
    xor ecx, ecx                ; bus:dev:fn as (bus<<8)|(dev<<3)|fn
.scan:
    mov eax, ecx
    shl eax, 8
    or eax, 0x80000000          ; enable bit, offset 0
    mov dx, PCI_ADDR
    out dx, eax
    mov dx, PCI_DATA
    in eax, dx
    cmp eax, VBE_VGA_ID
    je .found
    inc ecx
    cmp ecx, 256 * 32 * 8
    jb .scan
    xor eax, eax
    ret
.found:
    mov eax, ecx
    shl eax, 8
    or eax, 0x80000000 | PCI_BAR0
    mov dx, PCI_ADDR
    out dx, eax
    mov dx, PCI_DATA
    in eax, dx
    and eax, 0xFFFFFFF0         ; drop the flag bits
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
    pop edx
    pop ebx
    pop eax
    ret

; Enter 640×480×32 linear mode. CF set on failure (DISPI missing, no BAR,
; or map failed); then the mode is unchanged. On success gfx_* describe
; the LFB and gfx_vbe is 1.
gfx_vbe_640_32:
    pushad
    call vbe_present
    jc .fail
    call vbe_lfb
    test eax, eax
    jz .fail
    mov [vbe_fb], eax
    mov ecx, VBE_BYTES
    call vm_map_range
    jc .fail
    xor ebx, ebx
    mov al, DISPI_ENABLE
    call vbe_write
    mov bx, DISPI_ID_MAGIC
    mov al, DISPI_ID
    call vbe_write
    mov bx, VBE_W
    mov al, DISPI_XRES
    call vbe_write
    mov al, DISPI_VWIDTH
    call vbe_write
    mov bx, VBE_H
    mov al, DISPI_YRES
    call vbe_write
    mov al, DISPI_VHEIGHT
    call vbe_write
    mov bx, VBE_BPP
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
    mov eax, [vbe_fb]
    mov [gfx_base], eax
    mov dword [gfx_width], VBE_W
    mov dword [gfx_height], VBE_H
    mov dword [gfx_pitch], VBE_PITCH
    mov byte [gfx_bpp], VBE_BPP
    mov byte [gfx_vbe], 1
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; vbetest: prefer VBE 640×480×32; fall back to mode 13h. Write two colours
; to one pixel, read each back, return to text, print vbe: PASS or vbe: 13h
; (or vbe: FAIL).
VBET_X equ 100
VBET_Y equ 100

cmd_vbetest_run:
    mov byte [vbet_ok], 1
    mov byte [vbet_fb], 0       ; 0 = VBE path, 1 = 13h fallback
    call gfx_vbe_640_32
    jnc .draw
    mov byte [vbet_fb], 1
    call gfx_mode13
    jc .fail_mode
.draw:
    mov cl, 0x2A
    call .one
    mov cl, 0x15
    call .one
    call gfx_text
    cmp byte [vbet_ok], 1
    jne .fail
    mov esi, vbet_pass
    cmp byte [vbet_fb], 0
    je .say
    mov esi, vbet_13h
    jmp .say
.fail_mode:
    mov esi, vbet_fail
    jmp .say
.fail:
    call gfx_text
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

vbet_ok db 0
vbet_fb db 0
vbet_pass db 'vbe: PASS', 10, 0
vbet_13h  db 'vbe: 13h', 10, 0
vbet_fail db 'vbe: FAIL', 10, 0

align 4
vbe_fb dd 0
