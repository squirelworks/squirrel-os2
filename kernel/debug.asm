; Squirrel-OS/2 — kernel debug interface: SYS_DEBUG (A.4)
; Included from pm.asm, in the high image. Original code.
;
; A program (the debugger, programs/debugger.asm) traces another loaded
; program: it starts it stopped at its entry or attaches to a running one,
; reads and writes its registers and memory, plants INT3 breakpoints and
; single-steps it with the trap flag. See documentation/kernel/debug.md.
;
; How a traced process stops: a CPU exception it takes in ring 3 (#DB
; after a single step or a stop request, #BP from an INT3, or a fault)
; goes to exc_report, which calls dbg_trap first. dbg_trap parks the
; process in state P_STOPPED with the exception frame still on its kernel
; stack, wakes the debugger if it waits in DBG_WAIT, and switches away.
; DBG_GETREGS / DBG_SETREGS read and change that frame; DBG_CONT makes the
; process READY again, and it returns to ring 3 through the frame (after a
; fault: the faulting instruction runs again). A traced process is never
; ended by a fault: its debugger decides (DBG_KILL).
;
; Who may trace whom: only a loaded program (an address space of its own)
; is traced, by a process of another address space, one tracer at a time.
; A tracer's tracees are let go (detached, resumed) when it exits.

SYS_DEBUG       equ 45

DBG_ATTACH      equ 0           ; ecx = pid -> 0, or -1
DBG_DETACH      equ 1           ; ecx = pid -> 0, or -1: resumes it untraced
DBG_EXEC        equ 2           ; ecx = file, edx = argument or 0 -> pid stopped at its entry, or LD_E*
DBG_WAIT        equ 3           ; ecx = pid, edx = 0 wait / 1 poll -> reason, -2 ended, -3 running (poll)
DBG_STOP        equ 4           ; ecx = pid -> 0: it stops (reason DBG_R_STOP) when it next runs
DBG_GETREGS     equ 5           ; ecx = pid, edx = DBG_REGS_SIZE buffer -> 0, or -1 when not stopped
DBG_SETREGS     equ 6           ; ecx = pid, edx = DBG_REGS_SIZE buffer -> 0, or -1
DBG_READ        equ 7           ; ecx = pid, edx = {address, buffer, length} -> bytes copied
DBG_WRITE       equ 8           ; ecx = pid, edx = {address, buffer, length} -> bytes copied
DBG_CONT        equ 9           ; ecx = pid, edx = 0 run / 1 one instruction -> 0, or -1
DBG_KILL        equ 10          ; ecx = pid -> 0: it ends with -1 instead of running on
DBG_OPS         equ 11

; stop reasons (DBG_WAIT, DBG_REGS +40): a CPU exception number, or
DBG_R_ENTRY     equ 0x100       ; started by DBG_EXEC, before its first instruction
DBG_R_STOP      equ 0x101       ; after DBG_STOP
DBG_ENDED       equ -2
DBG_RUNNING     equ -3

; register block (DBG_GETREGS / DBG_SETREGS)
DR_EAX          equ 0
DR_EBX          equ 4
DR_ECX          equ 8
DR_EDX          equ 12
DR_ESI          equ 16
DR_EDI          equ 20
DR_EBP          equ 24
DR_ESP          equ 28
DR_EIP          equ 32
DR_EFLAGS       equ 36
DR_REASON       equ 40          ; read only
DR_ERR          equ 44          ; the exception's error code, read only
DR_CR2          equ 48          ; the fault address of a page fault, read only
DBG_REGS_SIZE   equ 52

DBG_XFER_MAX    equ 4096        ; DBG_READ / DBG_WRITE: bytes per call

P_STOPPED       equ 5           ; process state: stopped for its debugger

DBGF_STOP       equ 1           ; stop when it next runs
DBGF_KILL       equ 2           ; end it when it next runs
DBGF_ENTRY      equ 4           ; stop before its first instruction
DBGF_STEPPING   equ 8           ; resumed with the trap flag by DBG_CONT

EFL_TF          equ 0x100
EFL_USER        equ 0x0CD5      ; CF PF AF ZF SF DF OF: what SETREGS may change

; pm.asm, after syscall_init: INT3 may be used from ring 3 (a breakpoint
; is #BP, not a general-protection fault)
dbg_init:
    mov byte [idt+3*8+5], 0xEE  ; interrupt gate, DPL 3
    ret

; ---------- the stop ----------

; exc_report, ebp = its pushad frame (EXC_* offsets in crash.asm), eax =
; what vm_ustack_fault said for a page fault. CF: the process was stopped
; and resumed, return to it through the frame. NC: not traced, report as
; usual (eax kept).
dbg_trap:
    push eax
    call dbg_slot_cur           ; ebx = slot
    jc .no
    mov ecx, [ebp+EXC_VEC]
    lea esi, [ebp+EXC_VEC+4]    ; -> error code or EIP
    xor edx, edx
    mov eax, 1
    shl eax, cl
    test eax, EXC_ERRCODE_MASK
    jz .noerr
    mov edx, [esi]
    add esi, 4
.noerr:
    test byte [esi+4], 3        ; from ring 3 only
    jz .no
    mov eax, ecx
    cmp eax, 1
    jne .stop
    test byte [dbg_flags+ebx], DBGF_STOP
    jz .stop
    mov eax, DBG_R_STOP         ; the trap flag DBG_STOP set
.stop:
    and byte [dbg_flags+ebx], ~(DBGF_STOP|DBGF_STEPPING)
    call dbg_stop
    pop eax
    stc
    ret
.no:
    pop eax
    clc
    ret

; proc_enter_user, just before its iretd to a new program: a program its
; debugger started (or asked to stop) stops here first, with all general
; registers 0. Returns when it is not traced; otherwise it enters ring 3
; itself after the stop. ebx = the current PCB.
dbg_entry:
    push ebx
    call dbg_slot_cur
    jc .no
    test byte [dbg_flags+ebx], DBGF_ENTRY|DBGF_STOP|DBGF_KILL
    jnz .stop
.no:
    pop ebx
    ret
.stop:
    pop eax
    add esp, 4                  ; our return address: the iret frame is on top
    push dword 0                ; where exc_report has the vector
    pushad
    mov edi, esp
    mov ecx, 8
    xor eax, eax
    rep stosd                   ; no kernel values leak into ring 3
    mov ebp, esp
    call dbg_slot_cur
    and byte [dbg_flags+ebx], ~(DBGF_ENTRY|DBGF_STOP)
    lea esi, [ebp+EXC_VEC+4]
    mov eax, DBG_R_ENTRY
    xor edx, edx
    call dbg_stop
    popad
    add esp, 4
    iretd

; ebx = slot, ebp = pushad frame, esi -> EIP of the iret frame, eax =
; reason, edx = error code: parks the current process until its debugger
; lets it go. Ends it if the debugger said so.
dbg_stop:
    test byte [dbg_flags+ebx], DBGF_KILL
    jnz .kill
    mov [dbg_frame+ebx*4], ebp
    mov [dbg_iret+ebx*4], esi
    mov [dbg_reason+ebx*4], eax
    mov [dbg_err+ebx*4], edx
    mov eax, cr2
    mov [dbg_cr2+ebx*4], eax
    and dword [esi+8], ~EFL_TF  ; stopped: no single step pending
    mov edi, [proc_cur]
    mov dword [edi+PCB_STATE], P_STOPPED
    call dbg_wake_tracer
    push ebx
    call proc_switch
    pop ebx
    mov dword [dbg_frame+ebx*4], 0
    test byte [dbg_flags+ebx], DBGF_KILL
    jnz .kill
    ret
.kill:
    mov dword [dbg_tracee+ebx*4], 0
    mov byte [dbg_flags+ebx], 0
    mov ebx, -1
    jmp proc_exit

; ebx = slot of the current process: its tracer, if it waits in DBG_WAIT
; for it, becomes READY
dbg_wake_tracer:
    pushad
    mov edx, [proc_cur]
    mov edx, [edx+PCB_PID]
    push ebx
    mov ebx, [dbg_tracer+ebx*4]
    call proc_find
    pop ebx
    test edi, edi
    jz .r
    cmp dword [edi+PCB_STATE], P_WAITING
    jne .r
    cmp [edi+PCB_WAITPID], edx
    jne .r
    mov dword [edi+PCB_STATE], P_READY
.r:
    popad
    ret

; -> ebx = the current process's slot, CF unless it is traced. Keeps the
; other registers.
dbg_slot_cur:
    push eax
    mov ebx, [proc_cur]
    mov eax, [ebx+PCB_PID]
    sub ebx, proc_table
    shr ebx, 6
    cmp ebx, PROC_MAX
    jae .no
    cmp dword [dbg_tracee+ebx*4], 0
    je .no
    cmp [dbg_tracee+ebx*4], eax
    jne .no
    pop eax
    clc
    ret
.no:
    pop eax
    stc
    ret

; proc_exit, esi = the exiting PCB: lets go of every process it traces
; (each one stopped resumes, untraced). Keeps every register.
dbg_exit:
    pushad
    mov eax, [esi+PCB_PID]
    xor ebx, ebx
.s:
    cmp dword [dbg_tracee+ebx*4], 0
    je .n
    cmp [dbg_tracer+ebx*4], eax
    jne .n
    call dbg_release
.n:
    inc ebx
    cmp ebx, PROC_MAX
    jb .s
    popad
    ret

; ebx = slot of a traced process: no longer traced; stopped, it runs on
dbg_release:
    push eax
    push edi
    mov eax, ebx
    shl eax, 6
    lea edi, [proc_table+eax]
    mov eax, [dbg_tracee+ebx*4]
    mov dword [dbg_tracee+ebx*4], 0
    mov byte [dbg_flags+ebx], 0
    cmp [edi+PCB_PID], eax
    jne .r                      ; the slot has moved on
    call dbg_untrap_top         ; a pending stop request's trap flag
    cmp dword [edi+PCB_STATE], P_STOPPED
    jne .r
    mov eax, [dbg_iret+ebx*4]
    and dword [eax+8], ~EFL_TF
    mov dword [edi+PCB_STATE], P_READY
.r:
    pop edi
    pop eax
    ret

; ---------- SYS_DEBUG ----------

; ebx = DBG_* operation, ecx = pid (or file name), edx = argument
sys_debug:
    cmp ebx, DBG_OPS
    jae .bad
    cmp ebx, DBG_EXEC
    je dbg_exec
    push ebx
    mov ebx, ecx
    call proc_find              ; edi = the target's PCB
    pop ebx
    test edi, edi
    jz .gone
    cmp ebx, DBG_ATTACH
    je dbg_attach
    cmp ebx, DBG_WAIT
    je dbg_wait
    ; every other operation: a process the caller traces
    mov eax, edi
    sub eax, proc_table
    shr eax, 6
    mov esi, [proc_cur]
    mov esi, [esi+PCB_PID]
    cmp [dbg_tracee+eax*4], ecx
    jne .bad
    cmp [dbg_tracer+eax*4], esi
    jne .bad
    xchg eax, ebx               ; ebx = slot, eax = operation
    jmp [.ops+eax*4]
.ops:
    dd .bad, dbg_detach, .bad, .bad, dbg_stopreq, dbg_getregs, dbg_setregs
    dd dbg_read, dbg_write, dbg_cont, dbg_kill
.gone:
    cmp ebx, DBG_WAIT
    jne .bad
    mov eax, DBG_ENDED
    ret
.bad:
    or eax, -1
    ret

; edi = target PCB, ecx = its pid
dbg_attach:
    cmp dword [edi+PCB_STATE], P_ZOMBIE
    je .bad
    mov eax, [edi+PCB_AS]
    test eax, eax
    jz .bad                     ; kernel threads and the shell are not traced
    mov esi, [proc_cur]
    cmp eax, [esi+PCB_AS]
    je .bad                     ; not itself, nor a thread of its own program
    mov eax, edi
    sub eax, proc_table
    shr eax, 6
    cmp [dbg_tracee+eax*4], ecx
    je .bad                     ; somebody traces it already
    mov edx, [esi+PCB_PID]
    test edx, edx
    jz .bad
    call dbg_slot_cur           ; a traced process does not trace its tracer
    jc .ok
    cmp [dbg_tracer+ebx*4], ecx
    je .bad
.ok:
    mov [dbg_tracee+eax*4], ecx
    mov [dbg_tracer+eax*4], edx
    mov byte [dbg_flags+eax], 0
    mov dword [dbg_frame+eax*4], 0
    xor eax, eax
    ret
.bad:
    or eax, -1
    ret

; ecx = file name, edx = argument or 0: loads it like SYS_EXEC, traced
; by the caller and stopped before its first instruction
dbg_exec:
    mov esi, [proc_cur]
    cmp dword [esi+PCB_PID], 0
    je .bad
    mov esi, ecx
    mov edi, edx
    call prog_exec
    test eax, eax
    js .r
    mov ebx, eax
    call proc_find
    test edi, edi
    jz .r
    cmp dword [edi+PCB_AS], 0
    je .r                       ; (cannot happen: a loaded program)
    mov edx, edi
    sub edx, proc_table
    shr edx, 6
    mov [dbg_tracee+edx*4], eax
    mov esi, [proc_cur]
    mov esi, [esi+PCB_PID]
    mov [dbg_tracer+edx*4], esi
    mov byte [dbg_flags+edx], DBGF_ENTRY
    mov dword [dbg_frame+edx*4], 0
.r:
    ret
.bad:
    or eax, -1
    ret

; edi = target PCB, ecx = pid, edx = 1 to poll
dbg_wait:
    mov eax, edi
    sub eax, proc_table
    shr eax, 6
    mov esi, [proc_cur]
    mov ebx, [esi+PCB_PID]
    cmp [dbg_tracee+eax*4], ecx
    jne .notours
    cmp [dbg_tracer+eax*4], ebx
    jne .bad
.again:
    cmp [edi+PCB_PID], ecx
    jne .ended
    cmp dword [edi+PCB_STATE], P_ZOMBIE
    je .ended
    cmp dword [edi+PCB_STATE], P_FREE
    je .ended
    cmp dword [edi+PCB_STATE], P_STOPPED
    je .stopped
    test edx, edx
    jnz .running
    mov [esi+PCB_WAITPID], ecx
    mov dword [esi+PCB_STATE], P_WAITING
    push eax
    call proc_switch
    pop eax
    mov esi, [proc_cur]
    jmp .again
.stopped:
    mov eax, [dbg_reason+eax*4]
    ret
.running:
    mov eax, DBG_RUNNING
    ret
.notours:
    cmp dword [edi+PCB_STATE], P_ZOMBIE
    jne .bad                    ; (DBG_EXIT kept no record: it ended)
    cmp [edi+PCB_PARENT], ebx
    jne .bad
.ended:
    mov eax, DBG_ENDED
    ret
.bad:
    or eax, -1
    ret

; In the operations below: ebx = slot, edi = PCB, ecx = pid, edx = argument.

dbg_detach:
    call dbg_release
    xor eax, eax
    ret

dbg_stopreq:
    cmp dword [edi+PCB_STATE], P_STOPPED
    je .r
    or byte [dbg_flags+ebx], DBGF_STOP
    call dbg_trap_top
.r:
    xor eax, eax
    ret

dbg_kill:
    or byte [dbg_flags+ebx], DBGF_KILL
    cmp dword [edi+PCB_STATE], P_STOPPED
    je .wake
    call dbg_trap_top           ; it ends at its next instruction
    xor eax, eax
    ret
.wake:
    mov dword [edi+PCB_STATE], P_READY
    xor eax, eax
    ret

; edx = 1: one instruction, then it stops again (reason 1)
dbg_cont:
    cmp dword [edi+PCB_STATE], P_STOPPED
    jne dbg_fail
    mov eax, [dbg_iret+ebx*4]
    and dword [eax+8], ~EFL_TF
    test edx, edx
    jz .go
    or dword [eax+8], EFL_TF
    or byte [dbg_flags+ebx], DBGF_STEPPING
.go:
    mov dword [edi+PCB_STATE], P_READY
    xor eax, eax
    ret

dbg_getregs:
    cmp dword [edi+PCB_STATE], P_STOPPED
    jne dbg_fail
    mov esi, [dbg_frame+ebx*4]
    mov eax, [esi+EXC_EAX]
    mov [edx+DR_EAX], eax
    mov eax, [esi+EXC_EBX]
    mov [edx+DR_EBX], eax
    mov eax, [esi+EXC_ECX]
    mov [edx+DR_ECX], eax
    mov eax, [esi+EXC_EDX]
    mov [edx+DR_EDX], eax
    mov eax, [esi+EXC_ESI]
    mov [edx+DR_ESI], eax
    mov eax, [esi+EXC_EDI]
    mov [edx+DR_EDI], eax
    mov eax, [esi+EXC_EBP]
    mov [edx+DR_EBP], eax
    mov esi, [dbg_iret+ebx*4]
    mov eax, [esi]
    mov [edx+DR_EIP], eax
    mov eax, [esi+8]
    mov [edx+DR_EFLAGS], eax
    mov eax, [esi+12]
    mov [edx+DR_ESP], eax
    mov eax, [dbg_reason+ebx*4]
    mov [edx+DR_REASON], eax
    mov eax, [dbg_err+ebx*4]
    mov [edx+DR_ERR], eax
    mov eax, [dbg_cr2+ebx*4]
    mov [edx+DR_CR2], eax
    xor eax, eax
    ret

dbg_setregs:
    cmp dword [edi+PCB_STATE], P_STOPPED
    jne dbg_fail
    mov esi, [dbg_frame+ebx*4]
    mov eax, [edx+DR_EAX]
    mov [esi+EXC_EAX], eax
    mov eax, [edx+DR_EBX]
    mov [esi+EXC_EBX], eax
    mov eax, [edx+DR_ECX]
    mov [esi+EXC_ECX], eax
    mov eax, [edx+DR_EDX]
    mov [esi+EXC_EDX], eax
    mov eax, [edx+DR_ESI]
    mov [esi+EXC_ESI], eax
    mov eax, [edx+DR_EDI]
    mov [esi+EXC_EDI], eax
    mov eax, [edx+DR_EBP]
    mov [esi+EXC_EBP], eax
    mov esi, [dbg_iret+ebx*4]
    mov eax, [edx+DR_EIP]
    mov [esi], eax
    mov eax, [edx+DR_ESP]
    mov [esi+12], eax
    mov eax, [edx+DR_EFLAGS]    ; only the arithmetic flags and DF: IF,
    and eax, EFL_USER           ; IOPL and the rest stay as they are
    and dword [esi+8], ~EFL_USER
    or [esi+8], eax
    xor eax, eax
    ret

dbg_fail:
    or eax, -1
    ret

; edi = target PCB, ebx = its slot: a process that is not running now has
; the ring-3 frame it will return through at the top of its kernel stack.
; Set its trap flag there, so it stops (#DB) after one more instruction.
; A process that never ran has no frame yet: dbg_entry stops it.
dbg_trap_top:
    push eax
    call dbg_kstack_frame
    jc .r
    or dword [eax+8], EFL_TF
.r:
    pop eax
    ret

dbg_untrap_top:
    push eax
    call dbg_kstack_frame
    jc .r
    and dword [eax+8], ~EFL_TF
.r:
    pop eax
    ret

; ebx = slot -> eax -> the EIP of the ring-3 frame at the top of its
; kernel stack, CF when there is none
dbg_kstack_frame:
    mov eax, ebx
    imul eax, PROC_STACK_SIZE
    add eax, PROC_STACK_BASE-20 ; EIP, CS, EFLAGS, ESP, SS
    cmp dword [eax+4], USER_CS
    jne .no
    cmp dword [eax+16], USER_DS
    jne .no
    clc
    ret
.no:
    stc
    ret

; DBG_READ / DBG_WRITE: edx -> {address in the target, buffer of the
; caller, length}. Copies page by page through the target's page tables
; (its user pages only) and stops at the first page it may not touch.
; -> eax = bytes copied
dbg_read:
    xor ebp, ebp
    jmp dbg_xfer
dbg_write:
    mov ebp, 1
dbg_xfer:
    mov esi, [edi+PCB_AS]
    mov [dbg_x_as], esi
    mov esi, [edx]              ; target address
    mov ebx, [edx+4]            ; caller's buffer
    mov ecx, [edx+8]
    cmp ecx, DBG_XFER_MAX
    jbe .len
    mov ecx, DBG_XFER_MAX
.len:
    xor edx, edx                ; copied so far
.page:
    test ecx, ecx
    jz .done
    mov eax, esi
    call dbg_xlat               ; eax = physical address
    jc .done
    mov edi, PAGE_SIZE
    mov eax, esi
    and eax, PAGE_SIZE-1
    sub edi, eax                ; bytes left in this page
    cmp edi, ecx
    jbe .n
    mov edi, ecx
.n:
    push ecx
    push esi
    mov ecx, edi
    mov eax, esi
    call dbg_xlat
    test ebp, ebp
    jnz .w
    mov esi, eax                ; target -> caller
    mov edi, ebx
    jmp .copy
.w:
    mov esi, ebx                ; caller -> target
    mov edi, eax
.copy:
    add ebx, ecx
    add edx, ecx
    mov eax, ecx
    rep movsb
    pop esi
    pop ecx
    add esi, eax
    sub ecx, eax
    jmp .page
.done:
    mov eax, edx
    ret

; eax = an address in the address space dbg_x_as -> eax = where the
; kernel reaches it (identity-mapped physical address), CF if it is not
; a present user page there. Keeps the other registers.
dbg_xlat:
    push ebx
    push edx
    mov edx, eax
    mov ebx, [dbg_x_as]
    mov ebx, [ebx+AS_PD]
    shr eax, 22
    mov eax, [ebx+eax*4]
    test eax, PG_P
    jz .no
    test eax, PG_U
    jz .no
    test eax, PG_PS
    jnz .no
    and eax, -PAGE_SIZE
    mov ebx, edx
    shr ebx, 12
    and ebx, 1023
    mov eax, [eax+ebx*4]
    test eax, PG_P
    jz .no
    test eax, PG_U
    jz .no
    and eax, -PAGE_SIZE
    cmp eax, MM_LIMIT
    jae .no
    and edx, PAGE_SIZE-1
    or eax, edx
    pop edx
    pop ebx
    clc
    ret
.no:
    pop edx
    pop ebx
    stc
    ret

; ring-3 pointer checks for SYS_DEBUG (sys_uargs, kind UA_DEBUG):
; ebx = operation, ecx, edx = its arguments -> CF if a pointer is bad
dbg_uargs:
    pushad
    cmp ebx, DBG_EXEC
    je .exec
    cmp ebx, DBG_GETREGS
    je .regs
    cmp ebx, DBG_SETREGS
    je .regs
    cmp ebx, DBG_READ
    je .xfer
    cmp ebx, DBG_WRITE
    je .xfer
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
.regs:
    mov esi, edx
    mov ecx, DBG_REGS_SIZE
    call ua_range
    jc .bad
    jmp .ok
.xfer:
    mov esi, edx
    mov ecx, 12
    call ua_range
    jc .bad
    mov esi, [edx+4]
    mov ecx, [edx+8]
    cmp ecx, DBG_XFER_MAX
    jbe .x
    mov ecx, DBG_XFER_MAX
.x:
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

dbg_tracee times PROC_MAX dd 0  ; per slot: pid of the traced process there, 0 = none
dbg_tracer times PROC_MAX dd 0  ; and the pid that traces it
dbg_frame times PROC_MAX dd 0   ; while stopped: its pushad frame
dbg_iret times PROC_MAX dd 0    ; and the EIP of its ring-3 iret frame
dbg_reason times PROC_MAX dd 0
dbg_err times PROC_MAX dd 0
dbg_cr2 times PROC_MAX dd 0
dbg_flags times PROC_MAX db 0   ; DBGF_*
dbg_x_as dd 0
