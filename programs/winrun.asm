; winrun — Win32 PE32 console programs on Squirrel-OS/2 (P.5). Original
; code, written from the public PE/COFF format description; no Wine or
; ReactOS code. See documentation/architecture/foreign-compatibility.md.
;
;   run winrun prog.exe [arguments]
;   run prog.exe [arguments]          (the kernel loader hands MZ files here)
;
; winrun is an ordinary SQX program. It reads the PE headers, takes
; SizeOfImage bytes of heap (SYS_SBRK, page aligned, so the image lands at
; 0x40000000 + ...), reads every section to its RVA, applies the base
; relocations (HIGHLOW) when the image is not at its ImageBase, binds the
; KERNEL32.dll imports to the small stdcall shim below, and calls the entry
; point. Imports it does not know (any DLL) are bound to a stub that names
; the function and ends the program with exit code 3 when it is called, so
; a program that never calls them still runs. Returning from the entry
; point ends the program with eax as the exit code, like ExitThread.
;
; Not provided: TEB/fs:, SEH, threads, DLL loading, GUI subsystems, PE32+.
%include "sqx.inc"
SQX_HEADER main

HDR_MAX     equ 4096            ; headers are read into hdr first
STUB_MAX    equ 256             ; imports that can be bound to the stub
STUB_SIZE   equ 10              ; push imm32 / jmp rel32
H_IN        equ 0x10            ; console handles from GetStdHandle
H_OUT       equ 0x11
H_ERR       equ 0x12
H_FILE      equ 0x100           ; file handle = native fd + H_FILE
INVALID     equ -1
E_FILE_NOT_FOUND    equ 2
E_INVALID_HANDLE    equ 6
E_NOT_ENOUGH_MEMORY equ 8

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

; esi = argument text -> runs the program; eax = exit code
load:
    ; command line: copy of the whole argument; the file name is its
    ; first word
    mov edi, cmdline
    mov ecx, 79
.cl:
    lodsb
    stosb
    test al, al
    jz .clz
    loop .cl
    mov byte [edi], 0
.clz:
    mov esi, cmdline
    mov edi, exe_name
    xor ecx, ecx
.nm:
    mov al, [esi+ecx]
    cmp al, ' '
    je .nmz
    test al, al
    jz .nmz
    mov [edi+ecx], al
    inc ecx
    cmp ecx, 31
    jb .nm
.nmz:
    mov byte [edi+ecx], 0
    test ecx, ecx
    jz e_usage
    ; read the headers
    mov eax, SYS_OPEN
    mov ebx, exe_name
    xor ecx, ecx
    int 0x80
    cmp eax, -1
    je e_open
    mov [fd], eax
    mov ebx, eax
    mov eax, SYS_READ
    mov ecx, hdr
    mov edx, HDR_MAX
    int 0x80
    cmp eax, 64
    jl e_format
    mov [hdr_len], eax
    cmp word [hdr], 'MZ'
    jne e_format
    ; an MZ without 'PE',0,0 at e_lfanew is a DOS program: dosrun runs it
    cmp eax, 0x40
    jb to_dos
    mov ebx, [hdr+0x3C]
    lea ecx, [ebx+4]
    cmp ecx, eax
    ja to_dos
    cmp dword [hdr+ebx], 'PE'
    jne to_dos
    mov ebx, [hdr+0x3C]         ; e_lfanew
    lea ecx, [ebx+24+96+16*8]   ; PE signature, COFF and optional header
    cmp ecx, eax
    ja e_format
    add ebx, hdr
    cmp dword [ebx], 'PE'       ; 'P' 'E' 0 0
    jne e_format
    add ebx, 4                  ; COFF file header
    cmp word [ebx], 0x14C       ; IMAGE_FILE_MACHINE_I386
    jne e_machine
    movzx ecx, word [ebx+2]
    mov [nsect], ecx
    movzx edx, word [ebx+16]    ; SizeOfOptionalHeader
    lea esi, [ebx+20]           ; optional header
    cmp word [esi], 0x10B       ; PE32 (PE32+ is P.7)
    jne e_machine
    cmp word [esi+68], 3        ; IMAGE_SUBSYSTEM_WINDOWS_CUI
    jne e_subsys
    lea edi, [esi+edx]          ; section table
    mov [sects], edi
    imul ecx, 40
    add ecx, edi
    sub ecx, hdr
    cmp ecx, [hdr_len]
    ja e_format
    mov eax, [esi+16]
    mov [entry], eax
    mov eax, [esi+28]
    mov [want_base], eax
    mov eax, [esi+104]          ; data directory 1: imports
    mov [imp_rva], eax
    mov eax, [esi+136]          ; data directory 5: base relocations
    mov [rel_rva], eax
    mov eax, [esi+140]
    mov [rel_size], eax
    cmp dword [esi+92], 6       ; NumberOfRvaAndSizes must reach entry 5
    jae .dirs
    mov dword [imp_rva], 0
    mov dword [rel_size], 0
