; os2run — OS/2 32-bit text-mode programs on Squirrel-OS/2 (P.9). Original
; code, written from the public description of the LX executable format
; and the documented DOSCALLS interface; no IBM or other OS/2 code.
;
;   run os2run prog.exe [arguments]
;   run prog.exe [arguments]          (the kernel loader hands LX files here)
;
; os2run is an ordinary SQX program. It reads the whole file into its heap,
; finds the LX header behind the MZ stub, gives every object page-aligned
; heap memory, copies the pages, applies the fixups (32-bit offsets and
; 32-bit self-relative, to internal objects and to imports by ordinal or
; by name), binds DOSCALLS imports to the _System shims below and any
; other import to a stub that names it when called, builds a thread and a
; process information block (TIB through FS, PIB), and calls the entry
; point on the program's stack object as entry(hmod, 0, env, cmdline).
; DosExit, or returning from the entry point, ends the program.
;
; Not provided: 16-bit code and fixups (16:16, selectors), iterated pages,
; DLLs of the program's own, threads, PM, VIO/KBD/MOU calls.
%include "sqx.inc"
SQX_HEADER main

STUB_MAX    equ 64
STUB_SIZE   equ 10              ; push imm32 / jmp rel32
OBJ_MAX     equ 16
PAGE_MAX    equ 256
H_FILE      equ 3               ; OS/2 handle = native fd + 3
NO_ERROR            equ 0
ERROR_FILE_NOT_FOUND equ 2
ERROR_ACCESS_DENIED equ 5
ERROR_INVALID_HANDLE equ 6
ERROR_NOT_ENOUGH_MEMORY equ 8
ERROR_INVALID_PARAMETER equ 87
ERROR_OPEN_FAILED   equ 110
ERROR_BUFFER_OVERFLOW equ 111
ERROR_ENVVAR_NOT_FOUND equ 203

main:
    mov esi, [esp+4]
    push ebx
    push esi
    push edi
    push ebp
    call load
    pop ebp
    pop edi
    pop esi
    pop ebx
    ret

; esi = argument text -> eax = the exit code
load:
    ; the command line: "name" NUL "arguments" NUL NUL, as OS/2 passes it
    mov edi, cmdline
    xor ecx, ecx
.nm:
    lodsb
    cmp al, ' '
    je .nmz
    test al, al
    jz .nmz
    cmp ecx, 31
    jae .nm
    mov [exe_name+ecx], al
    stosb
    inc ecx
    jmp .nm
.nmz:
    test ecx, ecx
    jz e_usage
    mov byte [edi], 0
    inc edi
    test al, al
    jz .tz
.ta:                            ; the arguments, after the spaces
    lodsb
    cmp al, ' '
    je .ta
.tc:
    test al, al
    jz .tz
    cmp edi, cmdline+126
    jae .tz
    stosb
    lodsb
    jmp .tc
.tz:
    mov word [edi], 0
    ; the whole file into the heap
    mov eax, SYS_OPEN
    mov ebx, exe_name
    xor ecx, ecx
    int 0x80
    cmp eax, -1
    je e_open
    mov [fd], eax
    mov ebx, eax
    mov eax, SYS_SEEK
    xor ecx, ecx
    mov edx, 2
    int 0x80
    cmp eax, 0x40
    jb e_format
    mov [flen], eax
    mov eax, SYS_SEEK
    mov ebx, [fd]
    xor ecx, ecx
    xor edx, edx
    int 0x80
    mov ebx, [flen]
    call grow
    jc e_nomem
    mov [fbuf], eax
    mov ecx, eax
    mov eax, SYS_READ
    mov ebx, [fd]
    mov edx, [flen]
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    mov ebx, [fd]
    int 0x80
    pop eax
    cmp eax, [flen]
    jne e_format
    ; MZ stub, then LX
    mov esi, [fbuf]
    cmp word [esi], 'MZ'
    jne e_format
    mov eax, [esi+0x3C]
    lea ecx, [eax+0xB0]
    cmp ecx, [flen]
    ja e_format
    add esi, eax
    mov [lx], esi
    cmp word [esi], 'LX'
    jne e_format
    cmp word [esi+8], 2         ; 80386 or later
    jb e_format
    cmp word [esi+10], 1        ; OS/2
    jne e_format
    test dword [esi+0x10], 0x38000 ; a DLL or a PDD/VDD, not a program
    jnz e_format
    cmp dword [esi+0x28], 0x1000 ; page size
    jne e_format
    mov ecx, [esi+0x44]
    test ecx, ecx
    jz e_format
    cmp ecx, OBJ_MAX
    ja e_format
    mov [nobj], ecx
    call place
    jc e_nomem
    call copy_pages
    jc e_format
    call fixups
    jc e_format
    call make_tib
    jc e_nomem
    ; the stack: the ESP object, or 64 KB of heap
    mov esi, [lx]
    mov eax, [esi+0x20]
    test eax, eax
    jz .ownstack
    dec eax
    cmp eax, [nobj]
    jae e_format
    mov eax, [obj_addr+eax*4]
    add eax, [esi+0x24]
    jmp .stack
