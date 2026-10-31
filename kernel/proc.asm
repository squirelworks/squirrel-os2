; Squirrel-OS/2 — basic process model (0.1.2)
; Included from pm.asm. Original code.
;
; Round-robin within priorities. Slot 0 is the kernel shell (pid 0),
; which runs on the boot stack and never exits. Other slots get a private
; stack and start in proc_trampoline. Since 1.1 the timer also preempts
; loaded programs (see proc_preempt); everything else still switches only
; when it yields or blocks. See documentation/kernel/processes.md.

PROC_MAX        equ 8
PROC_STACK_BASE equ 0x70000     ; slot i stack top = base + i * size
PROC_STACK_SIZE equ 0x2000

; states
P_FREE          equ 0
P_READY         equ 1
P_RUNNING       equ 2
P_WAITING       equ 3           ; blocked in wait()
P_ZOMBIE        equ 4           ; exited, not yet reaped
P_SLEEPING      equ 5           ; in SYS_SLEEP until PCB_WAKE (1.1)

PRIO_MIN        equ 0           ; background
PRIO_NORMAL     equ 1           ; the default
PRIO_MAX        equ 3
SLICE_TICKS     equ 5           ; 50 ms at the PIT's 100 Hz
FPU_SAVE        equ 108         ; fnsave area

; PCB layout (64 bytes)
PCB_PID         equ 0
PCB_STATE       equ 4
PCB_ESP         equ 8
PCB_ENTRY       equ 12
PCB_ARG         equ 16
PCB_CODE        equ 20          ; exit code
PCB_WAITPID     equ 24          ; pid this process waits on
PCB_PARENT      equ 28
PCB_AS          equ 32          ; address space record, 0 = the kernel's
PCB_PRIO        equ 36          ; PRIO_MIN..PRIO_MAX (1.1)
PCB_NAME        equ 40          ; 16 bytes: program or app name (0.8.2)
PCB_WAKE        equ 56          ; tick to wake at, while P_SLEEPING (1.1)
PCB_FPU         equ 60          ; 1 once its FPU state has been saved (1.1)
PROC_NAMELEN    equ 16
PCB_SIZE        equ 64

proc_init:
    mov edi, proc_table
    mov ecx, PROC_MAX*PCB_SIZE/4
    xor eax, eax
    rep stosd
    mov dword [proc_table+PCB_STATE], P_RUNNING     ; pid 0 = shell
    mov dword [proc_table+PCB_PRIO], PRIO_NORMAL
    mov dword [sched_left], SLICE_TICKS
    mov esi, proc_shell_name
    mov edi, proc_table
    call proc_set_name
    mov dword [proc_cur], proc_table
    mov dword [proc_next_pid], 1
    ret

; ebx = entry, ecx = arg -> eax = pid, or -1 if the table is full.
; The entry is called as entry(arg) with the cdecl convention; its
; return value becomes the exit code.
proc_spawn:
    push ebx
    push ecx
    push edx
    push edi
    mov edi, proc_table+PCB_SIZE
    mov edx, 1                ; slot index
.find:
    cmp dword [edi+PCB_STATE], P_FREE
    je .got
    add edi, PCB_SIZE
    inc edx
    cmp edx, PROC_MAX
    jb .find
    mov eax, -1
    jmp .out
.got:
    mov eax, [proc_next_pid]
    inc dword [proc_next_pid]
    mov [edi+PCB_PID], eax
    mov [edi+PCB_ENTRY], ebx
    mov [edi+PCB_ARG], ecx
    mov dword [edi+PCB_CODE], 0
    mov dword [edi+PCB_WAITPID], 0
    mov byte [edi+PCB_NAME], 0
    mov dword [edi+PCB_FPU], 0
    mov ebx, [proc_cur]
    push dword [ebx+PCB_PRIO]   ; same priority as its parent
    pop dword [edi+PCB_PRIO]
    push eax
    mov eax, [ebx+PCB_AS]       ; runs in its parent's address space
    mov [edi+PCB_AS], eax
    call as_retain
    pop eax
    mov ebx, [ebx+PCB_PID]
    mov [edi+PCB_PARENT], ebx
    ; initial stack: popad frame (zeros), eflags (IF set), return address
    shl edx, 13               ; * PROC_STACK_SIZE
    add edx, PROC_STACK_BASE
    sub edx, 4
    mov dword [edx], proc_trampoline
    sub edx, 4
    mov dword [edx], 0x202
    sub edx, 32
    push eax
    push edi
    mov edi, edx
    mov ecx, 8
    xor eax, eax
    rep stosd
    pop edi
    pop eax
    mov [edi+PCB_ESP], edx
    mov dword [edi+PCB_STATE], P_READY
