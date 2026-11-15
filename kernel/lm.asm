; Squirrel-OS/2 — long mode entry and exit (2.8-lm-entry, 2.9 paging/stay)
; Included from pm.asm, in the high image. Original code.
;
; The 64-bit bridge: the kernel can switch from 32-bit protected mode with
; paging into long mode (IA-32e, 64-bit code), run a 64-bit routine, and
; come back. lm_call does the round trip with interrupts off. CR3 in long
; mode is a 4-level root from as_lm_cr3 (kernel or per-process): a PML4
; whose PDPT mirrors the everyday PAE tables, so program-area pages and
; the kernel identity map mean the same in both modes. lm_enter_perm stays
; in IA-32e with compatibility-mode thunks into the 32-bit kernel (2.9).
; See documentation/kernel/long-mode.md.
;
; Sequence (Intel SDM vol. 3, 9.8.5, and AMD APM vol. 2, 14.6):
;   in:  paging off, CR4.PAE on (already on since 2.8-pae), CR3 = PML4,
;        EFER.LME on, paging on (now IA-32e compatibility mode), far jump
;        to a 64-bit segment
;   out: far return to the 32-bit kernel segment, paging off, EFER.LME
;        off, CR4 restored (PAE stays on), CR3 = the PAE PDPT, paging on
;        (EFER.NXE is left alone)

LM_EFER      equ 0xC0000080
LM_EFER_LME  equ 1 << 8
LM_EFER_LMA  equ 1 << 10
LM_CS64      equ 0x40               ; 64-bit kernel code (gdt_cs64, pm.asm)

; -> CF clear when the CPU has long mode (CPUID 0x80000001 EDX bit 29).
; Keeps every register.
lm_supported:
    pushad
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb .no
    mov eax, 0x80000001
    cpuid
    bt edx, 29
    jnc .no
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; Ensures a 4-level root exists for the current process (or the kernel).
; Optional: set lm_as_override to an address-space record (or leave 0 to
; use PCB_AS / kernel) before calling. -> CF if long mode is missing or
; there is no memory. Keeps every register except when CF is set on the
; supported check (then nothing else changed).
lm_init:
    call lm_supported
    jc .r
    pushad
    mov eax, [lm_as_override]
    test eax, eax
    jnz .sync
    mov edi, [proc_cur]
    test edi, edi
    jz .kern
    mov eax, [edi+PCB_AS]
    jmp .sync
.kern:
    xor eax, eax
.sync:
    call as_lm_cr3
    jc .nomem
    mov [lm_pml4], eax          ; PML4 for this entry
    popad
    clc
.r:
    ret
.nomem:
    popad
    stc
    ret

; eax = 64-bit routine (it ends with ret; it may use every register but
; rsp) -> runs it in long mode with interrupts off and comes back. CF if
; long mode is not available. The 32-bit registers are kept. Uses the
; 4-level root from lm_init (per-process or kernel via as_lm_cr3).
lm_call:
    call lm_init
    jnc .go
    ret
.go:
    pushad
    pushfd
    cli
    mov [lm_target], eax
    mov [lm_esp], esp
    mov eax, cr3
    mov [lm_cr3], eax
    mov eax, cr0                ; paging off: allowed, we run identity-mapped
    and eax, 0x7FFFFFFF
    mov cr0, eax
    mov eax, cr4
    mov [lm_cr4], eax
    or eax, 1 << 5              ; PAE
    mov cr4, eax
    mov eax, [lm_pml4]
    mov cr3, eax
    mov ecx, LM_EFER
    rdmsr
    or eax, LM_EFER_LME
    wrmsr
    mov eax, cr0
    or eax, 0x80000000          ; paging on: IA-32e mode is active
    mov cr0, eax
    jmp LM_CS64:lm_in64

lm_back32:                      ; 32-bit again, still IA-32e compatibility mode
    mov ax, 0x10
    mov ss, ax
    mov esp, [lm_esp]
    mov eax, cr0
    and eax, 0x7FFFFFFF         ; leave long mode: paging off first
    mov cr0, eax
    mov ecx, LM_EFER
    rdmsr
    and eax, ~LM_EFER_LME
    wrmsr
    mov eax, [lm_cr4]
    mov cr4, eax
    mov eax, [lm_cr3]
    mov cr3, eax
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    jmp 0x08:.flat              ; a plain 32-bit far jump settles CS
.flat:
    mov ax, USER_DS
    mov ds, ax
    mov es, ax
    popfd
    popad
    clc
    ret

