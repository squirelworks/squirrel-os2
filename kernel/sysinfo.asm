; Squirrel-OS/2 — system information for programs: GUI_SYSINFO (A.5)
; Included from pm.asm, after appsys.asm (section .high). Original code.
;
; What the system monitor (programs/sysmon.asm) and the log viewer
; (programs/logview.asm) read:
;   - CPU time: the timer counts each tick for the process that was
;     running, or as idle time when proc_idle had halted the CPU
;     (sysinfo_tick, called from timer_isr);
;   - the kernel log: a ring of text lines, "[seconds] what happened",
;     written at boot, when a program starts, ends or crashes (klog_*);
;   - GUI_SYSINFO (SYS_GUI operation 12) copies a snapshot of these, the
;     process table and the page counts to the caller, and sets another
;     process's priority. See documentation/kernel/syscalls.md.

SI_PART_SYS     equ 0           ; ecx = buffer (SI_SYS_SIZE bytes)
SI_PART_PROCS   equ 1           ; ecx = buffer (PROC_MAX * SI_ROW bytes)
SI_PART_LOG     equ 2           ; ecx = buffer (KLOG_SIZE bytes) -> bytes copied
SI_PART_PRIO    equ 3           ; ecx = pid | priority << 16 -> 0, or -1

; SI_PART_SYS block
SI_TICKS        equ 0           ; timer ticks since boot (100 a second)
SI_IDLE         equ 4           ; of them, ticks with the CPU halted
SI_PAGES        equ 8           ; 4 KB pages of RAM the kernel manages
SI_FREE         equ 12          ; of them, free
SI_PROCS        equ 16          ; process slots in use
SI_SLOTS        equ 20          ; PROC_MAX
SI_SWITCHES     equ 24          ; preemptions by the timer
SI_LOGLEN       equ 28          ; bytes in the kernel log
SI_SYS_SIZE     equ 32

; SI_PART_PROCS rows, one per slot (state P_FREE: an unused slot)
SI_PID          equ 0
SI_STATE        equ 4
SI_PRIO         equ 8
SI_PARENT       equ 12
SI_KB           equ 16          ; memory of its own address space, -1: the kernel's
SI_CPU          equ 20          ; ticks it has run
SI_NAME         equ 24          ; 16 bytes
SI_ROW          equ 40

KLOG_SIZE       equ 4096

%if PCB_SIZE != 64
%error sysinfo_tick assumes 64-byte PCBs
%endif

; timer_isr: one tick for whoever had the CPU. Keeps every register but eax.
sysinfo_tick:
    cmp byte [proc_idling], 0
    jne .idle
    mov eax, [proc_cur]
    sub eax, proc_table
    shr eax, 6
    cmp eax, PROC_MAX
    jae .r
    inc dword [proc_cpu+eax*4]
.r:
    ret
.idle:
    inc dword [idle_ticks]
    ret

; ecx = buffer or argument, edx = part
gui_sysinfo:
    cmp edx, SI_PART_SYS
    je .sys
    cmp edx, SI_PART_PROCS
    je .procs
    cmp edx, SI_PART_LOG
    je .log
    cmp edx, SI_PART_PRIO
    je .prio
    or eax, -1
    ret
.sys:
    mov edi, ecx
    mov eax, [ticks]
    mov [edi+SI_TICKS], eax
    mov eax, [idle_ticks]
    mov [edi+SI_IDLE], eax
    mov eax, [mm_total]
    mov [edi+SI_PAGES], eax
    mov eax, [mm_free]
    mov [edi+SI_FREE], eax
    xor eax, eax
    mov esi, proc_table
    mov edx, PROC_MAX
.count:
    cmp dword [esi+PCB_STATE], P_FREE
    je .c1
    inc eax
.c1:
    add esi, PCB_SIZE
    dec edx
    jnz .count
    mov [edi+SI_PROCS], eax
    mov dword [edi+SI_SLOTS], PROC_MAX
    mov eax, [sched_preempts]
    mov [edi+SI_SWITCHES], eax
    mov eax, [klog_len]
    mov [edi+SI_LOGLEN], eax
    xor eax, eax
    ret
.procs:
    mov edi, ecx
    mov esi, proc_table
    xor edx, edx
.row:
    mov eax, [esi+PCB_PID]
    mov [edi+SI_PID], eax
    mov eax, [esi+PCB_STATE]
    mov [edi+SI_STATE], eax
    mov eax, [esi+PCB_PRIO]
    mov [edi+SI_PRIO], eax
    mov eax, [esi+PCB_PARENT]
    mov [edi+SI_PARENT], eax
    mov eax, [esi+PCB_AS]
    test eax, eax
    jz .kern
    mov eax, [eax+AS_PAGES]
    shl eax, 2
    jmp .kb
.kern:
    or eax, -1
.kb:
    mov [edi+SI_KB], eax
    mov eax, [proc_cpu+edx*4]
    mov [edi+SI_CPU], eax
    push esi
    push edi
    add esi, PCB_NAME
    add edi, SI_NAME
    mov ecx, PROC_NAMELEN / 4
    rep movsd
    pop edi
    pop esi
    mov byte [edi+SI_NAME+PROC_NAMELEN-1], 0
    add esi, PCB_SIZE
    add edi, SI_ROW
    inc edx
    cmp edx, PROC_MAX
    jb .row
    xor eax, eax
    ret
.log:
    mov edi, ecx
    mov esi, klog_buf
    mov ecx, [klog_len]
    mov eax, ecx
    rep movsb
    ret
.prio:                          ; another process's priority
    mov ebx, ecx
    shr ebx, 16
    cmp ebx, PRIO_MAX
    ja .no
    and ecx, 0xFFFF
    mov esi, proc_table
    mov edx, PROC_MAX
