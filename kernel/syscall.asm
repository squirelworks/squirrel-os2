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
SYS_COUNT   equ 4

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

; ---------- handlers: args in ebx/ecx/edx, result in eax ----------
sys_putc:
    mov al, bl
    call putc
    xor eax, eax
    ret

sys_puts:
    mov esi, ebx
    call puts
    mov eax, esi
    sub eax, ebx
    dec eax                 ; puts leaves esi one past the terminator
    ret

; Waits for a key press and returns its ASCII code.
; Enter -> 10, Backspace -> 8, Esc -> 27; releases and unmapped keys are skipped.
sys_getc:
    cli
    call kbd_dequeue
    jnc .got
    sti
    hlt
    jmp sys_getc
.got:
    sti
    call kbd_shift_track
    je sys_getc
    cmp al, 0x80
    jae sys_getc
    cmp al, 0x01
    je .esc
    cmp al, 0x0E
    je .bs
    call kbd_ascii
    movzx eax, al
    test eax, eax
    jz sys_getc
    ret
.esc:
    mov eax, 27
    ret
.bs:
    mov eax, 8
    ret

; Gives up the CPU until the next interrupt. Becomes a scheduler entry
; once the process model (0.1.2) exists.
sys_yield:
    sti
    hlt
    xor eax, eax
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

    mov eax, SYS_COUNT      ; first unused number
    int SYSCALL_VEC
    cmp eax, SYS_ENOSYS
    call st_check

    cmp esi, 0x5A5A1234
    call st_check
    cmp edi, 0xA5A54321
    call st_check

    mov esi, st_pass
    cmp dword [st_fail], 0
    je .out
    mov esi, st_failmsg
.out:
    call puts
    ret

st_check:                   ; counts a failure unless ZF is set
    je .ok
    inc dword [st_fail]
.ok:
    ret

; keys: echoes typed characters through getc/putc until Enter.
cmd_keys_run:
    mov eax, SYS_PUTS
    mov ebx, keys_msg
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
st_pass db 'systest: PASS', 10, 0
st_failmsg db 'systest: FAIL', 10, 0
st_fail dd 0
keys_msg db 'Type keys, Enter to finish:', 10, 0