.dirs:
    mov eax, [esi+56]           ; SizeOfImage
    add eax, 0xFFF
    and eax, -0x1000
    jz e_format
    mov [img_size], eax
    mov eax, [esi+60]           ; SizeOfHeaders
    cmp eax, [hdr_len]
    jbe .hs
    mov eax, [hdr_len]
.hs:
    mov [hdr_size], eax
    ; memory: page-align the break, then take SizeOfImage
    mov eax, SYS_SBRK
    xor ebx, ebx
    int 0x80
    cmp eax, -1
    je e_nomem
    neg eax
    and eax, 0xFFF
    mov ebx, eax
    mov eax, SYS_SBRK
    int 0x80
    cmp eax, -1
    je e_nomem
    mov eax, SYS_SBRK
    mov ebx, [img_size]
    int 0x80
    cmp eax, -1
    je e_nomem
    mov [base], eax
    ; headers, then each section's raw data at its RVA
    mov esi, hdr
    mov edi, eax
    mov ecx, [hdr_size]
    rep movsb
    mov esi, [sects]
    mov ebp, [nsect]
.sec:
    test ebp, ebp
    jz .secs_done
    mov ecx, [esi+16]           ; SizeOfRawData
    mov eax, [esi+8]            ; VirtualSize (0: use the raw size)
    test eax, eax
    jz .raw
    cmp ecx, eax
    jbe .raw
    mov ecx, eax                ; the rest of the raw data is padding
.raw:
    jecxz .nextsec
    mov eax, [esi+12]           ; VirtualAddress
    lea edx, [eax+ecx]
    cmp edx, [img_size]
    ja e_format
    push ecx
    push eax
    mov eax, SYS_SEEK
    mov ebx, [fd]
    mov ecx, [esi+20]           ; PointerToRawData
    xor edx, edx
    int 0x80
    pop ecx                     ; RVA
    pop edx                     ; length
    cmp eax, [esi+20]
    jne e_format
    add ecx, [base]
    mov eax, SYS_READ
    mov ebx, [fd]
    push edx
    int 0x80
    pop edx
    cmp eax, edx
    jne e_format
.nextsec:
    add esi, 40
    dec ebp
    jmp .sec
.secs_done:
    mov eax, SYS_CLOSE
    mov ebx, [fd]
    int 0x80
    call relocate
    jc e_fixed
    call bind
    jc e_format
    call make_teb
    jc e_nomem
    ; run it: entry() with the Windows callee-saved registers kept
    mov eax, [base]
    add eax, [entry]
    call eax
    ret

