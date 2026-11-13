; Squirrel-OS/2 — application processors (2.8-smp-ap)
; Included from pm.asm, in the high image. Original code.
;
; At boot the bootstrap processor (BSP) finds the other CPUs in the
; ACPI MADT, starts each one with INIT and two STARTUP IPIs through its
; local APIC, and waits for it. An application processor (AP) begins in
; real mode at SMP_TRAMP, the page where the BSP copied ap_tramp: it
; loads the kernel's GDT, enters protected mode, takes the next AP stack,
; turns on the kernel's paging and IDT, enables its local APIC, counts
; itself online and enters ap_idle.
;
; Scheduling (2.8-smp-sched): the kernel itself still runs only on the
; BSP. An AP runs ring-3 threads: in ap_idle it claims a READY thread
; that a ring-3 preemption stopped (PCB_UFRAME), loads its address space,
; FPU state and kernel stack and returns it to ring 3 the way the BSP
; would. When that thread enters the kernel on the AP (a system call or
; an exception), the AP hands it back as READY with the kernel entry as
; its continuation (ap_divert) and wakes the BSP, which then runs the
; kernel part. The AP's local APIC timer hands a thread back as
; preempted (resumable anywhere) when others are waiting.
; See documentation/kernel/smp.md.

SMP_MAX       equ 16              ; CPUs the tables hold
SMP_TRAMP     equ 0x7000          ; AP start page (STARTUP vector 0x07)
SMP_STACK     equ 4096            ; per AP
LAPIC_ID      equ 0x20
LAPIC_EOI     equ 0xB0
LAPIC_SVR     equ 0xF0
LAPIC_ICR_LO  equ 0x300
LAPIC_ICR_HI  equ 0x310
LAPIC_PENDING equ 1 << 12         ; ICR delivery status
SMP_SPURIOUS  equ 0xFF            ; spurious vector: default_isr

; per-CPU record
CPU_APIC      equ 0               ; local APIC id
CPU_STATE     equ 4               ; 0 absent, 1 found, 2 online
CPU_STACK     equ 8               ; AP stack top (0 for the BSP)
CPU_CUR       equ 12              ; the thread an AP runs, or 0
CPU_SIZE      equ 16
SEL_TSS_CPU0  equ 0x48            ; gdt_tss_cpu (pm.asm): one per record
LAPIC_LVT_TMR equ 0x320
LAPIC_TMR_INI equ 0x380
LAPIC_TMR_DIV equ 0x3E0
SMP_TIMER_VEC equ 0x41            ; AP local APIC timer
SMP_WAKE_VEC  equ 0x42            ; IPI that wakes the BSP
SMP_TMR_COUNT equ 0x40000         ; local APIC timer period (divide by 16)
%if SMP_MAX != 16
%error gdt_tss_cpu in pm.asm has 16 entries
%endif

; Finds the CPUs and starts the APs. Runs once at boot, with the timer
; running and interrupts on. Keeps every register.
smp_init:
    pushad
    mov dword [smp_count], 1
    mov dword [smp_online], 1
    call smp_find_madt
    jc .out                     ; no MADT: one CPU
    call smp_parse_madt
    cmp dword [smp_count], 1
    jbe .out
    mov eax, [smp_lapic]
    mov ecx, 0x1000
    call vm_map_range           ; the local APIC registers (kernel pages)
    jc .out
    call smp_lapic_on
    mov edi, idt+SMP_TIMER_VEC*8
    mov eax, ap_timer_isr
    call set_gate
    mov edi, idt+SMP_WAKE_VEC*8
    mov eax, smp_wake_isr
    call set_gate
    mov eax, [smp_lapic]
    mov eax, [eax+LAPIC_ID]
    shr eax, 24
    mov [smp_bsp_id], eax
    ; the trampoline into its page below 1 MB
    mov esi, ap_tramp
    mov edi, SMP_TRAMP
    mov ecx, ap_tramp_end-ap_tramp
    rep movsb
    xor ebx, ebx