.ownstack:
    mov ebx, 0x10000
    call grow
    jc e_nomem
    add eax, 0x10000
.stack:
    and eax, -4
    mov [prog_esp], eax
    mov ecx, [tib]
    mov [ecx+8], eax            ; tib_pstacklimit: the top
    sub eax, 0x10000
    mov [ecx+4], eax            ; tib_pstack
    mov eax, [esi+0x18]         ; EIP object and offset
    dec eax
    cmp eax, [nobj]
    jae e_format
    mov eax, [obj_addr+eax*4]
    add eax, [esi+0x1C]
    mov [entry], eax
    ; entry(hmod, 0, env, cmdline) on the program's stack
    mov [our_esp], esp
    mov esp, [prog_esp]
    push dword [pib+12]         ; pchcmd
    push dword [pib+16]         ; pchenv
    push 0
    push 1                      ; hmod
    call [entry]
    mov esp, [our_esp]
    ret

; heap for every object, each page aligned -> obj_addr[]
place:
    call page_align
    jc .r
    mov esi, [lx]
    add esi, [esi+0x40]         ; object table
    xor ebp, ebp
.o:
    mov ebx, [esi]              ; virtual size
    add ebx, 0xFFF
    and ebx, -0x1000
    jnz .sz
    mov ebx, 0x1000
.sz:
    call grow
    jc .r
    mov [obj_addr+ebp*4], eax
    mov edi, eax                ; zeroed: the heap may hold old data
    mov ecx, ebx
    shr ecx, 2
    xor eax, eax
    rep stosd
    add esi, 24
    inc ebp
    cmp ebp, [nobj]
    jb .o
    clc
.r:
    ret

; copies each object's pages from the file; page_addr[] for the fixups
copy_pages:
    mov esi, [lx]
    mov ebx, esi
    add ebx, [esi+0x40]         ; object table
    xor ebp, ebp
.o:
    mov ecx, [ebx+16]           ; page count
    mov edx, [ebx+12]           ; first page (1-based)
    mov edi, [obj_addr+ebp*4]
.p:
    jecxz .on
    cmp edx, PAGE_MAX
    ja .bad
    cmp edx, [esi+0x14]         ; within the module's pages
    ja .bad
    mov [page_addr+edx*4-4], edi
    push ecx
    push esi
    ; page table entry: offset (shifted), size, flags
    mov eax, [esi+0x48]
    lea eax, [eax+edx*8-8]
    add eax, esi
    movzx ecx, word [eax+4]     ; bytes in the file
    movzx esi, word [eax+6]
    cmp esi, 3                  ; zero-filled (the heap is zero)
    je .next
    cmp esi, 1                  ; iterated: not provided
    je .badp
    cmp esi, 0
    jne .next                   ; invalid or range: left zero
    mov esi, [eax]
    mov eax, [lx]
    push ecx
    mov ecx, [eax+0x2C]         ; page offset shift
    shl esi, cl
    pop ecx
    add esi, [eax+0x80]         ; data pages, from the start of the file
    lea eax, [esi+ecx]
    cmp eax, [flen]
    ja .badp
    cmp ecx, 0x1000
    ja .badp
    add esi, [fbuf]
    push edi
    rep movsb
    pop edi