; The thread and process blocks Win32 code reaches through FS: a TEB
; (exception list -1, stack base and limit, self pointer, PEB, ids,
; TLS slots) and a PEB with the image base. SYS_SETTLS points FS at
; the TEB. CF if there is no memory.
make_teb:
    mov eax, SYS_SBRK               ; page-align the break
    xor ebx, ebx
    int 0x80
    neg eax
    and eax, 0xFFF
    mov ebx, eax
    mov eax, SYS_SBRK
    int 0x80
    mov eax, SYS_SBRK
    mov ebx, 0x2000                 ; TEB page, PEB page
    int 0x80
    cmp eax, -1
    je .no
    mov [teb], eax
    mov dword [eax], -1             ; ExceptionList: none
    lea ecx, [esp+0xFFF]
    and ecx, -0x1000
    mov [eax+4], ecx                ; StackBase
    sub ecx, 0x2000
    mov [eax+8], ecx                ; StackLimit
    mov [eax+0x18], eax             ; Self
    lea ecx, [eax+0x1000]
    mov [eax+0x30], ecx             ; PEB
    mov edx, [base]
    mov [ecx+8], edx                ; PEB.ImageBaseAddress
    lea edx, [eax+0xE10]
    mov [eax+0x2C], edx             ; ThreadLocalStoragePointer: the slots
    push eax
    mov eax, SYS_GETPID
    int 0x80
    mov ecx, eax
    pop eax
    mov [eax+0x20], ecx             ; ClientId: process ...
    mov [eax+0x24], ecx             ; ... and thread
    mov ebx, eax
    mov eax, SYS_SETTLS
    int 0x80
    mov fs, ax
    clc
    ret
.no:
    stc
    ret

; base relocations: adds base - ImageBase to every HIGHLOW site. CF if
; the image must move but has no relocations, or a block is malformed.
relocate:
    mov edx, [base]
    sub edx, [want_base]
    jz .ok
    mov esi, [rel_rva]
    mov ecx, [rel_size]
    test esi, esi
    jz .bad
    test ecx, ecx
    jz .bad
    add esi, [base]
    add ecx, esi                ; end of the table
.block:
    lea eax, [esi+8]
    cmp eax, ecx
    ja .ok
    mov edi, [esi]              ; page RVA
    mov ebx, [esi+4]            ; block size
    cmp ebx, 8
    jb .ok                      ; padding at the end
    add ebx, esi                ; end of this block
    add esi, 8
    add edi, [base]
.entry:
    cmp esi, ebx
    jae .block
    movzx eax, word [esi]
    add esi, 2
    mov ebp, eax
    shr ebp, 12
    jz .entry                   ; IMAGE_REL_BASED_ABSOLUTE: padding
    cmp ebp, 3                  ; IMAGE_REL_BASED_HIGHLOW
    jne .bad
    and eax, 0xFFF
    add [edi+eax], edx
    jmp .entry
.ok:
    clc
    ret
.bad:
    stc
    ret

; imports: every thunk of every DLL gets an address. CF if a table lies
; outside the image.
bind:
    mov esi, [imp_rva]
    test esi, esi
    jz .done
    add esi, [base]
.dll:
    mov eax, [esi+12]           ; Name
    test eax, eax
    jz .done
    add eax, [base]
    mov [dll_name], eax
    call is_known_dll
    mov [dll_known], al
    mov edi, [esi+16]           ; FirstThunk (IAT)
    mov ebx, [esi]              ; OriginalFirstThunk (lookup), or the IAT
    test ebx, ebx
    jnz .lt
    mov ebx, edi
.lt:
    add edi, [base]
    add ebx, [base]
.thunk:
    mov eax, [ebx]
    test eax, eax
    jz .nextdll
    test eax, eax
    js .ordinal
    add eax, [base]
    add eax, 2                  ; skip the hint
    mov ebp, eax                ; function name
    cmp byte [dll_known], 0
    je .stub
    call find_shim
    test eax, eax
    jnz .set
    jmp .stub
.ordinal:
    mov ebp, m_ordinal
.stub:
    call make_stub
    jc .full
.set:
    mov [edi], eax
    add ebx, 4
    add edi, 4
    jmp .thunk
.nextdll:
    add esi, 20
    jmp .dll
.full:
    stc
    ret
.done:
    clc
    ret

; [dll_name] -> al = 1 if it is a DLL the shim stands in for:
; kernel32.dll or msvcrt.dll (any case, ".dll" optional)
is_known_dll:
    push edi
    mov edi, n_kernel32
    call dll_is
    je .yes
    mov edi, n_msvcrt
    call dll_is
.yes:
    sete al
    pop edi
    ret

; edi = lower-case name -> ZF if [dll_name] is that DLL
dll_is:
    push esi
    push edi
    mov esi, [dll_name]
