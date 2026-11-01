; Squirrel-OS/2 boot sector
; Loads the 96 KB kernel image (sectors 1..192) to 0x8000 and jumps to it.
; Hard disks use the BIOS extended read (int 0x13, AH=0x42), in three
; 64-sector reads because some firmware caps one read at 127 sectors.
; Floppies, and disks whose firmware refuses AH=0x42, are read one
; sector at a time by cylinder/head/sector (AH=0x02) using the geometry
; from AH=0x08 (0.9.3).
; Original code.

KERNEL_SECTORS equ 64           ; per extended read
KERNEL_READS   equ 3            ; 192 sectors in all (96 KB, up to 0x1FFFF)

BITS 16
ORG 0x7C00
start:
    cli
    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00
    sti
    ; dl holds the boot drive from the firmware; keep it for later reads
    mov [boot_drive], dl
    test dl, 0x80
    jz chs_load                 ; a floppy: no extended reads
    mov si, dap
    mov ah, 0x42
    int 0x13
    jc chs_load
    ; second: sectors 65..128 to 0x1000:0x0000 (0x10000)
    mov word [dap+4], 0x0000
    mov word [dap+6], 0x1000
    mov dword [dap+8], 1+KERNEL_SECTORS
    mov dl, [boot_drive]
    mov si, dap
    mov ah, 0x42
    int 0x13
    jc chs_load
    ; third: sectors 129..192 to 0x1800:0x0000 (0x18000)
    mov word [dap+6], 0x1800
    mov dword [dap+8], 1+2*KERNEL_SECTORS
    mov dl, [boot_drive]
    mov si, dap
    mov ah, 0x42
    int 0x13
    jc chs_load
    jmp 0x0000:0x8000

; One sector at a time, LBA 1..192, to 0x0800:0 onwards.
chs_load:
    mov dl, [boot_drive]
    mov ah, 0x08                ; geometry
    xor di, di
    mov es, di
    int 0x13
    jc fail
    and cx, 0x3F                ; sectors per track
    jz fail
    mov [spt], cx
    movzx ax, dh
    inc ax
    mov [heads], ax
    mov ax, 0x0800
    mov es, ax
    mov word [lba], 1
.next:
    mov byte [tries], 3
.again:
    mov ax, [lba]
    xor dx, dx
    div word [spt]              ; ax = track, dx = sector - 1
    mov cl, dl
    inc cl
    xor dx, dx
    div word [heads]            ; ax = cylinder, dx = head
    mov ch, al
    shl ah, 6                   ; cylinder bits 8-9 go in cl bits 6-7
    or cl, ah
    mov dh, dl
    mov dl, [boot_drive]
    xor bx, bx
    mov ax, 0x0201
    int 0x13
    jnc .ok
    xor ah, ah                  ; reset the drive and try again
    mov dl, [boot_drive]
    int 0x13
    dec byte [tries]
    jnz .again
    jmp fail
.ok:
    mov ax, es
    add ax, 0x20                ; 512 bytes further
    mov es, ax
    inc word [lba]
    cmp word [lba], 1+KERNEL_READS*KERNEL_SECTORS
    jb .next
    jmp 0x0000:0x8000

fail:
    mov si, m_fail
.p:
    lodsb
    test al, al
    jz .h
    mov ah, 0x0E
    xor bx, bx
    int 0x10
    jmp .p
.h:
    hlt
    jmp .h

m_fail db 'Squirrel-OS/2: cannot read the kernel from the boot disk', 0
boot_drive db 0
tries db 0
spt dw 0
heads dw 0
lba dw 0
dap:
    db 0x10, 0                  ; packet size, reserved
    dw KERNEL_SECTORS
    dw 0x8000, 0x0000           ; offset, segment
    dq 1                        ; starting LBA

%if $-$$ > 440
%error the boot code must end before the disk signature and partition table (byte 440)
%endif
times 510-($-$$) db 0
dw 0xAA55