BITS 64
lm_in64:
    mov ax, 0x10
    mov ss, ax
    mov ds, ax
    mov es, ax
    mov eax, [rel lm_esp]       ; the same stack, 16-byte aligned for the call
    mov rsp, rax
    and rsp, -16
    mov eax, [rel lm_target]
    call rax
    ; far return to the 32-bit kernel code segment
    push qword 0x08
    lea rax, [rel lm_back32]
    push rax
    retfq
BITS 32

; ---------- lmtest (2.8-lm-entry) ----------
; Runs lm_selftest in long mode and checks what it left: EFER.LMA read
; inside, 64-bit arithmetic, r8–r15, and a 64-bit push. "lm: PASS",
; "lm: no long mode" on CPUs without it, else "lm: FAIL".
cmd_lmtest_run:
    mov dword [lm_res], 0
    mov dword [lm_res+4], 0
    mov dword [lm_res+8], 0
    mov dword [lm_res+12], 0
    mov eax, lm_selftest
    call lm_call
    jc .nolm
    mov esi, lm_m_fail
    cmp dword [lm_res], LM_EFER_LMA     ; long mode was active
    jne .say
    cmp dword [lm_res+4], 0x9ABCDEF0    ; low half of the 64-bit product
    jne .say
    cmp dword [lm_res+8], 0x00000001    ; and its high half
    jne .say
    cmp dword [lm_res+12], 8            ; a push moved rsp by 8 bytes
    jne .say
    mov esi, lm_m_pass
.say:
    jmp puts
.nolm:
    mov esi, lm_m_nolm
    jmp puts

BITS 64
lm_selftest:
    mov ecx, LM_EFER
    rdmsr
    and eax, LM_EFER_LMA
    mov [rel lm_res], eax
    ; 0x9ABCDEF0 + 2^32 built from r8..r15 and 64-bit arithmetic
    mov r8, 0x100000000
    mov r9, 0x4D5E6F78
    lea r10, [r9+r9]            ; 0x9ABCDEF0
    lea r11, [r8+r10]
    mov r12, 3
    mov r13, r11
    imul r13, r12               ; 3 * (2^32 + x)
    mov r14, r11
    add r14, r14                ; 2 * (2^32 + x)
    sub r13, r14                ; back to 2^32 + x, through 64-bit values
    mov r15, r13
    mov [rel lm_res+4], r15     ; both halves
    mov rax, rsp
    push rax
    sub rax, rsp
    pop rcx
    mov [rel lm_res+12], eax
    ret
BITS 32

lm_m_pass db 'lm: PASS', 10, 0
lm_m_fail db 'lm: FAIL', 10, 0
lm_m_nolm db 'lm: no long mode', 10, 0
cmd_lmtest db 'lmtest', 0
align 4
lm_pml4        dd 0             ; PML4 selected for the current lm_call
lm_as_override dd 0             ; non-zero: as_lm_cr3 uses this AS record
lm_target      dd 0
lm_esp         dd 0
lm_cr3         dd 0             ; saved PAE CR3
lm_cr4         dd 0
lm_res         times 4 dd 0
lm_probe_addr  dd 0             ; VA for lm_probe64 / lmpage

; ---------- 2.9-lm-kernel (IDT): 64-bit IDT + TSS with IST ----------
; Stay in long mode with a 64-bit IDT long enough for the timer to fire
; through a 64-bit gate (and IST1 ready for double faults), then leave and
; put the 32-bit IDT/TSS back. CR3 while staying is the 4-level wrapper
; (as_lm_cr3); everyday paging remains the PAE PDPT. See
; documentation/kernel/long-mode.md.

SEL_TSS64     equ 0xC8              ; gdt_tss64 in pm.asm (16-byte descriptor)
LM64_TSS_SIZE equ 104
LM64_IST1_OFF equ 36                ; IST1 pointer in a 64-bit TSS
LM64_IOMAP    equ 102
LM64_IDT_BYTES equ 256*16

