; Squirrel-OS/2 — application processors (2.8-smp-ap)
; Included from pm.asm, in the high image. Original code.
;
; At boot the bootstrap processor (BSP) finds the other CPUs in the
; ACPI MADT, starts each one with INIT and two STARTUP IPIs through its
; local APIC, and waits for it. An application processor (AP) begins in
; real mode at SMP_TRAMP, the page where the BSP copied ap_tramp: it
; loads the kernel's GDT, enters protected mode, takes the next AP stack,
; turns on the kernel's paging and IDT, enables its local APIC, counts
; itself online and parks (sti / hlt). Parked APs only wake for IPIs;
; nothing sends them work yet (2.8-smp-sched). `cpus` lists them.
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
CPU_SIZE      equ 16

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
    fninit
    call smp_lapic_on
    mov dword [edi+CPU_STATE], 2
    lock inc dword [smp_online]
.park:
    sti
    hlt
    jmp .park

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
smp_m_online db ', online (parked)', 10, 0
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
