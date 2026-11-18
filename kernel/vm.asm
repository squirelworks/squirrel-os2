; Squirrel-OS/2 — PAE paging and per-process address spaces (0.6.1, 2.8-pae,
; 2.9-lm-kernel paging step)
; Included from pm.asm. Original code.
;
; Paging is on from boot, in PAE mode (CR4.PAE, 64-bit entries, a PDPT).
; The kernel's tables identity-map the first 256 MB: 0-4 MB with 4 KB
; pages (two page tables), the rest with 2 MB pages. Every loaded
; program gets an address space of its own: a copy of the PDPT and of
; the low page directory and tables, with the program area (PROG_BASE,
; 64 KB) backed by fresh pages. So two programs linked at the same
; address can be alive at once, and a program's stray access above
; 256 MB faults and ends only that program. Since 0.6.2 a program also
; has a heap at HEAP_BASE that SYS_SBRK grows and shrinks. Since 2.8-pae
; the heap and ring-3 stacks are mapped with the NX bit when the CPU
; has it (EFER.NXE), so a jump into them is a page fault. Since 2.9 each
; space also has a 4-level (PML4) wrapper for long mode that points at
; the same page directories through a long-mode PDPT (W allowed there;
; PAE PDPTE.W stays clear). Everyday CR3 is still the PAE PDPT. See
; documentation/kernel/memory.md and long-mode.md.

PG_P        equ 1                   ; present
PG_W        equ 2                   ; writable
PG_U        equ 4                   ; ring 3 may use it (2.4)
PG_PS       equ 0x80                ; 2 MB page (PAE) / was 4 MB with PSE
PG_NX_HI    equ 0x80000000          ; high dword: execute-disable (bit 63)
VM_EFER     equ 0xC0000080          ; IA32_EFER (also in lm.asm)
VM_EFER_NXE equ 1 << 11

; PAE walk: [31:30] PDPT, [29:21] PD, [20:12] PT; 512 entries per table
PAE_PD_SHIFT    equ 21
PAE_PT_SHIFT    equ 12
PAE_IDX_MASK    equ 0x1FF
PAE_ENT_SIZE    equ 8
PAE_ENTS        equ 512
PAE_PDPT_ENTS   equ 4
PAE_2MB         equ 1 << 21

PROG_PTE    equ PROG_BASE >> 12     ; first PTE index in the 0-2 MB table
PROG_PAGES  equ PROG_MAX >> 12      ; 16

; address space record
AS_PD       equ 0                   ; PDPT (physical; what CR3 holds in PAE)
AS_REFS     equ 4                   ; processes using it; 0 = slot free
AS_PAGES    equ 8                   ; pages it owns (tables included)
AS_BRK      equ 12                  ; end of the heap (0.6.2)
AS_PML4     equ 16                  ; 4-level root for long mode (2.9), 0 = none yet
AS_SIZE     equ 20
AS_MAX      equ PROC_MAX

HEAP_BASE   equ 0x40000000          ; heap: up to 4 MB (two PAE page tables)
HEAP_MAX    equ 0x400000

; Ring-3 stacks (2.4): one 512 KB window per process slot in the top 4 MB
; below 2 GB. Pages are mapped when first touched (vm_ustack_fault); the
; lowest page of each window never is, so a runaway stack faults there
; and is reported as a stack overflow. Two PAE PDs cover the 4 MB.
USTACK_BASE equ 0x7FC00000
USTACK_SIZE equ 0x80000
%if PROC_MAX*USTACK_SIZE > 0x400000
%error the ring-3 stack windows must fit 4 MB
%endif

; Builds the kernel PDPT and turns PAE paging on. Enables EFER.NXE when
; the CPU has NX (CPUID 0x80000001 EDX bit 20).
vm_init:
    pushad
    call nx_probe
    call pg_alloc               ; page table for 0-2 MB
    test eax, eax
    jz .nomem
    mov [kernel_pt], eax
    mov edi, eax
    mov eax, PG_P|PG_W
    mov ecx, PAE_ENTS