; Build the 64-bit IDT and TSS once (needs the page allocator). CF on failure.
lm_idt_init:
    cmp dword [lm_idt_ready], 0
    jne .ok
    call lm_init
    jc .r
    pushad
    call pg_alloc
    test eax, eax
    jz .fail
    mov [lm_ist1_page], eax
    add eax, PAGE_SIZE              ; IST points at the top of the page
    mov [lm_ist1_top], eax
    mov edi, lm64_tss
    mov ecx, LM64_TSS_SIZE/4
    xor eax, eax
    rep stosd
    mov eax, [lm_ist1_top]
    mov [lm64_tss+LM64_IST1_OFF], eax
    mov dword [lm64_tss+LM64_IST1_OFF+4], 0
    mov word [lm64_tss+LM64_IOMAP], LM64_TSS_SIZE
    ; 16-byte 64-bit TSS descriptor at gdt_tss64
    mov edi, gdt_tss64
    mov word [edi], LM64_TSS_SIZE-1
    mov eax, lm64_tss
    mov [edi+2], ax
    shr eax, 16
    mov [edi+4], al
    mov byte [edi+5], 0x89          ; available 64-bit TSS
    mov byte [edi+6], 0
    mov [edi+7], ah
    mov dword [edi+8], 0            ; base 63:32
    mov dword [edi+12], 0
    ; fill every vector with the default 64-bit stub, then override a few
    mov edi, lm64_idt
    mov ecx, 256
.fill:
    mov eax, lm64_default_isr
    call lm_set_gate64
    add edi, 16
    loop .fill
    mov edi, lm64_idt+0x20*16       ; IRQ0 timer
    mov eax, lm64_timer_isr
    call lm_set_gate64
    mov edi, lm64_idt+8*16          ; #DF uses IST1
    mov eax, lm64_df_isr
    mov ebx, 1                      ; IST index
    call lm_set_gate64_ist
    mov word [lm64_idt_desc], LM64_IDT_BYTES-1
    mov dword [lm64_idt_desc+2], lm64_idt
    mov dword [lm64_idt_desc+6], 0
    mov dword [lm_idt_ready], 1
    popad
.ok:
    clc
.r:
    ret
.fail:
    popad
    stc
    ret

; edi = gate, eax = 64-bit handler, IST = 0
lm_set_gate64:
    xor ebx, ebx
; edi = gate, eax = handler, ebx = IST index (0..7)
lm_set_gate64_ist:
    mov [edi], ax                   ; offset 15:0
    mov word [edi+2], LM_CS64
    mov [edi+4], bl                 ; IST in bits 2:0
    mov byte [edi+5], 0x8E          ; present interrupt gate
    shr eax, 16
    mov [edi+6], ax                 ; offset 31:16
    mov dword [edi+8], 0            ; offset 63:32 (handlers are below 4 GB)
    mov dword [edi+12], 0
    ret

; Like lm_call, but after the 64-bit routine returns the 32-bit IDT and
; TSS are restored (the stay test loads the 64-bit ones).
lm_call_stay:
    call lm_idt_init
    jc .r
    call lm_init                ; refresh the per-process / kernel PML4
    jnc .go
.r:
    ret
.go:
    pushad
    pushfd
    cli
    mov [lm_target], eax
    mov [lm_esp], esp
    mov eax, cr3
    mov [lm_cr3], eax
    mov eax, cr0
    and eax, 0x7FFFFFFF
    mov cr0, eax
    mov eax, cr4
    mov [lm_cr4], eax
    or eax, 1 << 5
    mov cr4, eax
    mov eax, [lm_pml4]
    mov cr3, eax
    mov ecx, LM_EFER
    rdmsr
    or eax, LM_EFER_LME
    wrmsr
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    jmp LM_CS64:lm_in64_stay

lm_back32_stay:
    mov ax, 0x10
    mov ss, ax
    mov esp, [lm_esp]
    mov eax, cr0
    and eax, 0x7FFFFFFF
    mov cr0, eax
    mov ecx, LM_EFER
    rdmsr
    and eax, ~LM_EFER_LME
    wrmsr
    mov eax, [lm_cr4]
    mov cr4, eax
    mov eax, [lm_cr3]
    mov cr3, eax
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    jmp 0x08:.flat
.flat:
    mov ax, USER_DS
    mov ds, ax
    mov es, ax
    ; IA-32e is off: put the 32-bit IDT and the normal TSS back
    lidt [idt_desc]
    mov byte [gdt_tss_main+5], 0x89
    mov byte [gdt_tss_df+5], 0x89
    mov byte [gdt_tss64+5], 0x89
    mov ax, [lm_tr_save]
    test ax, ax
    jnz .tr
    mov ax, SEL_TSS_MAIN
