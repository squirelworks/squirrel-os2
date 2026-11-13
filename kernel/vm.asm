; Squirrel-OS/2 — paging and per-process address spaces (0.6.1)
; Included from pm.asm. Original code.
;
; Paging is on from boot. The kernel's page directory identity-maps the
; first 256 MB: 0-4 MB with 4 KB pages (one page table), the rest with
; 4 MB pages. Every loaded program gets an address space of its own: a
; copy of that directory and of the low page table, with the program
; area (PROG_BASE, 64 KB) backed by fresh pages. So two programs linked
; at the same address can be alive at once, and a program's stray
; access above 256 MB faults and ends only that program. Since 0.6.2 a
; program also has a heap at HEAP_BASE that SYS_SBRK grows and shrinks.
; See documentation/kernel/memory.md.

PG_P        equ 1                   ; present
PG_W        equ 2                   ; writable
PG_U        equ 4                   ; ring 3 may use it (2.4)
PG_PS       equ 0x80                ; 4 MB page (needs CR4.PSE)
VM_IDENT    equ MM_LIMIT >> 22      ; identity-mapped 4 MB slots: 64

PROG_PTE    equ PROG_BASE >> 12     ; first page-table entry of the area
PROG_PAGES  equ PROG_MAX >> 12      ; 16

; address space record
AS_PD       equ 0                   ; page directory (physical)
AS_REFS     equ 4                   ; processes using it; 0 = slot free
AS_PAGES    equ 8                   ; pages it owns (tables included)
AS_BRK      equ 12                  ; end of the heap (0.6.2)
AS_SIZE     equ 16
AS_MAX      equ PROC_MAX

HEAP_BASE   equ 0x40000000          ; heap: one page table, PDE 256
HEAP_MAX    equ 0x400000
HEAP_PDE    equ HEAP_BASE >> 22

; Ring-3 stacks (2.4): one 512 KB window per process slot in the top 4 MB
; below 2 GB, one page table (PDE 511). Pages are mapped when first
; touched (vm_ustack_fault); the lowest page of each window never is, so
; a runaway stack faults there and is reported as a stack overflow.
USTACK_BASE equ 0x7FC00000
USTACK_SIZE equ 0x80000
USTACK_PDE  equ USTACK_BASE >> 22
%if PROC_MAX*USTACK_SIZE > 0x400000
%error the ring-3 stack windows must fit one page table
%endif

; Builds the kernel page directory and turns paging on.
vm_init:
    pushad
    call pg_alloc               ; page table for 0-4 MB
    test eax, eax
    jz .nomem
    mov [kernel_pt], eax
    mov edi, eax
    mov eax, PG_P|PG_W
    mov ecx, 1024
.pt:
    stosd
    add eax, PAGE_SIZE
    loop .pt
    ; stack guard pages (KB-17): not present, so running off the bottom
    ; of a stack faults instead of writing the memory below it. Program
    ; address spaces copy this table, so they have the holes too.
    mov edi, [kernel_pt]
    add edi, (PROC_STACK_BASE >> 12) * 4
    mov ecx, PROC_GUARDS
.guard:
    mov dword [edi], 0
    add edi, (PROC_STACK_SIZE >> 12) * 4
    loop .guard
    call pg_alloc
    test eax, eax
    jz .nomem
    mov [kernel_pd], eax
    mov edi, eax
    mov eax, [kernel_pt]
    or eax, PG_P|PG_W
    stosd
    mov eax, (1 << 22)|PG_P|PG_W|PG_PS
    mov ecx, VM_IDENT-1
.pd:
    stosd
    add eax, 1 << 22
    loop .pd
    mov eax, cr4
    or eax, 0x10                ; PSE
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

; -> eax = a new address space (record pointer), or 0 if out of
; records or memory. Its program area is zeroed.
as_create:
    push ebx
    push ecx
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
    call pg_alloc
    test eax, eax
    jz .fail
    mov [ebx+AS_PD], eax
    inc dword [ebx+AS_PAGES]
    mov edi, eax
    mov esi, [kernel_pd]
    mov ecx, 1024
    rep movsd
    call pg_alloc               ; private copy of the 0-4 MB table
    test eax, eax
    jz .fail
    inc dword [ebx+AS_PAGES]
    mov edi, eax
    mov esi, [kernel_pt]
    mov ecx, 1024
    rep movsd
    mov esi, [ebx+AS_PD]
    lea edi, [eax+PROG_PTE*4]
    or eax, PG_P|PG_W|PG_U      ; the identity entries in it stay kernel-only
    mov [esi], eax
    mov ecx, PROG_PAGES
.area:
    call pg_alloc
    test eax, eax
    jz .fail
    or eax, PG_P|PG_W|PG_U
    stosd
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
    mov esi, [ebx+AS_PD]
    test esi, esi
    jz .done
    mov edx, [esi+HEAP_PDE*4]   ; heap pages and their table
    call as_free_table
    mov edx, [esi+USTACK_PDE*4] ; ring-3 stack pages and their table (2.4)
    call as_free_table