.pt0:
    mov [edi], eax
    mov dword [edi+4], 0
    add edi, PAE_ENT_SIZE
    add eax, PAGE_SIZE
    loop .pt0
    ; stack guard pages (KB-17): not present, so running off the bottom
    ; of a stack faults instead of writing the memory below it. Program
    ; address spaces copy this table, so they have the holes too.
    mov edi, [kernel_pt]
    add edi, (PROC_STACK_BASE >> 12) * PAE_ENT_SIZE
    mov ecx, PROC_GUARDS
.guard:
    mov dword [edi], 0
    mov dword [edi+4], 0
    add edi, (PROC_STACK_SIZE >> 12) * PAE_ENT_SIZE
    loop .guard
    call pg_alloc               ; page table for 2-4 MB
    test eax, eax
    jz .nomem
    mov [kernel_pt_hi], eax
    mov edi, eax
    mov eax, (2 << 20)|PG_P|PG_W
    mov ecx, PAE_ENTS
.pt1:
    mov [edi], eax
    mov dword [edi+4], 0
    add edi, PAE_ENT_SIZE
    add eax, PAGE_SIZE
    loop .pt1
    call pg_alloc               ; page directory for 0-1 GB
    test eax, eax
    jz .nomem
    mov [kernel_pd0], eax
    mov edi, eax
    mov eax, [kernel_pt]
    or eax, PG_P|PG_W
    mov [edi], eax
    mov dword [edi+4], 0
    mov eax, [kernel_pt_hi]
    or eax, PG_P|PG_W
    mov [edi+PAE_ENT_SIZE], eax
    mov dword [edi+PAE_ENT_SIZE+4], 0
    add edi, 2*PAE_ENT_SIZE
    mov eax, (2*PAE_2MB)|PG_P|PG_W|PG_PS
    mov ecx, (MM_LIMIT >> PAE_PD_SHIFT) - 2   ; 4 MB .. 256 MB
.pd2m:
    mov [edi], eax
    mov dword [edi+4], 0
    add edi, PAE_ENT_SIZE
    add eax, PAE_2MB
    loop .pd2m
    call pg_alloc               ; PDPT (CR3)
    test eax, eax
    jz .nomem
    mov [kernel_pd], eax
    mov edi, eax
    mov eax, [kernel_pd0]
    or eax, PG_P                ; PDPTE: only P (W is reserved in PAE)
    mov [edi], eax              ; PDPT[0] -> PD0; the rest stay 0
    mov dword [edi+4], 0
    call nx_enable              ; EFER.NXE before PG, when the CPU has it
    mov eax, cr4
    or eax, 1 << 5              ; PAE
    mov cr4, eax
    mov eax, [kernel_pd]
    mov cr3, eax
    mov eax, cr0
    or eax, 0x80000000          ; PG
    mov cr0, eax
    jmp .on                     ; (identity mapped: execution just goes on)
.on:
    popad
    ret
.nomem:
    mov esi, vm_m_nomem
    call puts
.h:
    hlt
    jmp .h

; Sets vm_nx when CPUID 0x80000001 EDX bit 20 (NX) is present.
nx_probe:
    pushad
    mov byte [vm_nx], 0
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb .r
    mov eax, 0x80000001
    cpuid
    bt edx, 20
    jnc .r
    mov byte [vm_nx], 1
.r:
    popad
    ret

; Turns on EFER.NXE when vm_nx is set. Keeps every register.
nx_enable:
    cmp byte [vm_nx], 0
    je .r
    push eax
    push ecx
    push edx
    mov ecx, VM_EFER
    rdmsr
    or eax, VM_EFER_NXE
    wrmsr
    pop edx
    pop ecx
    pop eax
.r:
    ret

; -> eax = high dword for a new user data page (NX when available).
vm_nx_hi:
    xor eax, eax
    cmp byte [vm_nx], 0
    je .r
    mov eax, PG_NX_HI
.r:
    ret

; -> eax = a new address space (record pointer), or 0 if out of
; records or memory. Its program area is zeroed.
as_create:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov ebx, as_table
    mov ecx, AS_MAX