.tr:
    mov byte [gdt_tss_main+5], 0x89
    ltr ax
    popfd
    popad
    clc
    ret

BITS 64
lm_in64_stay:
    mov ax, 0x10
    mov ss, ax
    mov ds, ax
    mov es, ax
    mov eax, [rel lm_esp]
    mov rsp, rax
    and rsp, -16
    mov eax, [rel lm_target]
    call rax
    push qword 0x08
    lea rax, [rel lm_back32_stay]
    push rax
    retfq

; Stay: load 64-bit IDT + TSS, take a few timer IRQs through 64-bit gates.
lm_stay64:
    lidt [rel lm64_idt_desc]
    mov byte [rel gdt_tss64+5], 0x89
    str ax
    mov [rel lm_tr_save], ax
    mov ax, SEL_TSS64
    ltr ax
    mov ecx, LM_EFER
    rdmsr
    and eax, LM_EFER_LMA
    mov [rel lm_res], eax
    mov dword [rel lm_ticks64], 0
    ; Only IRQ0 (timer) while in the 64-bit IDT: other lines must not
    ; fire through a stub that EOIs without draining the device.
    in al, 0x21
    mov [rel lm_pic1], al
    in al, 0xA1
    mov [rel lm_pic2], al
    mov al, 0xFE                    ; unmask only IRQ0
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al
    sti
.wait:
    pause
    cmp dword [rel lm_ticks64], 3
    jb .wait
    cli
    mov al, [rel lm_pic1]
    out 0x21, al
    mov al, [rel lm_pic2]
    out 0xA1, al
    mov eax, [rel lm_ticks64]
    mov [rel lm_res+4], eax
    ret

lm64_timer_isr:
    push rax
    inc dword [rel lm_ticks64]
    mov al, 0x20
    out 0x20, al
    pop rax
    iretq

; Drain the keyboard/mouse data port so a masked line does not stay high.
lm64_default_isr:
    push rax
    in al, 0x64
    test al, 1
    jz .eoi
    in al, 0x60
.eoi:
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    pop rax
    iretq

; Double fault on IST1: record and halt (the stay test must not reach here).
lm64_df_isr:
    mov dword [rel lm_df_hit], 1
.hang:
    hlt
    jmp .hang
BITS 32

; "lmstay: PASS" when long mode stayed up and the 64-bit timer ISR ran.
cmd_lmstay_run:
    mov dword [lm_res], 0
    mov dword [lm_res+4], 0
    mov dword [lm_ticks64], 0
    mov dword [lm_df_hit], 0
    mov eax, lm_stay64
    call lm_call_stay
    jc .nolm
    mov esi, lmstay_m_fail
    cmp dword [lm_res], LM_EFER_LMA
    jne .say
    cmp dword [lm_res+4], 3
    jb .say
    cmp dword [lm_df_hit], 0
    jne .say
    mov esi, lmstay_m_pass
.say:
    jmp puts
.nolm:
    mov esi, lmstay_m_nolm
    jmp puts

lmstay_m_pass db 'lmstay: PASS', 10, 0
lmstay_m_fail db 'lmstay: FAIL', 10, 0
lmstay_m_nolm db 'lmstay: no long mode', 10, 0
cmd_lmstay db 'lmstay', 0

; ---------- 2.9-lm-kernel (paging): per-process 4-level roots ----------
; Creates two address spaces, stamps different bytes at the program area
; (0x30000 = PROG_BASE in loader.asm; that equ is defined after this
; file is included) under PAE, enters long mode with each space's PML4,
; and checks that the private page is isolated while a kernel mark stays
; shared.
LMPAGE_PROG equ 0x30000

