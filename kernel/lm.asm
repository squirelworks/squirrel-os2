; Squirrel-OS/2 — long mode entry and exit (2.8-lm-entry, 2.9 paging/stay)
; Included from pm.asm, in the high image. Original code.
;
; The 64-bit bridge: the kernel can switch from 32-bit protected mode with
; paging into long mode (IA-32e, 64-bit code), run a 64-bit routine, and
; come back. lm_call does the round trip with interrupts off. CR3 in long
; mode is a 4-level root from as_lm_cr3 (kernel or per-process): a PML4
; whose PDPT mirrors the everyday PAE tables, so program-area pages and
; the kernel identity map mean the same in both modes. lm_enter_perm stays
; in IA-32e with compatibility-mode thunks into the 32-bit kernel (2.9);
; LM_BOOT64 / lm_boot_enter keeps that stay for the whole run. See
; documentation/kernel/long-mode.md.
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
LM_EFER_SCE  equ 1 << 0            ; syscall/sysret enable (2.9-syscall64)
LM_STAR      equ 0xC0000081
LM_LSTAR     equ 0xC0000082
LM_SFMASK    equ 0xC0000084
LM_STAR_CS   equ 0xD8               ; gdt_star_kcs (SYSCALL_CS)
LM_STAR_USER equ 0xE8               ; gdt_star_ucs32 (SYSRET_CS)
; SFMASK: clear IF, TF, DF, NT, AC on syscall entry
LM_SFMASK_BITS equ (1<<9)|(1<<8)|(1<<10)|(1<<14)|(1<<18)
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
; While a permanent stay is active, switches CR3 to that PML4 and uses
; lm_thunk64 instead of entering and leaving.
lm_call:
    call lm_init
    jnc .go
    ret
.go:
    cmp dword [lm_perm], 0
    jne lm_call_via_thunk
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

; Already in IA-32e: load the requested PML4 and thunk to the routine.
; Saved CR3 lives on this stack frame (nestable); lm_thunk64 nests its
; own globals the same way, so a re-entrant lm_call during a thunk is safe.
lm_call_via_thunk:
    pushad
    pushfd
    cli
    mov ebx, eax                ; target
    mov eax, cr3
    push eax                    ; nestable saved CR3
    mov eax, [lm_pml4]
    mov cr3, eax
    mov eax, ebx
    call lm_thunk64
    pop eax                     ; saved CR3
    mov cr3, eax
    popfd
    popad
    clc
    ret

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
LM64_RSP0     equ 4                 ; RSP0 in a 64-bit TSS (qword)
LM64_IST1_OFF equ 36                ; IST1 pointer in a 64-bit TSS
LM64_IOMAP    equ 102
LM64_IDT_BYTES equ 256*16
LM_NEST_MAX   equ 8                 ; nestable call32 frames (IRQ / syscall)
LM_NEST_SIZE  equ 32                ; bytes per nest frame
; frame: +0 target, +4 in_use, +8 rsp64 (qword), +16 reserved

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
    ; RSP0: ring-3 entries use the same kernel stack top as the 32-bit TSS
    mov eax, [tss_main+TSS_ESP0]
    mov [lm64_tss+LM64_RSP0], eax
    mov dword [lm64_tss+LM64_RSP0+4], 0
    ; fill every vector with the default 64-bit stub, then override a few
    mov edi, lm64_idt
    mov ecx, 256
.fill:
    mov eax, lm64_default_isr
    call lm_set_gate64
    add edi, 16
    loop .fill
    call lm_idt_everyday            ; timer, kbd, mouse, int 0x80
    call lm_idt_exc_install         ; 0..31 → report/kill (not the EOI stub)
    mov edi, lm64_idt+8*16          ; #DF uses IST1
    mov eax, lm64_df_isr
    mov ebx, 1                      ; IST index
    call lm_set_gate64_ist
    ; INT3 from ring 3 (software breakpoints) needs DPL 3 — same as
    ; dbg_init on the 32-bit IDT. A DPL-0 gate makes INT3 a #GP(idt[3]).
    mov byte [lm64_idt+3*16+5], 0xEE
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