.find:
    cmp dword [ebx+AS_REFS], 0
    je .got
    add ebx, AS_SIZE
    loop .find
    xor eax, eax
    jmp .out
.got:
    mov dword [ebx+AS_PD], 0
    mov dword [ebx+AS_PAGES], 0
    mov dword [ebx+AS_BRK], HEAP_BASE
    mov dword [ebx+AS_PML4], 0  ; 4-level wrapper built on demand (as_lm_sync)
    call pg_alloc               ; private PDPT
    test eax, eax
    jz .fail
    mov [ebx+AS_PD], eax
    inc dword [ebx+AS_PAGES]
    mov edi, eax
    mov esi, [kernel_pd]
    mov ecx, PAGE_SIZE/4
    rep movsd
    call pg_alloc               ; private PD0 (0-1 GB)
    test eax, eax
    jz .fail
    inc dword [ebx+AS_PAGES]
    mov edi, eax
    mov esi, [kernel_pd0]
    mov ecx, PAGE_SIZE/4
    rep movsd
    mov esi, [ebx+AS_PD]
    or eax, PG_P                ; PDPTE: only P (and PWT/PCD); W is reserved
    mov [esi], eax              ; PDPT[0] -> private PD0
    mov dword [esi+4], 0
    call pg_alloc               ; private 0-2 MB table
    test eax, eax
    jz .fail
    inc dword [ebx+AS_PAGES]
    mov edi, eax
    mov esi, [kernel_pt]
    mov ecx, PAGE_SIZE/4
    rep movsd
    mov edx, [ebx+AS_PD]
    mov edx, [edx]              ; PD0
    and edx, -PAGE_SIZE
    mov esi, eax                ; physical PT (flags clear from pg_alloc)
    or eax, PG_P|PG_W|PG_U
    mov [edx], eax
    mov dword [edx+4], 0
    lea edi, [esi+PROG_PTE*PAE_ENT_SIZE]
    call pg_alloc               ; private 2-4 MB table
    test eax, eax
    jz .fail
    inc dword [ebx+AS_PAGES]
    push edi                    ; keep the program-area PTE pointer
    mov edi, eax
    mov esi, [kernel_pt_hi]
    mov ecx, PAGE_SIZE/4
    rep movsd
    or eax, PG_P|PG_W|PG_U
    mov [edx+PAE_ENT_SIZE], eax
    mov dword [edx+PAE_ENT_SIZE+4], 0
    pop edi
    mov ecx, PROG_PAGES
.area:
    call pg_alloc
    test eax, eax
    jz .fail
    or eax, PG_P|PG_W|PG_U      ; executable: program code lives here
    mov [edi], eax
    mov dword [edi+4], 0
    add edi, PAE_ENT_SIZE
    inc dword [ebx+AS_PAGES]
    loop .area
    mov dword [ebx+AS_REFS], 1
    mov eax, ebx
    jmp .out
.fail:
    mov eax, ebx
    call as_teardown
    xor eax, eax