.next:
    pop esi
    pop ecx
    add edi, 0x1000
    inc edx
    dec ecx
    jmp .p
.on:
    add ebx, 24
    inc ebp
    cmp ebp, [nobj]
    jb .o
    clc
    ret
.badp:
    pop esi
    pop ecx
.bad:
    stc
    ret

; every page's fixup records
fixups:
    mov esi, [lx]
    mov eax, [esi+0x14]         ; pages in the module
    mov [npages], eax
    xor ebp, ebp                ; page index, 0-based
.pg:
    cmp ebp, [npages]
    jae .done
    mov esi, [lx]
    mov eax, [esi+0x68]         ; fixup page table
    add eax, esi
    mov ecx, [eax+ebp*4]
    mov edx, [eax+ebp*4+4]
    mov eax, [esi+0x6C]         ; fixup records
    add eax, esi
    add ecx, eax
    add edx, eax
    mov [rec_end], edx
    mov eax, [page_addr+ebp*4]
    mov [cur_page], eax
    mov esi, ecx
.rec:
    cmp esi, [rec_end]
    jae .np
    cmp dword [cur_page], 0
    je .bad
    call fixup_one
    jc .bad
    jmp .rec
.np:
    inc ebp
    jmp .pg
.done:
    clc
    ret
.bad:
    stc
    ret

; esi = one fixup record -> applied, esi past it; CF if not understood
fixup_one:
    lodsb
    mov [f_src], al
    lodsb
    mov [f_flags], al
    test byte [f_src], 0x20     ; a source list: the count now, offsets last
    jz .one
    lodsb
    movzx eax, al
    mov [f_count], eax
    jmp .target
.one:
    lodsw
    movsx eax, ax
    mov [f_off], eax
    mov dword [f_count], 0
.target:
    mov al, [f_flags]
    and al, 3
    cmp al, 0
    je .internal
    cmp al, 1
    je .ordinal
    cmp al, 2
    je .byname
    stc                         ; via the entry table: not provided
    ret
.internal:
    call .objnum
    dec eax
    cmp eax, [nobj]
    jae .bad
    mov edx, [obj_addr+eax*4]
    mov al, [f_src]
    and al, 15
    cmp al, 2                   ; a selector has no offset
    je .bad
    test byte [f_flags], 0x10
    jz .t16
    lodsd
    jmp .tadd
.t16:
    xor eax, eax
    lodsw
.tadd:
    add edx, eax
    jmp .additive
.ordinal:
    call .objnum                ; the module
    mov [f_mod], eax
    test byte [f_flags], 0x80
    jz .o16
    xor eax, eax
    lodsb
    jmp .ores
.o16:
    test byte [f_flags], 0x10
    jz .o16b
    lodsd
    jmp .ores
.o16b:
    xor eax, eax
    lodsw
.ores:
    mov [f_ord], eax
    mov dword [f_name], 0
    call resolve
    jc .bad
    mov edx, eax
    jmp .additive
.byname:
    call .objnum
    mov [f_mod], eax
    test byte [f_flags], 0x10
    jz .n16
    lodsd
    jmp .nres
.n16:
    xor eax, eax
    lodsw
.nres:
    mov ecx, [lx]
    add eax, [ecx+0x78]         ; import procedure name table
    add eax, ecx
    mov [f_name], eax
    mov dword [f_ord], 0
    call resolve
    jc .bad
    mov edx, eax
.additive:
    test byte [f_flags], 0x04
    jz .apply
    test byte [f_flags], 0x20
    jz .a16
    lodsd
    jmp .aadd
.a16:
    xor eax, eax
    lodsw
.aadd:
    add edx, eax
.apply:                         ; edx = the target's address
    mov ecx, [f_count]
    jecxz .single
.list:
    push ecx
    lodsw
    movsx eax, ax
    mov [f_off], eax
    call .site
    pop ecx
    jc .bad
    loop .list
    clc
    ret
