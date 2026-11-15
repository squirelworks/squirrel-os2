; Squirrel-OS/2 — PCI configuration space for the audio drivers (3.0)
; Included from pm.asm. Original code.
;
; Configuration mechanism #1 (ports 0xCF8 / 0xCFC). A device is named by
; its configuration address: 0x80000000 | bus << 16 | device << 11 |
; function << 8. See documentation/kernel/audio.md.

APCI_ADDR   equ 0x0CF8
APCI_DATA   equ 0x0CFC
APCI_CMD    equ 0x04                ; command register
APCI_CLASS  equ 0x08                ; revision, prog-if, subclass, class
APCI_BAR0   equ 0x10
APCI_BAR1   equ 0x14
APCI_IO     equ 1                   ; command: I/O space, memory space, bus master
APCI_MEM    equ 2
APCI_MASTER equ 4

; ebx = device address, ecx = register (dword aligned) -> eax. Keeps the rest.
apci_read:
    push edx
    mov eax, ebx
    or eax, ecx
    mov dx, APCI_ADDR
    out dx, eax
    mov dx, APCI_DATA
    in eax, dx
    pop edx
    ret

; ebx = device address, ecx = register, eax = value. Keeps registers.
apci_write:
    push eax
    push edx
    push eax
    mov eax, ebx
    or eax, ecx
    mov dx, APCI_ADDR
    out dx, eax
    pop eax
    mov dx, APCI_DATA
    out dx, eax
    pop edx
    pop eax
    ret

; ax = class << 8 | subclass (0x0403 HD audio, 0x0401 audio).
; -> CF clear and ebx = the first device of that class, or CF set.
; Walks bus 0..255, device 0..31, and functions 1..7 only on devices whose
; function 0 is there and says it has more (header type bit 7).
apci_find_class:
    push ecx
    push edx
    push esi
    movzx esi, ax
    xor ebx, ebx
.dev:
    mov eax, ebx
    or eax, 0x80000000
    push ebx
    mov ebx, eax
    xor ecx, ecx
    call apci_read                  ; vendor/device of function 0
    cmp eax, 0xFFFFFFFF
    je .skip
    call .match
    jnc .found
    mov ecx, 0x0C
    call apci_read
    test eax, 0x00800000            ; multi-function
    jz .skip
    mov edx, 1
.fn:
    mov eax, edx
    shl eax, 8
    pop ebx
    push ebx
    or eax, ebx
    or eax, 0x80000000
    push ebx
    mov ebx, eax
    xor ecx, ecx
    call apci_read
    cmp eax, 0xFFFFFFFF
    je .fnext
    call .match
    jnc .foundfn
.fnext:
    pop ebx
    inc edx
    cmp edx, 8
    jb .fn
    jmp .skip
.foundfn:
    add esp, 4
.found:
    add esp, 4
    clc
    jmp .out
.skip:
    pop ebx
    add ebx, 1 << 11                ; next device (and bus after 32)
    cmp ebx, 1 << 24
    jb .dev
    stc
.out:
    pop esi
    pop edx
    pop ecx
    ret
; ebx = device -> CF clear when its class and subclass are esi
.match:
    mov ecx, APCI_CLASS
    call apci_read
    shr eax, 16
    cmp eax, esi
    je .yes
    stc
    ret
.yes:
    clc
    ret

; ebx = device: turn on I/O, memory and bus mastering. Keeps registers.
apci_enable:
    push eax
    push ecx
    mov ecx, APCI_CMD
    call apci_read
    or eax, APCI_IO | APCI_MEM | APCI_MASTER
    and eax, 0xFFFF                 ; do not write status bits back
    call apci_write
    pop ecx
    pop eax
    ret
