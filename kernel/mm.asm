; Squirrel-OS/2 — physical page allocator (0.6.0)
; Included from pm.asm. Original code.
;
; Manages 4 KB pages of RAM above 1 MB, as reported by the BIOS memory
; map (E820, read in real mode by stage2). Free pages form a singly
; linked list threaded through the pages themselves; a bitmap marks
; pages in use so bad and double frees are refused.
; See documentation/kernel/memory.md.

PAGE_SIZE   equ 4096
MM_START    equ 0x100000            ; first managed address (1 MB)
MM_LIMIT    equ 0x10000000          ; manage at most 256 MB
MM_BITMAP   equ 0x58000             ; 1 bit per page below MM_LIMIT: 8 KB
E820_BUF    equ 0x1000              ; entries left by stage2 (24 bytes each)
E820_MAX    equ 32
MM_FALLBACK equ 0x2000000           ; assume 32 MB if there is no map

; Builds the free list from the memory map.
mm_init:
    pushad
    ; every page starts "in use"; free ones are cleared below
    mov edi, MM_BITMAP
    mov ecx, MM_LIMIT/PAGE_SIZE/32
    mov eax, -1
    rep stosd
    mov dword [mm_head], 0
    mov dword [mm_free], 0
    mov dword [mm_total], 0
    mov dword [mm_top], 0
    movzx ecx, word [e820_count]
    test ecx, ecx
    jz .fallback
    mov esi, E820_BUF
.entry:
    cmp dword [esi+16], 1       ; type 1 = usable RAM
    jne .next
    cmp dword [esi+4], 0        ; ignore anything at or above 4 GB
    jne .next
    mov eax, [esi]              ; base
    mov edx, [esi+12]
    test edx, edx
    mov edx, [esi+8]            ; length (capped below 4 GB)
    jz .len
    mov edx, -1
.len:
    add edx, eax                ; end
    jnc .add
    mov edx, -1
.add:
    call mm_add_range
.next:
    add esi, 24
    loop .entry
    cmp dword [mm_total], 0
    jne .out
.fallback:
    mov eax, MM_START
    mov edx, MM_FALLBACK
    call mm_add_range
    mov byte [mm_guessed], 1
.out:
    popad
    ret

; eax = start, edx = end of usable RAM: frees its whole pages within
; [MM_START, MM_LIMIT)
mm_add_range:
    cmp eax, MM_START
    jae .lo
    mov eax, MM_START
.lo:
    cmp edx, MM_LIMIT
    jbe .hi
    mov edx, MM_LIMIT
.hi:
    add eax, PAGE_SIZE-1
    and eax, -PAGE_SIZE
    and edx, -PAGE_SIZE
.p:
    cmp eax, edx
    jae .r
    inc dword [mm_total]
    cmp edx, [mm_top]
    jbe .push
    mov [mm_top], edx
.push:
    call mm_push
    add eax, PAGE_SIZE
    jmp .p
.r:
    ret

; eax = page: puts it on the free list and clears its bit
mm_push:
    push ebx
    mov ebx, [mm_head]
    mov [eax], ebx
    mov [mm_head], eax
    mov ebx, eax
    shr ebx, 12
    btr [MM_BITMAP], ebx
    inc dword [mm_free]
    pop ebx
    ret

; -> eax = a zeroed page, or 0 when memory is exhausted
pg_alloc:
    pushfd
    cli
    mov eax, [mm_head]
    test eax, eax
    jz .out
    push ebx
    push ecx
    push edi
    mov ebx, [eax]
    mov [mm_head], ebx
    dec dword [mm_free]
    mov ebx, eax
    shr ebx, 12
    bts [MM_BITMAP], ebx
    mov edi, eax
    mov ebx, eax
    xor eax, eax
    mov ecx, PAGE_SIZE/4
    rep stosd
    mov eax, ebx
    pop edi
    pop ecx
    pop ebx
.out:
    popfd
    ret