.out:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; eax = address space (or 0 for the kernel's): one more user
as_retain:
    test eax, eax
    jz .r
    inc dword [eax+AS_REFS]
.r:
    ret

; eax = address space (or 0): one user fewer; the last frees its pages
as_release:
    test eax, eax
    jz .r
    dec dword [eax+AS_REFS]
    jnz .r
    jmp as_teardown
.r:
    ret

; eax = address space record: frees everything it owns (also a
; half-built one) and clears the record.
as_teardown:
    pushad
    mov ebx, eax
    ; 4-level wrapper: PML4 and its long-mode PDPT only (the PDs stay
    ; owned by the PAE PDPT path below).
    mov eax, [ebx+AS_PML4]
    test eax, eax
    jz .pae
    mov edx, [eax]              ; PML4[0] -> LM PDPT
    and edx, -PAGE_SIZE
    push eax
    test edx, edx
    jz .pml4
    mov eax, edx
    call pg_free
.pml4:
    pop eax
    call pg_free
    mov dword [ebx+AS_PML4], 0
.pae:
    mov esi, [ebx+AS_PD]
    test esi, esi
    jz .done
    ; PDPT[1..3]: heap, stacks, late MMIO maps (2.8-pae).
    ; as_free_pd clobbers esi; reload the PDPT from the record each time.
    mov edx, [esi+1*PAE_ENT_SIZE]
    call as_free_pd
    mov esi, [ebx+AS_PD]
    mov edx, [esi+2*PAE_ENT_SIZE]
    call as_free_pd
    mov esi, [ebx+AS_PD]
    mov edx, [esi+3*PAE_ENT_SIZE]
    call as_free_pd
    mov esi, [ebx+AS_PD]
    ; PD0: private low tables and the program-area pages
    mov edx, [esi]
    and edx, -PAGE_SIZE
    cmp edx, [kernel_pd0]
    je .pdpt
    mov eax, [edx]              ; PT 0-2 MB
    and eax, -PAGE_SIZE
    cmp eax, [kernel_pt]
    je .pd0
    mov ecx, PROG_PAGES
    lea edi, [eax+PROG_PTE*PAE_ENT_SIZE]
.area:
    push eax
    mov eax, [edi]
    and eax, -PAGE_SIZE
    cmp eax, MM_START           ; still the identity entry: not ours
    jb .next
    call pg_free
.next:
    pop eax
    add edi, PAE_ENT_SIZE
    loop .area
    call pg_free                ; 0-2 MB table (eax still holds it)
    mov eax, [edx+PAE_ENT_SIZE]
    and eax, -PAGE_SIZE
    cmp eax, [kernel_pt_hi]
    je .pd0
    call pg_free                ; 2-4 MB table
.pd0:
    mov eax, edx
    call pg_free
.pdpt:
    mov eax, esi
    call pg_free
.done:
    mov dword [ebx+AS_PD], 0
    mov dword [ebx+AS_REFS], 0
    mov dword [ebx+AS_PAGES], 0
    mov dword [ebx+AS_PML4], 0
    popad
    ret

; edx = a PDPT entry (0: none): frees every page table it points at
; (and the pages those tables map), then the page directory. Clobbers
; eax, ecx, edi, esi.
as_free_pd:
    test edx, edx
    jz .r
    and edx, -PAGE_SIZE
    mov ecx, PAE_ENTS
    mov edi, edx
.pde:
    mov eax, [edi]
    test eax, PG_P
    jz .n
    test eax, PG_PS
    jnz .n                      ; a 2 MB identity page: not ours to free
    push ecx
    push edi
    mov esi, eax
    call as_free_table
    pop edi
    pop ecx
.n:
    add edi, PAE_ENT_SIZE
    loop .pde
    mov eax, edx
    call pg_free
.r:
    ret

; esi = a page directory entry (with flags): frees every page its table
; maps, then the table. Clobbers eax, ecx, edi.
as_free_table:
    and esi, -PAGE_SIZE
    mov ecx, PAE_ENTS
    mov edi, esi
.p:
    mov eax, [edi]
    test eax, eax
    jz .n
    and eax, -PAGE_SIZE
    call pg_free
.n:
    add edi, PAE_ENT_SIZE
    loop .p
    mov eax, esi
    call pg_free
    ret

; edi = PCB: loads its page directory (if not already loaded).
; Under a permanent long-mode stay (lm_perm), CR3 must be the 4-level
; PML4 from as_lm_cr3 — a PAE PDPT is not a valid long-mode root and
; triple-faults as soon as ring-3 code runs (2.9-lm-ring3-stay).
; Clobbers eax, ebx.
vm_load:
    mov ebx, [edi+PCB_AS]
    cmp dword [lm_perm], 0
    jne .stay
    mov eax, [kernel_pd]
    test ebx, ebx
    jz .set
    mov eax, [ebx+AS_PD]
    jmp .set
.stay:
    mov eax, ebx                ; AS record, or 0 for the kernel/shell
    call as_lm_cr3
    jc .r
.set:
    mov ebx, cr3
    cmp eax, ebx
    je .r
    mov cr3, eax
.r:
    ret

; Reloads the current process's page directory.
vm_reload:
    push eax
    push ebx
    push edi
    mov edi, [proc_cur]
    call vm_load
    pop edi
    pop ebx
    pop eax
    ret

; ---------- heap (0.6.2) ----------

; ebx = bytes to add (negative shrinks) -> eax = the old break, or -1
; if the caller has no address space of its own, the heap would leave
; [HEAP_BASE, HEAP_BASE+HEAP_MAX], or memory ran out. New heap memory
; reads as zero; memory given back is unmapped at once.
sys_sbrk:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    mov ebp, [proc_cur]
    mov ebp, [ebp+PCB_AS]
    test ebp, ebp
    jz .fail
    mov edx, [ebp+AS_BRK]       ; old break
    lea ecx, [edx+ebx]          ; new break
    cmp ecx, HEAP_BASE          ; (also catches a wrap-around)
    jb .fail
    cmp ecx, HEAP_BASE+HEAP_MAX
    ja .fail
    lea esi, [edx+PAGE_SIZE-1]  ; first page past the old heap
    and esi, -PAGE_SIZE
    lea edi, [ecx+PAGE_SIZE-1]  ; first page past the new heap
    and edi, -PAGE_SIZE
    cmp edi, esi
    jb .shrink
    call heap_map
    jnc .moved
    ; out of memory: give back what this call mapped
    mov edi, esi
    lea esi, [edx+PAGE_SIZE-1]
    and esi, -PAGE_SIZE
    call heap_unmap
    jmp .fail
.shrink:
    xchg esi, edi
    call heap_unmap
.moved:
    mov [ebp+AS_BRK], ecx
    mov eax, edx
    jmp .out
.fail:
    mov eax, -1
.out:
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ebp = address space (the current one), esi = first page, edi = end:
; maps fresh pages -> esi = where it stopped, CF if memory ran out.
; Under permanent stay a CR3 reload at the end drops any cached
; non-present walks so the new PTEs are visible (2.9-lm-kernel).
heap_map:
    cmp esi, edi
    jae .ok
    call as_pte
    jc .r
    call pg_alloc
    test eax, eax
    jz .no
    or eax, PG_P|PG_W|PG_U
    mov [ebx], eax
    call vm_nx_hi
    mov [ebx+4], eax
    inc dword [ebp+AS_PAGES]
    invlpg [esi]
    add esi, PAGE_SIZE
    jmp heap_map
.no:
    stc
    ret
.ok:
    cmp dword [lm_perm], 0
    je .ok_clc
    mov eax, cr3
    mov cr3, eax
.ok_clc:
    clc
.r:
    ret

; ebp = address space (the current one), esi = first page, edi = end:
; unmaps and frees those pages
heap_unmap:
    cmp esi, edi
    jae .r
    call as_pte
    mov eax, [ebx]
    mov dword [ebx], 0
    mov dword [ebx+4], 0
    invlpg [esi]
    and eax, -PAGE_SIZE
    call pg_free
    dec dword [ebp+AS_PAGES]
    add esi, PAGE_SIZE
    jmp heap_unmap
.r:
    ret

; ebp = address space, esi = virtual address -> ebx = its page table
; entry; a ring-3 PD and PT are made on first use. CF if there is no
; memory for them. Clobbers eax. Keeps edx (sys_sbrk keeps the old break
; there).
as_pte:
    push edx
    mov ebx, [ebp+AS_PD]
    mov eax, esi
    shr eax, 30                 ; PDPT index
    lea ebx, [ebx+eax*8]
    mov eax, [ebx]
    test eax, eax
    jnz .have_pd
    call pg_alloc
    test eax, eax
    jz .no
    inc dword [ebp+AS_PAGES]
    or eax, PG_P                ; PDPTE: W is reserved
    mov [ebx], eax
    mov dword [ebx+4], 0
    ; Permanent stay walks the LM PDPT: mirror a new PAE PDPTE there
    ; (ring-3 stacks live in PDPT[1] at 0x7FC00000 — 2.9-lm-ring3-stay).
    cmp dword [lm_perm], 0
    je .have_pd
    push eax
    mov eax, ebp
    call as_lm_sync
    mov eax, cr3
    mov cr3, eax                ; flush cached non-present walks
    pop eax
.have_pd:
    and eax, -PAGE_SIZE
    mov edx, esi
    shr edx, PAE_PD_SHIFT
    and edx, PAE_IDX_MASK
    lea ebx, [eax+edx*8]
    mov eax, [ebx]
    test eax, eax
    jnz .have_pt
    call pg_alloc
    test eax, eax
    jz .no
    inc dword [ebp+AS_PAGES]
    or eax, PG_P|PG_W|PG_U
    mov [ebx], eax
    mov dword [ebx+4], 0        ; NX is on PTEs only (stack top page must stay executable)
    mov eax, [ebx]
.have_pt:
    test eax, PG_PS
    jnz .no                     ; a 2 MB page: not a table
    and eax, -PAGE_SIZE
    mov edx, esi
    shr edx, PAE_PT_SHIFT
    and edx, PAE_IDX_MASK
    lea ebx, [eax+edx*8]
    pop edx
    clc
    ret
.no:
    pop edx
    stc
    ret

; ---------- ring-3 stacks (2.4) ----------

; edi = PCB -> eax = the top of its ring-3 stack window
vm_ustack_top:
    mov eax, edi
    sub eax, proc_table
    shr eax, 6                  ; / PCB_SIZE: the slot
    inc eax
    imul eax, USTACK_SIZE
    add eax, USTACK_BASE
    ret

; eax = fault address (CR2) -> eax = 0 when it was in the current
; thread's own ring-3 stack window and a zeroed page is now mapped there,
; 1 when it hit that window's guard page, 2 for anything else (also out
; of memory), 3 when that page is already mapped (a fault there is a
; protection fault). Keeps the other registers.
vm_ustack_fault:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    mov esi, eax
    mov eax, 2
    mov edi, [proc_cur]
    mov ebp, [edi+PCB_AS]
    test ebp, ebp
    jz .out                     ; kernel processes have no ring-3 stack
    push eax
    call vm_ustack_top
    mov ecx, eax                ; top
    pop eax
    cmp esi, ecx
    jae .out
    lea edx, [ecx-USTACK_SIZE]  ; the window's bottom: the guard page
    cmp esi, edx
    jb .out
    sub esi, edx
    cmp esi, PAGE_SIZE
    jb .guard
    add esi, edx
    and esi, -PAGE_SIZE
    call as_pte
    jc .no
    mov eax, 3
    cmp dword [ebx], 0
    jne .out                    ; already mapped
    call pg_alloc
    test eax, eax
    jz .no
    or eax, PG_P|PG_W|PG_U
    mov [ebx], eax
    ; NX on stack pages, except the window's top page: the exit stub
    ; that proc_enter_user writes there must stay executable (2.4, 2.8-pae)
    call vm_nx_hi
    lea edx, [ecx-PAGE_SIZE]
    cmp esi, edx
    jb .nx
    xor eax, eax