.cpu:
    cmp ebx, [smp_count]
    jae .out
    mov edi, ebx
    shl edi, 4                  ; * CPU_SIZE
    add edi, smp_cpus
    mov eax, [edi+CPU_APIC]
    cmp eax, [smp_bsp_id]
    jne .ap
    mov dword [edi+CPU_STATE], 2  ; the BSP is online already
    jmp .next
.ap:
    call smp_start_ap
.next:
    inc ebx
    jmp .cpu
.out:
    popad
    ret

; edi = per-CPU record of an AP: gives it a stack, sends INIT and two
; STARTUP IPIs, and waits up to ~100 ms for it to come online.
smp_start_ap:
    call pg_alloc
    test eax, eax
    jz .r
    add eax, SMP_STACK
    mov [edi+CPU_STACK], eax
    mov dword [edi+CPU_CUR], 0
    call smp_tss_setup
    mov [smp_ap_rec], edi       ; the AP reads its record from here
    mov eax, [smp_online]
    mov [smp_was], eax
    mov ecx, [edi+CPU_APIC]
    shl ecx, 24
    mov eax, 0x00004500         ; INIT, level assert
    call smp_ipi
    mov ecx, 2
    call smp_ticks              ; 10-20 ms
    mov ecx, [edi+CPU_APIC]
    shl ecx, 24
    mov eax, 0x00004600 | (SMP_TRAMP >> 12)   ; STARTUP
    call smp_ipi
    call smp_wait_on
    jnc .r
    mov ecx, [edi+CPU_APIC]
    shl ecx, 24
    mov eax, 0x00004600 | (SMP_TRAMP >> 12)   ; a second STARTUP
    call smp_ipi
    call smp_wait_on
.r:
    ret

; waits up to 10 ticks for smp_online to pass smp_was -> CF if it did not
smp_wait_on:
    push ecx
    mov ecx, 10
.w:
    mov eax, [smp_online]
    cmp eax, [smp_was]
    ja .on
    push ecx
    mov ecx, 1
    call smp_ticks
    pop ecx
    loop .w
    pop ecx
    stc
    ret
.on:
    pop ecx
    clc
    ret

; ecx = timer ticks to wait (interrupts must be on)
smp_ticks:
    mov eax, [ticks]
    add eax, ecx
.w:
    sti
    hlt
    cmp [ticks], eax
    jb .w
    ret

; eax = ICR low dword, ecx = ICR high dword (destination << 24): sends
; the IPI and waits until the local APIC has delivered it
smp_ipi:
    push edx
    mov edx, [smp_lapic]
    mov [edx+LAPIC_ICR_HI], ecx
    mov [edx+LAPIC_ICR_LO], eax
.w:
    pause
    test dword [edx+LAPIC_ICR_LO], LAPIC_PENDING
    jnz .w
    pop edx
    ret

; this CPU's local APIC on, spurious interrupts to SMP_SPURIOUS
smp_lapic_on:
    push eax
    push edx
    mov edx, [smp_lapic]
    mov eax, [edx+LAPIC_SVR]
    or eax, 0x100 | SMP_SPURIOUS
    mov [edx+LAPIC_SVR], eax
    pop edx
    pop eax
    ret

; ---------- ACPI ----------

; -> esi = the MADT, or CF
smp_find_madt:
    call smp_find_rsdp
    jc .r
    mov esi, [esi+16]           ; RSDT (ACPI 1.0 pointer, every version has it)
    cmp esi, MM_LIMIT
    jae .no
    cmp dword [esi], 'RSDT'
    jne .no
    mov ecx, [esi+4]            ; length
    sub ecx, 36
    shr ecx, 2                  ; entries
    jz .no
    lea ebx, [esi+36]
.t:
    mov esi, [ebx]
    cmp esi, MM_LIMIT
    jae .n
    cmp dword [esi], 'APIC'
    je .found
.n:
    add ebx, 4
    loop .t
.no:
    stc
.r:
    ret
.found:
    clc
    ret

; -> esi = the RSDP ('RSD PTR ' with a good checksum), or CF. It is on a
; 16-byte boundary in the first KB of the EBDA or in 0xE0000-0xFFFFF.
smp_find_rsdp:
    movzx esi, word [0x40E]     ; EBDA segment
    shl esi, 4
    jz .bios
    lea edx, [esi+1024]
    call .scan
    jnc .r
