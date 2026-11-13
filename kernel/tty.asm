; Squirrel-OS/2 — terminals for programs: SYS_TTY (A.3)
; Included from pm.asm, in the high image. Original code.
;
; A terminal program (programs/terminal.asm) opens a tty and starts
; programs on it. Everything such a program (and every process it starts,
; which inherits the tty) prints goes into the tty's output ring instead
; of the screen, and SYS_GETC reads the tty's input ring instead of the
; keyboard. The terminal drains the output into its window and feeds the
; keys typed in it. See documentation/kernel/tty.md.

SYS_TTY         equ 48

; ebx = operation | tty << 8
TTY_OPEN        equ 0           ; -> tty number (1..TTY_MAX), or -1
TTY_CLOSE       equ 1           ; -> 0: its programs go back to the console
TTY_EXEC        equ 2           ; ecx = file, edx = argument or 0 -> pid, or LD_E*
TTY_READ        equ 3           ; ecx = buffer, edx = size -> bytes of output taken
TTY_WRITE       equ 4           ; ecx = bytes, edx = count -> bytes of input accepted
TTY_POLL        equ 5           ; ecx = pid (a child), edx -> dword: 0 running, 1 ended (code stored, reaped), -1 no such child
TTY_OPS         equ 6

TTY_MAX         equ 4
TTY_OUT         equ 4096        ; output ring (a power of 2)
TTY_IN          equ 256         ; input ring (a power of 2)
TTY_EOF         equ 4           ; Ctrl+D in the input: SYS_GETC returns -1

; per tty
tty_owner   times TTY_MAX dd 0  ; pid of the terminal, 0 = free
tty_ohead   times TTY_MAX dd 0  ; output: written up to here
tty_otail   times TTY_MAX dd 0  ; taken up to here
tty_ihead   times TTY_MAX dd 0
tty_itail   times TTY_MAX dd 0
tty_obuf    times TTY_MAX*TTY_OUT db 0
tty_ibuf    times TTY_MAX*TTY_IN db 0
proc_tty    times PROC_MAX db 0 ; per slot: its tty, 0 = the console

; -> eax = the current process's tty index (0-based), CF if it has none.
; Keeps the other registers.
tty_cur:
    push ebx
    mov ebx, [proc_cur]
    sub ebx, proc_table
    shr ebx, 6
    movzx eax, byte [proc_tty+ebx]
    pop ebx
    sub eax, 1
    ret                         ; (CF from the sub when it was 0)

; putc: al = character. A process on a tty writes into its ring; when the
; ring is full it waits for the terminal (or drops the character when
; interrupts are off, inside an exception report).
tty_putc:
    push eax
    call tty_cur
    jc .con
    push ebx
    push ecx
    push edx
    mov ebx, eax
    mov dl, [esp+12]            ; the character
.full:
    mov eax, [tty_ohead+ebx*4]
    mov ecx, eax
    sub ecx, [tty_otail+ebx*4]
    cmp ecx, TTY_OUT
    jb .room
    cmp dword [tty_owner+ebx*4], 0
    je .out                     ; nobody reads it any more
    pushfd
    pop ecx
    test ecx, 0x200
    jz .out
    call proc_idle
    jmp .full
.room:
    and eax, TTY_OUT-1
    mov ecx, ebx
    shl ecx, 12                 ; * TTY_OUT
    mov [tty_obuf+ecx+eax], dl
    inc dword [tty_ohead+ebx*4]
.out:
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret
.con:
    pop eax
    jmp putc.con

; sys_getc for a process on a tty -> eax = the next input byte (waits),
; -1 at Ctrl+D or when the tty is closed. CF when it has no tty.
tty_getc:
    call tty_cur
    jc .no
    mov ebx, eax
.wait:
    cmp dword [tty_owner+ebx*4], 0
    je .eof
    mov eax, [tty_itail+ebx*4]
    cmp eax, [tty_ihead+ebx*4]
    jne .got
    call proc_idle
    jmp .wait
.got:
    and eax, TTY_IN-1
    mov ecx, ebx
    shl ecx, 8                  ; * TTY_IN
    movzx eax, byte [tty_ibuf+ecx+eax]
    inc dword [tty_itail+ebx*4]
    cmp eax, TTY_EOF
    je .eof
    clc
    ret
.eof:
    or eax, -1
    clc
    ret
.no:
    stc
    ret

; GUI_KEY for a process on a tty -> eax = the next input byte (as ASCII
; only), 0 when there is none; CF when it has no tty
tty_pollkey:
    call tty_cur
    jc .no
    mov ebx, eax
    mov eax, [tty_itail+ebx*4]
    cmp eax, [tty_ihead+ebx*4]
    je .none
    and eax, TTY_IN-1
    mov ecx, ebx
    shl ecx, 8
    movzx eax, byte [tty_ibuf+ecx+eax]
    inc dword [tty_itail+ebx*4]
    clc
    ret
.none:
    xor eax, eax
    clc
    ret
.no:
    stc
    ret

; proc_spawn, edi = the new PCB: it inherits the current process's tty
tty_inherit:
    push eax
    push ebx
    mov eax, [proc_cur]
    sub eax, proc_table
    shr eax, 6
    mov al, [proc_tty+eax]
    mov ebx, edi
    sub ebx, proc_table
    shr ebx, 6
    mov [proc_tty+ebx], al
    pop ebx
    pop eax
    ret

; proc_exit, esi = the exiting PCB: the ttys it owns are closed
tty_exit:
    pushad
    mov eax, [esi+PCB_PID]
    xor ebx, ebx
