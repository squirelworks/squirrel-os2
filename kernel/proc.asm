; Squirrel-OS/2 — basic process model (0.1.2)
; Included from pm.asm. Original code.
;
; Cooperative round-robin. Slot 0 is the kernel shell (pid 0), which
; runs on the boot stack and never exits. Other slots get a private
; stack and start in proc_trampoline. See documentation/kernel/processes.md.

PROC_MAX        equ 8
PROC_STACK_BASE equ 0x70000     ; slot i stack top = base + i * size
PROC_STACK_SIZE equ 0x2000

; states
P_FREE          equ 0
P_READY         equ 1
P_RUNNING       equ 2
P_WAITING       equ 3           ; blocked in wait()
P_ZOMBIE        equ 4           ; exited, not yet reaped

; PCB layout (32 bytes)
PCB_PID         equ 0
PCB_STATE       equ 4
PCB_ESP         equ 8
PCB_ENTRY       equ 12
PCB_ARG         equ 16
PCB_CODE        equ 20          ; exit code
PCB_WAITPID     equ 24          ; pid this process waits on
PCB_PARENT      equ 28
PCB_SIZE        equ 32

proc_init:
    mov edi, proc_table
    mov ecx, PROC_MAX*PCB_SIZE/4
    xor eax, eax
    rep stosd
    mov dword [proc_table+PCB_STATE], P_RUNNING     ; pid 0 = shell
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
    mov ebx, [proc_cur]
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
    mov eax, [edi+PCB_CODE]
    mov dword [edi+PCB_STATE], P_FREE
    jmp .out
.bad:
    mov eax, -1
.out:
    pop edi
    pop esi
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

; Switches to the next READY process after the current one, round-robin.
; Returns (in the caller's context) when this process is scheduled again.
; If nothing else is READY and the caller can keep running, returns at
; once with CF set; a caller that cannot run (waiting/zombie) with
; nobody READY is a deadlock and panics.
proc_switch:
    pushfd
    cli
    pushad
    mov esi, [proc_cur]
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
    je .go
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
    mov [esi+PCB_ESP], esp
    mov dword [edi+PCB_STATE], P_RUNNING
    mov [proc_cur], edi
    mov esp, [edi+PCB_ESP]
    popad
    popfd
    clc
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
    mov al, 10
    call putc
    pop ecx
.skip:
    add ebx, PCB_SIZE
    loop .row
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
proc_next_pid dd 0
pt_pids times 3 dd 0

state_names dd st_free, st_ready, st_running, st_waiting, st_zombie
st_free db 'free', 0
st_ready db 'ready', 0
st_running db 'running', 0
st_waiting db 'waiting', 0
st_zombie db 'zombie', 0
ps_header db 'PID      STATE', 10, 0
pt_msg db 'worker ', 0
pt_step db ' step ', 0
pt_reaped db 'reaped pid ', 0
pt_code db ' exit code ', 0
panic_deadlock db 10, '*** kernel panic: no runnable process', 10, 0