.bios:
    mov esi, 0xE0000
    mov edx, 0x100000
.scan:
    cmp esi, edx
    jae .no
    cmp dword [esi], 'RSD '
    jne .next
    cmp dword [esi+4], 'PTR '
    jne .next
    push ecx
    push esi
    xor eax, eax
    mov ecx, 20                 ; the ACPI 1.0 part's checksum
.sum:
    add al, [esi]
    inc esi
    loop .sum
    pop esi
    pop ecx
    test al, al
    jz .ok
.next:
    add esi, 16
    jmp .scan
.no:
    stc
.r:
    ret
.ok:
    clc
    ret

; esi = MADT: the local APIC address and every enabled processor
; local APIC (type 0) into smp_cpus / smp_count
smp_parse_madt:
    pushad
    mov eax, [esi+36]
    mov [smp_lapic], eax
    mov dword [smp_count], 0
    mov edx, esi
    add edx, [esi+4]            ; end of the table
    add esi, 44
.e:
    cmp esi, edx
    jae .done
    movzx ecx, byte [esi+1]     ; entry length
    test ecx, ecx
    jz .done
    cmp byte [esi], 0           ; processor local APIC
    jne .next
    test byte [esi+4], 1        ; enabled
    jz .next
    mov eax, [smp_count]
    cmp eax, SMP_MAX
    jae .next
    shl eax, 4
    movzx ebx, byte [esi+3]     ; APIC id
    mov [smp_cpus+eax+CPU_APIC], ebx
    mov dword [smp_cpus+eax+CPU_STATE], 1
    inc dword [smp_count]
.next:
    add esi, ecx
    jmp .e
.done:
    cmp dword [smp_count], 0
    jne .r
    mov dword [smp_count], 1    ; an empty MADT: just us
.r:
    popad
    ret

; ---------- the AP side ----------

; Copied to SMP_TRAMP and entered there in real mode (CS = 0x0700, IP 0).
; Only absolute addresses: it runs at a different place than it was
; assembled for.
BITS 16
ap_tramp:
    cli
    xor ax, ax
    mov ds, ax
    o32 lgdt [gdt_desc]         ; the kernel's GDT, below 32 KB
    mov eax, cr0
    or al, 1
    mov cr0, eax
    jmp dword 0x08:ap_pm32
ap_tramp_end:
BITS 32

ap_pm32:
    mov ax, 0x10
    mov ss, ax
    mov ax, USER_DS
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax
    mov edi, [smp_ap_rec]       ; this AP's record: the BSP waits for us
    mov esp, [edi+CPU_STACK]
    mov eax, cr4
    or eax, 0x10                ; PSE, as the kernel's directory needs
    mov cr4, eax
    mov eax, [kernel_pd]
    mov cr3, eax
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    jmp .paged
.paged:
    lidt [idt_desc]
    mov eax, cr0                ; caches on, FPU as on the BSP (fpu_init)
    and eax, ~((1 << 30) | (1 << 29) | (1 << 2) | (1 << 3))
    or eax, (1 << 1) | (1 << 5)
    mov cr0, eax
    fninit
    mov eax, edi                ; this CPU's TSS
    sub eax, smp_cpus
    shr eax, 1                  ; / CPU_SIZE * 8
    add eax, SEL_TSS_CPU0
    ltr ax
    call smp_lapic_on
    mov edx, [smp_lapic]        ; its timer: periodic, SMP_TIMER_VEC
    mov dword [edx+LAPIC_TMR_DIV], 3
    mov dword [edx+LAPIC_LVT_TMR], SMP_TIMER_VEC | (1 << 17)
    mov dword [edx+LAPIC_TMR_INI], SMP_TMR_COUNT
    mov dword [edi+CPU_STATE], 2
    lock inc dword [smp_online]
    jmp ap_idle

