; Squirrel-OS/2 — PCI helpers for the H.x drivers (OS2-HW)
; Included from pm.asm (high image). Original code.
;
; Configuration mechanism #1 (ports 0xCF8/0xCFC), the access every PC
; chipset and QEMU's pc and q35 machines have. A "config address" below is
; 0x80000000 | bus<<16 | device<<11 | function<<8, register offset 0.
; Everything here is plain 32-bit code with no kernel state, so a 64-bit
; kernel can take it over unchanged apart from the register widths.
; See documentation/kernel/hardware.md.

PCI_CFG_ADDR    equ 0x0CF8
PCI_CFG_DATA    equ 0x0CFC
PCI_REG_ID      equ 0x00
PCI_REG_CMD     equ 0x04
PCI_REG_CLASS   equ 0x08            ; revision 7:0, prog-if 15:8, subclass 23:16, class 31:24
PCI_REG_HDR     equ 0x0C            ; header type in bits 23:16
PCI_REG_BAR0    equ 0x10
PCI_CMD_MEM     equ 0x02
PCI_CMD_MASTER  equ 0x04
PCI_CMD_NOINT   equ 0x400           ; INTx disabled: these drivers poll

; eax = config address, edx = register -> eax = dword. Keeps the rest.
pci_read:
    push edx
    and edx, 0xFC
    or eax, edx
    mov dx, PCI_CFG_ADDR
    out dx, eax
    mov dx, PCI_CFG_DATA
    in eax, dx
    pop edx
    ret

; eax = config address, edx = register, ecx = value. Keeps registers.
pci_write:
    push eax
    push edx
    and edx, 0xFC
    or eax, edx
    mov dx, PCI_CFG_ADDR
    out dx, eax
    mov dx, PCI_CFG_DATA
    mov eax, ecx
    out dx, eax
    pop edx
    pop eax
    ret

; Finds a PCI function by class code.
; eax = class<<16 | subclass<<8 | prog-if, ecx = which match (0 = first)
; -> eax = config address, CF clear; or CF set if there is none.
pci_find_class:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov edi, eax                    ; wanted class triple
    mov esi, ecx                    ; matches still to skip
    mov ebx, 0x80000000             ; bus 0, device 0, function 0
.slot:
    mov eax, ebx
    xor edx, edx
    call pci_read
    cmp ax, 0xFFFF
    je .skipdev                     ; nothing here: skip the other functions
.func:
    mov eax, ebx
    mov edx, PCI_REG_CLASS
    call pci_read
    shr eax, 8
    cmp eax, edi
    jne .nextfn
    test esi, esi
    jz .found
    dec esi
.nextfn:
    test ebx, 0x700                 ; function 0: only go on if multi-function
    jnz .fn1
    mov eax, ebx
    mov edx, PCI_REG_HDR
    call pci_read
    test eax, 0x800000
    jz .skipdev
.fn1:
    add ebx, 0x100
    test ebx, 0x700
    jz .nextdev                     ; past function 7
    mov eax, ebx
    xor edx, edx
    call pci_read
    cmp ax, 0xFFFF
    je .fn1
    jmp .func
.skipdev:
    and ebx, ~0x700
    add ebx, 0x800
    jmp .chk
.nextdev:
.chk:
    cmp ebx, 0x81000000             ; past bus 255
    jb .slot
    stc
    jmp .out
.found:
    mov eax, ebx
    clc
.out:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; eax = config address, edx = BAR register (0x10, 0x14, ...)
; -> eax = memory base (flag bits dropped), CF set if it is an I/O BAR,
; zero, or a 64-bit BAR above 4 GB (out of a 32-bit kernel's reach).
pci_bar_mem:
    push ebx
    push ecx
    mov ebx, eax
    call pci_read
    test al, 1
    jnz .bad                        ; I/O space
    mov ecx, eax
    and ecx, 6
    cmp ecx, 4                      ; 64-bit BAR: the high half must be 0
    jne .lo
    push eax
    mov eax, ebx
    add edx, 4
    call pci_read
    sub edx, 4
    test eax, eax
    pop eax
    jnz .bad
.lo:
    and eax, 0xFFFFFFF0
    jz .bad
    pop ecx
    pop ebx
    clc
    ret
.bad:
    pop ecx
    pop ebx
    stc
    ret

; eax = config address: memory decoding and bus mastering on, INTx off
pci_enable:
    push ecx
    push edx
    push eax
    mov edx, PCI_REG_CMD
    call pci_read
    mov ecx, eax
    and ecx, 0xFFFF
    or ecx, PCI_CMD_MEM|PCI_CMD_MASTER|PCI_CMD_NOINT
    pop eax
    call pci_write
    pop edx
    pop ecx
    ret

; Busy-waits about ecx microseconds (one ISA bus cycle per microsecond on
; real hardware; much faster under QEMU, where nothing needs the time).
; Usable before the PIT runs and with interrupts off. Keeps registers.
hw_udelay:
    push eax
    push ecx
.l:
    out 0x80, al
    loop .l
    pop ecx
    pop eax
    ret

; eax = MMIO base, ecx = length: maps it into the kernel page directory
; (vm_map_range). Must run before the first program's address space is
; made, since address spaces copy the kernel directory. CF on failure.
hw_map_mmio:
    jmp vm_map_range
