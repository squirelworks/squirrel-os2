; spin — exercises the 1.1 scheduler. Original code.
;   run spin          two threads busy-loop without ever yielding; with
;                     preemption both make progress: "preempt: PASS"
;   run spin sleep    SYS_SLEEP for 20 ticks: "sleep: PASS"
;   run spin prio     a priority-0 thread gets no time while its
;                     priority-1 parent is busy, then runs while the
;                     parent sleeps: "prio: PASS"
%include "sqx.inc"
SQX_HEADER main

TIMEOUT   equ 300               ; ticks (3 s) before giving up
ENOUGH    equ 100000            ; worker iterations that prove it ran

main:
    mov esi, [esp+4]
    cmp byte [esi], 's'
    je sleep_test
    cmp byte [esi], 'p'
    je prio_test
    ; --- preemption: the parent never yields while it waits ---
    call start_worker
    mov eax, SYS_TICKS
    int 0x80
    lea ebp, [eax+TIMEOUT]
.busy:
    cmp dword [count], ENOUGH
    jae .ran
    mov eax, SYS_TICKS          ; (does not yield)
    int 0x80
    cmp eax, ebp
    jb .busy
    mov ebx, m_pre_fail
    jmp finish
.ran:
    mov ebx, m_pre_pass
    jmp finish

sleep_test:
    mov eax, SYS_TICKS
    int 0x80
    mov ebp, eax
    mov eax, SYS_SLEEP
    mov ebx, 20
    int 0x80
    mov eax, SYS_TICKS
    int 0x80
    sub eax, ebp
    mov ebx, m_sleep_pass
    cmp eax, 20
    jae .say
    mov ebx, m_sleep_fail
.say:
    mov eax, SYS_PUTS
    int 0x80
    xor eax, eax
    ret

prio_test:
    call start_worker
    mov eax, SYS_SETPRIO        ; the worker drops to background
    mov ebx, [worker]
    xor ecx, ecx
    int 0x80
    mov dword [count], 0
    mov eax, SYS_TICKS          ; stay busy for 30 ticks
    int 0x80
    lea ebp, [eax+30]
.busy:
    mov eax, SYS_TICKS
    int 0x80
    cmp eax, ebp
    jb .busy
    mov ebx, m_prio_starved
    cmp dword [count], 0        ; a lower priority must not have run
    jne finish
    mov eax, SYS_SLEEP          ; now it is the only one ready
    mov ebx, 20
    int 0x80
    mov ebx, m_prio_pass
    cmp dword [count], 0
    jne finish
    mov ebx, m_prio_fail
    jmp finish

; ebx = message: stops the worker, waits for it, prints, exits 0
finish:
    mov [msg], ebx
    mov byte [stop], 1
    mov eax, SYS_WAIT
    mov ebx, [worker]
    int 0x80
    mov eax, SYS_PUTS
    mov ebx, [msg]
    int 0x80
    xor eax, eax
    ret

start_worker:
    mov eax, SYS_SPAWN
    mov ebx, worker_main
    xor ecx, ecx
    int 0x80
    mov [worker], eax
    ret

; counts as fast as it can, never yielding, until told to stop
worker_main:
    cmp byte [stop], 0
    jne .done
    inc dword [count]
    jmp worker_main
.done:
    xor eax, eax
    ret

m_pre_pass db 'preempt: PASS', 10, 0
m_pre_fail db 'preempt: FAIL (the worker never ran)', 10, 0
m_sleep_pass db 'sleep: PASS', 10, 0
m_sleep_fail db 'sleep: FAIL (woke too early)', 10, 0
m_prio_pass db 'prio: PASS', 10, 0
m_prio_starved db 'prio: FAIL (background ran while a higher priority was busy)', 10, 0
m_prio_fail db 'prio: FAIL (background never ran)', 10, 0

SQX_BSS
count resd 1
worker resd 1
msg resd 1
stop resb 1
SQX_END