.single:
    jmp .site
.site:
    mov edi, [cur_page]
    add edi, [f_off]
    mov al, [f_src]
    and al, 15
    cmp al, 7                   ; 32-bit offset
    je .abs
    cmp al, 8                   ; 32-bit self-relative
    jne .bad
    mov eax, edx
    sub eax, edi
    sub eax, 4
    mov [edi], eax
    clc
    ret
.abs:
    mov [edi], edx
    clc
    ret
.objnum:                        ; -> eax = object or module number
    test byte [f_flags], 0x40
    jz .ob8
    xor eax, eax
    lodsw
    ret
.ob8:
    xor eax, eax
    lodsb
    ret
.bad:
    stc
    ret

; f_mod, f_ord or f_name -> eax = the address to bind; CF when full
resolve:
    push esi
    push edi
    mov eax, [f_mod]
    call module_name            ; esi = its Pascal string
    jc .stub
    mov edi, s_doscalls
    call pas_eq
    jne .stub
    cmp dword [f_name], 0
    jne .stub                   ; DOSCALLS by name: not used by linkers
    mov eax, [f_ord]
    mov edi, dos_table
.f:
    cmp dword [edi], 0
    je .stub
    cmp [edi], eax
    je .hit
    add edi, 8
    jmp .f
.hit:
    mov eax, [edi+4]
    clc
    jmp .r
.stub:
    call make_stub
.r:
    pop edi
    pop esi
    ret

; eax = module number (1-based) -> esi = its name (Pascal); CF if none
module_name:
    mov esi, [lx]
    cmp eax, [esi+0x74]
    ja .no
    test eax, eax
    jz .no
    mov ecx, eax
    mov eax, [esi+0x70]
    add esi, eax
.n:
    dec ecx
    jz .yes
    movzx eax, byte [esi]
    lea esi, [esi+eax+1]
    jmp .n
.yes:
    clc
    ret
.no:
    stc
    ret

; esi, edi = Pascal strings -> ZF when equal, ignoring case
pas_eq:
    push ecx
    push esi
    push edi
    movzx ecx, byte [esi]
    cmp cl, [edi]
    jne .r
.c:
    dec ecx
    js .eq
    inc esi
    inc edi
    mov al, [esi]
    mov ah, [edi]
    or ax, 0x2020
    cmp al, ah
    jne .r
    jmp .c
.eq:
    xor eax, eax                ; ZF
.r:
    pop edi
    pop esi
    pop ecx
    ret

