; Squirrel-OS/2 — basic process model (0.1.2)
; Included from pm.asm. Original code.
;
; Priority round-robin (1.9.9). Kernel code switches cooperatively; since
; 1.1 the timer also preempts a loaded program whose slice (SLICE_TICKS)
; has run out, but only while the CPU is in the program area, because the
; kernel is not reentrant. Among READY processes the highest PCB_PRIO
; runs; equals take turns. Slot 0 is the kernel shell (pid 0), which
; runs on the boot stack and never exits. Other slots get a private
; stack and start in proc_trampoline. See documentation/kernel/processes.md.

PROC_MAX        equ 8
; Each slot is 12 KB: an unmapped guard page, then an 8 KB stack (KB-17).
; Slot i's stack top is base + i * size, so the guard pages sit at
; base + k * size for k = 0..7; the eighth (k = 7) guards the shell's
; boot stack, which runs from SHELL_STACK down to it.
PROC_STACK_BASE equ 0x7C000     ; slot i stack top = base + i * size
PROC_STACK_SIZE equ 0x3000
PROC_GUARDS     equ PROC_MAX    ; guard pages, one under every stack
SLICE_TICKS     equ 5           ; 50 ms at 100 Hz (1.1)
PRIO_MIN        equ 0
PRIO_NORM       equ 1
PRIO_MAX        equ 3

; states
P_FREE          equ 0
P_READY         equ 1
P_RUNNING       equ 2
P_WAITING       equ 3           ; blocked in wait()
P_ZOMBIE        equ 4           ; exited, not yet reaped

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
PCB_NAME        equ 40          ; 16 bytes: program or app name (0.8.2)
PROC_NAMELEN    equ 16
PCB_PRIO        equ 56          ; 0..3; higher runs first (1.9.9)
PCB_FPU         equ 60          ; 1 once its x87 state has been saved (1.0.1)
FPU_SAVE        equ 108         ; bytes per fnsave area
PCB_SIZE        equ 64

proc_init:
    mov edi, proc_table
    mov ecx, PROC_MAX*PCB_SIZE/4
    xor eax, eax
    rep stosd
    mov dword [proc_table+PCB_STATE], P_RUNNING     ; pid 0 = shell
    mov dword [proc_table+PCB_PRIO], PRIO_NORM
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
    call proc_reap_orphans
.retry:
    mov edi, proc_table+PCB_SIZE
    mov edx, 1                ; slot index
.find:
    cmp dword [edi+PCB_STATE], P_FREE
    je .got
    add edi, PCB_SIZE
    inc edx
    cmp edx, PROC_MAX
    jb .find
    call proc_reclaim_zombie    ; table full: the oldest zombie gives way
    jnc .retry
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
    mov dword [edi+PCB_PRIO], PRIO_NORM
    mov dword [edi+PCB_FPU], 0  ; starts with a freshly reset FPU
    call msg_reset              ; and an empty message queue (1.2)
    mov ebx, [proc_cur]
    push eax
    mov eax, [ebx+PCB_AS]       ; runs in its parent's address space
    mov [edi+PCB_AS], eax
    call as_retain
    pop eax
    mov ebx, [ebx+PCB_PID]
    mov [edi+PCB_PARENT], ebx
    ; initial stack: popad frame (zeros), eflags (IF set), return address
    imul edx, PROC_STACK_SIZE
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
    call proc_wait_cycle        ; would nobody ever wake us?
    jc .bad
    mov esi, [proc_cur]
    mov [esi+PCB_WAITPID], ebx
    mov dword [esi+PCB_STATE], P_WAITING
    call proc_switch
    jmp .again
.reap:
    mov eax, [edi+PCB_CODE]
    call proc_free
    jmp .out
.bad:
    mov eax, -1
.out:
    pop edi
    pop esi
    ret

; edi = PCB the caller is about to wait for. CF if that process is
; itself waiting, directly or through others, for the caller: the wait
; would never end, and with nobody left to run the kernel would panic.
; Keeps every register.
proc_wait_cycle:
    push ebx
    push ecx
    push edi
    mov ecx, PROC_MAX           ; a chain visits each slot at most once
.link:
    cmp dword [edi+PCB_STATE], P_WAITING
    jne .no
    mov ebx, [edi+PCB_WAITPID]
    call proc_find
    test edi, edi
    jz .no
    cmp edi, [proc_cur]
    je .yes
    loop .link
.no:
    clc
    jmp .r
.yes:
    stc
.r:
    pop edi
    pop ecx
    pop ebx
    ret

; edi = zombie PCB: releases its address space and frees the slot
; (eax is kept)
proc_free:
    push eax
    mov eax, [edi+PCB_AS]
    mov dword [edi+PCB_AS], 0
    call as_release
    mov dword [edi+PCB_STATE], P_FREE
    pop eax
    ret

; Frees every zombie whose parent has exited: nobody can wait for it
; any more (1.0.4). A pid is never reused, so a parent is alive only
; if a live, non-zombie slot still carries its pid.
proc_reap_orphans:
    pushad
    mov edi, proc_table
    mov ecx, PROC_MAX