.nx:
    mov [ebx+4], eax
    inc dword [ebp+AS_PAGES]
    invlpg [esi]
    xor eax, eax
    jmp .out
.guard:
    mov eax, 1
    jmp .out
.no:
    mov eax, 2
.out:
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ---------- framebuffer map (2.1) ----------
; eax = physical address (any), ecx = byte length.
; Identity-maps enough 2 MB pages (PAE PS) in the kernel page tables to
; cover [eax, eax+ecx). Addresses below MM_LIMIT are already mapped.
; Reloads CR3. CF set if ecx is 0. Keeps registers (pushad/popad).
; Under permanent long-mode stay CR3 is a PML4, not a PAE PDPT: never
; feed it to vm_pde_in_root (that would corrupt PML4[0..3]). Map the
; process PAE PDPT instead and refresh the LM wrappers (2.9-lm-kernel).
vm_map_range:
    pushad
    test ecx, ecx
    jz .fail
    mov edx, eax                ; start
    lea ebp, [eax+ecx-1]        ; last byte (ebp: end; ebx is the PDE pointer)
    and edx, -PAE_2MB           ; 2 MB align down
    or ebp, PAE_2MB-1           ; align up to end of its 2 MB page
    inc ebp                     ; first byte past the range
.map:
    cmp edx, ebp
    jae .ok
    cmp edx, MM_LIMIT           ; already identity-mapped
    jb .next
    mov esi, edx
    call vm_kernel_pde          ; ebx = &PDE in the kernel tables
    jc .next
    mov eax, edx
    or eax, PG_P|PG_W|PG_PS
    mov [ebx], eax
    mov dword [ebx+4], 0
    cmp dword [lm_perm], 0
    jne .stay_cur               ; CR3 is PML4 — do not treat as PAE PDPT
    mov ecx, cr3                ; and in the directory in use, when a
    and ecx, -4096              ; program asked (2.2-progwin)
    cmp ecx, [kernel_pd]
    je .next
    mov esi, edx
    mov eax, ecx
    call vm_pde_in_root         ; ebx = &PDE in the current root
    jc .next
    mov eax, edx
    or eax, PG_P|PG_W|PG_PS
    mov [ebx], eax
    mov dword [ebx+4], 0
    jmp .next