.out:
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

proc_trampoline:
    mov ebx, [proc_cur]
    push dword [ebx+PCB_ARG]
    call [ebx+PCB_ENTRY]
    add esp, 4
    mov ebx, eax
    ; fall through
; ebx = exit code. Does not return.
proc_exit:
    cli
    mov esi, [proc_cur]
    mov [esi+PCB_CODE], ebx
    mov dword [esi+PCB_STATE], P_ZOMBIE
    mov eax, [esi+PCB_PID]
    mov edi, proc_table
    mov ecx, PROC_MAX
.wake:
    cmp dword [edi+PCB_STATE], P_WAITING
    jne .next
    cmp [edi+PCB_WAITPID], eax
    jne .next
    mov dword [edi+PCB_STATE], P_READY
.next:
    add edi, PCB_SIZE
    loop .wake
    call proc_switch
    jmp proc_panic            ; a zombie is never scheduled again

; ebx = pid -> eax = its exit code (slot is freed), or -1 if there is
; no such process or it is the caller.
proc_wait:
    push esi
    push edi
.again:
    call proc_find
    test edi, edi
    jz .bad
    cmp edi, [proc_cur]
    je .bad
    cmp dword [edi+PCB_STATE], P_ZOMBIE
    je .reap
    mov esi, [proc_cur]
    mov [esi+PCB_WAITPID], ebx
    mov dword [esi+PCB_STATE], P_WAITING
    call proc_switch
    jmp .again
.reap:
    mov eax, [edi+PCB_AS]
    mov dword [edi+PCB_AS], 0
    call as_release
    mov eax, [edi+PCB_CODE]
    mov dword [edi+PCB_STATE], P_FREE
    jmp .out
.bad:
    mov eax, -1
.out:
    pop edi
    pop esi
    ret

; esi = name, edi = PCB: names the process (cut to 15 characters)
proc_set_name:
    push eax
    push ecx
    push esi
    push edi
    add edi, PCB_NAME
    mov ecx, PROC_NAMELEN-1
.c:
    lodsb
    test al, al
    jz .z
    stosb
    loop .c
.z:
    mov byte [edi], 0
    pop edi
    pop esi
    pop ecx
    pop eax
    ret

; ebx = pid -> edi = PCB or 0
proc_find:
    mov edi, proc_table
    push ecx
    mov ecx, PROC_MAX
.f:
    cmp dword [edi+PCB_STATE], P_FREE
    je .n
    cmp [edi+PCB_PID], ebx
    je .hit
.n:
    add edi, PCB_SIZE
    loop .f
    xor edi, edi
.hit:
    pop ecx
    ret