cmd_lmpage_run:
    mov dword [lm_as_override], 0
    mov dword [lmpage_as1], 0
    mov dword [lmpage_as2], 0
    mov dword [lmpage_save_cr3], 0
    call lm_supported
    jc .nolm
    call as_create
    test eax, eax
    jz .fail
    mov [lmpage_as1], eax
    call as_create
    test eax, eax
    jz .fail
    mov [lmpage_as2], eax
    ; Stamp private program-area bytes under each PAE PDPT.
    mov eax, cr3
    mov [lmpage_save_cr3], eax
    mov ebx, [lmpage_as1]
    mov eax, [ebx+AS_PD]
    mov cr3, eax
    mov byte [LMPAGE_PROG], 0xA1
    mov ebx, [lmpage_as2]
    mov eax, [ebx+AS_PD]
    mov cr3, eax
    mov byte [LMPAGE_PROG], 0xB2
    mov eax, [lmpage_save_cr3]
    mov cr3, eax
    ; Long mode with AS1: private byte + shared kernel mark
    mov eax, [lmpage_as1]
    mov [lm_as_override], eax
    mov dword [lm_probe_addr], LMPAGE_PROG
    mov eax, lm_probe64
    call lm_call
    jc .nolm_clean
    cmp dword [lm_res], 0xA1
    jne .fail
    mov dword [lm_probe_addr], lmpage_kern_mark
    mov eax, lm_probe64
    call lm_call
    jc .nolm_clean
    mov ebx, [lm_res]
    mov [lmpage_k1], ebx
    cmp bl, 0x5C
    jne .fail
    ; Long mode with AS2
    mov eax, [lmpage_as2]
    mov [lm_as_override], eax
    mov dword [lm_probe_addr], LMPAGE_PROG
    mov eax, lm_probe64
    call lm_call
    jc .nolm_clean
    cmp dword [lm_res], 0xB2
    jne .fail
    mov dword [lm_probe_addr], lmpage_kern_mark
    mov eax, lm_probe64
    call lm_call
    jc .nolm_clean
    mov eax, [lm_res]
    cmp eax, [lmpage_k1]
    jne .fail
    cmp al, 0x5C
    jne .fail
    call lmpage_cleanup
    mov esi, lmpage_m_pass
    jmp puts
.fail:
    call lmpage_cleanup
    mov esi, lmpage_m_fail
    jmp puts
.nolm_clean:
    call lmpage_cleanup
.nolm:
    mov dword [lm_as_override], 0
    mov esi, lmpage_m_nolm
    jmp puts

lmpage_cleanup:
    push eax
    mov dword [lm_as_override], 0
    mov eax, [lmpage_as1]
    test eax, eax
    jz .a2
    call as_release
    mov dword [lmpage_as1], 0
.a2:
    mov eax, [lmpage_as2]
    test eax, eax
    jz .cr3
    call as_release
    mov dword [lmpage_as2], 0
.cr3:
    mov eax, [lmpage_save_cr3]
    test eax, eax
    jz .r
    mov cr3, eax
.r:
    pop eax
    ret

BITS 64
; Read the byte at lm_probe_addr into lm_res (zero-extended).
lm_probe64:
    mov eax, [rel lm_probe_addr]
    movzx eax, byte [rax]
    mov [rel lm_res], eax
    ret
BITS 32

lmpage_kern_mark db 0x5C                ; shared kernel byte both PML4s must see
lmpage_m_pass db 'lmpage: PASS', 10, 0
lmpage_m_fail db 'lmpage: FAIL', 10, 0
lmpage_m_nolm db 'lmpage: no long mode', 10, 0
cmd_lmpage db 'lmpage', 0
align 4
lmpage_as1      dd 0
lmpage_as2      dd 0
lmpage_save_cr3 dd 0
lmpage_k1       dd 0

; ---------- 2.9-lm-kernel (stay + thunks): permanent IA-32e + compat ----------
; Enter long mode, load the 64-bit IDT/TSS, drop to compatibility mode (CS
; 0x08) and stay with EFER.LMA set and CR3 on the 4-level wrapper. 32-bit
; kernel code runs there; lm_thunk64 / lm_thunk32 cross to 64-bit code and
; back. lm_leave_perm undoes the stay (for tests and until boot stays for
; good). See documentation/kernel/long-mode.md.