.stay_cur:
    mov eax, [proc_cur]
    test eax, eax
    jz .next
    mov eax, [eax+PCB_AS]
    test eax, eax
    jz .next                    ; shell shares the kernel tables
    mov eax, [eax+AS_PD]
    test eax, eax
    jz .next
    mov esi, edx
    call vm_pde_in_root
    jc .next
    mov eax, edx
    or eax, PG_P|PG_W|PG_PS
    mov [ebx], eax
    mov dword [ebx+4], 0
.next:
    add edx, PAE_2MB
    jmp .map
.ok:
    cmp dword [lm_perm], 0
    jne .lm_ok
    mov eax, cr3                ; flush TLB / reload PAE PDPTRs
    mov cr3, eax
    popad
    clc
    ret
.lm_ok:
    ; New PAE PDPTEs (high MMIO) must appear in the LM PDPT; shared PDs
    ; already show new PDEs, but a fresh PDPTE does not until sync.
    xor eax, eax
    call as_lm_sync             ; kernel wrapper
    mov eax, [proc_cur]
    test eax, eax
    jz .lm_cr3
    mov eax, [eax+PCB_AS]
    test eax, eax
    jz .lm_cr3
    call as_lm_sync             ; current process wrapper
.lm_cr3:
    mov edi, [proc_cur]
    test edi, edi
    jz .lm_kern
    call vm_load                ; PML4 for this PCB (or kernel if AS=0)
    jmp .lm_done
