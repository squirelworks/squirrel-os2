; Squirrel-OS/2 — device drivers: registration and dispatch (0.7.x)
; Included from pm.asm. Original code.
;
; A driver describes each device it handles with a static descriptor
; (name, type, operations) and registers it with dev_register, which
; probes it. Callers find a device by name and go through dev_read /
; dev_write (character devices) or dev_bread / dev_bwrite (block
; devices) instead of calling the driver directly.
; See documentation/kernel/drivers.md.

DEV_MAX     equ 16

; descriptor (40 bytes; DEV_FLAGS and DEV_SIZE are filled in here)
DEV_NAME    equ 0                   ; 8 bytes, zero-padded
DEV_TYPE    equ 8
DEV_PROBE   equ 12                  ; ebx = descriptor -> CF if absent
DEV_READ    equ 16
DEV_WRITE   equ 20
DEV_UNIT    equ 24                  ; driver's own number (drive, ...)
DEV_FLAGS   equ 28
DEV_SIZE    equ 32                  ; block devices: sectors
DEV_DESC    equ 40

DEV_CHAR    equ 1
DEV_BLOCK   equ 2
DEV_NET     equ 3                   ; network cards (1.9.4)
DEVF_UP     equ 1                   ; probed and present
DEVF_RO     equ 2                   ; programs may not write it

; Operations, all with ebx = descriptor:
;   char   read:  edi = buffer, ecx = count -> eax = bytes, or -1
;          write: esi = buffer, ecx = count -> eax = bytes, or -1
;   block  read:  ecx = sector, edi = 512-byte buffer -> CF on error
;          write: ecx = sector, esi = 512-byte buffer -> CF on error

; Registers the built-in drivers' devices (after ata_init).
dev_init:
    mov dword [dev_count], 0
    mov esi, dev_builtin
.l:
    lodsd
    test eax, eax
    jz .r
    push esi
    mov esi, eax
    call dev_register
    pop esi
    jmp .l
.r:
    ret

; esi = descriptor: probes it and adds it to the table -> CF if full
dev_register:
    push eax
    push ebx
    mov eax, [dev_count]
    cmp eax, DEV_MAX
    jae .full
    mov [dev_table+eax*4], esi
    inc dword [dev_count]
    mov ebx, esi
    and dword [ebx+DEV_FLAGS], DEVF_RO
    call [ebx+DEV_PROBE]
    jc .ok
    or dword [ebx+DEV_FLAGS], DEVF_UP
.ok:
    pop ebx
    pop eax
    clc
    ret
.full:
    pop ebx
    pop eax
    stc
    ret

; esi = name -> ebx = descriptor of a present device, or 0
dev_find:
    push ecx
    push edi
    xor ecx, ecx
.l:
    cmp ecx, [dev_count]
    jae .none
    mov ebx, [dev_table+ecx*4]
    lea edi, [ebx+DEV_NAME]
    call streq
    jne .next
    test dword [ebx+DEV_FLAGS], DEVF_UP
    jnz .out
.next:
    inc ecx
    jmp .l
.none:
    xor ebx, ebx
.out:
    pop edi
    pop ecx
    ret

; ebx = character device, edi = buffer, ecx = count -> eax = bytes or -1
dev_read:
    mov eax, DEV_CHAR
    call dev_check
    jc dev_fail
    jmp [ebx+DEV_READ]

; ebx = character device, esi = buffer, ecx = count -> eax = bytes or -1
dev_write:
    mov eax, DEV_CHAR
    call dev_check
    jc dev_fail
    jmp [ebx+DEV_WRITE]

; ebx = block device, ecx = sector, edi = buffer -> CF on error.
; Like the block operations, preserves all registers.
dev_bread:
    push eax
    mov eax, DEV_BLOCK
    call dev_check
    pop eax
    jc .r
    jmp [ebx+DEV_READ]
.r:
    ret

; ebx = block device, ecx = sector, esi = buffer -> CF on error
dev_bwrite:
    push eax
    mov eax, DEV_BLOCK
    call dev_check
    pop eax
    jc .r
    jmp [ebx+DEV_WRITE]
.r:
    ret

dev_fail:
    mov eax, -1
    ret

; ebx = descriptor, eax = type wanted -> CF unless present and that type
dev_check:
    test ebx, ebx
    jz .no
    cmp [ebx+DEV_TYPE], eax
    jne .no
    test dword [ebx+DEV_FLAGS], DEVF_UP
    jz .no
    clc
    ret
.no:
    stc
    ret

; a probe for devices that are always there
dev_probe_yes:
    clc
    ret

; Null character device ops (1.9.12): reads fill with zero, writes discard
dev_null_read:
    push edi
    push ecx
    xor eax, eax
    rep stosb
    pop eax
    pop edi
    ret

dev_null_write:
    mov eax, ecx
    ret

; ebx = ASCIIZ name (1..7 chars): register a ready null char device.
; eax = 0, or -1 if the name is bad, taken, or no free slot.
dev_reg_null:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov esi, ebx
    call strlen
    test eax, eax
    jz .bad
    cmp eax, 7
    ja .bad
    push esi
    call dev_find               ; already present under that name?
    pop esi
    test ebx, ebx
    jnz .bad
    ; also refuse a name that matches an absent built-in
    xor ecx, ecx
.scan:
    cmp ecx, [dev_count]
    jae .slot
    mov ebx, [dev_table+ecx*4]
    lea edi, [ebx+DEV_NAME]
    call streq
    je .bad
    inc ecx
    jmp .scan
.slot:
    mov edx, [dev_dyn_used]
    cmp edx, DEV_DYN_MAX
    jae .bad
    imul eax, edx, DEV_DESC
    lea edi, [dev_dyn+eax]
    push edi
    mov ecx, DEV_DESC/4
    xor eax, eax
    rep stosd
    pop edi
    push edi
    lea edi, [edi+DEV_NAME]
    mov ecx, 8