; -> CF if long mode is missing or the 64-bit IDT cannot be built. On
; success the CPU is in IA-32e compatibility mode (LMA=1, CS=0x08), the
; 64-bit IDT and TSS are loaded, and IRQ lines other than the timer are
; masked. Keeps the general registers (like lm_call).
lm_enter_perm:
    cmp dword [lm_perm], 0
    jne .ok
    call lm_idt_init
    jc .r
    call lm_init
    jc .r
    pushad
    pushfd
    cli
    mov [lm_esp], esp
    mov eax, cr3
    mov [lm_cr3], eax
    mov eax, cr0
    and eax, 0x7FFFFFFF
    mov cr0, eax
    mov eax, cr4
    mov [lm_cr4], eax
    or eax, 1 << 5
    mov cr4, eax
    mov eax, [lm_pml4]
    mov cr3, eax
    mov ecx, LM_EFER
    rdmsr
    or eax, LM_EFER_LME
    wrmsr
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    jmp LM_CS64:lm_enter64
.ok:
    clc
.r:
    ret

BITS 64
lm_enter64:
    mov ax, 0x10
    mov ss, ax
    mov ds, ax
    mov es, ax
    lidt [rel lm64_idt_desc]
    mov byte [rel gdt_tss64+5], 0x89
    str ax
    mov [rel lm_tr_save], ax
    mov ax, SEL_TSS64
    ltr ax
    in al, 0x21
    mov [rel lm_pic1], al
    in al, 0xA1
    mov [rel lm_pic2], al
    mov al, 0xFE                    ; IRQ0 only while the 64-bit IDT is up
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al
    mov dword [rel lm_perm], 1
    push qword 0x08
    lea rax, [rel lm_enter_compat]
    push rax
    retfq
BITS 32

lm_enter_compat:
    mov ax, 0x10
    mov ss, ax
    mov esp, [lm_esp]
    mov ax, USER_DS
    mov ds, ax
    mov es, ax
    popfd
    popad
    clc
    ret

; Leave a permanent stay: restore PIC, drop LME, put the PAE CR3 and the
; 32-bit IDT/TSS back. No-op if not staying. Keeps the general registers.
lm_leave_perm:
    cmp dword [lm_perm], 0
    je .r
    pushad
    pushfd
    cli
    mov [lm_esp], esp
    jmp LM_CS64:lm_leave64
.r:
    ret

BITS 64
lm_leave64:
    mov ax, 0x10
    mov ss, ax
    mov ds, ax
    mov es, ax
    mov al, [rel lm_pic1]
    out 0x21, al
    mov al, [rel lm_pic2]
    out 0xA1, al
    mov dword [rel lm_perm], 0
    push qword 0x08
    lea rax, [rel lm_leave_compat]
    push rax
    retfq
BITS 32

lm_leave_compat:
    mov ax, 0x10
    mov ss, ax
    mov esp, [lm_esp]
    mov eax, cr0
    and eax, 0x7FFFFFFF
    mov cr0, eax
    mov ecx, LM_EFER
    rdmsr
    and eax, ~LM_EFER_LME
    wrmsr
    mov eax, [lm_cr4]
    mov cr4, eax
    mov eax, [lm_cr3]
    mov cr3, eax
    mov eax, cr0
    or eax, 0x80000000
    mov cr0, eax
    jmp 0x08:.flat
.flat:
    mov ax, USER_DS
    mov ds, ax
    mov es, ax
    lidt [idt_desc]
    mov byte [gdt_tss_main+5], 0x89
    mov byte [gdt_tss_df+5], 0x89
    mov byte [gdt_tss64+5], 0x89
    mov ax, [lm_tr_save]
    test ax, ax
    jnz .tr
    mov ax, SEL_TSS_MAIN
.tr:
    mov byte [gdt_tss_main+5], 0x89
    ltr ax
    popfd
    popad
    clc
    ret

; From compatibility mode (lm_perm=1): eax = 64-bit routine -> call it and
; return here in compat. CF if not staying. Keeps the 32-bit registers.
lm_thunk64:
    cmp dword [lm_perm], 0
    jne .go
    stc
    ret
.go:
    pushad
    pushfd
    cli
    mov [lm_target], eax
    mov [lm_thunk_esp], esp
    jmp LM_CS64:lm_thunk64_in

BITS 64
lm_thunk64_in:
    mov ax, 0x10
    mov ss, ax
    mov ds, ax
    mov es, ax
    mov eax, [rel lm_thunk_esp]
    mov rsp, rax
    and rsp, -16
    mov eax, [rel lm_target]
    call rax
    push qword 0x08
    lea rax, [rel lm_thunk64_back]
    push rax
    retfq
BITS 32