.lm_kern:
    xor eax, eax
    call as_lm_cr3
    jc .lm_done
    mov cr3, eax
.lm_done:
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; esi = address -> ebx = &PDE in the kernel tables (creates a PD when
; needed). CF if out of memory. Clobbers eax, edi.
vm_kernel_pde:
    mov eax, [kernel_pd]
    jmp vm_pde_in_root

; eax = PDPT, esi = address -> ebx = &PDE (allocates a PD when the PDPTE
; is empty). CF if out of memory. Keeps edx (vm_map_range walks with it).
vm_pde_in_root:
    push edx
    push edi
    mov edi, eax
    mov eax, esi
    shr eax, 30
    lea ebx, [edi+eax*8]
    mov eax, [ebx]
    test eax, eax
    jnz .pd
    call pg_alloc
    test eax, eax
    jz .no
    or eax, PG_P                ; PDPTE: W is reserved
    mov [ebx], eax
    mov dword [ebx+4], 0
.pd:
    and eax, -PAGE_SIZE
    mov edx, esi
    shr edx, PAE_PD_SHIFT
    and edx, PAE_IDX_MASK
    lea ebx, [eax+edx*8]
    pop edi
    pop edx
    clc
    ret
.no:
    pop edi
    pop edx
    stc
    ret