; Switches to the READY process with the highest priority, taking the
; first one after the current process among equals (round-robin).
; Returns (in the caller's context) when this process is scheduled again.
; If nothing else is READY and the caller can keep running, returns at
; once with CF set. A caller that cannot run (waiting, sleeping, zombie)
; waits here for a sleeper to wake; with no sleepers that is a deadlock
; and panics.
proc_switch:
    pushfd
    cli
    pushad
    mov dword [sched_floor], PRIO_MIN
sched_pick:                     ; (proc_preempt enters here with a floor)
    call proc_wake_sleepers
    mov esi, [proc_cur]
    mov edi, esi
    xor edx, edx                ; best so far
    mov ecx, PROC_MAX
.scan:
    add edi, PCB_SIZE
    cmp edi, proc_table+PROC_MAX*PCB_SIZE
    jb .inrange
    mov edi, proc_table
.inrange:
    cmp edi, esi
    je .scanned
    cmp dword [edi+PCB_STATE], P_READY
    jne .next
    test edx, edx
    jz .better
    mov eax, [edi+PCB_PRIO]
    cmp eax, [edx+PCB_PRIO]
    jbe .next
.better:
    mov edx, edi
.next:
    loop .scan
.scanned:
    test edx, edx
    jz .none
    mov eax, [edx+PCB_PRIO]
    cmp eax, [sched_floor]
    jb .none
    mov edi, edx
    jmp .go
.none:
    cmp dword [esi+PCB_STATE], P_READY
    jne .notready
    mov dword [esi+PCB_STATE], P_RUNNING   ; a sleeper that just woke
.notready:
    cmp dword [esi+PCB_STATE], P_RUNNING
    je .stay
    call proc_any_sleeper       ; nothing can run until a sleeper wakes
    jnc proc_panic
    sti
    hlt
    cli
    jmp sched_pick
.stay:
    popad
    popfd
    stc
    ret
.go:
    cmp dword [esi+PCB_STATE], P_RUNNING
    jne .keep
    mov dword [esi+PCB_STATE], P_READY
.keep:
    call proc_fpu_swap
    mov [esi+PCB_ESP], esp
    mov dword [edi+PCB_STATE], P_RUNNING
    mov dword [sched_left], SLICE_TICKS
    mov [proc_cur], edi
    call vm_load
    mov esp, [edi+PCB_ESP]
    popad
    popfd
    clc
    ret

; From the timer interrupt, when the current process's slice is used up
; in a loaded program: switches only to a READY process of at least the
; same priority, so a busy program cannot keep its equals from running.
proc_preempt:
    pushfd
    cli
    pushad
    inc dword [sched_preempts]
    mov eax, [proc_cur]
    mov eax, [eax+PCB_PRIO]
    mov [sched_floor], eax
    jmp sched_pick

; Marks sleepers whose time has come READY.
proc_wake_sleepers:
    push eax
    push ecx
    push edi
    mov edi, proc_table
    mov ecx, PROC_MAX
    mov eax, [ticks]
.l:
    cmp dword [edi+PCB_STATE], P_SLEEPING
    jne .n
    cmp eax, [edi+PCB_WAKE]
    jb .n
    mov dword [edi+PCB_STATE], P_READY
.n:
    add edi, PCB_SIZE
    loop .l
    pop edi
    pop ecx
    pop eax
    ret

; -> CF if some process is sleeping
proc_any_sleeper:
    push ecx
    push edi
    mov edi, proc_table
    mov ecx, PROC_MAX
.l:
    cmp dword [edi+PCB_STATE], P_SLEEPING
    je .yes
    add edi, PCB_SIZE
    loop .l
    clc
    jmp .r
.yes:
    stc
.r:
    pop edi
    pop ecx
    ret

; esi = outgoing PCB, edi = incoming: gives each process its own FPU
; registers (a freshly reset FPU for one that never had them saved)
proc_fpu_swap:
    mov eax, esi
    call proc_fpu_area
    fnsave [eax]
    mov dword [esi+PCB_FPU], 1
    mov eax, edi
    call proc_fpu_area
    cmp dword [edi+PCB_FPU], 0
    je .fresh
    frstor [eax]
    ret
.fresh:
    fninit
    ret

; eax = PCB -> eax = its FPU save area
proc_fpu_area:
    sub eax, proc_table
    shr eax, 6                  ; / PCB_SIZE
    imul eax, FPU_SAVE
    add eax, proc_fpu
    ret

; ebx = ticks (10 ms each): sleeps at least that long; 0 just yields
proc_sleep:
    test ebx, ebx
    jz proc_idle
    push eax
    push esi
    cli
    mov esi, [proc_cur]
    mov eax, [ticks]
    add eax, ebx
    mov [esi+PCB_WAKE], eax
    mov dword [esi+PCB_STATE], P_SLEEPING
    call proc_switch
    sti
    pop esi
    pop eax
    ret

; ebx = pid (0 = the caller), ecx = priority -> eax = 0, or -1 if there
; is no such process or the priority is out of range
proc_setprio:
    cmp ecx, PRIO_MAX
    ja .bad
    push edi
    mov edi, [proc_cur]
    test ebx, ebx
    jz .set
    call proc_find
    test edi, edi
    jz .nopid
.set:
    mov [edi+PCB_PRIO], ecx
    pop edi
    xor eax, eax
    ret
.nopid:
    pop edi
.bad:
    mov eax, -1
    ret

; Let others run; if nobody else is READY, sleep until an interrupt.
proc_idle:
    call proc_switch
    jnc .ran
    sti
    hlt
.ran:
    ret

proc_panic:
    cli
    mov esi, panic_deadlock
    call puts
.h:
    hlt
    jmp .h

; ---------- shell commands ----------
; ps: list live processes
cmd_ps_run:
    mov esi, ps_header
    call puts
    mov ebx, proc_table
    mov ecx, PROC_MAX
.row:
    mov eax, [ebx+PCB_STATE]
    cmp eax, P_FREE
    je .skip
    push ecx
    mov eax, [ebx+PCB_PID]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 9
    call puts_pad
    mov eax, [ebx+PCB_STATE]
    mov esi, [state_names+eax*4]
    call puts
    mov al, 18
    call puts_pad
    lea esi, [ebx+PCB_NAME]
    cmp byte [esi], 0
    jne .named
    mov esi, ps_none
.named:
    call puts
    mov al, 36
    call puts_pad
    mov eax, [ebx+PCB_AS]
    test eax, eax
    jz .kernel
    mov eax, [eax+AS_PAGES]
    shl eax, 2
    call itoa
    mov esi, num_buf
    call puts
    mov esi, ps_kb
    call puts
    jmp .eol
.kernel:
    mov esi, ps_kernel
    call puts
.eol:
    mov al, 46
    call puts_pad
    mov eax, [ebx+PCB_PRIO]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    pop ecx
.skip:
    add ebx, PCB_SIZE
    dec ecx
    jnz .row
    ret

; sched: how processes are scheduled, and the counters (1.1)
cmd_sched_run:
    mov esi, sc_m_mode
    call puts
    mov esi, sc_m_preempt
    cmp byte [sched_on], 0
    jne .m
    mov esi, sc_m_coop
.m:
    call puts
    mov esi, sc_m_ticks
    call puts
    mov eax, [ticks]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, sc_m_count
    call puts
    mov eax, [sched_preempts]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    jmp putc

; sched coop | sched preempt
cmd_sched_set:
    call next_word
    mov edi, sc_w_coop
    call streq
    je .coop
    mov edi, sc_w_preempt
    call streq
    je .pre
    mov esi, sc_m_usage
    jmp puts
.coop:
    mov byte [sched_on], 0
    jmp cmd_sched_run
.pre:
    mov byte [sched_on], 1
    jmp cmd_sched_run

; prio <pid> <0-3>
cmd_prio_run:
    call next_word              ; esi = pid, edi = the rest
    call parse_uint
    jc .usage
    mov ebx, eax
    mov esi, edi
    call next_word
    call parse_uint
    jc .usage
    mov ecx, eax
    call proc_setprio
    test eax, eax
    jnz .bad
    mov esi, fs_ok
    jmp puts
.bad:
    mov esi, sc_m_noproc
    jmp puts
.usage:
    mov esi, sc_m_prio
    jmp puts

; esi = decimal digits -> eax = value, CF if empty or not a number
parse_uint:
    push ebx
    push esi
    xor eax, eax
    cmp byte [esi], 0
    je .bad
.l:
    movzx ebx, byte [esi]
    test ebx, ebx
    jz .ok
    sub ebx, '0'
    cmp ebx, 9
    ja .bad
    imul eax, 10
    add eax, ebx
    inc esi
    jmp .l
.ok:
    pop esi
    pop ebx
    clc
    ret
.bad:
    pop esi
    pop ebx
    stc
    ret

; prints spaces until the cursor column is >= al
puts_pad:
    push eax
    push ebx
    push edx
    movzx ebx, al
.p:
    call con_column
    cmp eax, ebx
    jae .d
    mov al, ' '
    call putc
    jmp .p
.d:
    pop edx
    pop ebx
    pop eax
    ret

; proctest: three workers interleave via yield; the shell waits for each.
cmd_proctest_run:
    mov dword [pt_pids], 0
    mov ecx, 1
.spawn:
    mov eax, SYS_SPAWN
    mov ebx, pt_worker
    int SYSCALL_VEC
    mov [pt_pids+ecx*4-4], eax
    inc ecx
    cmp ecx, 4
    jb .spawn
    mov ecx, 1
.wait:
    mov eax, SYS_WAIT
    mov ebx, [pt_pids+ecx*4-4]
    int SYSCALL_VEC
    push eax
    mov esi, pt_reaped
    call puts
    mov eax, ebx
    call itoa
    mov esi, num_buf
    call puts
    mov esi, pt_code
    call puts
    pop eax
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    inc ecx
    cmp ecx, 4
    jb .wait
    ret

; worker(n): prints three steps, yielding between them; exits with n*10
pt_worker:
    mov edx, [esp+4]
    mov ecx, 1
.step:
    mov eax, SYS_PUTS
    mov ebx, pt_msg
    int SYSCALL_VEC
    mov eax, edx
    call itoa
    mov eax, SYS_PUTS
    mov ebx, num_buf
    int SYSCALL_VEC
    mov eax, SYS_PUTS
    mov ebx, pt_step
    int SYSCALL_VEC
    mov eax, ecx
    call itoa
    mov eax, SYS_PUTS
    mov ebx, num_buf
    int SYSCALL_VEC
    mov eax, SYS_PUTC
    mov ebx, 10
    int SYSCALL_VEC
    mov eax, SYS_YIELD
    int SYSCALL_VEC
    inc ecx
    cmp ecx, 4
    jb .step
    mov eax, edx
    imul eax, 10
    ret

; Hosts an app as a process: arg = the app's start routine, which runs
; its own key loop and returns when the app quits.
app_host:
    jmp [esp+4]

; Blocking raw scancode read; lets other processes run while waiting.
kbd_getscan:
    cli
    call kbd_dequeue
    jnc .got
    sti
    call proc_idle
    jmp kbd_getscan
.got:
    sti
    ret

proc_table times PROC_MAX*PCB_SIZE db 0
proc_cur dd 0
sched_floor dd 0                ; lowest priority a switch may pick
sched_left dd 0                 ; ticks left in the current slice
sched_preempts dd 0             ; preemptions so far
sched_on db 1                   ; 0: cooperative only ("sched coop")
align 4
proc_fpu times PROC_MAX*FPU_SAVE db 0
proc_next_pid dd 0
pt_pids times 3 dd 0

state_names dd st_free, st_ready, st_running, st_waiting, st_zombie, st_sleeping
st_free db 'free', 0
st_ready db 'ready', 0
st_running db 'running', 0
st_waiting db 'waiting', 0
st_zombie db 'zombie', 0
st_sleeping db 'sleeping', 0
ps_header db 'PID      STATE    NAME              MEMORY    PRIO', 10, 0
ps_none db '-', 0
proc_shell_name db 'shell', 0
ps_kb db ' KB', 0
ps_kernel db 'kernel', 0
pt_msg db 'worker ', 0
pt_step db ' step ', 0
pt_reaped db 'reaped pid ', 0
pt_code db ' exit code ', 0
sc_m_mode db 'Scheduler: ', 0
sc_m_preempt db 'preemptive (loaded programs, 50 ms slices), priorities 0-3', 10, 0
sc_m_coop db 'cooperative (switches only on yield or block), priorities 0-3', 10, 0
sc_m_ticks db 'Ticks: ', 0
sc_m_count db '  Preemptions: ', 0
sc_m_usage db 'Usage: sched [coop|preempt]', 10, 0
sc_m_prio db 'Usage: prio <pid> <0-3>', 10, 0
sc_m_noproc db 'No such process, or priority above 3', 10, 0
sc_w_coop db 'coop', 0
sc_w_preempt db 'preempt', 0
panic_deadlock db 10, '*** kernel panic: no runnable process', 10, 0
