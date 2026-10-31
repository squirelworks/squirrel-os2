; Squirrel-OS/2 — CPU exception reports and recovery (0.8.2)
; Included from pm.asm. Original code.
;
; The stubs in pm.asm push the vector and jump to exc_report, which
; prints what went wrong (exception name, process, registers, the error
; code decoded for a page fault, the top of the stack) and then:
;   - in any process but the shell: ends that process (exit code -1);
;   - in the shell: waits for Enter (restart the shell) or R (reboot);
;   - before the shell is up: halts.
; See documentation/kernel/crash-reports.md.

; frame on entry, after pushad: the saved registers, then the vector,
; then (error code,) EIP, CS, EFLAGS pushed by the CPU
EXC_EDI     equ 0
EXC_ESI     equ 4
EXC_EBP     equ 8
EXC_EBX     equ 16
EXC_EDX     equ 20
EXC_ECX     equ 24
EXC_EAX     equ 28
EXC_VEC     equ 32

SHELL_STACK equ 0x9F000             ; the boot stack, which the shell runs on

exc_report:
    cli
    pushad
    mov ebp, esp
    call vm_reload_kernel       ; the report's own pages must be there
    mov ebx, [ebp+EXC_VEC]
    lea esi, [ebp+EXC_VEC+4]    ; the CPU's frame
    xor edx, edx                ; error code (0 when there is none)
    mov eax, 1
    mov ecx, ebx
    shl eax, cl
    test eax, EXC_ERRCODE_MASK
    jz .noerr
    mov edx, [esi]
    add esi, 4
.noerr:
    mov [exc_eip], esi          ; -> EIP, CS, EFLAGS
    lea eax, [esi+12]           ; ESP before the fault
    mov [exc_esp], eax
    mov [exc_err], edx
    ; headline: number, name, process
    mov esi, exc_m_head
    call puts
    mov eax, ebx
    call itoa
    mov esi, num_buf
    call puts
    mov esi, exc_m_open
    call puts
    mov esi, exc_m_unknown
    cmp ebx, 20
    ja .named
    mov esi, [exc_names+ebx*4]
.named:
    call puts
    mov esi, exc_m_close
    call puts
    call exc_who
    ; EIP, error code, fault address
    mov esi, exc_m_eip
    call puts
    mov eax, [exc_eip]
    mov eax, [eax]
    call puthex
    mov eax, 1
    mov ecx, ebx
    shl eax, cl
    test eax, EXC_ERRCODE_MASK
    jz .nocode
    mov esi, exc_m_err
    call puts
    mov eax, [exc_err]
    call puthex
.nocode:
    cmp ebx, 14
    jne .regs
    call exc_page_fault
.regs:
    mov al, 10
    call putc
    ; registers, as they were
    mov esi, exc_regs
.r:
    lodsd
    test eax, eax
    jz .stack
    push esi
    mov esi, eax
    call puts                   ; "EAX=" ...
    pop esi
    lodsd                       ; frame offset, or -1 for ESP
    cmp eax, -1
    je .esp
    mov eax, [ebp+eax]
    jmp .show
.esp:
    mov eax, [exc_esp]
.show:
    call puthex
    jmp .r
.stack:
    ; the four dwords on top of the faulting stack
    mov esi, exc_m_stack
    call puts
    mov esi, [exc_esp]
    cmp esi, MM_LIMIT-16        ; only where every address space maps it
    ja .nostack
    mov ecx, 4
.s:
    mov al, ' '
    call putc
    lodsd
    call puthex
    loop .s
.nostack:
    mov al, 10
    call putc
    ; what happens now
    cmp byte [shell_up], 0
    je .halt
    mov esi, [proc_cur]
    cmp dword [esi+PCB_PID], 0
    je exc_shell
    mov esi, exc_m_killed
    call puts
    mov esi, [proc_cur]
    mov eax, [esi+PCB_PID]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    mov ebx, -1
    jmp proc_exit
.halt:
    mov esi, exc_m_halt
    call puts
.h:
    hlt
    jmp .h

; prints " in pid N (name)"; nothing before the process table exists
exc_who:
    cmp byte [shell_up], 0
    je .r
    mov esi, exc_m_inpid
    call puts
    mov edi, [proc_cur]
    mov eax, [edi+PCB_PID]
    call itoa
    mov esi, num_buf
    call puts
    mov edi, [proc_cur]         ; (itoa does not keep edi)
    cmp byte [edi+PCB_NAME], 0
    je .r
    mov esi, exc_m_open
    call puts
    lea esi, [edi+PCB_NAME]
    call puts
    mov al, ')'
    call putc
.r:
    mov al, 10
    jmp putc

; page fault: the address and what the error code says
exc_page_fault:
    mov esi, exc_m_addr
    call puts
    mov eax, cr2
    call puthex
    mov esi, exc_m_read
    test byte [exc_err], 2
    jz .rw
    mov esi, exc_m_write