.cpy:
    lodsb
    test al, al
    jz .pad
    stosb
    dec ecx
    jnz .cpy
    jmp .filled
.pad:
    xor al, al
    rep stosb
.filled:
    pop edi
    mov dword [edi+DEV_TYPE], DEV_CHAR
    mov dword [edi+DEV_PROBE], dev_probe_yes
    mov dword [edi+DEV_READ], dev_null_read
    mov dword [edi+DEV_WRITE], dev_null_write
    mov esi, edi
    call dev_register
    jc .bad
    inc dword [dev_dyn_used]
    xor eax, eax
    jmp .out
.bad:
    mov eax, -1
.out:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ---------- syscalls ----------

; SYS_DEVFIND: ebx = name -> eax = handle (table index), or -1
sys_devfind:
    mov esi, ebx
    call dev_find
    test ebx, ebx
    jz dev_fail
    xor eax, eax
.l:
    cmp [dev_table+eax*4], ebx
    je .r
    inc eax
    jmp .l
.r:
    ret

; ebx = handle -> ebx = descriptor (0 if the handle is not valid)
dev_handle:
    cmp ebx, [dev_count]
    jae .bad
    mov ebx, [dev_table+ebx*4]
    ret
.bad:
    xor ebx, ebx
    ret

; SYS_DEVREAD: ebx = handle, ecx = buffer, edx = count (character) or
; sector (block) -> eax = bytes read, or -1
sys_devread:
    call dev_handle
    mov edi, ecx
    test ebx, ebx
    jz dev_fail
    cmp dword [ebx+DEV_TYPE], DEV_BLOCK
    je .block
    mov ecx, edx
    jmp dev_read
.block:
    mov ecx, edx
    call dev_bread
    jmp dev_cf_bytes

; SYS_DEVWRITE: as SYS_DEVREAD; read-only devices refuse
sys_devwrite:
    call dev_handle
    mov esi, ecx
    test ebx, ebx
    jz dev_fail
    test dword [ebx+DEV_FLAGS], DEVF_RO
    jnz dev_fail
    cmp dword [ebx+DEV_TYPE], DEV_BLOCK
    je .block
    mov ecx, edx
    jmp dev_write
.block:
    mov ecx, edx
    call dev_bwrite
dev_cf_bytes:                   ; CF -> -1, else a sector's worth
    mov eax, -1
    jc .r
    mov eax, SECTOR_SIZE
.r:
    ret

; ---------- shell: devices ----------
cmd_devices_run:
    mov esi, dev_m_head
    call puts
    xor ecx, ecx
.row:
    cmp ecx, [dev_count]
    jae .r
    mov ebx, [dev_table+ecx*4]
    lea esi, [ebx+DEV_NAME]
    call puts
    mov al, 8
    call puts_pad
    mov esi, dev_m_char
    cmp dword [ebx+DEV_TYPE], DEV_CHAR
    je .t
    cmp dword [ebx+DEV_TYPE], DEV_BLOCK
    jne .tn
    mov esi, dev_m_block
    jmp .t
.tn:
    mov esi, dev_m_net
.t:
    call puts
    mov al, 16
    call puts_pad
    mov esi, dev_m_up
    test dword [ebx+DEV_FLAGS], DEVF_UP
    jnz .s
    mov esi, dev_m_absent
.s:
    call puts
    test dword [ebx+DEV_FLAGS], DEVF_UP
    jz .eol
    cmp dword [ebx+DEV_TYPE], DEV_NET
    jne .blk
    call dev_put_mac
    jmp .eol
.blk:
    cmp dword [ebx+DEV_TYPE], DEV_BLOCK
    jne .ro
    mov al, ' '
    call putc
    mov eax, [ebx+DEV_SIZE]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, dev_m_sectors
    call puts
.ro:
    test dword [ebx+DEV_FLAGS], DEVF_RO
    jz .eol
    mov esi, dev_m_ro
    call puts
.eol:
    mov al, 10
    call putc
    inc ecx
    jmp .row
.r:
    ret

; ebx = a network card's descriptor: prints ' ' and its MAC address,
; which its driver keeps at [DEV_UNIT]
dev_put_mac:
    push eax
    push ecx
    push esi
    mov esi, [ebx+DEV_UNIT]
    mov ecx, 6
.b:
    mov al, ':'
    cmp ecx, 6
    jne .sep
    mov al, ' '
.sep:
    call putc
    lodsb
    call dev_hex2
    loop .b
    pop esi
    pop ecx
    pop eax
    ret

; al -> two lower-case hex digits
dev_hex2:
    push eax
    shr al, 4
    call .d
    pop eax
    and al, 15
.d:
    push eax
    and al, 15
    add al, '0'
    cmp al, '9'
    jbe .p
    add al, 'a' - '9' - 1
.p:
    call putc
    pop eax
    ret

; the built-in drivers' devices, in registration order
dev_builtin dd dev_con, dev_kbd, dev_hd0, dev_hd1, dev_ne0, 0

dev_m_head db 'NAME    TYPE    STATUS', 10, 0
dev_m_char db 'char', 0
dev_m_block db 'block', 0
dev_m_net db 'net', 0
dev_m_up db 'ready', 0
dev_m_absent db 'absent', 0
dev_m_sectors db ' sectors', 0
dev_m_ro db ' (read-only for programs)', 0

DEV_DYN_MAX equ 4                   ; run-time null devices (1.9.12)

align 4
dev_count dd 0
dev_dyn_used dd 0
dev_table times DEV_MAX dd 0
dev_dyn times DEV_DYN_MAX*DEV_DESC db 0