.c:
    mov al, [esi]
    cmp al, 'A'
    jb .l
    cmp al, 'Z'
    ja .l
    or al, 0x20
.l:
    mov ah, [edi]
    test ah, ah
    jz .end
    cmp al, ah
    jne .r
    inc esi
    inc edi
    jmp .c
.end:
    test al, al
    jz .r
    cmp al, '.'
.r:
    pop edi
    pop esi
    ret

; ebp = function name -> eax = shim address, or 0. The table (shims) is
; a list of entries: dd address, db 'Name', 0; a 0 address ends it.
find_shim:
    push esi
    push edi
    push ecx
    mov ecx, shims
.next:
    mov eax, [ecx]
    test eax, eax
    jz .r
    lea edi, [ecx+4]
    mov esi, ebp
.cmp:
    mov dl, [esi]
    cmp dl, [edi]
    jne .skip
    inc esi
    inc edi
    test dl, dl
    jnz .cmp
    jmp .r                          ; eax = its address
.skip:                              ; past this entry's name
    cmp byte [edi], 0
    je .past
    inc edi
    jmp .skip
.past:
    lea ecx, [edi+1]
    jmp .next
.r:
    pop ecx
    pop edi
    pop esi
    ret

; ebp = function name -> eax = a new stub that reports it; CF if full
make_stub:
    mov eax, [nstubs]
    cmp eax, STUB_MAX
    jae .full
    inc dword [nstubs]
    imul eax, STUB_SIZE
    add eax, stubs
    mov byte [eax], 0x68        ; push imm32
    mov [eax+1], ebp
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

; a call to an import with no shim: [esp] = its name
missing:
    mov ebx, m_missing
    call puts
    pop ebx
    call puts
    mov ebx, m_nl
    call puts
    mov eax, SYS_EXIT
    mov ebx, 3
    int 0x80

puts:                           ; ebx = ASCIIZ (keeps registers but eax)
    mov eax, SYS_PUTS
    int 0x80
    ret

; a DOS MZ program: "dosrun <our command line>", waited for; its exit code
to_dos:
    mov eax, SYS_CLOSE
    mov ebx, [fd]
    int 0x80
    mov eax, SYS_EXEC
    mov ebx, m_dosrun
    mov ecx, cmdline
    int 0x80
    test eax, eax
    js e_dosrun
    mov ebx, eax
    mov eax, SYS_WAIT
    int 0x80
    ret

; ---------- load errors (each ends the program with exit code 1) ----------
e_dosrun:  mov ebx, m_nodos
           jmp e_out
e_usage:   mov ebx, m_usage
           jmp e_out
e_open:    mov ebx, m_open
           jmp e_out
e_format:  mov ebx, m_format
           jmp e_out
e_machine: mov ebx, m_machine
           jmp e_out
e_subsys:  mov ebx, m_subsys
           jmp e_out
e_nomem:   mov ebx, m_nomem
           jmp e_out
e_fixed:   mov ebx, m_fixed
e_out:
    push ebx
    mov ebx, m_prefix
    call puts
    pop ebx
    call puts
    mov eax, 1
    ret

; ================= KERNEL32 shim (stdcall, callee pops) =================
; Every function keeps ebx, esi, edi and ebp, returns in eax, and sets
; the last error on failure.

; HANDLE GetStdHandle(DWORD n): -10 in, -11 out, -12 err
k_GetStdHandle:
    mov eax, [esp+4]
    neg eax
    sub eax, 10
    cmp eax, 2
    ja .bad
    add eax, H_IN
    ret 4
.bad:
    mov dword [last_error], E_INVALID_HANDLE
    mov eax, INVALID
    ret 4

; BOOL WriteFile(h, buf, n, *written, overlapped)
; BOOL WriteConsoleA(h, buf, n, *written, reserved)
k_WriteFile:
k_WriteConsoleA:
    push ebx
    push esi
    push edi
    mov edx, [esp+16]           ; handle
    mov esi, [esp+20]           ; buffer
    mov edi, [esp+24]           ; count
    cmp edx, H_OUT
    je .con
    cmp edx, H_ERR
    je .con
    sub edx, H_FILE
    jb hfail
    mov ebx, edx
    mov eax, SYS_WRITE
    mov ecx, esi
    mov edx, edi
    int 0x80
    cmp eax, -1
    je hfail
    jmp io_done