.rw:
    call puts
    mov esi, exc_m_notpresent
    test byte [exc_err], 1
    jz .p
    mov esi, exc_m_protect
.p:
    jmp puts

; The shell itself faulted: Enter starts it again, R reboots.
exc_shell:
    mov esi, exc_m_ask
    call puts
.wait:
    cli
    call kbd_dequeue
    jnc .key
    sti
    hlt
    jmp .wait
.key:
    cmp al, 0x1C                ; Enter
    je shell_restart
    cmp al, 0x13                ; R
    jne .wait
    mov al, 0xFE                ; pulse the CPU reset line
    out 0x64, al
    jmp .wait

; Back to an empty prompt on a fresh shell stack; programs and apps
; started earlier keep running.
shell_restart:
    cli
    mov esp, SHELL_STACK
    call vm_reload_kernel
    mov byte [cap_on], 0
    mov byte [in_on], 0
    mov byte [bat_active], 0
    mov esi, exc_m_restarted
    call puts
    call sh_prompt
    sti
    jmp pm.cmdloop

; Loads the kernel page directory (the shell's) if another is loaded.
vm_reload_kernel:
    push eax
    mov eax, [kernel_pd]
    test eax, eax
    jz .r                       ; paging not on yet
    mov cr3, eax
.r:
    pop eax
    ret

; ---------- double faults and stack overflows (KB-17) ----------
; A kernel-mode fault is delivered on the stack that faulted. When a stack
; runs into its guard page (proc.asm), the push of the page-fault frame
; faults again: a double fault. Vector 8 is therefore a task gate. The CPU
; switches to the double-fault task, which has a stack of its own and
; saves everything that was running in tss_main. df_task reports it,
; points the saved state at df_kill (or the shell's restart prompt) on a
; fresh stack, and returns there with iretd, the way back from a task.

TSS_SIZE    equ 104
TSS_CR3     equ 28
TSS_EIP     equ 32
TSS_EFLAGS  equ 36
TSS_ESP     equ 56
TSS_ES      equ 72
TSS_CS      equ 76
TSS_SS      equ 80
TSS_DS      equ 84
TSS_FS      equ 88
TSS_GS      equ 92
TSS_IOMAP   equ 102
SEL_TSS_MAIN equ 0x18
SEL_TSS_DF  equ 0x20
DF_STACK    equ PROC_STACK_BASE     ; 4 KB below the first guard page

; edi = GDT entry, eax = base: sets a descriptor's base address
tss_base:
    mov [edi+2], ax
    shr eax, 16
    mov [edi+4], al
    mov [edi+7], ah
    ret

; After vm_init: both TSS descriptors, the double-fault task's state,
; the task gate for vector 8, and TR.
tss_init:
    pushad
    mov edi, gdt_tss_main
    mov eax, tss_main
    call tss_base
    mov edi, gdt_tss_df
    mov eax, tss_df
    call tss_base
    mov word [tss_main+TSS_IOMAP], TSS_SIZE
    mov edi, tss_df
    mov word [edi+TSS_IOMAP], TSS_SIZE
    mov eax, [kernel_pd]
    mov [edi+TSS_CR3], eax
    mov dword [edi+TSS_EIP], df_task
    mov dword [edi+TSS_EFLAGS], 0x2     ; interrupts off
    mov dword [edi+TSS_ESP], DF_STACK
    mov dword [edi+TSS_CS], 0x08
    mov eax, 0x10
    mov [edi+TSS_ES], eax
    mov [edi+TSS_SS], eax
    mov [edi+TSS_DS], eax
    mov [edi+TSS_FS], eax
    mov [edi+TSS_GS], eax
    mov edi, idt+8*8                    ; vector 8: task gate
    mov dword [edi], SEL_TSS_DF << 16
    mov dword [edi+4], 0x8500
    mov ax, SEL_TSS_MAIN
    ltr ax
    popad
    ret

; The double-fault task. Each entry runs from here; iretd leaves it, and
; the next double fault resumes after the iretd.
df_task:
    add esp, 4                  ; the error code (always 0)
    call df_report
    iretd
    jmp df_task

; Reports the double fault and decides where the interrupted task goes.
df_report:
    mov eax, [kernel_pd]
    mov cr3, eax
    mov eax, cr2
    mov [exc_err], eax
    ; a fault address in a guard page means a stack ran out
    sub eax, PROC_STACK_BASE
    cmp eax, PROC_GUARDS*PROC_STACK_SIZE
    jae .df
    xor edx, edx
    mov ecx, PROC_STACK_SIZE
    div ecx
    cmp edx, PAGE_SIZE
    jae .df
    mov esi, df_m_overflow
    jmp .head
.df:
    mov esi, df_m_double
.head:
    call puts
    call exc_who
    mov esi, exc_m_eip
    call puts
    mov eax, [tss_main+TSS_EIP]
    call puthex
    mov esi, df_m_esp
    call puts
    mov eax, [tss_main+TSS_ESP]
    call puthex
    mov esi, exc_m_addr
    call puts
    mov eax, [exc_err]
    call puthex
    mov al, 10
    call putc
    ; where the interrupted task goes now. CR3 is not saved on a task
    ; switch, only loaded, so give the way back the kernel's directory
    ; (every stack is mapped there).
    mov eax, [kernel_pd]
    mov [tss_main+TSS_CR3], eax
    mov dword [tss_main+TSS_EFLAGS], 0x2
    cmp byte [shell_up], 0
    je .halt
    mov esi, [proc_cur]
    cmp dword [esi+PCB_PID], 0
    je .shell
    sub esi, proc_table         ; the dying process's own stack, from its top
    shr esi, 6
    imul esi, PROC_STACK_SIZE
    add esi, PROC_STACK_BASE
    mov [tss_main+TSS_ESP], esi
    mov dword [tss_main+TSS_EIP], df_kill
    ret
.shell:
    mov dword [tss_main+TSS_ESP], SHELL_STACK
    mov dword [tss_main+TSS_EIP], df_shell
    ret
.halt:
    mov dword [tss_main+TSS_ESP], SHELL_STACK
    mov dword [tss_main+TSS_EIP], exc_report.halt
    ret

; Back in the normal task, on a fresh stack. A task switch sets CR0.TS,
; so clear it before anything touches the FPU.
df_kill:
    clts
    mov esi, exc_m_killed
    call puts
    mov esi, [proc_cur]
    mov eax, [esi+PCB_PID]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    mov ebx, -1
    jmp proc_exit

df_shell:
    clts
    call vm_reload_kernel
    jmp exc_shell

df_m_overflow db '*** stack overflow', 0
df_m_double db '*** CPU exception 8 (double fault)', 0
df_m_esp db ' ESP=', 0

align 4
tss_main times TSS_SIZE db 0
tss_df times TSS_SIZE db 0

; #DF #TS #NP #SS #GP #PF #AC push an error code
EXC_ERRCODE_MASK equ (1<<8)|(1<<10)|(1<<11)|(1<<12)|(1<<13)|(1<<14)|(1<<17)

exc_names:
    dd exc_n0, exc_n1, exc_n2, exc_n3, exc_n4, exc_n5, exc_n6, exc_n7
    dd exc_n8, exc_n9, exc_n10, exc_n11, exc_n12, exc_n13, exc_n14
    dd exc_m_unknown, exc_n16, exc_n17, exc_n18, exc_n19, exc_n20
exc_n0 db 'divide error', 0
exc_n1 db 'debug', 0
exc_n2 db 'NMI', 0
exc_n3 db 'breakpoint', 0
exc_n4 db 'overflow', 0
exc_n5 db 'bound range', 0
exc_n6 db 'invalid opcode', 0
exc_n7 db 'no FPU', 0
exc_n8 db 'double fault', 0
exc_n9 db 'FPU segment overrun', 0
exc_n10 db 'invalid TSS', 0
exc_n11 db 'segment not present', 0
exc_n12 db 'stack fault', 0
exc_n13 db 'general protection', 0
exc_n14 db 'page fault', 0
exc_n16 db 'FPU error', 0
exc_n17 db 'alignment check', 0
exc_n18 db 'machine check', 0
exc_n19 db 'SIMD error', 0
exc_n20 db 'virtualization', 0
exc_m_unknown db 'reserved', 0

; label, frame offset (-1: ESP); 0 ends the list
exc_regs:
    dd exc_r_eax, EXC_EAX, exc_r_ebx, EXC_EBX, exc_r_ecx, EXC_ECX
    dd exc_r_edx, EXC_EDX, exc_r_esi, EXC_ESI, exc_r_edi, EXC_EDI
    dd exc_r_ebp, EXC_EBP, exc_r_esp, -1, 0
exc_r_eax db '    EAX=', 0
exc_r_ebx db ' EBX=', 0
exc_r_ecx db ' ECX=', 0
exc_r_edx db ' EDX=', 0
exc_r_esi db 10, '    ESI=', 0
exc_r_edi db ' EDI=', 0
exc_r_ebp db ' EBP=', 0
exc_r_esp db ' ESP=', 0

exc_m_head db 10, '*** CPU exception ', 0
exc_m_open db ' (', 0
exc_m_close db ')', 0
exc_m_inpid db ' in pid ', 0
exc_m_eip db '    EIP=', 0
exc_m_err db ' error=', 0
exc_m_addr db ' address=', 0
exc_m_read db ' (read, ', 0
exc_m_write db ' (write, ', 0
exc_m_notpresent db 'page not present)', 0
exc_m_protect db 'protection)', 0
exc_m_stack db 10, '    stack:', 0
exc_m_killed db 'Program ended: pid ', 0
exc_m_halt db 'System halted.', 10, 0
exc_m_ask db 'The shell crashed. Enter: restart the shell   R: reboot', 10, 0
exc_m_restarted db 'Shell restarted.', 10, 0

align 4
exc_eip dd 0
exc_esp dd 0
exc_err dd 0
shell_up db 0