; edi = a CPU record: its TSS (kernel stack segment, no I/O map) and
; GDT descriptor
smp_tss_setup:
    pushad
    mov eax, edi
    sub eax, smp_cpus
    mov ebx, eax
    shr ebx, 1                  ; descriptor offset: record index * 8
    shr eax, 4                  ; record index
    imul eax, TSS_SIZE
    add eax, smp_tss
    mov dword [eax+TSS_SS0], 0x10
    mov word [eax+TSS_IOMAP], TSS_SIZE
    lea edi, [gdt_tss_cpu+ebx]
    mov word [edi], TSS_SIZE-1
    mov word [edi+5], 0x0089    ; present 32-bit TSS, limit 19:16 = 0
    call tss_base
    popad
    ret

; -> ebx = this AP's CPU record (from its task register). Clobbers eax.
smp_cpu_rec:
    str ax
    movzx ebx, ax
    sub ebx, SEL_TSS_CPU0
    shl ebx, 1                  ; / 8 * CPU_SIZE
    add ebx, smp_cpus
    ret

; ---------- AP scheduling (2.8-smp-sched) ----------

; The AP's scheduler loop, on its own stack with the kernel's page
; directory: claims a READY ring-3 thread that may run anywhere and
; resumes it; otherwise sleeps until its timer.
ap_idle:
    cli
    call smp_cpu_rec
    mov esp, [ebx+CPU_STACK]
    mov dword [ebx+CPU_CUR], 0
    mov eax, [kernel_pd]        ; never keep a page directory that may go
    mov cr3, eax
.scan:
    mov edi, proc_table+PCB_SIZE    ; slot 0 is the shell: BSP only
    mov ecx, PROC_MAX-1
.l:
    cmp dword [edi+PCB_STATE], P_READY
    jne .next
    cmp dword [edi+PCB_UFRAME], 1
    jne .next
    cmp dword [edi+PCB_AS], 0
    je .next
    mov eax, edi                ; threads with a TLS segment stay on the
    sub eax, proc_table         ; BSP: its descriptor is per CPU there
    shr eax, 4
    cmp dword [tls_base+eax], 0
    jne .next
    mov eax, P_READY
    mov edx, P_APRUN
    lock cmpxchg [edi+PCB_STATE], edx
    je .run
.next:
    add edi, PCB_SIZE
    loop .l
    sti
    hlt
    cli
    jmp .scan
.run:
    mov dword [edi+PCB_UFRAME], 0
    mov [ebx+CPU_CUR], edi
    ; ring-3 entries on this CPU land on the thread's kernel stack
    mov eax, edi
    sub eax, proc_table
    shr eax, 6                  ; slot
    imul eax, PROC_STACK_SIZE
    add eax, PROC_STACK_BASE
    mov edx, ebx
    sub edx, smp_cpus
    shr edx, 4                  ; record index
    imul edx, TSS_SIZE
    mov [smp_tss+edx+TSS_ESP0], eax
    mov eax, [edi+PCB_AS]
    mov eax, [eax+AS_PD]
    mov cr3, eax
    mov eax, edi
    call proc_fpu_area
    cmp dword [edi+PCB_FPU], 0
    je .fresh
    frstor [eax]
    jmp .go
.fresh:
    fninit
.go:
    mov esp, [edi+PCB_ESP]      ; what proc_switch would pop
    popad
    popfd
    clc
    ret

; Entered by jmp with the continuation on the stack, on an AP running a
; thread that just entered the kernel: hands the thread to the BSP.
; ap_divert: it resumes at the continuation in the kernel, on the BSP.
; ap_yield: it was preempted in ring 3 and may resume on any CPU.
ap_yield:
    pushfd
    pushad
    mov ebp, 1
    jmp ap_handback
ap_divert:
    pushfd
    pushad
    xor ebp, ebp
ap_handback:
    call smp_cpu_rec
    mov edi, [ebx+CPU_CUR]
    test edi, edi
    jz .lost
    mov [edi+PCB_ESP], esp
    mov eax, cr2                ; a page fault's address, for the BSP
    mov edx, edi
    sub edx, proc_table
    shr edx, 6
    mov [proc_cr2+edx*4], eax
    mov eax, edi
    call proc_fpu_area
    fnsave [eax]
    mov dword [edi+PCB_FPU], 1
    mov dword [ebx+CPU_CUR], 0
    mov [edi+PCB_UFRAME], ebp
    mov dword [edi+PCB_STATE], P_READY  ; last: from here the BSP may take it
    mov eax, SMP_WAKE_VEC | 0x4000      ; fixed, assert
    mov ecx, [smp_bsp_id]
    shl ecx, 24
    call smp_ipi
    jmp ap_idle