.con:
    xor ecx, ecx
.c:
    cmp ecx, edi
    jae .cd
    movzx ebx, byte [esi+ecx]
    mov eax, SYS_PUTC
    int 0x80
    inc ecx
    jmp .c
.cd:
    mov eax, edi
    ; fall through
io_done:                        ; eax = bytes moved -> *count, TRUE
    mov ecx, [esp+28]
    jecxz .nc
    mov [ecx], eax
.nc:
    mov eax, 1
    pop edi
    pop esi
    pop ebx
    ret 20
hfail:
    mov dword [last_error], E_INVALID_HANDLE
    mov ecx, [esp+28]
    jecxz .nc
    mov dword [ecx], 0
.nc:
    xor eax, eax
    pop edi
    pop esi
    pop ebx
    ret 20

; BOOL ReadFile(h, buf, n, *read, overlapped): the console gives one
; line (Enter arrives as CR LF, like a Windows console), echoing keys
k_ReadFile:
    push ebx
    push esi
    push edi
    mov edx, [esp+16]
    mov esi, [esp+20]
    mov edi, [esp+24]
    cmp edx, H_IN
    je .con
    sub edx, H_FILE
    jb hfail
    mov ebx, edx
    mov eax, SYS_READ
    mov ecx, esi
    mov edx, edi
    int 0x80
    cmp eax, -1
    je hfail
    jmp io_done
.con:
    xor ecx, ecx
.k:
    cmp ecx, edi
    jae .kd
    mov eax, SYS_GETC
    int 0x80
    cmp eax, -1
    je .kd                      ; end of redirected input
    cmp al, 10
    jne .store
    lea edx, [ecx+2]
    cmp edx, edi
    ja .store                   ; no room for CR LF: plain LF
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
    jmp io_done

; HANDLE CreateFileA(name, access, share, security, disposition, flags, template)
k_CreateFileA:
    push ebx
    mov ebx, [esp+8]
    mov eax, [esp+24]           ; disposition
    xor ecx, ecx
    cmp eax, 3                  ; OPEN_EXISTING
    je .open
    mov ecx, O_CREATE|O_TRUNC
    cmp eax, 2                  ; CREATE_ALWAYS
    je .open
    cmp eax, 1                  ; CREATE_NEW
    je .open
    mov ecx, O_CREATE
    cmp eax, 4                  ; OPEN_ALWAYS
    je .open
    mov ecx, O_TRUNC            ; TRUNCATE_EXISTING
.open:
    mov eax, SYS_OPEN
    int 0x80
    cmp eax, -1
    je .fail
    add eax, H_FILE
    pop ebx
    ret 28
.fail:
    mov dword [last_error], E_FILE_NOT_FOUND
    pop ebx
    ret 28

; BOOL CloseHandle(h)
k_CloseHandle:
    push ebx
    mov ebx, [esp+8]
    sub ebx, H_FILE
    jb .con                     ; console handles stay open
    mov eax, SYS_CLOSE
    int 0x80
    cmp eax, -1
    je .bad
.con:
    mov eax, 1
    pop ebx
    ret 4
.bad:
    mov dword [last_error], E_INVALID_HANDLE
    xor eax, eax
    pop ebx
    ret 4

; DWORD SetFilePointer(h, distance, *high, method): FILE_BEGIN/CURRENT/END
; are 0/1/2 like the native SYS_SEEK; *high is ignored (files are small)
k_SetFilePointer:
    push ebx
    mov ebx, [esp+8]
    sub ebx, H_FILE
    jb .bad
    mov eax, SYS_SEEK
    mov ecx, [esp+12]
    mov edx, [esp+20]
    int 0x80
    cmp eax, -1
    jne .r
.bad:
    mov dword [last_error], E_INVALID_HANDLE
    mov eax, INVALID
.r:
    pop ebx
    ret 16

; void ExitProcess(code)
k_ExitProcess:
    mov ebx, [esp+4]
    mov eax, SYS_EXIT
    int 0x80