.l: cmp [tty_owner+ebx*4], eax
    jne .n
    call tty_free
.n: inc ebx
    cmp ebx, TTY_MAX
    jb .l
    popad
    ret

; ebx = tty index: free it; its programs print on the console again
tty_free:
    push eax
    push ecx
    mov dword [tty_owner+ebx*4], 0
    lea eax, [ebx+1]
    xor ecx, ecx
.p: cmp [proc_tty+ecx], al
    jne .pn
    mov byte [proc_tty+ecx], 0
.pn:
    inc ecx
    cmp ecx, PROC_MAX
    jb .p
    dec byte [tty_count]
    pop ecx
    pop eax
    ret

; ---------- SYS_TTY ----------
sys_tty:
    movzx eax, bl
    cmp eax, TTY_OPS
    jae .bad
    cmp eax, TTY_OPEN
    je tty_open
    movzx ebx, bh               ; the tty, 1-based
    dec ebx
    cmp ebx, TTY_MAX
    jae .bad
    mov esi, [proc_cur]
    mov esi, [esi+PCB_PID]
    cmp [tty_owner+ebx*4], esi
    jne .bad
    test esi, esi
    jz .bad
    jmp [.ops+eax*4]
.ops:
    dd .bad, tty_close, tty_exec, tty_read, tty_write, tty_poll
.bad:
    or eax, -1
    ret

tty_open:
    mov esi, [proc_cur]
    mov esi, [esi+PCB_PID]
    test esi, esi
    jz .bad                     ; the shell has the console
    call tty_cur
    jnc .bad                    ; a program on a tty does not open another
    xor ebx, ebx
.f: cmp dword [tty_owner+ebx*4], 0
    je .got
    inc ebx
    cmp ebx, TTY_MAX
    jb .f
.bad:
    or eax, -1
    ret
.got:
    mov [tty_owner+ebx*4], esi
    xor eax, eax
    mov [tty_ohead+ebx*4], eax
    mov [tty_otail+ebx*4], eax
    mov [tty_ihead+ebx*4], eax
    mov [tty_itail+ebx*4], eax
    inc byte [tty_count]
    lea eax, [ebx+1]
    ret

; ebx = tty index below
tty_close:
    call tty_free
    xor eax, eax
    ret

tty_exec:
    push ebx
    mov esi, ecx
    mov edi, edx
    call prog_exec
    pop ebx
    test eax, eax
    js .r
    push eax
    push ebx
    mov ebx, eax
    call proc_find
    pop ebx
    pop eax
    test edi, edi
    jz .r
    sub edi, proc_table
    shr edi, 6
    inc ebx
    mov [proc_tty+edi], bl      ; before it ever runs
.r: ret

; ecx = buffer, edx = size
tty_read:
    mov edi, ecx
    xor ecx, ecx
    mov esi, ebx
    shl esi, 12
    add esi, tty_obuf
.l: cmp ecx, edx
    jae .r
    mov eax, [tty_otail+ebx*4]
    cmp eax, [tty_ohead+ebx*4]
    je .r
    and eax, TTY_OUT-1
    mov al, [esi+eax]
    stosb
    inc dword [tty_otail+ebx*4]
    inc ecx
    jmp .l
.r: mov eax, ecx
    ret

; ecx = bytes, edx = count
tty_write:
    mov esi, ecx
    xor ecx, ecx
    mov edi, ebx
    shl edi, 8
    add edi, tty_ibuf
.l: cmp ecx, edx
    jae .r
    mov eax, [tty_ihead+ebx*4]
    push eax
    sub eax, [tty_itail+ebx*4]
    cmp eax, TTY_IN
    pop eax
    jae .r                      ; full
    and eax, TTY_IN-1
    push ebx
    mov bl, [esi]
    mov [edi+eax], bl
    pop ebx
    inc esi
    inc dword [tty_ihead+ebx*4]
    inc ecx
    jmp .l
.r: mov eax, ecx
    ret

; ecx = pid, edx -> exit code
tty_poll:
    push ebx
    mov ebx, ecx
    call proc_find
    pop ebx
    test edi, edi
    jz .none
    mov eax, [proc_cur]
    mov eax, [eax+PCB_PID]
    cmp [edi+PCB_PARENT], eax
    jne .none
    cmp dword [edi+PCB_STATE], P_ZOMBIE
    je .ended
    xor eax, eax
    ret
.ended:
    mov eax, [edi+PCB_CODE]
    mov [edx], eax
    call proc_free
    mov eax, 1
    ret
.none:
    or eax, -1
    ret

; ring-3 pointer checks (sys_uargs, kind UA_TTY): ebx = op | tty << 8
tty_uargs:
    pushad
    movzx eax, bl
    cmp eax, TTY_EXEC
    je .exec
    cmp eax, TTY_READ
    je .buf
    cmp eax, TTY_WRITE
    je .buf
    cmp eax, TTY_POLL
    je .poll
    jmp .ok
.exec:
    mov esi, ecx
    call ua_str
    jc .bad
    test edx, edx
    jz .ok
    mov esi, edx
    call ua_str
    jc .bad
    jmp .ok
.buf:
    mov esi, ecx
    mov ecx, edx
    call ua_range
    jc .bad
    jmp .ok
.poll:
    mov esi, edx
    mov ecx, 4
    call ua_range
    jc .bad
.ok:
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

tty_count db 0                  ; ttys open: putc looks only when there are some
