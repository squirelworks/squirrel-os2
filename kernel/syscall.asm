; Squirrel-OS/2 — system call interface (0.1.1)
; Included from pm.asm. Original code.
;
; ABI (see documentation/kernel/syscalls.md):
;   int 0x80, eax = call number, ebx/ecx/edx = arguments
;   return value in eax; every other register is preserved
;   unknown call number returns SYS_ENOSYS (-1)

SYS_PUTC    equ 0           ; ebx = char            -> 0
SYS_PUTS    equ 1           ; ebx = ptr to ASCIIZ   -> length written
SYS_GETC    equ 2           ; (blocking)            -> ASCII code
SYS_YIELD   equ 3           ;                       -> 0
SYS_SPAWN   equ 4           ; ebx = entry, ecx = arg -> pid or -1
SYS_EXIT    equ 5           ; ebx = exit code       (does not return)
SYS_WAIT    equ 6           ; ebx = pid             -> exit code or -1
SYS_GETPID  equ 7           ;                       -> pid
SYS_BREAD   equ 8           ; ebx = LBA, ecx = buf, edx = drive -> 0 or -1
SYS_BWRITE  equ 9           ; ebx = LBA, ecx = buf (data disk only) -> 0 or -1
SYS_OPEN    equ 10          ; ebx = name, ecx = O_* flags -> fd or -1
SYS_READ    equ 11          ; ebx = fd, ecx = buf, edx = len -> bytes or -1
SYS_WRITE   equ 12          ; ebx = fd, ecx = buf, edx = len -> bytes or -1
SYS_CLOSE   equ 13          ; ebx = fd              -> 0 or -1
SYS_CREATE  equ 14          ; ebx = name            -> 0 or -1
SYS_DELETE  equ 15          ; ebx = name            -> 0 or -1
SYS_RENAME  equ 16          ; ebx = old, ecx = new  -> 0 or -1
SYS_EXEC    equ 17          ; ebx = file name, ecx = argument -> pid or LD_E* (< 0)
SYS_READDIR equ 18          ; ebx = cursor (0 first), ecx = 20-byte buf -> next cursor, 0 at end, -1 no disk
SYS_PALLOC  equ 19          ;                       -> zeroed 4 KB page or 0
SYS_PFREE   equ 20          ; ebx = page            -> 0 or -1
SYS_SBRK    equ 21          ; ebx = bytes (signed)   -> old break or -1
SYS_DEVFIND equ 22          ; ebx = name             -> handle or -1
SYS_DEVREAD equ 23          ; ebx = handle, ecx = buf, edx = count/sector -> bytes or -1
SYS_DEVWRITE equ 24         ; as SYS_DEVREAD
SYS_COUNT   equ 25

SYS_ENOSYS  equ -1
SYSCALL_VEC equ 0x80

; Install the gate: 32-bit trap gate, DPL 3, so IF is left as the caller
; had it and future ring-3 code may call it.
syscall_init:
    mov edi, idt+SYSCALL_VEC*8
    mov eax, syscall_isr
    call set_gate
    mov byte [edi+5], 0xEF
    ret

syscall_isr:
    cmp eax, SYS_COUNT
    jae .bad
    pushad
    call [syscall_table+eax*4]
    mov [esp+28], eax       ; overwrite saved eax so popad returns it
    popad
    iretd
.bad:
    mov eax, SYS_ENOSYS
    iretd

syscall_table:
    dd sys_putc
    dd sys_puts
    dd sys_getc
    dd sys_yield
    dd sys_spawn
    dd sys_exit
    dd sys_wait
    dd sys_getpid
    dd sys_bread
    dd sys_bwrite
    dd sys_open
    dd sys_read
    dd sys_write
    dd sys_close
    dd sys_create
    dd sys_delete
    dd sys_rename
    dd sys_exec
    dd sys_readdir
    dd sys_palloc
    dd sys_pfree
    dd sys_sbrk
    dd sys_devfind
    dd sys_devread
    dd sys_devwrite

; ---------- handlers: args in ebx/ecx/edx, result in eax ----------
sys_putc:
    mov al, bl
    call putc
    xor eax, eax
    ret