; Install 64-bit gates used for everyday stay (IRQ0/1/12 and int 0x80).
; Safe to call more than once. Clobbers eax, ebx, edi.
lm_idt_everyday:
    mov edi, lm64_idt+0x20*16       ; IRQ0 timer
    mov eax, lm64_timer_isr
    call lm_set_gate64
    mov edi, lm64_idt+0x21*16       ; IRQ1 keyboard
    mov eax, lm64_kbd_isr
    call lm_set_gate64
    mov edi, lm64_idt+0x2C*16       ; IRQ12 mouse
    mov eax, lm64_mouse_isr
    call lm_set_gate64
    mov edi, lm64_idt+SYSCALL_VEC*16
    mov eax, lm64_syscall_isr
    call lm_set_gate64
    mov byte [edi+5], 0xEF          ; trap gate, DPL 3 (same as 32-bit)
    ret

; Keep 64-bit TSS.RSP0 equal to tss_main.ESP0 (proc_set_esp0 calls this).
lm_sync_rsp0:
    mov eax, [tss_main+TSS_ESP0]
    mov [lm64_tss+LM64_RSP0], eax
    mov dword [lm64_tss+LM64_RSP0+4], 0
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
; TSS are restored (the stay test loads the 64-bit ones). While a
; permanent stay is already active, just thunks (IDT/TSS stay put).
lm_call_stay:
    call lm_idt_init
    jc .r
    call lm_init                ; refresh the per-process / kernel PML4
    jnc .go
.r:
    ret
.go:
    cmp dword [lm_perm], 0
    jne lm_call_via_thunk
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

; Everyday 64-bit IRQ0: count stay-test ticks, then the shared timer body.
; Save the GPRs lm64_call32 / the 32-bit body clobber — a timer mid
; ring-3 loop (heap fill, etc.) must not trash edi/esi (2.9-lm-kernel).
lm64_timer_isr:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    mov eax, [rsp+64]               ; CS (7 pushes + RIP)
    mov [rel lm_irq_cs], eax
    inc dword [rel lm_ticks64]
    mov eax, timer_isr_body
    call lm64_call32
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    iretq

lm64_kbd_isr:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    mov eax, kbd_isr_body
    call lm64_call32
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    iretq

lm64_mouse_isr:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    mov eax, mouse_isr_body
    call lm64_call32
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    iretq

; int 0x80 from compat / ring 3 while LMA=1.
; Native path: args in lm_sys_*; body returns the result in eax through
; lm64_call32 (not lm_sysret), so a yield/switch inside syscall_isr_body
; cannot race another process's return value. Nest frames are free-list
; allocated and the frame pointer rides the process stack across a switch.
; Linux/BSD (2.9-syscall64): returnable lx_syscall_body / bsd_syscall_body
; through lm64_call32 (no iretd). BSD plants RFLAGS.CF from lm_bsd_cf.
lm64_syscall_isr:
    push rax
    push rbx
    push rcx
    push rdx
    push rsi
    push rdi
    push rbp
    mov eax, [rsp+64]               ; CS (7 pushes + RIP)
    mov [rel lm_irq_cs], eax
    mov eax, [rsp+48]               ; saved rax = call number
    mov [rel lm_sys_eax], eax
    mov eax, [rsp+40]
    mov [rel lm_sys_ebx], eax
    mov eax, [rsp+32]
    mov [rel lm_sys_ecx], eax
    mov eax, [rsp+24]
    mov [rel lm_sys_edx], eax
    mov eax, [rsp+16]
    mov [rel lm_sys_esi], eax
    mov eax, [rsp+8]
    mov [rel lm_sys_edi], eax
    mov eax, [rsp]
    mov [rel lm_sys_ebp], eax
    mov eax, [rsp+80]               ; user RSP (for a later BSD-stay body)
    mov [rel lm_sys_uesp], eax
    mov esi, [rel proc_cur]
    cmp dword [esi+PCB_LINUX], 0
    jne .linux
    mov eax, lm64_syscall_body
    jmp .call
