; lxsig — Linux i386 signals (P.2): rt_sigaction with and without a
; restorer, SA_SIGINFO, kill/tgkill to itself, registers kept across a
; handler, SIG_IGN, blocking with rt_sigprocmask and rt_sigpending,
; SA_RESETHAND, the error cases, and last a default action (SIGTERM)
; that ends the program. Original code.
; Prints "lxsig: PASS", then the kernel's "Program ended by signal 15";
; "lxsig: still here" must never appear. "lxsig: FAIL x" on a failure.
%include "lxelf.inc"
LX_ELF_HEADER _start

SIGUSR1 equ 10
SIGUSR2 equ 12
SIGTERM equ 15
SA_SIGINFO equ 4
SA_RESTORER equ 0x04000000
SA_RESETHAND equ 0x80000000

%macro STEP 1
    mov byte [step], %1
%endmacro
%macro SYS 1-4
    mov eax, %1
%if %0 > 1
    mov ebx, %2
%endif
%if %0 > 2
    mov ecx, %3
%endif
%if %0 > 3
    mov edx, %4
%endif
    int 0x80
%endmacro
; ACT handler, flags, restorer: fill the act buffer
%macro ACT 3
    mov dword [act], %1
    mov dword [act+4], %2
    mov dword [act+8], %3
    mov dword [act+12], 0
    mov dword [act+16], 0
%endmacro

_start:
    SYS 20                          ; getpid
    mov [mypid], eax
    STEP 'a'                        ; a handler with our own restorer
    ACT h_usr1, SA_RESTORER, restorer
    mov esi, 8                      ; sigsetsize
    SYS 174, SIGUSR1, act, oact
    test eax, eax
    jnz fail
    cmp dword [oact], 0             ; was SIG_DFL
    jne fail
    STEP 'b'                        ; kill ourselves: registers survive
    mov esi, 0x51515151
    mov edi, 0xD1D1D1D1
    mov ebp, 0xB0B0B0B0
    SYS 37, [mypid], SIGUSR1
    test eax, eax
    jnz fail
    cmp esi, 0x51515151
    jne fail
    cmp edi, 0xD1D1D1D1
    jne fail
    cmp ebp, 0xB0B0B0B0
    jne fail
    cmp dword [ebx_after], 0
    jne fail
    cmp ebx, [mypid]
    jne fail
    cmp dword [n_usr1], 1
    jne fail
    cmp dword [got_sig], SIGUSR1
    jne fail
    cmp dword [blocked_in], 1       ; SIGUSR1 was blocked inside its handler
    jne fail
    SYS 175, 0, 0, oldmask          ; and is not any more
    test dword [oldmask], 1 << (SIGUSR1-1)
    jnz fail
    STEP 'c'                        ; SA_SIGINFO, the kernel's own return stub
    ACT h_usr2, SA_SIGINFO, 0
    mov esi, 8
    SYS 174, SIGUSR2, act, 0
    test eax, eax
    jnz fail
    SYS 270, [mypid], [mypid], SIGUSR2  ; tgkill
    test eax, eax
    jnz fail
    cmp dword [n_usr2], 1
    jne fail
    cmp dword [info_signo], SIGUSR2
    jne fail
    cmp dword [uc_ok], 1
    jne fail
    STEP 'd'                        ; SIG_IGN
    ACT 1, 0, 0
    mov esi, 8
    SYS 174, SIGUSR1, act, oact
    cmp dword [oact], h_usr1
    jne fail
    SYS 37, 0, SIGUSR1
    test eax, eax
    jnz fail
    cmp dword [n_usr1], 1
    jne fail
    STEP 'e'                        ; blocked: pending, then delivered
    mov dword [set], 1 << (SIGUSR2-1)
    mov esi, 8
    SYS 175, 0, set, 0              ; SIG_BLOCK
    SYS 238, [mypid], SIGUSR2       ; tkill
    cmp dword [n_usr2], 1
    jne fail
    SYS 176, pend
    test eax, eax
    jnz fail
    cmp dword [pend], 1 << (SIGUSR2-1)
    jne fail
    mov esi, 8
    SYS 175, 1, set, 0              ; SIG_UNBLOCK: delivered on the way out
    cmp dword [n_usr2], 2
    jne fail
    STEP 'f'                        ; SA_RESETHAND: one shot
    ACT h_usr1, SA_RESETHAND, 0
    mov esi, 8
    SYS 174, SIGUSR1, act, 0
    SYS 37, [mypid], SIGUSR1
    cmp dword [n_usr1], 2
    jne fail
    mov esi, 8
    SYS 174, SIGUSR1, 0, oact
    cmp dword [oact], 0
    jne fail
    STEP 'g'                        ; errors
    ACT h_usr1, 0, 0
    mov esi, 8
    SYS 174, 9, act, 0              ; SIGKILL cannot be caught
    cmp eax, -22
    jne fail
    SYS 37, [mypid], 33
    cmp eax, -22
    jne fail
    SYS 37, 9999, SIGUSR1
    cmp eax, -3                     ; ESRCH
    jne fail
    SYS 174, SIGUSR1, 0x8000, 0     ; kernel memory
    cmp eax, -14
    jne fail
    SYS 64                          ; getppid: the shell
    test eax, eax
    js fail
    SYS 4, 1, pass, pass_len
    STEP 'h'                        ; the default action of SIGTERM
    SYS 37, [mypid], SIGTERM
    SYS 4, 1, still, still_len
    SYS 1, 2

h_usr1:
    mov eax, [esp+4]
    mov [got_sig], eax
    inc dword [n_usr1]
    push ebx
    mov eax, 175
    xor ebx, ebx
    xor ecx, ecx
    mov edx, hmask
    int 0x80
    pop ebx
    mov eax, [hmask]
    shr eax, SIGUSR1-1
    and eax, 1
    mov [blocked_in], eax
    xor ebx, ebx                    ; clobbered here, restored by sigreturn
    mov [ebx_after], ebx
    mov esi, -1
    mov edi, -1
    mov ebp, -1
    ret

h_usr2:                             ; (sig, siginfo *, ucontext *)
    inc dword [n_usr2]
    mov eax, [esp+8]
    mov eax, [eax]
    mov [info_signo], eax
    mov eax, [esp+12]               ; uc_mcontext.eip is inside our code
    mov eax, [eax+20+56]
    cmp eax, _start
    jb .r
    cmp eax, h_usr1
    jae .r
    mov dword [uc_ok], 1
.r:
    ret

restorer:
    mov eax, 173
    int 0x80

fail:
    SYS 4, 1, failmsg, failmsg_len
    SYS 1, 1

pass db 'lxsig: PASS', 10
pass_len equ $ - pass
still db 'lxsig: still here', 10
still_len equ $ - still
failmsg db 'lxsig: FAIL '
step db '?', 10
failmsg_len equ $ - failmsg
LX_ELF_BSS
mypid resd 1
act resd 5
oact resd 5
oldmask resd 2
hmask resd 2
set resd 2
pend resd 2
n_usr1 resd 1
n_usr2 resd 1
got_sig resd 1
blocked_in resd 1
ebx_after resd 1
info_signo resd 1
uc_ok resd 1
LX_ELF_END