.low:
    mov edx, [esi]
    and edx, -PAGE_SIZE         ; its 0-4 MB table
    cmp edx, [kernel_pt]
    je .pd                      ; not replaced yet
    mov ecx, PROG_PAGES
    lea edi, [edx+PROG_PTE*4]
.area:
    mov eax, [edi]
    and eax, -PAGE_SIZE
    cmp eax, MM_START           ; still the identity entry: not ours
    jb .next
    call pg_free
.next:
    add edi, 4
    loop .area
    mov eax, edx
    call pg_free
.pd:
    mov eax, esi
    call pg_free
.done:
    mov dword [ebx+AS_PD], 0
    mov dword [ebx+AS_REFS], 0
    mov dword [ebx+AS_PAGES], 0
    popad
    ret

; edx = a page directory entry (0: none): frees every page its table
; maps, then the table. Clobbers eax, ecx, edi.
as_free_table:
    test edx, edx
    jz .r
    and edx, -PAGE_SIZE
    mov ecx, 1024
    mov edi, edx
.p:
    mov eax, [edi]
    test eax, eax
    jz .n
    and eax, -PAGE_SIZE
    call pg_free
.n:
    add edi, 4
    loop .p
    mov eax, edx
    call pg_free
.r:
    ret

; edi = PCB: loads its page directory (if not already loaded).
; Clobbers eax, ebx.
vm_load:
    mov eax, [kernel_pd]
    mov ebx, [edi+PCB_AS]
    test ebx, ebx
    jz .k
    mov eax, [ebx+AS_PD]
.k:
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
; maps fresh pages -> esi = where it stopped, CF if memory ran out
heap_map:
    cmp esi, edi
    jae .ok
    call heap_pte
    jc .r
    call pg_alloc
    test eax, eax
    jz .no
    or eax, PG_P|PG_W|PG_U
    mov [ebx], eax
    inc dword [ebp+AS_PAGES]
    add esi, PAGE_SIZE
    jmp heap_map
.no:
    stc
    ret
.ok:
    clc
.r:
    ret

; ebp = address space (the current one), esi = first page, edi = end:
; unmaps and frees those pages
heap_unmap:
    cmp esi, edi
    jae .r
    call heap_pte
    mov eax, [ebx]
    mov dword [ebx], 0
    invlpg [esi]
    and eax, -PAGE_SIZE
    call pg_free
    dec dword [ebp+AS_PAGES]
    add esi, PAGE_SIZE
    jmp heap_unmap
.r:
    ret

; ebp = address space, esi = heap address -> ebx = its page table
; entry; the table is made on first use. CF if there is no memory for it.
heap_pte:
    push edx
    mov edx, HEAP_PDE
    call as_pte
    pop edx
    ret

; ebp = address space, esi = address, edx = its directory index -> ebx =
; its page table entry; a ring-3 table is made on first use. CF if there
; is no memory for it.
as_pte:
    mov ebx, [ebp+AS_PD]
    mov eax, [ebx+edx*4]
    test eax, eax
    jnz .have
    call pg_alloc
    test eax, eax
    jz .no
    inc dword [ebp+AS_PAGES]
    or eax, PG_P|PG_W|PG_U
    mov [ebx+edx*4], eax
.have:
    and eax, -PAGE_SIZE
    mov ebx, esi
    shr ebx, 12
    and ebx, 1023
    lea ebx, [eax+ebx*4]
    clc
    ret
.no:
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
    mov edx, USTACK_PDE
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
; Identity-maps enough 4 MB pages (PSE) in the kernel page directory to
; cover [eax, eax+ecx). Addresses below MM_LIMIT are already mapped.
; Reloads CR3. CF set if ecx is 0. Keeps registers (pushad/popad).
vm_map_range:
    pushad
    test ecx, ecx
    jz .fail
    mov edx, eax                ; start
    lea ebx, [eax+ecx-1]        ; last byte
    and edx, -0x400000          ; 4 MB align down
    or ebx, 0x3FFFFF            ; align up to end of its 4 MB page
    inc ebx                     ; first byte past the range
.map:
    cmp edx, ebx
    jae .ok
    cmp edx, MM_LIMIT           ; already identity-mapped
    jb .next
    mov eax, edx
    shr eax, 22                 ; PDE index
    mov ecx, [kernel_pd]
    lea ecx, [ecx+eax*4]
    mov eax, edx
    or eax, PG_P|PG_W|PG_PS
    mov [ecx], eax
    mov ecx, cr3                ; and in the directory in use, when a program
    and ecx, -4096              ; asked (2.2-progwin): its own copy of the
    mov esi, edx                ; kernel directory was made before this map
    shr esi, 22
    mov [ecx+esi*4], eax
.next:
    add edx, 0x400000
    jmp .map
.ok:
    mov eax, cr3                ; flush TLB for the new entries, staying in
    mov cr3, eax                ; the address space in use (2.2-progwin)
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

vm_m_nomem db '*** no memory for page tables', 10, 0

align 4
kernel_pd dd 0
kernel_pt dd 0
as_table times AS_MAX*AS_SIZE db 0