; eax = page -> eax = 0, or -1 if it is not an allocated page
pg_free:
    pushfd
    cli
    test eax, PAGE_SIZE-1
    jnz .bad
    cmp eax, MM_START
    jb .bad
    cmp eax, [mm_top]
    jae .bad
    push ebx
    mov ebx, eax
    shr ebx, 12
    bt [MM_BITMAP], ebx
    pop ebx
    jnc .bad                    ; already free
    call mm_push
    xor eax, eax
    popfd
    ret
.bad:
    mov eax, -1
    popfd
    ret

sys_palloc:
    jmp pg_alloc

sys_pfree:
    mov eax, ebx
    jmp pg_free

; ---------- shell: mem, memtest ----------

; mem: the BIOS map and the page counts
cmd_mem_run:
    pushad
    mov esi, mm_m_map
    call puts
    movzx ecx, word [e820_count]
    test ecx, ecx
    jz .counts
    mov ebx, E820_BUF
.e:
    mov al, ' '
    call putc
    mov eax, [ebx]
    call puthex
    mov al, '-'
    call putc
    mov eax, [ebx]
    add eax, [ebx+8]
    dec eax
    call puthex
    mov esi, mm_m_usable
    cmp dword [ebx+16], 1
    je .t
    mov esi, mm_m_reserved
.t:
    call puts
    add ebx, 24
    loop .e
.counts:
    mov esi, mm_m_pages
    call puts
    mov eax, [mm_total]
    shl eax, 2
    call itoa
    mov esi, num_buf
    call puts
    mov esi, mm_m_kbtotal
    call puts
    mov eax, [mm_free]
    shl eax, 2
    call itoa
    mov esi, num_buf
    call puts
    mov esi, mm_m_kbfree
    call puts
    cmp byte [mm_guessed], 0
    je .out
    mov esi, mm_m_guess
    call puts
.out:
    popad
    ret

; memtest: allocates every page, checks each is zeroed and distinct,
; frees them all and checks the counts and the double-free guard.
cmd_memtest_run:
    pushad
    mov ebp, [mm_free]
    xor edx, edx                ; pages taken
    xor esi, esi                ; chain of taken pages (first dword)
.take:
    call pg_alloc
    test eax, eax
    jz .taken
    cmp dword [eax+PAGE_SIZE-4], 0
    jne .fail
    mov [eax], esi              ; link it, and mark the page
    mov [eax+4], eax
    mov esi, eax
    inc edx
    jmp .take
.taken:
    cmp dword [mm_free], 0
    jne .fail
    cmp edx, ebp
    jne .fail
    ; give them back, checking each still holds its own address
.give:
    test esi, esi
    jz .given
    cmp [esi+4], esi
    jne .fail
    mov eax, esi
    mov esi, [esi]
    call pg_free
    test eax, eax
    jnz .fail
    jmp .give
.given:
    cmp [mm_free], ebp
    jne .fail
    ; a second free of the same page and a misaligned free are refused
    call pg_alloc
    mov ebx, eax
    call pg_free
    mov eax, ebx
    call pg_free
    cmp eax, -1
    jne .fail
    mov eax, MM_START+12
    call pg_free
    cmp eax, -1
    jne .fail
    cmp [mm_free], ebp
    jne .fail
    mov esi, mm_m_pass
    call puts
    mov eax, edx
    call itoa
    mov esi, num_buf
    call puts
    mov esi, mm_m_passend
    call puts
    popad
    ret
.fail:
    mov esi, mm_m_fail
    call puts
    popad
    ret

mm_m_map db 'BIOS memory map:', 10, 0
mm_m_usable db '  usable', 10, 0
mm_m_reserved db '  reserved', 10, 0
mm_m_pages db 'Pages above 1 MB: ', 0
mm_m_kbtotal db ' KB total, ', 0
mm_m_kbfree db ' KB free', 10, 0
mm_m_guess db '(no BIOS map: assumed 32 MB)', 10, 0
mm_m_pass db 'memtest: PASS (', 0
mm_m_passend db ' pages)', 10, 0
mm_m_fail db 'memtest: FAIL', 10, 0

align 4
mm_head dd 0
mm_free dd 0
mm_total dd 0
mm_top dd 0
mm_guessed db 0