.lost:                          ; a kernel entry with no thread: an AP bug
    cli
    hlt
    jmp .lost

; -> CF unless this CPU is an AP (its task register is not tss_main).
; Keeps every register.
smp_on_ap:
    push eax
    str ax
    cmp ax, SEL_TSS_MAIN
    pop eax
    je .bsp
    clc
    ret
.bsp:
    stc
    ret

; The continuation of a fault an AP handed over: its CR2 on this CPU,
; then the report as usual
ap_exc_resume:
    push eax
    push edx
    mov eax, [proc_cur]
    sub eax, proc_table
    shr eax, 6
    mov edx, [proc_cr2+eax*4]
    mov cr2, edx
    pop edx
    pop eax
    jmp exc_report.bsp

; AP local APIC timer
ap_timer_isr:
    KSEGS
    push eax
    mov eax, [smp_lapic]
    mov dword [eax+LAPIC_EOI], 0
    test byte [esp+8], 3        ; from ring 3?
    jz .out                     ; no: ap_idle was waiting, it rescans
    call smp_others_wait
    jc .out
    pop eax
    push dword ap_utail         ; resume: straight back to ring 3
    jmp ap_yield
.out:
    pop eax
    iretd
ap_utail:
    iretd

; -> CF unless some other thread is READY (it should get a turn)
smp_others_wait:
    push edi
    push ecx
    mov edi, proc_table
    mov ecx, PROC_MAX
.l:
    cmp dword [edi+PCB_STATE], P_READY
    je .yes
    add edi, PCB_SIZE
    loop .l
    pop ecx
    pop edi
    stc
    ret
.yes:
    pop ecx
    pop edi
    clc
    ret

; BSP: an AP handed a thread back
smp_wake_isr:
    KSEGS
    push eax
    mov eax, [smp_lapic]
    mov dword [eax+LAPIC_EOI], 0
    pop eax
    iretd

; ---------- cpus (2.8-smp-ap) ----------
; One line per CPU, then "N CPU(s) online".
cmd_cpus_run:
    pushad
    xor ebx, ebx
.l:
    cmp ebx, [smp_count]
    jae .total
    mov esi, smp_m_cpu
    call puts
    mov eax, ebx
    call itoa
    mov esi, num_buf
    call puts
    mov esi, smp_m_apic
    call puts
    mov edi, ebx
    shl edi, 4
    mov eax, [smp_cpus+edi+CPU_APIC]
    call itoa
    mov esi, num_buf
    call puts
    mov edi, ebx                ; (itoa and puts may change edi)
    shl edi, 4
    mov esi, smp_m_bsp
    mov eax, [smp_cpus+edi+CPU_APIC]
    cmp eax, [smp_bsp_id]
    je .say
    mov esi, smp_m_online
    cmp dword [smp_cpus+edi+CPU_STATE], 2
    je .say
    mov esi, smp_m_off
.say:
    call puts
    inc ebx
    jmp .l
.total:
    mov eax, [smp_online]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, smp_m_total
    call puts
    popad
    ret

smp_m_cpu    db 'CPU ', 0
smp_m_apic   db ': APIC id ', 0
smp_m_bsp    db ', boot processor', 10, 0
smp_m_online db ', online', 10, 0
smp_m_off    db ', did not start', 10, 0
smp_m_total  db ' CPU(s) online', 10, 0
cmd_cpus     db 'cpus', 0
align 4
smp_lapic    dd 0xFEE00000
smp_bsp_id   dd 0
smp_count    dd 1
smp_online   dd 1
smp_was      dd 0
smp_ap_rec   dd 0
smp_cpus     times SMP_MAX*CPU_SIZE db 0
smp_tss      times SMP_MAX*TSS_SIZE db 0
