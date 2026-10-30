; Squirrel-OS/2 — paging and per-process address spaces (0.6.1)
; Included from pm.asm. Original code.
;
; Paging is on from boot. The kernel's page directory identity-maps the
; first 256 MB: 0-4 MB with 4 KB pages (one page table), the rest with
; 4 MB pages. Every loaded program gets an address space of its own: a
; copy of that directory and of the low page table, with the program
; area (PROG_BASE, 64 KB) backed by fresh pages. So two programs linked
; at the same address can be alive at once, and a program's stray
; access above 256 MB faults and ends only that program.
; See documentation/kernel/memory.md.

PG_P        equ 1                   ; present
PG_W        equ 2                   ; writable
PG_PS       equ 0x80                ; 4 MB page (needs CR4.PSE)
VM_IDENT    equ MM_LIMIT >> 22      ; identity-mapped 4 MB slots: 64

PROG_PTE    equ PROG_BASE >> 12     ; first page-table entry of the area
PROG_PAGES  equ PROG_MAX >> 12      ; 16

; address space record
AS_PD       equ 0                   ; page directory (physical)
AS_REFS     equ 4                   ; processes using it; 0 = slot free
AS_PAGES    equ 8                   ; pages it owns (tables included)
AS_SIZE     equ 16
AS_MAX      equ PROC_MAX

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
    or eax, PG_P|PG_W
    mov [esi], eax
    mov ecx, PROG_PAGES
.area:
    call pg_alloc
    test eax, eax
    jz .fail
    or eax, PG_P|PG_W
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

vm_m_nomem db '*** no memory for page tables', 10, 0

align 4
kernel_pd dd 0
kernel_pt dd 0
as_table times AS_MAX*AS_SIZE db 0