.find:
    cmp dword [esi+PCB_STATE], P_FREE
    je .f1
    cmp dword [esi+PCB_STATE], P_ZOMBIE
    je .f1
    cmp [esi+PCB_PID], ecx
    jne .f1
    mov [esi+PCB_PRIO], ebx
    xor eax, eax
    ret
.f1:
    add esi, PCB_SIZE
    dec edx
    jnz .find
.no:
    or eax, -1
    ret

; Ring-3 pointer check for GUI_SYSINFO: ecx = buffer, edx = part -> CF
gui_sysinfo_uargs:
    mov esi, ecx
    mov ecx, SI_SYS_SIZE
    cmp edx, SI_PART_SYS
    je .range
    mov ecx, PROC_MAX * SI_ROW
    cmp edx, SI_PART_PROCS
    je .range
    mov ecx, KLOG_SIZE
    cmp edx, SI_PART_LOG
    je .range
    clc                         ; the others take no buffer
    ret
.range:
    jmp ua_range

; ---------- the kernel log ----------
; esi = text -> the log
klog_str:
    push eax
    push esi
.c:
    lodsb
    test al, al
    jz .r
    call klog_char
    jmp .c
.r:
    pop esi
    pop eax
    ret

; eax = number (unsigned) -> the log
klog_num:
    push eax
    push ebx
    push ecx
    push edx
    mov ebx, 10
    xor ecx, ecx
.d:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    test eax, eax
    jnz .d
.p:
    pop eax
    add al, '0'
    call klog_char
    loop .p
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

klog_char:
    push edi
    mov edi, [klog_len]
    cmp edi, KLOG_SIZE
    jae .r                      ; (klog_room keeps a line's worth free)
    mov [klog_buf+edi], al
    inc dword [klog_len]
.r:
    pop edi
    ret

; at least 128 bytes free: the oldest lines go
klog_room:
.again:
    mov ecx, [klog_len]
    cmp ecx, KLOG_SIZE - 128
    jbe .r
    mov esi, klog_buf           ; the first line's length
    xor edx, edx
.l:
    cmp edx, ecx
    jae .all
    inc edx
    cmp byte [esi+edx-1], 10
    jne .l
    mov edi, klog_buf
    lea esi, [klog_buf+edx]
    sub ecx, edx
    mov [klog_len], ecx
    rep movsb
    jmp .again
.all:
    mov dword [klog_len], 0
.r:
    ret

; esi = what, edi = PCB: "what NAME (pid N)" or "what pid N"
klog_proc:
    pushad
    pushfd
    cli
    call klog_room
    call klog_head
    call klog_str
    lea esi, [edi+PCB_NAME]
    cmp byte [esi], 0
    je .anon
    call klog_str
    mov esi, klog_pid_b
    call klog_str
    mov eax, [edi+PCB_PID]
    call klog_num
    mov al, ')'
    call klog_char
    jmp .tail
.anon:
    mov esi, klog_pid
    call klog_str
    mov eax, [edi+PCB_PID]
    call klog_num
.tail:
    popfd
    popad
    ret

; the time stamp: "[seconds] "
klog_head:
    mov al, '['
    call klog_char
    mov eax, [ticks]
    xor edx, edx
    mov ebx, 100
    div ebx
    push edx
    call klog_num
    mov al, '.'
    call klog_char
    pop eax
    cmp eax, 10
    jae .two
    push eax
    mov al, '0'
    call klog_char
    pop eax
.two:
    call klog_num
    mov al, ']'
    call klog_char
    mov al, ' '
    jmp klog_char

; a program starts: edi = its PCB
klog_start:
    push esi
    mov esi, klog_m_start
    call klog_proc
    mov esi, klog_nl
    call klog_more
    pop esi
    ret

; proc_exit: esi = the PCB, ebx = the exit code
klog_exit:
    pushad
    mov edi, esi
    mov esi, klog_m_end
    call klog_proc
    mov esi, klog_m_code
    call klog_more
    mov eax, ebx
    test eax, eax
    jns .pos
    neg eax
    push esi
    mov esi, klog_minus
    call klog_more
    pop esi
.pos:
    pushfd
    cli
    call klog_num
    mov al, 10
    call klog_char
    popfd
    popad
    ret

; exc_report, before it ends a program: esi = the exception's name
klog_crash:
    pushad
    push esi
    mov edi, [proc_cur]
    mov esi, klog_m_crash
    call klog_proc
    pop esi
    mov eax, esi
    mov esi, klog_colon
    call klog_more
    mov esi, eax
    call klog_more
    mov esi, klog_nl
    call klog_more
    popad
    ret

; esi = text, more of the current line
klog_more:
    pushfd
    cli
    call klog_str
    popfd
    ret

; boot: "Squirrel-OS/2 started: N KB of memory"
klog_boot:
    pushad
    pushfd
    cli
    call klog_head
    mov esi, klog_m_boot
    call klog_str
    mov eax, [mm_total]
    shl eax, 2
    call klog_num
    mov esi, klog_m_kb
    call klog_str
    mov al, 10
    call klog_char
    popfd
    popad
    ret

klog_m_boot db 'Squirrel-OS/2 started: ', 0
klog_m_kb db ' KB of memory', 0
klog_m_start db 'started ', 0
klog_m_end db 'ended ', 0
klog_m_crash db 'crashed ', 0
klog_m_code db ', exit code ', 0
klog_minus db '-', 0
klog_colon db ': ', 0
klog_pid db 'pid ', 0
klog_pid_b db ' (pid ', 0
klog_nl db 10, 0

align 4
klog_len dd 0
idle_ticks dd 0
proc_cpu times PROC_MAX dd 0
proc_idling db 0
klog_buf times KLOG_SIZE db 0