; a stub that names the import (module, ordinal or name) when called
make_stub:
    mov eax, [nstubs]
    cmp eax, STUB_MAX
    jae .full
    inc dword [nstubs]
    mov ecx, [f_mod]
    mov [stub_mod+eax*4], ecx
    mov ecx, [f_ord]
    mov [stub_ord+eax*4], ecx
    mov ecx, [f_name]
    mov [stub_name+eax*4], ecx
    mov ecx, eax
    imul eax, STUB_SIZE
    add eax, stubs
    mov byte [eax], 0x68        ; push imm32 (the stub's number)
    mov [eax+1], ecx
    mov byte [eax+5], 0xE9      ; jmp rel32
    mov edx, missing
    sub edx, eax
    sub edx, STUB_SIZE
    mov [eax+6], edx
    clc
    ret
.full:
    stc
    ret

; [esp] = the stub's number: "os2run: MODULE.ordinal is not implemented"
missing:
    pop ebp
    mov esp, [our_esp]          ; back on os2run's own stack
    mov ebx, m_missing
    call puts
    mov eax, [stub_mod+ebp*4]
    call module_name
    jc .noname
    movzx ecx, byte [esi]
    inc esi
.mn:
    jecxz .dot
    movzx ebx, byte [esi]
    mov eax, SYS_PUTC
    int 0x80
    inc esi
    dec ecx
    jmp .mn
.noname:
.dot:
    mov eax, SYS_PUTC
    mov ebx, '.'
    int 0x80
    mov esi, [stub_name+ebp*4]
    test esi, esi
    jz .ord
    movzx ecx, byte [esi]
    inc esi
.nn:
    jecxz .tail
    movzx ebx, byte [esi]
    mov eax, SYS_PUTC
    int 0x80
    inc esi
    dec ecx
    jmp .nn
.ord:
    mov eax, [stub_ord+ebp*4]
    call putdec
.tail:
    mov ebx, m_notimpl
    call puts
    mov eax, SYS_EXIT
    mov ebx, 3
    int 0x80

; the TIB (through FS), its second part, the PIB, environment and
; command line, in one page of heap
make_tib:
    call page_align
    jc .no
    mov ebx, 0x1000
    call grow
    jc .no
    mov [tib], eax
    mov edi, eax
    mov ecx, 0x1000/4
    push eax
    xor eax, eax
    rep stosd
    pop eax
    mov dword [eax], -1         ; tib_pexchain: no exception handlers
    lea edx, [eax+0x40]
    mov [eax+12], edx           ; tib_ptib2
    mov dword [eax+16], 20      ; tib_version
    mov dword [eax+20], 1       ; tib_ordinal
    mov dword [edx], 1          ; tib2_ultid
    mov dword [edx+4], 0x200    ; tib2_ulpri: regular, level 0
    mov dword [edx+8], 20       ; tib2_version
    ; the PIB, copied out for the program
    lea edi, [eax+0x80]
    mov [pib_ptr], edi
    push eax
    mov eax, SYS_GETPID
    int 0x80
    mov [pib], eax              ; pib_ulpid
    pop eax
    mov dword [pib+8], 1        ; pib_hmte
    lea ecx, [eax+0x200]
    mov [pib+12], ecx           ; pib_pchcmd
    lea edx, [eax+0x100]
    mov [pib+16], edx           ; pib_pchenv: empty, "" ""
    mov dword [pib+24], 2       ; pib_ultype: VIO windowable
    mov esi, pib
    mov ecx, 7
    rep movsd
    lea edi, [eax+0x200]        ; the command line copy
    mov esi, cmdline
    mov ecx, 128
    rep movsb
    mov ebx, [tib]
    mov eax, SYS_SETTLS
    int 0x80
    mov fs, ax
    clc
    ret
.no:
    stc
    ret

; the heap break to a page boundary
page_align:
    mov eax, SYS_SBRK
    xor ebx, ebx
    int 0x80
    neg eax
    and eax, 0xFFF
    mov ebx, eax
    ; fall through
; ebx = bytes of heap -> eax = their start; CF if refused
grow:
    mov eax, SYS_SBRK
    int 0x80
    cmp eax, -1
    je .no
    clc
    ret
.no:
    stc
    ret

puts:                           ; ebx = ASCIIZ (keeps registers but eax)
    mov eax, SYS_PUTS
    int 0x80
    ret

putdec:                         ; eax, unsigned
    push ebx
    push ecx
    push edx
    mov ecx, 10
    xor ebx, ebx
.d:
    xor edx, edx
    div ecx
    push edx
    inc ebx
    test eax, eax
    jnz .d
.p:
    pop eax
    push ebx
    lea ebx, [eax+'0']
    mov eax, SYS_PUTC
    int 0x80
    pop ebx
    dec ebx
    jnz .p
    pop edx
    pop ecx
    pop ebx
    ret

; ---------- load errors (each ends the program with exit code 1) ----------
e_usage:   mov ebx, m_usage
           jmp e_out
e_open:    mov ebx, m_open
           jmp e_out
e_format:  mov ebx, m_format
           jmp e_out
e_nomem:   mov ebx, m_nomem
e_out:
    push ebx
    mov ebx, m_prefix
    call puts
    pop ebx
    call puts
    mov eax, 1
    ret

; ---------- DOSCALLS: _System, arguments at [esp+4]..., caller pops ----------
%define ARG(n) [esp+4+4*(n)+12]     ; after the three pushes of SAVE
%macro SAVE 0
    push ebx
    push esi
    push edi
%endmacro
%macro RESTORE 0
    pop edi
    pop esi
    pop ebx
%endmacro

; DosWrite(hFile, pBuffer, cbWrite, pcbActual)
Dos32Write:
    SAVE
    mov edx, ARG(0)
    mov esi, ARG(1)
    mov edi, ARG(2)
    cmp edx, 1
    je .con
    cmp edx, 2
    je .con
    sub edx, H_FILE
    jb .badh
    mov ebx, edx
    mov eax, SYS_WRITE
    mov ecx, esi
    mov edx, edi
    int 0x80
    cmp eax, -1
    je .acc
    jmp dos_count
.con:
    xor ecx, ecx
.c:
    cmp ecx, edi
    jae .cd
    movzx ebx, byte [esi+ecx]
    cmp bl, 13                  ; CR LF: the console wants LF alone
    je .skip
    mov eax, SYS_PUTC
    int 0x80
.skip:
    inc ecx
    jmp .c
.cd:
    mov eax, edi
    jmp dos_count
.badh:
    mov eax, ERROR_INVALID_HANDLE
    jmp dos_ret
.acc:
    mov eax, ERROR_ACCESS_DENIED
    jmp dos_ret
dos_count:                      ; eax = bytes -> *ARG(3), NO_ERROR
    mov ecx, ARG(3)
    jecxz .n
    mov [ecx], eax
.n:
    xor eax, eax
dos_ret:
    RESTORE
    ret

; DosRead(hFile, pBuffer, cbRead, pcbActual): the console gives one line
; with CR LF, echoing keys
Dos32Read:
    SAVE
    mov edx, ARG(0)
    mov esi, ARG(1)
    mov edi, ARG(2)
    test edx, edx
    jz .con
    sub edx, H_FILE
    jb Dos32Write.badh
    mov ebx, edx
    mov eax, SYS_READ
    mov ecx, esi
    mov edx, edi
    int 0x80
    cmp eax, -1
    je Dos32Write.acc
    jmp dos_count
.con:
    xor ecx, ecx
.k:
    cmp ecx, edi
    jae .kd
    mov eax, SYS_GETC
    int 0x80
    cmp eax, -1
    je .kd
    cmp al, 10
    jne .store
    lea edx, [ecx+2]
    cmp edx, edi
    ja .store
    mov byte [esi+ecx], 13
    inc ecx
.store:
    mov [esi+ecx], al
    inc ecx
    push eax
    mov ebx, eax
    mov eax, SYS_PUTC
    int 0x80
    pop eax
    cmp al, 10
    jne .k
.kd:
    mov eax, ecx
    jmp dos_count

; DosOpen(pszName, phf, pulAction, cbFile, ulAttribute, fsOpenFlags,
;         fsOpenMode, peaop2): low nibble of the flags = if it exists
;         (0 fail, 1 open, 2 replace), high nibble = if not (0 fail, 1 create)
Dos32Open:
    SAVE
    mov ebx, ARG(0)
    mov eax, SYS_OPEN
    xor ecx, ecx
    int 0x80
    mov edx, ARG(5)
    cmp eax, -1
    je .new
    mov ebx, edx
    and ebx, 15
    jz .exists                  ; fail if it exists
    mov esi, 1                  ; FILE_EXISTED
    cmp ebx, 2
    jne .done
    push eax                    ; replace: open again, truncated
    mov ebx, eax
    mov eax, SYS_CLOSE
    int 0x80
    pop eax
    mov ebx, ARG(0)
    mov eax, SYS_OPEN
    mov ecx, O_TRUNC
    int 0x80
    cmp eax, -1
    je .fail
    mov esi, 3                  ; FILE_TRUNCATED
    jmp .done
.new:
    test edx, 0x10
    jz .fail
    mov ebx, ARG(0)
    mov eax, SYS_OPEN
    mov ecx, O_CREATE
    int 0x80
    cmp eax, -1
    je .fail
    mov esi, 2                  ; FILE_CREATED
.done:
    add eax, H_FILE
    mov ecx, ARG(1)
    mov [ecx], eax
    mov ecx, ARG(2)
    jecxz .na
    mov [ecx], esi
.na:
    xor eax, eax
    jmp dos_ret
.exists:
    mov ebx, eax
    mov eax, SYS_CLOSE
    int 0x80
.fail:
    mov eax, ERROR_OPEN_FAILED
    jmp dos_ret

; DosClose(hFile)
Dos32Close:
    SAVE
    mov ebx, ARG(0)
    sub ebx, H_FILE
    jb .con
    mov eax, SYS_CLOSE
    int 0x80
    cmp eax, -1
    je .bad
.con:
    xor eax, eax
    jmp dos_ret
.bad:
    mov eax, ERROR_INVALID_HANDLE
    jmp dos_ret

; DosSetFilePtr(hFile, ib, method, pibActual): FILE_BEGIN/CURRENT/END
Dos32SetFilePtr:
    SAVE
    mov ebx, ARG(0)
    sub ebx, H_FILE
    jb .bad
    mov eax, SYS_SEEK
    mov ecx, ARG(1)
    mov edx, ARG(2)
    int 0x80
    cmp eax, -1
    je .bad
    jmp dos_count
.bad:
    mov eax, ERROR_INVALID_HANDLE
    jmp dos_ret

; DosDelete(pszName)
Dos32Delete:
    SAVE
    mov ebx, ARG(0)
    mov eax, SYS_DELETE
    int 0x80
    cmp eax, -1
    mov eax, NO_ERROR
    jne dos_ret
    mov eax, ERROR_FILE_NOT_FOUND
    jmp dos_ret

; DosExit(action, result)
Dos32Exit:
    mov ebx, [esp+8]
    mov eax, SYS_EXIT
    int 0x80

; DosAllocMem(ppb, cb, flag): page-aligned heap, zeroed
Dos32AllocMem:
    SAVE
    call page_align
    jc .no
    mov ebx, ARG(1)
    test ebx, ebx
    jz .inval
    add ebx, 0xFFF
    and ebx, -0x1000
    call grow
    jc .no
    mov edi, eax
    mov edx, eax
    mov ecx, ebx
    shr ecx, 2
    xor eax, eax
    rep stosd
    mov ecx, ARG(0)
    mov [ecx], edx
    jmp dos_ret
.no:
    mov eax, ERROR_NOT_ENOUGH_MEMORY
    jmp dos_ret
.inval:
    mov eax, ERROR_INVALID_PARAMETER
    jmp dos_ret

; DosFreeMem(pb), DosBeep(freq, ms), DosError(flag): accepted
Dos32FreeMem:
Dos32Beep:
Dos32Error:
    xor eax, eax
    ret

; DosSleep(ms): the processor for others, once
Dos32Sleep:
    push ebx
    mov eax, SYS_YIELD
    int 0x80
    pop ebx
    xor eax, eax
    ret

; DosGetInfoBlocks(pptib, pppib)
Dos32GetInfoBlocks:
    mov ecx, [esp+4]
    jecxz .p
    mov eax, [tib]
    mov [ecx], eax
.p:
    mov ecx, [esp+8]
    jecxz .r
    mov eax, [pib_ptr]
    mov [ecx], eax
.r:
    xor eax, eax
    ret

; DosQuerySysInfo(iStart, iLast, pBuf, cbBuf)
Dos32QuerySysInfo:
    SAVE
    mov ebx, ARG(0)
    mov edx, ARG(1)
    test ebx, ebx
    jz .inval
    cmp ebx, edx
    ja .inval
    mov ecx, edx
    sub ecx, ebx
    inc ecx
    shl ecx, 2
    cmp ecx, ARG(3)
    ja .over
    mov edi, ARG(2)
.v:
    xor eax, eax
    cmp ebx, 1                  ; QSV_MAX_PATH_LENGTH
    jne .v10
    mov eax, 260
.v10:
    cmp ebx, 10                 ; QSV_PAGE_SIZE
    jne .v11
    mov eax, 4096
.v11:
    cmp ebx, 11                 ; QSV_VERSION_MAJOR
    jne .v12
    mov eax, 20
.v12:
    cmp ebx, 12                 ; QSV_VERSION_MINOR: 4.5
    jne .v14
    mov eax, 45
.v14:
    cmp ebx, 14                 ; QSV_MS_COUNT
    jne .st
    push ebx
    push edx
    mov eax, 35                 ; SYS_GUI
    mov ebx, 7                  ; GUI_TICKS: 100 a second
    int 0x80
    imul eax, 10
    pop edx
    pop ebx
.st:
    stosd
    inc ebx
    cmp ebx, edx
    jbe .v
    xor eax, eax
    jmp dos_ret
.inval:
    mov eax, ERROR_INVALID_PARAMETER
    jmp dos_ret
.over:
    mov eax, ERROR_BUFFER_OVERFLOW
    jmp dos_ret

; DosQueryCurrentDisk(pdisknum, plogical): C:
Dos32QueryCurrentDisk:
    mov ecx, [esp+4]
    mov dword [ecx], 3
    mov ecx, [esp+8]
    mov dword [ecx], 1 << 2
    xor eax, eax
    ret

; DosQueryCurrentDir(disknum, pBuf, pcbBuf): the root, ""
Dos32QueryCurrentDir:
    mov ecx, [esp+12]
    cmp dword [ecx], 1
    jb .over
    mov edx, [esp+8]
    mov byte [edx], 0
    xor eax, eax
    ret
.over:
    mov dword [ecx], 1
    mov eax, ERROR_BUFFER_OVERFLOW
    ret

; DosScanEnv(pszName, ppszValue): the environment is empty
Dos32ScanEnv:
    mov eax, ERROR_ENVVAR_NOT_FOUND
    ret

; DosQueryHType(hFile, pType, pAttr): 0-2 character devices, else files
Dos32QueryHType:
    mov eax, [esp+4]
    mov ecx, [esp+8]
    mov edx, [esp+12]
    cmp eax, H_FILE
    jae .file
    mov dword [ecx], 1          ; HANDTYPE_DEVICE
    mov dword [edx], 3          ; stdin and stdout device
    xor eax, eax
    ret
.file:
    mov dword [ecx], 0          ; HANDTYPE_FILE
    mov dword [edx], 0
    xor eax, eax
    ret

; DOSCALLS ordinals -> shims
dos_table:
    dd 212, Dos32Error
    dd 224, Dos32QueryHType
    dd 227, Dos32ScanEnv
    dd 229, Dos32Sleep
    dd 234, Dos32Exit
    dd 256, Dos32SetFilePtr
    dd 257, Dos32Close
    dd 259, Dos32Delete
    dd 273, Dos32Open
    dd 274, Dos32QueryCurrentDir
    dd 275, Dos32QueryCurrentDisk
    dd 281, Dos32Read
    dd 282, Dos32Write
    dd 286, Dos32Beep
    dd 299, Dos32AllocMem
    dd 304, Dos32FreeMem
    dd 312, Dos32GetInfoBlocks
    dd 348, Dos32QuerySysInfo
    dd 0

s_doscalls db 8, 'DOSCALLS'
m_prefix db 'os2run: ', 0
m_usage db 'usage: run os2run prog.exe [arguments]', 10, 0
m_open db 'cannot open the program file', 10, 0
m_format db 'not an OS/2 32-bit LX program this loader understands', 10, 0
m_nomem db 'not enough memory', 10, 0
m_missing db 'os2run: ', 0
m_notimpl db ' is not implemented', 10, 0

SQX_BSS
fd resd 1
flen resd 1
fbuf resd 1
lx resd 1
nobj resd 1
npages resd 1
entry resd 1
our_esp resd 1
prog_esp resd 1
tib resd 1
pib_ptr resd 1
pib resd 7
rec_end resd 1
cur_page resd 1
f_off resd 1
f_count resd 1
f_mod resd 1
f_ord resd 1
f_name resd 1
nstubs resd 1
f_src resb 1
f_flags resb 1
alignb 4
obj_addr resd OBJ_MAX
page_addr resd PAGE_MAX
stub_mod resd STUB_MAX
stub_ord resd STUB_MAX
stub_name resd STUB_MAX
stubs resb STUB_MAX*STUB_SIZE
exe_name resb 32
cmdline resb 128
SQX_END