sys_puts:                   ; through the console device (0.7.1)
    mov esi, ebx
    call strlen
    mov ecx, eax
    mov ebx, dev_con
    jmp dev_write

; Waits for a key press and returns its ASCII code.
; Enter -> 10, Backspace -> 8, Esc -> 27; releases and unmapped keys are skipped.
sys_getc:
    cmp byte [in_on], 0
    jne in_getc                 ; input redirected (shell.asm): -1 at the end
    push eax                    ; one byte from the keyboard device (0.7.1)
    mov edi, esp
    mov ecx, 1
    mov ebx, dev_kbd
    call dev_read
    pop eax
    movzx eax, al
    ret

; Lets the next READY process run; if there is none, sleeps until the
; next interrupt.
sys_yield:
    call proc_idle
    xor eax, eax
    ret

sys_spawn:
    jmp proc_spawn

sys_exit:
    jmp proc_exit

sys_wait:
    jmp proc_wait

sys_getpid:
    mov eax, [proc_cur]
    mov eax, [eax+PCB_PID]
    ret

; Raw sector access. Writes are limited to the data disk (drive 1) so a
; program cannot overwrite the boot image.
; Both go through the hd0/hd1 block devices (0.7.2).
sys_bread:
    mov edi, ecx
    mov ecx, ebx
    xor ebx, ebx                ; drive numbers other than 0/1: no device
    cmp edx, 1
    ja .dev
    mov ebx, [ata_devs+edx*4]
.dev:
    call dev_bread
    jmp sys_cf_result

sys_bwrite:
    mov esi, ecx
    mov ecx, ebx
    mov ebx, dev_hd1
    call dev_bwrite
    ; fall through
sys_cf_result:                  ; CF -> eax = -1, else 0
    mov eax, 0
    jnc .ok
    dec eax
.ok:
    ret

; file system (0.2.2): thin register shuffles onto fs.asm
sys_open:
    mov esi, ebx
    jmp fs_open

sys_read:
    mov edi, ecx
    mov ecx, edx
    jmp fs_read

sys_write:
    mov esi, ecx
    mov ecx, edx
    jmp fs_write

sys_close:
    jmp fs_close

sys_create:
    mov esi, ebx
    jmp fs_create

sys_delete:
    mov esi, ebx
    jmp fs_delete

sys_rename:
    mov esi, ebx
    mov edi, ecx
    jmp fs_rename

; Directory listing, one entry per call: copies the 16-byte name and the
; size (dword) of the next entry of the current directory at or after
; the cursor into the buffer and returns the cursor for the next call.
; A subdirectory's size reads as -1 (0.8.0).
sys_readdir:
    mov eax, -1
    cmp byte [fs_mounted], 0
    je .r
.l:
    xor eax, eax
    cmp ebx, FS_MAXFILES
    jae .r
    mov esi, ebx
    shl esi, 5                  ; * FS_DIRENT
    add esi, FS_DIR
    inc ebx
    cmp byte [esi], 0
    je .l
    mov dl, [fs_cwd]
    cmp [esi+DE_PARENT], dl
    jne .l
    mov edi, ecx
    mov edx, [esi+DE_SIZE]
    cmp byte [esi+DE_KIND], DK_DIR
    jne .copy
    mov edx, -1
.copy:
    push ecx
    mov ecx, FS_NAMELEN/4
    rep movsd
    pop ecx
    mov [edi], edx
    mov eax, ebx
.r:
    ret