.z:
    cmp dword [edi+PCB_STATE], P_ZOMBIE
    jne .next
    cmp edi, [proc_cur]
    je .next
    mov ebx, [edi+PCB_PARENT]
    push edi
    call proc_find
    mov esi, edi
    pop edi
    test esi, esi
    jz .orphan
    cmp dword [esi+PCB_STATE], P_ZOMBIE
    jne .next
.orphan:
    call proc_free
.next:
    add edi, PCB_SIZE
    loop .z
    popad
    ret

; The process table is full: frees the zombie with the lowest pid (the
; one waited for least recently), so a parent that never waits cannot
; use up the table. A later wait for that pid returns -1. CF if there
; is no zombie to free.
proc_reclaim_zombie:
    pushad
    xor esi, esi                ; best so far
    mov edi, proc_table
    mov ecx, PROC_MAX
.z:
    cmp dword [edi+PCB_STATE], P_ZOMBIE
    jne .next
    cmp edi, [proc_cur]
    je .next
    test esi, esi
    jz .take
    mov eax, [edi+PCB_PID]
    cmp eax, [esi+PCB_PID]
    jae .next
.take:
    mov esi, edi
.next:
    add edi, PCB_SIZE
    loop .z
    test esi, esi
    jz .none
    mov edi, esi
    call proc_free
    popad
    clc
    ret
.none:
    popad
    stc
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

; Switches to a READY process: the highest PCB_PRIO, round-robin among
; equals (1.9.9). Returns (in the caller's context) when this process is
; scheduled again. If nothing else at that priority is READY and the
; caller can keep running, returns at once with CF set; a caller that
; cannot run (waiting/zombie) with nobody READY is a deadlock and panics.
proc_switch:
    pushfd
    cli
    pushad
    mov esi, [proc_cur]
    ; highest priority among READY slots, and the current if RUNNING
    mov ebx, -1
    mov edi, proc_table
    mov ecx, PROC_MAX
.findmax:
    mov eax, [edi+PCB_STATE]
    cmp eax, P_READY
    je .cand
    cmp eax, P_RUNNING
    jne .nmax
    cmp edi, esi
    jne .nmax
.cand:
    mov eax, [edi+PCB_PRIO]
    cmp eax, ebx
    jle .nmax
    mov ebx, eax
.nmax:
    add edi, PCB_SIZE
    loop .findmax
    cmp ebx, -1
    je proc_panic
    mov edi, esi
    mov ecx, PROC_MAX
.scan:
    add edi, PCB_SIZE
    cmp edi, proc_table+PROC_MAX*PCB_SIZE
    jb .inrange
    mov edi, proc_table
.inrange:
    cmp edi, esi
    je .none
    cmp dword [edi+PCB_STATE], P_READY
    jne .next
    cmp [edi+PCB_PRIO], ebx
    je .go
.next:
    loop .scan
.none:
    cmp dword [esi+PCB_STATE], P_RUNNING
    jne proc_panic
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
    mov dword [sched_left], SLICE_TICKS     ; a full slice for the next one
    mov [proc_cur], edi
    call vm_load
    mov esp, [edi+PCB_ESP]
    popad
    popfd
    clc
    ret

; esi = outgoing PCB, edi = incoming: gives each process its own x87
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

; From the timer interrupt (1.1), when a loaded program has used up its
; slice: the same priority switch as a yield. If nothing else at its
; priority is READY the program keeps the CPU for another slice.
proc_preempt:
    mov dword [sched_left], SLICE_TICKS
    inc dword [sched_preempts]
    jmp proc_switch

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
    call proc_reap_orphans      ; (1.0.4)
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
    mov esi, ps_prio
    call puts
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

; ebx = 0..PRIO_MAX -> sets the caller's priority; eax = 0, or -1 if out of range
proc_setprio:
    cmp ebx, PRIO_MAX
    ja .bad
    mov eax, [proc_cur]
    mov [eax+PCB_PRIO], ebx
    xor eax, eax
    ret
.bad:
    mov eax, -1
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
    cmp dword [kbd_wait_hook], 0
    je .idle
    call [kbd_wait_hook]        ; before waiting: e.g. redraw a text window
.idle:
    call proc_idle
    jmp kbd_getscan
.got:
    sti
    ret

proc_table times PROC_MAX*PCB_SIZE db 0
proc_fpu times PROC_MAX*FPU_SAVE db 0     ; fnsave areas, one per slot (1.0.1)
proc_cur dd 0
kbd_wait_hook dd 0              ; called (if set) while kbd_getscan waits
sched_left dd SLICE_TICKS        ; ticks left in the running process's slice (1.1)
sched_preempts dd 0             ; switches made by the timer
proc_next_pid dd 0
pt_pids times 3 dd 0

state_names dd st_free, st_ready, st_running, st_waiting, st_zombie
st_free db 'free', 0
st_ready db 'ready', 0
st_running db 'running', 0
st_waiting db 'waiting', 0
st_zombie db 'zombie', 0
ps_header db 'PID      STATE    NAME              MEMORY', 10, 0
ps_none db '-', 0
proc_shell_name db 'shell', 0
ps_kb db ' KB', 0
ps_kernel db 'kernel', 0
ps_prio db ' prio ', 0
pt_msg db 'worker ', 0
pt_step db ' step ', 0
pt_reaped db 'reaped pid ', 0
pt_code db ' exit code ', 0
panic_deadlock db 10, '*** kernel panic: no runnable process', 10, 0