.linux:
    mov eax, lx_syscall_body
.call:
    call lm64_call32
    jc .nosys_ret                   ; nest overflow: treat as ENOSYS
    mov [rsp+48], rax               ; result from body (eax), not lm_sysret
    jmp .out
.nosys_ret:
    mov qword [rsp+48], -1          ; SYS_ENOSYS
.out:
    pop rbp
    pop rdi
    pop rsi
    pop rdx
    pop rcx
    pop rbx
    pop rax
    iretq
BITS 32
lm64_syscall_body:
    mov eax, [lm_sys_eax]
    mov ebx, [lm_sys_ebx]
    mov ecx, [lm_sys_ecx]
    mov edx, [lm_sys_edx]
    mov esi, [lm_sys_esi]
    mov edi, [lm_sys_edi]
    mov ebp, [lm_sys_ebp]
    jmp syscall_isr_body
BITS 64

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

; Double fault on IST1. Temporary stay tests must not reach here (record
; and halt). Under permanent stay, recover like the 32-bit task gate:
; report a stack overflow (or #DF) and restart the shell / kill the
; process (KB-17 / stack-shell on the lm64 flavour).
; IST frame: err, RIP, CS, RFLAGS, RSP, SS.
lm64_df_isr:
    mov dword [rel lm_df_hit], 1
    cmp dword [rel lm_perm], 0
    je .hang
    mov rax, [rsp+8]
    mov [rel lm_exc_rip], eax
    mov rax, [rsp+16]
    mov [rel lm_exc_cs], eax
    mov rax, [rsp+32]
    mov [rel lm_exc_rsp], eax
    ; Still on IST1 (frame below). Far-return to compatibility without
    ; lm64_call32 — recovery never returns, so a nest frame would leak.
    ; Do not `mov rsp, [lm_ist1_top]`: that qword-load pulls the next
    ; dword (lm_ticks64) into RSP's high half and faults on the push.
    push qword 0x08
    lea rax, [rel lm64_df_body]
    push rax
    retfq
.hang:
    hlt
    jmp .hang

BITS 32
; Report #DF / stack overflow under permanent stay, then df_shell / df_kill.
lm64_df_body:
    mov ax, 0x10
    mov ss, ax
    mov ds, ax
    mov es, ax
    mov esp, SHELL_STACK
    clts
    call vm_reload_kernel
    mov eax, cr2
    mov [exc_err], eax
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
    mov eax, [lm_exc_rip]
    call puthex
    mov esi, df_m_esp
    call puts
    mov eax, [lm_exc_rsp]
    call puthex
    mov esi, exc_m_addr
    call puts
    mov eax, [exc_err]
    call puthex
    mov al, 10
    call putc
    cmp byte [shell_up], 0
    je .halt
    mov esi, [proc_cur]
    cmp dword [esi+PCB_PID], 0
    je df_shell
    sub esi, proc_table
    shr esi, 6
    imul esi, PROC_STACK_SIZE
    add esi, PROC_STACK_BASE
    mov esp, esi
    jmp df_kill
.halt:
    jmp exc_report.halt

; ---------- 64-bit exception trampolines (2.9-lm-ring3-stay) ----------
; Vectors 0..31 (except #DF on IST1) forward through lm64_call32 into the
; existing 32-bit exc_report path. Stack growth (#PF in a ring-3 window)
; is handled here and resumes with iretq; everything else builds a fake
; 32-bit frame and jumps to exc_report (kill / shell prompt / halt).

BITS 32
; Install interrupt gates for CPU exceptions. Vector 8 keeps lm64_df_isr.
; Clobbers eax, ecx, esi, edi.
lm_idt_exc_install:
    xor ecx, ecx
.fill:
    cmp ecx, 8
    je .next                    ; #DF: IST handler already / about to be set
    mov esi, lm64_exc_stubs
    mov eax, ecx
    shl eax, 4
    add esi, eax
    mov edi, lm64_idt
    mov eax, ecx
    shl eax, 4
    add edi, eax
    mov eax, esi
    call lm_set_gate64
.next:
    inc ecx
    cmp ecx, 32
    jb .fill
    ret

; One 16-byte stub per vector: push a fake error code when the CPU does
; not, push rax/rbx, load the vector into eax, join the common path.
BITS 64
align 16
lm64_exc_stubs:
%assign v 0
%rep 32
lm64_exc_stub_ %+ v:
    %assign has_err 0
    %if (v == 8) || (v == 10) || (v == 11) || (v == 12) || (v == 13) || (v == 14) || (v == 17)
        %assign has_err 1
    %endif
    %if has_err == 0
    push qword 0
    %endif
    push rax
    push rbx
    mov eax, v
    jmp lm64_exc_common
    times (lm64_exc_stubs + (v+1)*16) - $ nop
%assign v v+1
%endrep

; Stack on entry: rbx, rax, err, rip, cs, rflags, rsp, ss
lm64_exc_common:
    cli                             ; grow/report path is not re-entrant
    mov [rel lm_exc_vec], eax
    mov rax, [rsp+16]
    mov [rel lm_exc_err], eax
    mov rax, [rsp+24]
    mov [rel lm_exc_rip], eax
    mov rax, [rsp+32]
    mov [rel lm_exc_cs], eax
    mov [rel lm_irq_cs], eax
    mov rax, [rsp+40]
    mov [rel lm_exc_rflags], eax
    mov rax, [rsp+48]
    mov [rel lm_exc_rsp], eax
    mov rax, [rsp+56]
    mov [rel lm_exc_ss], eax
    mov rax, [rsp+8]
    mov [rel lm_exc_rax], eax
    mov rax, [rsp]
    mov [rel lm_exc_rbx], eax
    mov [rel lm_exc_rcx], ecx
    mov [rel lm_exc_rdx], edx
    mov [rel lm_exc_rsi], esi
    mov [rel lm_exc_rdi], edi
    mov [rel lm_exc_rbp], ebp
    mov eax, lm64_exc_body
    call lm64_call32
    test eax, eax
    jnz .bad                    ; report path should not return
    ; Restore GPRs clobbered by the 64-bit stub / call32 (stack grow
    ; resumes the faulting MOV that saved ecx in deep()).
    mov ecx, [rel lm_exc_rcx]
    mov edx, [rel lm_exc_rdx]
    mov esi, [rel lm_exc_rsi]
    mov edi, [rel lm_exc_rdi]
    mov ebp, [rel lm_exc_rbp]
    pop rbx
    pop rax
    add rsp, 8                  ; error code (real or fake)
    iretq
.bad:
    hlt
    jmp .bad

BITS 32
; -> eax = 0 to resume the interrupted instruction, 1 on unexpected return
lm64_exc_body:
    cmp dword [lm_exc_vec], 14
    jne .report
    mov eax, cr2
    call vm_ustack_fault
    test eax, eax
    jnz .report
    mov eax, cr3                ; new stack PTE must be visible under stay
    mov cr3, eax
    xor eax, eax
    ret
.report:
    ; Fake a 32-bit interrupt frame and enter exc_report. Ring-3 frames
    ; include SS:ESP; ring-0 frames do not (matches the CPU).
    test byte [lm_exc_cs], 3
    jz .kframe
    push dword [lm_exc_ss]
    push dword [lm_exc_rsp]
.kframe:
    push dword [lm_exc_rflags]
    push dword [lm_exc_cs]
    push dword [lm_exc_rip]
    mov ecx, [lm_exc_vec]
    mov eax, 1
    shl eax, cl
    test eax, EXC_ERRCODE_MASK
    jz .noerr
    push dword [lm_exc_err]
.noerr:
    push dword [lm_exc_vec]
    mov eax, [lm_exc_rax]
    mov ebx, [lm_exc_rbx]
    mov ecx, [lm_exc_rcx]
    mov edx, [lm_exc_rdx]
    mov esi, [lm_exc_rsi]
    mov edi, [lm_exc_rdi]
    mov ebp, [lm_exc_rbp]
    jmp exc_report

; eax = low address (inclusive), edx = high (exclusive): free nest frames
; whose saved rsp64 lies in that range. Used when a process dies inside
; lm64_call32 (SYS_EXIT / exception) so the slot is not leaked.
; Keeps every register.
lm_nest_free_range:
    pushad
    lea ebx, [lm_nest_pool]
    mov ecx, LM_NEST_MAX
.walk:
    cmp dword [ebx+4], 0
    je .next
    mov esi, [ebx+8]            ; rsp64 low half
    cmp esi, eax
    jb .next
    cmp esi, edx
    jae .next
    mov dword [ebx+4], 0
    cmp dword [lm_nest_sp], 0
    je .next
    dec dword [lm_nest_sp]
.next:
    add ebx, LM_NEST_SIZE
    loop .walk
    popad
    ret

; eax = 32-bit near routine -> call it in compatibility mode and return
; here in 64-bit. Nestable free-list frames (separate from lm_thunk* slots).
; Used by 64-bit IRQ and syscall gates. A yield/switch inside the 32-bit
; body is safe: the frame pointer is pushed on the process stack and
; returned in ebx across the far jump, so lm_nest_cur is not consulted
; after the body runs. CF set if every frame is busy (caller should EOI).
BITS 64
lm64_call32:
    push rbx
    cmp dword [rel lm_nest_sp], LM_NEST_MAX
    jae .fail
    lea rbx, [rel lm_nest_pool]
    mov ecx, LM_NEST_MAX
.find:
    cmp dword [rbx+4], 0            ; in_use?
    je .got
    add rbx, LM_NEST_SIZE
    loop .find
    jmp .fail
.got:
    mov dword [rbx+4], 1
    inc dword [rel lm_nest_sp]
    mov [rbx], eax                  ; frame.target
    mov [rbx+8], rsp                ; frame.rsp64
    mov [rel lm_nest_cur], rbx
    push qword 0x08
    lea rax, [rel lm64_call32_run]
    push rax
    retfq
.fail:
    inc dword [rel lm_nest_overflow]
    ; IRQ bodies never ran: ack both PICs so a burst cannot wedge the line
    ; (timer/keyboard). Harmless if the caller was a syscall gate.
    mov al, 0x20
    out 0xA0, al
    out 0x20, al
    stc
    pop rbx
    ret

BITS 32
lm64_call32_run:
    mov ax, 0x10
    mov ss, ax
    mov ebx, [lm_nest_cur]
    mov esp, [ebx+8]                ; low half of saved rsp64
    mov ax, USER_DS
    mov ds, ax
    mov es, ax
    mov eax, [ebx]                  ; target
    push ebx                        ; frame ptr rides this stack across yield
    call eax
    pop ebx                         ; frame (ebx -> rbx after far jump)
    jmp LM_CS64:lm64_call32_ret

BITS 64
lm64_call32_ret:
    mov ecx, eax                    ; preserve 32-bit result (syscall path)
    mov ax, 0x10
    mov ss, ax
    mov ds, ax
    mov es, ax
    ; rbx = nest frame from the 32-bit side (not the global lm_nest_cur)
    mov rsp, [rbx+8]
    mov dword [rbx+4], 0            ; free the slot
    dec dword [rel lm_nest_sp]
    mov eax, ecx
    clc
    pop rbx
    ret
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
    ; Stamp private program-area bytes under each space. In PAE, CR3 is
    ; the AS PDPT; under permanent stay CR3 must stay a PML4 (loading a
    ; PAE PDPT while LMA=1 walks garbage and hangs — lm64 flavour).
    mov eax, cr3
    mov [lmpage_save_cr3], eax
    cmp dword [lm_perm], 0
    jne .stamp_stay
    mov ebx, [lmpage_as1]
    mov eax, [ebx+AS_PD]
    mov cr3, eax
    mov byte [LMPAGE_PROG], 0xA1
    mov ebx, [lmpage_as2]
    mov eax, [ebx+AS_PD]
    mov cr3, eax
    mov byte [LMPAGE_PROG], 0xB2
    jmp .stamp_done
.stamp_stay:
    mov eax, [lmpage_as1]
    call as_lm_cr3
    jc .fail
    mov cr3, eax
    mov byte [LMPAGE_PROG], 0xA1
    mov eax, [lmpage_as2]
    call as_lm_cr3
    jc .fail
    mov cr3, eax
    mov byte [LMPAGE_PROG], 0xB2
.stamp_done:
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
    call lm_syscall64_msr_init      ; STAR/LSTAR/EFER.SCE for ELF64
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
; 32-bit IDT/TSS back. No-op if not staying, and refused when the boot
; flavour asked to stay for the whole run (lm_boot). Keeps the general
; registers.
lm_leave_perm:
    cmp dword [lm_boot], 0
    jne .r
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
    ; drop SCE with LME (syscall/sysret only while staying)
    mov ecx, LM_EFER
    rdmsr
    and eax, ~LM_EFER_SCE
    wrmsr
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
    mov dword [lm_everyday], 0
    popfd
    popad
    clc
    ret

; Enter permanent stay and restore the PIC masks saved during entry so
; keyboard / mouse IRQs keep working through the 64-bit gates. Used by
; lmboot and by the LM_BOOT64 build flavour.
lm_enter_everyday:
    call lm_enter_perm
    jc .r
    push eax
    mov al, [lm_pic1]
    out 0x21, al
    mov al, [lm_pic2]
    out 0xA1, al
    mov dword [lm_everyday], 1
    pop eax
    clc
.r:
    ret

; Boot-time stay (assembled with -DLM_BOOT64): enter everyday and latch
; lm_boot so lm_leave_perm will not drop LME for the rest of the run.
lm_boot_enter:
    call lm_supported
    jc .r
    call lm_enter_everyday
    jc .r
    mov dword [lm_boot], 1
    clc
.r:
    ret

; From compatibility mode (lm_perm=1): eax = 64-bit routine -> call it and
; return here in compat. CF if not staying. Keeps the 32-bit registers.
; Nests prior lm_target / lm_thunk_esp on the stack so a re-entrant
; lm_call_via_thunk (or nested thunk) cannot overwrite the outer save.
lm_thunk64:
    cmp dword [lm_perm], 0
    jne .go
    stc
    ret
.go:
    pushad
    pushfd
    cli
    push dword [lm_target]          ; nest outer target
    push dword [lm_thunk_esp]       ; nest outer esp
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
    pop dword [lm_thunk_esp]        ; restore outer
    pop dword [lm_target]
    mov ax, USER_DS
    mov ds, ax
    mov es, ax
    popfd
    popad
    clc
    ret

; From 64-bit code (while staying): eax = 32-bit routine -> call it in
; compatibility mode and return here in 64-bit. The routine may use the
; 32-bit calling convention on the shared stack. Nests lm_target32 /
; lm_thunk64_rsp on the 64-bit stack the same way.
BITS 64
lm_thunk32:
    push rbx
    mov ebx, eax                    ; new target
    mov eax, [rel lm_target32]
    push rax                        ; nest prior target32
    mov rax, [rel lm_thunk64_rsp]
    push rax                        ; nest prior rsp
    mov [rel lm_target32], ebx
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
    mov ecx, eax                    ; preserve 32-bit result
    mov rsp, [rel lm_thunk64_rsp]
    pop rax
    mov [rel lm_thunk64_rsp], rax
    pop rax
    mov [rel lm_target32], eax
    mov eax, ecx
    pop rbx
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

; ---------- 2.9-lm-kernel (boot64): everyday stay for the run ----------
; lmboot enters with everyday IRQs (or checks a boot-time stay), proves
; LMA + timer ticks through the 64-bit gates, and leaves only when the
; stay was not latched by LM_BOOT64.
BITS 64
lm_boot_body64:
    mov ecx, LM_EFER
    rdmsr
    and eax, LM_EFER_LMA
    mov [rel lm_res], eax
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

cmd_lmboot_run:
    mov dword [lm_res], 0
    mov dword [lm_res+4], 0
    mov dword [lm_mark_a], 0
    mov dword [lm_ticks64], 0
    mov dword [lm_df_hit], 0
    call lm_supported
    jc .nolm
    cmp dword [lm_boot], 0
    jne .check                  ; already stayed from boot
    call lm_enter_everyday
    jc .nolm
.check:
    call lm_compat_mark_a
    mov eax, lm_boot_body64
    call lm_thunk64
    jc .fail_leave
    cmp dword [lm_boot], 0
    jne .kept                   ; boot flavour: must still be in IA-32e
    call lm_leave_perm
.kept:
    mov esi, lmboot_m_fail
    cmp dword [lm_mark_a], 0xA1
    jne .say
    cmp dword [lm_res], LM_EFER_LMA
    jne .say
    cmp dword [lm_res+4], 3
    jb .say
    cmp dword [lm_df_hit], 0
    jne .say
    cmp dword [lm_boot], 0
    je .pass
    ; Boot stay: LMA must still be set after the check (leave was refused)
    mov ecx, LM_EFER
    rdmsr
    test eax, LM_EFER_LMA
    jz .say
.pass:
    mov esi, lmboot_m_pass
.say:
    jmp puts
.fail_leave:
    cmp dword [lm_boot], 0
    jne .fail_msg
    call lm_leave_perm
.fail_msg:
    mov esi, lmboot_m_fail
    jmp puts
.nolm:
    mov esi, lmboot_m_nolm
    jmp puts

lmboot_m_pass db 'lmboot: PASS', 10, 0
lmboot_m_fail db 'lmboot: FAIL', 10, 0
lmboot_m_nolm db 'lmboot: no long mode', 10, 0
cmd_lmboot db 'lmboot', 0

; ---------- 2.9-syscall64: STAR/LSTAR + ELF64 enter + syscall entry ----------
; Called from lm_enter64 while CS is 64-bit. Enables EFER.SCE and loads
; STAR/LSTAR/SFMASK. Keeps rax-rdx. Clobber-safe for the enter path.
BITS 64
lm_syscall64_msr_init:
    push rax
    push rcx
    push rdx
    mov ecx, LM_EFER
    rdmsr
    or eax, LM_EFER_SCE
    wrmsr
    ; STAR: [63:48]=SYSRET_CS (0xE8), [47:32]=SYSCALL_CS (0xD8)
    mov edx, (LM_STAR_USER << 16) | LM_STAR_CS
    xor eax, eax
    mov ecx, LM_STAR
    wrmsr
    lea rax, [rel syscall64_entry]
    mov rdx, rax
    shr rdx, 32
    mov ecx, LM_LSTAR
    wrmsr
    mov eax, LM_SFMASK_BITS
    xor edx, edx
    mov ecx, LM_SFMASK
    wrmsr
    pop rdx
    pop rcx
    pop rax
    ret

; iretq into a 64-bit ring-3 ELF (from lm_thunk64). Does not return.
lm_enter_user64_go:
    mov ax, USER_DS
    mov ds, ax
    mov es, ax
    xor eax, eax
    mov fs, ax
    mov gs, ax
    mov edi, [rel lm_u64_arg]       ; System V: rdi = first arg
    mov esi, [rel lm_u64_rsp]
    mov edx, [rel lm_u64_rip]
    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor ebp, ebp
    xor r8, r8
    xor r9, r9
    xor r10, r10
    xor r11, r11
    xor r12, r12
    xor r13, r13
    xor r14, r14
    xor r15, r15
    push qword USER64_DS            ; ss
    push rsi                        ; rsp
    push qword 0x202                ; rflags: IF
    push qword USER64_CS            ; cs
    push rdx                        ; rip
    iretq

; SYSCALL from 64-bit ring 3. RCX=rip, R11=rflags, RAX=number,
; RDI/RSI/RDX = args (mapped onto ebx/ecx/edx for the 32-bit table).
; Stack stays the user's until we load TSS.RSP0.
syscall64_entry:
    mov [rel lm_sys_eax], eax
    mov [rel lm_sys_ebx], edi
    mov [rel lm_sys_ecx], esi
    mov [rel lm_sys_edx], edx
    mov [rel lm_u64_rcx], rcx       ; return rip
    mov [rel lm_u64_r11], r11       ; return rflags
    mov [rel lm_u64_sav_rsp], rsp
    mov rsp, [rel lm64_tss+LM64_RSP0]
    push qword [rel lm_u64_sav_rsp]
    push qword [rel lm_u64_rcx]
    push qword [rel lm_u64_r11]
    mov ax, USER_DS
    mov ds, ax
    mov es, ax
    mov dword [rel lm_irq_cs], USER64_CS
    mov esi, [rel proc_cur]
    cmp dword [esi+PCB_LINUX], 0
    jne .bad                        ; ELF64 is native only
    mov eax, lm64_syscall_body
    call lm64_call32
    jc .bad
.back:
    mov r8d, eax                    ; result (do not use rcx — restored next)
    pop r11                         ; user rflags
    pop rcx                         ; user rip
    pop rsp                         ; user rsp
    mov eax, r8d
    db 0x48, 0x0F, 0x07             ; rex.w sysret (sysretq)
.bad:
    mov eax, -1
    jmp .back
BITS 32

align 4
lm_idt_ready  dd 0
lm_ist1_page  dd 0
lm_ist1_top   dd 0
lm_ticks64    dd 0
lm_df_hit     dd 0
lm_perm       dd 0             ; 1 while lm_enter_perm has not been left
lm_boot       dd 0             ; 1: boot flavour stays for the whole run
lm_everyday   dd 0             ; 1: PIC masks restored for everyday IRQs
lm_thunk_esp  dd 0             ; 32-bit frame for lm_thunk64
lm_target32   dd 0             ; 32-bit routine for lm_thunk32
lm_mark_a     dd 0
lm_mark_b     dd 0
lm_irq_cs     dd 0             ; interrupted CS for shared ISR bodies
lm_sysret     dd 0             ; return value from syscall_isr_body (32-bit path)
lm_sys_eax    dd 0
lm_sys_ebx    dd 0
lm_sys_ecx    dd 0
lm_sys_edx    dd 0
lm_sys_esi    dd 0
lm_sys_edi    dd 0
lm_sys_ebp    dd 0
lm_sys_uesp   dd 0             ; user ESP from the 64-bit int 0x80 frame (BSD)
lm_u64_arg    dd 0             ; ELF64 enter: rdi
lm_u64_rip    dd 0             ; ELF64 enter: entry RIP
lm_u64_rsp    dd 0             ; ELF64 enter: user RSP
align 8
lm_u64_rcx    dq 0             ; syscall: saved user RIP (RCX)
lm_u64_r11    dq 0             ; syscall: saved user RFLAGS (R11)
lm_u64_sav_rsp dq 0            ; syscall: saved user RSP
; Saved exception state for lm64_exc_* → exc_report (2.9-lm-ring3-stay)
lm_exc_vec    dd 0
lm_exc_err    dd 0
lm_exc_rip    dd 0
lm_exc_cs     dd 0
lm_exc_rflags dd 0
lm_exc_rsp    dd 0
lm_exc_ss     dd 0
lm_exc_rax    dd 0
lm_exc_rbx    dd 0
lm_exc_rcx    dd 0
lm_exc_rdx    dd 0
lm_exc_rsi    dd 0
lm_exc_rdi    dd 0
lm_exc_rbp    dd 0
lm_nest_sp    dd 0             ; lm64_call32 in-use count
lm_nest_overflow dd 0          ; times LM_NEST_MAX blocked a call32
align 8
lm_nest_cur   dq 0             ; frame chosen for the current lm64_call32 entry
lm_thunk64_rsp dq 0            ; RSP saved across lm_thunk32
lm_pic1       db 0
lm_pic2       db 0
lm_tr_save    dw 0
              dw 0
align 16
lm_nest_pool  times LM_NEST_MAX*LM_NEST_SIZE db 0
align 16
lm64_tss      times LM64_TSS_SIZE db 0
align 16
lm64_idt      times LM64_IDT_BYTES db 0
lm64_idt_desc:
    dw 0
    dd 0
    dd 0