lm_thunk64_back:
    mov ax, 0x10
    mov ss, ax
    mov esp, [lm_thunk_esp]
    mov ax, USER_DS
    mov ds, ax
    mov es, ax
    popfd
    popad
    clc
    ret

; From 64-bit code (while staying): eax = 32-bit routine -> call it in
; compatibility mode and return here in 64-bit. The routine may use the
; 32-bit calling convention on the shared stack.
BITS 64
lm_thunk32:
    mov [rel lm_target32], eax
    mov [rel lm_thunk64_rsp], rsp
    push qword 0x08
    lea rax, [rel lm_thunk32_run]
    push rax
    retfq
BITS 32

lm_thunk32_run:
    mov ax, 0x10
    mov ss, ax
    mov esp, [lm_thunk64_rsp]
    mov ax, USER_DS
    mov ds, ax
    mov es, ax
    call [lm_target32]
    jmp LM_CS64:lm_thunk32_ret

BITS 64
lm_thunk32_ret:
    mov ax, 0x10
    mov ss, ax
    mov ds, ax
    mov es, ax
    mov rsp, [rel lm_thunk64_rsp]
    ret
BITS 32

; 32-bit markers used by lmthunk (plain compat calls and via lm_thunk32).
lm_compat_mark_a:
    mov dword [lm_mark_a], 0xA1
    ret

lm_compat_mark_b:
    mov dword [lm_mark_b], 0xB2
    ret

; 64-bit body: prove LMA, thunk into 32-bit mark_b, take three timer IRQs.
BITS 64
lm_thunk_body64:
    mov ecx, LM_EFER
    rdmsr
    and eax, LM_EFER_LMA
    mov [rel lm_res], eax
    mov eax, lm_compat_mark_b
    call lm_thunk32
    mov dword [rel lm_ticks64], 0
    sti
.wait:
    pause
    cmp dword [rel lm_ticks64], 3
    jb .wait
    cli
    mov eax, [rel lm_ticks64]
    mov [rel lm_res+4], eax
    ret
BITS 32

; "lmthunk: PASS" when permanent stay kept LMA, both thunk directions worked,
; and the 64-bit timer ISR still ran.
cmd_lmthunk_run:
    mov dword [lm_res], 0
    mov dword [lm_res+4], 0
    mov dword [lm_mark_a], 0
    mov dword [lm_mark_b], 0
    mov dword [lm_ticks64], 0
    mov dword [lm_df_hit], 0
    call lm_enter_perm
    jc .nolm
    call lm_compat_mark_a
    mov eax, lm_thunk_body64
    call lm_thunk64
    jc .fail_leave
    call lm_leave_perm
    mov esi, lmthunk_m_fail
    cmp dword [lm_mark_a], 0xA1
    jne .say
    cmp dword [lm_mark_b], 0xB2
    jne .say
    cmp dword [lm_res], LM_EFER_LMA
    jne .say
    cmp dword [lm_res+4], 3
    jb .say
    cmp dword [lm_df_hit], 0
    jne .say
    mov esi, lmthunk_m_pass
.say:
    jmp puts
.fail_leave:
    call lm_leave_perm
    mov esi, lmthunk_m_fail
    jmp puts
.nolm:
    mov esi, lmthunk_m_nolm
    jmp puts

lmthunk_m_pass db 'lmthunk: PASS', 10, 0
lmthunk_m_fail db 'lmthunk: FAIL', 10, 0
lmthunk_m_nolm db 'lmthunk: no long mode', 10, 0
cmd_lmthunk db 'lmthunk', 0

align 4
lm_idt_ready  dd 0
lm_ist1_page  dd 0
lm_ist1_top   dd 0
lm_ticks64    dd 0
lm_df_hit     dd 0
lm_perm       dd 0             ; 1 while lm_enter_perm has not been left
lm_thunk_esp  dd 0             ; 32-bit frame for lm_thunk64
lm_target32   dd 0             ; 32-bit routine for lm_thunk32
lm_mark_a     dd 0
lm_mark_b     dd 0
align 8
lm_thunk64_rsp dq 0            ; RSP saved across lm_thunk32
lm_pic1       db 0
lm_pic2       db 0
lm_tr_save    dw 0
              dw 0
align 16
lm64_tss      times LM64_TSS_SIZE db 0
align 16
lm64_idt      times LM64_IDT_BYTES db 0
lm64_idt_desc:
    dw 0
    dd 0
    dd 0