; ---------- 4-level wrappers for long mode (2.9-lm-kernel paging) ----------
; PAE PDPTE.W is reserved, so the everyday PDPT cannot be CR3 in long mode
; with writable hierarchical permissions. Each address space (and the
; kernel) gets a PML4 whose PML4[0] points at a long-mode PDPT that
; mirrors the PAE PDPT's present entries with P|W and the same page
; directory pointers. Everyday CR3 stays the PAE PDPT; lm_call loads the
; PML4. Refresh before every long-mode entry so late PDPTEs (heap, MMIO)
; are visible.

; eax = address space record, or 0 for the kernel.
; Builds the wrapper if needed and copies PAE PDPT[0..3] into the
; long-mode PDPT. -> CF set if out of memory. Keeps every register
; except the flags.
as_lm_sync:
    pushad
    mov ebp, eax                ; AS or 0
    test ebp, ebp
    jnz .proc
    mov esi, [kernel_pd]        ; PAE PDPT
    mov edi, kernel_pml4        ; where to store the PML4 pointer
    jmp .have_src
.proc:
    mov esi, [ebp+AS_PD]
    lea edi, [ebp+AS_PML4]
.have_src:
    test esi, esi
    jz .fail
    mov ebx, [edi]              ; existing PML4?
    test ebx, ebx
    jnz .refresh
    call pg_alloc               ; PML4
    test eax, eax
    jz .fail
    mov ebx, eax
    call pg_alloc               ; long-mode PDPT
    test eax, eax
    jz .fail_pml4
    mov edx, eax
    or eax, PG_P|PG_W|PG_U      ; U: ring-3 page walks under permanent stay
    mov [ebx], eax              ; PML4[0] -> LM PDPT (high dword 0)
    mov dword [ebx+4], 0
    mov [edi], ebx
    test ebp, ebp
    jz .refresh
    add dword [ebp+AS_PAGES], 2
.refresh:
    mov edx, [ebx]              ; LM PDPT
    and edx, -PAGE_SIZE
    ; Existing PML4[0] may predate the U bit — keep it user-walkable.
    mov eax, [ebx]
    or eax, PG_P|PG_W|PG_U
    mov [ebx], eax
    xor ecx, ecx                ; PDPTE index 0..3
.copy:
    mov eax, [esi+ecx*8]
    test eax, PG_P
    jz .empty
    and eax, -PAGE_SIZE
    or eax, PG_P|PG_W|PG_U      ; long-mode PDPTE: W + U (ring-3 stay)
    mov [edx+ecx*8], eax
    mov dword [edx+ecx*8+4], 0
    jmp .next
.empty:
    mov dword [edx+ecx*8], 0
    mov dword [edx+ecx*8+4], 0
.next:
    inc ecx
    cmp ecx, PAE_PDPT_ENTS
    jb .copy
    popad
    clc
    ret
.fail_pml4:
    mov eax, ebx
    call pg_free
.fail:
    popad
    stc
    ret

; eax = address space record, or 0 for the kernel.
; Syncs the 4-level wrapper -> eax = PML4 physical address, CF on failure.
; Clobbers nothing else (pushad around the sync's allocations path via
; as_lm_sync; then reloads the pointer).
as_lm_cr3:
    push ebx
    mov ebx, eax
    call as_lm_sync
    jc .r
    test ebx, ebx
    jnz .proc
    mov eax, [kernel_pml4]
    jmp .ok
.proc:
    mov eax, [ebx+AS_PML4]
.ok:
    test eax, eax
    jz .bad
    pop ebx
    clc
    ret
.bad:
    stc
.r:
    pop ebx
    ret

vm_m_nomem db '*** no memory for page tables', 10, 0

align 4
kernel_pd dd 0                  ; PDPT (CR3 in PAE)
kernel_pd0 dd 0                 ; page directory for 0-1 GB
kernel_pt dd 0                  ; 0-2 MB page table
kernel_pt_hi dd 0               ; 2-4 MB page table
kernel_pml4 dd 0                ; 4-level root for long mode (2.9); never freed (boot-lifetime)
vm_nx db 0                      ; 1: NX is available and EFER.NXE is on
as_table times AS_MAX*AS_SIZE db 0