; ---------- shell commands exercising the gate ----------
; systest: calls each non-blocking syscall and checks results and
; register preservation. Prints PASS or FAIL.
cmd_systest_run:
    mov dword [st_fail], 0
    mov esi, 0x5A5A1234     ; sentinels that must survive every call
    mov edi, 0xA5A54321

    mov eax, SYS_PUTS
    mov ebx, st_puts_msg
    int SYSCALL_VEC
    cmp eax, st_puts_len
    call st_check

    mov eax, SYS_PUTC
    mov ebx, 'o'
    int SYSCALL_VEC
    test eax, eax
    call st_check
    mov eax, SYS_PUTC
    mov ebx, 'k'
    int SYSCALL_VEC
    mov eax, SYS_PUTC
    mov ebx, 10
    int SYSCALL_VEC

    mov eax, SYS_YIELD
    int SYSCALL_VEC
    test eax, eax
    call st_check

    mov eax, SYS_GETPID     ; the shell is pid 0
    int SYSCALL_VEC
    test eax, eax
    call st_check

    test dword [dev_hd0+DEV_FLAGS], DEVF_UP
    jz .nohd0               ; booted from a floppy: no hard disk 0 (0.9.3)
    mov eax, SYS_BREAD      ; boot sector of drive 0 ends in 0xAA55
    xor ebx, ebx
    mov ecx, KSCRATCH+0x600
    xor edx, edx
    int SYSCALL_VEC
    test eax, eax
    call st_check
    cmp word [KSCRATCH+0x600+510], 0xAA55
    call st_check
.nohd0:

    mov eax, SYS_BWRITE     ; past the end of any disk -> -1
    mov ebx, 0x0FFFFFFF
    mov ecx, KSCRATCH+0x600
    int SYSCALL_VEC
    cmp eax, -1
    call st_check

    cmp byte [fs_mounted], 0
    je .nofs
    mov eax, SYS_CREATE     ; file round trip through the syscalls
    mov ebx, st_file
    int SYSCALL_VEC
    test eax, eax
    call st_check
    mov eax, SYS_OPEN
    mov ebx, st_file
    mov ecx, O_APPEND
    int SYSCALL_VEC
    mov ebx, eax
    mov eax, SYS_WRITE
    mov ecx, st_puts_msg
    mov edx, 7
    int SYSCALL_VEC
    cmp eax, 7
    call st_check
    mov eax, SYS_CLOSE
    int SYSCALL_VEC
    mov eax, SYS_OPEN
    mov ebx, st_file
    xor ecx, ecx
    int SYSCALL_VEC
    mov ebx, eax
    mov eax, SYS_READ
    mov ecx, KSCRATCH+0x600
    mov edx, 100
    int SYSCALL_VEC
    cmp eax, 7
    call st_check
    cmp dword [KSCRATCH+0x600], 'sysc'
    call st_check
    mov eax, SYS_CLOSE
    int SYSCALL_VEC
    mov eax, SYS_DELETE
    mov ebx, st_file
    int SYSCALL_VEC
    test eax, eax
    call st_check
    mov eax, SYS_OPEN       ; gone now, and no O_CREATE -> -1
    mov ebx, st_file
    xor ecx, ecx
    int SYSCALL_VEC
    cmp eax, -1
    call st_check
.nofs:

    mov eax, SYS_COUNT      ; first unused number
    int SYSCALL_VEC
    cmp eax, SYS_ENOSYS
    call st_check

    cmp esi, 0x5A5A1234
    call st_check
    cmp edi, 0xA5A54321
    call st_check

    mov esi, [lstr+LS_SYSTEST_PASS*4]
    cmp dword [st_fail], 0
    je .out
    mov esi, [lstr+LS_SYSTEST_FAIL*4]
.out:
    jmp lputs_nl

st_check:                   ; counts a failure unless ZF is set
    je .ok
    inc dword [st_fail]
.ok:
    ret

; keys: echoes typed characters through getc/putc until Enter.
cmd_keys_run:
    mov eax, SYS_PUTS
    mov ebx, [lstr+LS_KEYS*4]
    int SYSCALL_VEC
    mov eax, SYS_PUTC
    mov ebx, 10
    int SYSCALL_VEC
.loop:
    mov eax, SYS_GETC
    int SYSCALL_VEC
    cmp eax, 10
    je .done
    mov ebx, eax
    mov eax, SYS_PUTC
    int SYSCALL_VEC
    jmp .loop
.done:
    mov eax, SYS_PUTC
    mov ebx, 10
    int SYSCALL_VEC
    ret

st_puts_msg db 'syscall puts: ok', 10, 0
st_puts_len equ $ - st_puts_msg - 1
st_file db 'systest.tmp', 0
st_fail dd 0