; LPSTR GetCommandLineA(void)
k_GetCommandLineA:
    mov eax, cmdline
    ret

; DWORD GetLastError(void) / void SetLastError(code)
k_GetLastError:
    mov eax, [last_error]
    ret
k_SetLastError:
    mov eax, [esp+4]
    mov [last_error], eax
    ret 4

; HMODULE GetModuleHandleA(name): only NULL (this program) is known
k_GetModuleHandleA:
    xor eax, eax
    cmp [esp+4], eax
    jne .r
    mov eax, [base]
.r:
    ret 4

; HANDLE GetProcessHeap(void)
k_GetProcessHeap:
    mov eax, 1
    ret

; LPVOID HeapAlloc(heap, flags, size): zeroed, 8-byte aligned, never
; given back before the program ends (HeapFree only says yes)
k_HeapAlloc:
    mov eax, [esp+12]
    push ebx
    lea ebx, [eax+7]
    and ebx, -8
    call grow
    pop ebx
    ret 12
k_HeapFree:
    mov eax, 1
    ret 12

; LPVOID VirtualAlloc(addr, size, type, protect): fresh pages; the address
; hint is ignored. VirtualFree only says yes.
k_VirtualAlloc:
    push ebx
    mov eax, SYS_SBRK           ; page-align the break first
    xor ebx, ebx
    int 0x80
    neg eax
    and eax, 0xFFF
    mov ebx, eax
    call grow
    mov ebx, [esp+12]
    add ebx, 0xFFF
    and ebx, -0x1000
    call grow
    pop ebx
    ret 16
k_VirtualFree:
    mov eax, 1
    ret 12

; ebx = bytes -> eax = new zeroed memory, or 0 with the last error set
grow:
    mov eax, SYS_SBRK
    int 0x80
    cmp eax, -1
    jne .r
    mov dword [last_error], E_NOT_ENOUGH_MEMORY
    xor eax, eax
.r:
    ret

%macro K 1                          ; a KERNEL32 function k_<name>
    dd k_%1
    db %str(%1), 0
%endmacro
%macro M 1                          ; an msvcrt function or variable m_<name>
    dd m_%1
    db %str(%1), 0
%endmacro
%include "winshim.inc"
shims:
    K GetStdHandle
    K WriteFile
    K WriteConsoleA
    K ReadFile
    K CreateFileA
    K CloseHandle
    K SetFilePointer
    K ExitProcess
    K GetCommandLineA
    K GetLastError
    K SetLastError
    K GetModuleHandleA
    K GetProcessHeap
    K HeapAlloc
    K HeapFree
    K VirtualAlloc
    K VirtualFree
    WINSHIM_TABLE
    dd 0

n_kernel32 db 'kernel32', 0
n_msvcrt db 'msvcrt', 0
m_prefix db 'winrun: ', 0
m_usage db 'usage: run winrun prog.exe [arguments]', 10, 0
m_open db 'cannot open the program file', 10, 0
m_format db 'not a valid PE file', 10, 0
m_dosrun db 'dosrun', 0
m_nodos db 'a DOS program, and dosrun is not on the disk', 10, 0
m_machine db 'only 32-bit x86 (PE32) programs run here', 10, 0
m_subsys db 'only console programs run here (no Windows GUI yet)', 10, 0
m_nomem db 'not enough memory for the image', 10, 0
m_fixed db 'the image cannot move from its ImageBase (no relocations)', 10, 0
m_missing db 'winrun: not implemented: ', 0
m_ordinal db '(import by ordinal)', 0
m_nl db 10, 0

SQX_BSS
fd resd 1
hdr_len resd 1
hdr_size resd 1
nsect resd 1
sects resd 1
entry resd 1
want_base resd 1
imp_rva resd 1
rel_rva resd 1
rel_size resd 1
img_size resd 1
base resd 1
dll_name resd 1
dll_known resb 1
alignb 4
teb resd 1
alignb 4
nstubs resd 1
last_error resd 1
exe_name resb 32
cmdline resb 80
stubs resb STUB_MAX*STUB_SIZE
hdr resb HDR_MAX
WINSHIM_BSS
SQX_END
