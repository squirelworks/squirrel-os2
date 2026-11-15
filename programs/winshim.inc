; winshim.inc — more of the Win32 surface for winrun (P.5): the KERNEL32
; calls that MinGW and MSVC start-up code makes, and a small msvcrt
; (C runtime: start-up, stdio with printf, strings, memory, exit).
; Original code, written from the public API descriptions.
;
; KERNEL32 functions are stdcall (k_*, callee pops); msvcrt functions are
; cdecl (m_*, caller pops). All keep ebx, esi, edi and ebp. Variables a
; program imports from msvcrt (_iob, __initenv, __mb_cur_max) are bound to
; their address, like functions.

; ======================= KERNEL32, start-up helpers =======================

; critical sections: one thread per program, so they do nothing
k_InitializeCriticalSection:
k_DeleteCriticalSection:
k_EnterCriticalSection:
k_LeaveCriticalSection:
    ret 4

k_InitializeCriticalSectionAndSpinCount:
    mov eax, 1
    ret 8

; BOOL FreeLibrary(h)
k_FreeLibrary:
    mov eax, 1
    ret 4

; LoadLibrary*, GetProcAddress, GetModuleHandle*: winrun.asm (the DLL loader)

; BOOL IsDBCSLeadByteEx(codepage, byte): single-byte code pages only
k_IsDBCSLeadByteEx:
    xor eax, eax
    ret 8

; LPTOP_LEVEL_EXCEPTION_FILTER SetUnhandledExceptionFilter(f)
k_SetUnhandledExceptionFilter:
    xor eax, eax
    ret 4

; void Sleep(ms): gives the processor away once
k_Sleep:
    mov eax, SYS_YIELD
    int 0x80
    ret 4

; DWORD GetCurrentProcessId / GetCurrentThreadId(void)
k_GetCurrentProcessId:
k_GetCurrentThreadId:
    mov eax, SYS_GETPID
    int 0x80
    ret

; HANDLE GetCurrentProcess / GetCurrentThread(void): pseudo handles
k_GetCurrentProcess:
    mov eax, -1
    ret
k_GetCurrentThread:
    mov eax, -2
    ret

; DWORD GetTickCount(void): no clock call yet, so a counter that moves
k_GetTickCount:
    add dword [tick_fake], 10
    mov eax, [tick_fake]
    ret

; void GetSystemTimeAsFileTime(*ft) / QueryPerformanceCounter(*li)
k_GetSystemTimeAsFileTime:
k_QueryPerformanceCounter:
    mov eax, [esp+4]
    add dword [tick_fake], 10
    mov ecx, [tick_fake]
    mov [eax], ecx
    mov dword [eax+4], 0
    mov eax, 1
    ret 4

; void GetStartupInfoA(*si): all zero but the size
k_GetStartupInfoA:
    push edi
    mov edi, [esp+8]
    mov ecx, 68/4
    xor eax, eax
    rep stosd
    mov edi, [esp+8]
    mov dword [edi], 68
    pop edi
    ret 4

; DWORD GetEnvironmentVariableA(name, buf, size): no environment
k_GetEnvironmentVariableA:
    mov dword [last_error], 203     ; ERROR_ENVVAR_NOT_FOUND
    xor eax, eax
    ret 12

; Thread-local storage slots: 64 per program, in the TEB's slot area
; (TEB+0xE10, as Windows has them)
k_TlsAlloc:
    mov eax, [teb]
    xor ecx, ecx
.f:
    cmp byte [tls_used+ecx], 0
    je .got
    inc ecx
    cmp ecx, 64
    jb .f
    mov eax, -1                     ; TLS_OUT_OF_INDEXES
    ret
.got:
    mov byte [tls_used+ecx], 1
    mov dword [eax+0xE10+ecx*4], 0
    mov eax, ecx
    ret
k_TlsFree:
    mov ecx, [esp+4]
    cmp ecx, 64
    jae .no
    mov byte [tls_used+ecx], 0
    mov eax, 1
    ret 4
.no:
    xor eax, eax
    ret 4
k_TlsGetValue:
    mov ecx, [esp+4]
    xor eax, eax
    cmp ecx, 64
    jae .r
    mov dword [last_error], 0
    mov eax, [teb]
    mov eax, [eax+0xE10+ecx*4]
.r:
    ret 4
k_TlsSetValue:
    mov ecx, [esp+4]
    xor eax, eax
    cmp ecx, 64
    jae .r
    mov eax, [teb]
    mov edx, [esp+8]
    mov [eax+0xE10+ecx*4], edx
    mov eax, 1
.r:
    ret 8

; BOOL VirtualProtect(addr, size, new, *old): everything stays
; read-write-execute; *old says PAGE_EXECUTE_READWRITE
k_VirtualProtect:
    mov eax, [esp+16]
    test eax, eax
    jz .r
    mov dword [eax], 0x40
.r:
    mov eax, 1
    ret 16

; SIZE_T VirtualQuery(addr, *mbi, size): one committed RWX page
k_VirtualQuery:
    push edi
    mov edi, [esp+12]               ; MEMORY_BASIC_INFORMATION
    mov eax, [esp+8]
    and eax, -0x1000
    mov [edi], eax                  ; BaseAddress
    mov eax, [base]
    mov [edi+4], eax                ; AllocationBase
    mov dword [edi+8], 0x40         ; AllocationProtect
    mov dword [edi+12], 0x1000      ; RegionSize
    mov dword [edi+16], 0x1000      ; State: MEM_COMMIT
    mov dword [edi+20], 0x40        ; Protect
    mov dword [edi+24], 0x1000000   ; Type: MEM_IMAGE
    mov eax, 28
    pop edi
    ret 12

; int MultiByteToWideChar(cp, flags, src, srclen, dst, dstlen): bytes
; become 16-bit characters one to one (ASCII and Latin-1)
k_MultiByteToWideChar:
    push esi
    push edi
    mov esi, [esp+20]               ; src
    mov ecx, [esp+24]               ; srclen, -1 = up to and with the NUL
    call wc_srclen_b
    mov edi, [esp+28]               ; dst
    mov edx, [esp+32]               ; dstlen, 0 = just count
    mov eax, ecx
    test edx, edx
    jz .r
    cmp ecx, edx
    ja .small
.c:
    jecxz .r
    movzx edx, byte [esi]
    mov [edi], dx
    inc esi
    add edi, 2
    dec ecx
    jmp .c
.small:
    mov dword [last_error], 122     ; ERROR_INSUFFICIENT_BUFFER
    xor eax, eax
.r:
    pop edi
    pop esi
    ret 24

; int WideCharToMultiByte(cp, flags, src, srclen, dst, dstlen, def, *used)
k_WideCharToMultiByte:
    push esi
    push edi
    mov esi, [esp+20]
    mov ecx, [esp+24]
    cmp ecx, -1
    jne .have
    xor ecx, ecx
.len:
    cmp word [esi+ecx*2], 0
    je .lz
    inc ecx
    jmp .len
.lz:
    inc ecx
.have:
    mov edi, [esp+28]
    mov edx, [esp+32]
    mov eax, ecx
    test edx, edx
    jz .r
    cmp ecx, edx
    ja .small
.c:
    jecxz .r
    mov dx, [esi]
    cmp dx, 0xFF
    jbe .b
    mov dl, '?'
.b:
    mov [edi], dl
    add esi, 2
    inc edi
    dec ecx
    jmp .c
.small:
    mov dword [last_error], 122
    xor eax, eax
.r:
    pop edi
    pop esi
    ret 32

; esi = bytes, ecx = length or -1 -> ecx = length (with the NUL if -1)
wc_srclen_b:
    cmp ecx, -1
    jne .r
    xor ecx, ecx
.l:
    cmp byte [esi+ecx], 0
    je .z
    inc ecx
    jmp .l
.z:
    inc ecx
.r:
    ret

; void ExitThread(code): the only thread, so the program ends
k_ExitThread:
    jmp k_ExitProcess

; BOOL FlushFileBuffers(h): nothing is buffered
k_FlushFileBuffers:
    mov eax, 1
    ret 4

; DWORD GetFileType(h): FILE_TYPE_CHAR for the console, DISK for files
k_GetFileType:
    mov eax, [esp+4]
    cmp eax, H_FILE
    jae .disk
    mov eax, 2
    ret 4
.disk:
    mov eax, 1
    ret 4

; BOOL GetConsoleMode(h, *mode) / SetConsoleMode(h, mode)
k_GetConsoleMode:
    mov eax, [esp+8]
    mov dword [eax], 3              ; processed input, line input
    mov eax, 1
    ret 8
k_SetConsoleMode:
    mov eax, 1
    ret 8

; UINT GetConsoleOutputCP / GetConsoleCP / GetACP(void): 437, 437, 1252
k_GetConsoleOutputCP:
k_GetConsoleCP:
    mov eax, 437
    ret
k_GetACP:
    mov eax, 1252
    ret

; BOOL DeleteFileA(name)
k_DeleteFileA:
    push ebx
    mov ebx, [esp+8]
    mov eax, SYS_DELETE
    int 0x80
    pop ebx
    inc eax                         ; 0 -> TRUE, -1 -> FALSE
    jnz .ok
    mov dword [last_error], E_FILE_NOT_FOUND
    ret 4
.ok:
    mov eax, 1
    ret 4

; ============================ msvcrt ============================

; --- start-up ---

; int __getmainargs(int *argc, char ***argv, char ***env, int glob, void *si)
; argv comes from the command line, split at spaces
m___getmainargs:
    push esi
    push edi
    mov esi, cmdline
    mov edi, argbuf
    xor ecx, ecx                    ; argc
.skip:
    cmp byte [esi], ' '
    jne .word
    inc esi
    jmp .skip
.word:
    cmp byte [esi], 0
    je .done
    cmp ecx, ARGV_MAX
    jae .done
    mov [argv_tab+ecx*4], edi
    inc ecx
.ch:
    lodsb
    cmp al, ' '
    je .end
    test al, al
    jz .last
    stosb
    jmp .ch
.end:
    mov byte [edi], 0
    inc edi
    jmp .skip
.last:
    mov byte [edi], 0
.done:
    mov dword [argv_tab+ecx*4], 0
    mov [argc_cache], ecx
    mov eax, [esp+12]
    mov [eax], ecx
    mov eax, [esp+16]
    mov dword [eax], argv_tab
    mov eax, [esp+20]
    mov dword [eax], env_tab
    xor eax, eax
    pop edi
    pop esi
    ret

; int *__p___argc / char ***__p___argv (MSVC style)
m___p___argc:
    mov eax, argc_cache
    ret

m___set_app_type:
m___setusermatherr:
m__lock:
m__unlock:
m__cexit:
m__c_exit:
m__fpreset:
    xor eax, eax
    ret

m___p__commode:
    mov eax, m__commode
    ret
m___p__fmode:
    mov eax, m__fmode
    ret
m___p__acmdln:                  ; char ** to the command line (GUI start-up)
    mov dword [acmdln], cmdline
    mov eax, acmdln
    ret
m__ismbblead:                   ; no multibyte code page: never a lead byte
    xor eax, eax
    ret
m__errno:
    mov eax, errno_v
    ret

; void _initterm(void (**a)(void), void (**b)(void)): calls each non-null
m__initterm:
    push esi
    push edi
    mov esi, [esp+12]
    mov edi, [esp+16]
.l:
    cmp esi, edi
    jae .r
    mov eax, [esi]
    add esi, 4
    test eax, eax
    jz .l
    call eax
    jmp .l
.r:
    pop edi
    pop esi
    ret

; _onexit_t _onexit(f) / int atexit(f): remembered, run by exit()
m__onexit:
    mov eax, [esp+4]
    mov ecx, [natexit]
    cmp ecx, ATEXIT_MAX
    jae .full
    mov [atexit_tab+ecx*4], eax
    inc dword [natexit]
    ret
.full:
    xor eax, eax
    ret
m_atexit:
    push dword [esp+4]
    call m__onexit
    add esp, 4
    test eax, eax
    jz .f
    xor eax, eax
    ret
.f:
    dec eax
    ret

; void exit(code): runs the atexit list (last first), then ends
m_exit:
    mov ecx, [natexit]
    jecxz .x
    dec dword [natexit]
    call [atexit_tab+ecx*4-4]
    jmp m_exit
.x:
m__exit:
    mov ebx, [esp+4]
    jmp win_exit

; void _amsg_exit(n) / abort(void)
m__amsg_exit:
m_abort:
    mov ebx, m_aborted
    call puts
    mov ebx, 3
    jmp win_exit

; void (*signal(int, void (*)(int)))(int): no signals; SIG_DFL back
m_signal:
    xor eax, eax
    ret

; char *setlocale(int, const char *) -> "C"; struct lconv *localeconv(void)
m_setlocale:
    mov eax, s_C
    ret
m_localeconv:
    mov eax, lconv_c
    ret

; --- memory ---

; void *malloc(n): heap memory with an 8-byte header holding the size;
; free gives nothing back before the program ends
m_malloc:
    push ebx
    mov ebx, [esp+8]
    add ebx, 8+7
    and ebx, -8
    call grow
    test eax, eax
    jz .r
    mov ecx, [esp+8]
    mov [eax], ecx
    add eax, 8
.r:
    pop ebx
    ret
m_calloc:                           ; heap memory starts zeroed
    mov eax, [esp+4]
    mul dword [esp+8]
    push eax
    call m_malloc
    add esp, 4
    ret
m_free:
    ret
; void *realloc(p, n)
m_realloc:
    push esi
    push edi
    push dword [esp+16]
    call m_malloc
    add esp, 4
    mov esi, [esp+12]
    test esi, esi
    jz .r
    test eax, eax
    jz .r
    mov ecx, [esi-8]                ; the old size
    cmp ecx, [esp+16]
    jbe .cp
    mov ecx, [esp+16]
.cp:
    mov edi, eax
    rep movsb
.r:
    pop edi
    pop esi
    ret

; --- strings and memory blocks ---

m_strlen:
    mov eax, [esp+4]
.l:
    cmp byte [eax], 0
    je .z
    inc eax
    jmp .l
.z:
    sub eax, [esp+4]
    ret

m_wcslen:
    mov eax, [esp+4]
.l:
    cmp word [eax], 0
    je .z
    add eax, 2
    jmp .l
.z:
    sub eax, [esp+4]
    shr eax, 1
    ret

m_memcpy:
m_memmove:
    push esi
    push edi
    mov edi, [esp+12]
    mov esi, [esp+16]
    mov ecx, [esp+20]
    cmp edi, esi
    jbe .fwd
    lea eax, [esi+ecx]
    cmp edi, eax
    jae .fwd
    lea esi, [esi+ecx-1]            ; overlapping, destination above:
    lea edi, [edi+ecx-1]            ; copy from the end
    std
    rep movsb
    cld
    jmp .r
.fwd:
    rep movsb
.r:
    mov eax, [esp+12]
    pop edi
    pop esi
    ret

m_memset:
    push edi
    mov edi, [esp+8]
    mov eax, [esp+12]
    mov ecx, [esp+16]
    rep stosb
    mov eax, [esp+8]
    pop edi
    ret

m_memcmp:
    push esi
    push edi
    mov esi, [esp+12]
    mov edi, [esp+16]
    mov ecx, [esp+20]
    xor eax, eax
    repe cmpsb
    je .r
    movzx eax, byte [esi-1]
    movzx ecx, byte [edi-1]
    sub eax, ecx
.r:
    pop edi
    pop esi
    ret

m_strcmp:
    mov ecx, -1
    jmp str_ncmp
m_strncmp:
    mov ecx, [esp+12]
str_ncmp:                           ; [esp+4], [esp+8], ecx = limit
    push esi
    push edi
    mov esi, [esp+12]
    mov edi, [esp+16]
    xor eax, eax
.l:
    jecxz .r
    movzx eax, byte [esi]
    movzx edx, byte [edi]
    sub eax, edx
    jnz .r
    test edx, edx
    jz .r
    inc esi
    inc edi
    dec ecx
    jmp .l
.r:
    pop edi
    pop esi
    ret

m_strcpy:
    push esi
    push edi
    mov edi, [esp+12]
    mov esi, [esp+16]
.l:
    lodsb
    stosb
    test al, al
    jnz .l
    mov eax, [esp+12]
    pop edi
    pop esi
    ret

m_strcat:
    push edi
    mov edi, [esp+8]
    xor eax, eax
    mov ecx, -1
    repne scasb
    dec edi
    push dword [esp+12]
    push edi
    call m_strcpy
    add esp, 8
    mov eax, [esp+8]
    pop edi
    ret

m_strchr:
    mov eax, [esp+4]
    mov edx, [esp+8]
.l:
    cmp [eax], dl
    je .r
    cmp byte [eax], 0
    je .no
    inc eax
    jmp .l
.no:
    xor eax, eax
.r:
    ret

m_strerror:
    mov eax, s_error
    ret

; int atoi(s) / long atol(s)
m_atoi:
m_atol:
    push esi
    mov esi, [esp+8]
    xor eax, eax
    xor ecx, ecx                    ; 1 = negative
.sp:
    cmp byte [esi], ' '
    jne .sg
    inc esi
    jmp .sp
.sg:
    cmp byte [esi], '-'
    jne .pl
    inc ecx
    inc esi
    jmp .d
.pl:
    cmp byte [esi], '+'
    jne .d
    inc esi
.d:
    movzx edx, byte [esi]
    sub edx, '0'
    cmp edx, 9
    ja .end
    imul eax, 10
    add eax, edx
    inc esi
    jmp .d
.end:
    jecxz .r
    neg eax
.r:
    pop esi
    ret

; --- stdio ---
; FILE: 32 bytes like msvcrt's. _iob[0..2] are stdin, stdout, stderr;
; fopen makes more, with the native fd at +16 and FILE_MAGIC at +12.
FILE_SIZE   equ 32
FILE_MAGIC  equ 0x454C4946          ; 'FILE'

; esi = FILE* -> CF clear and eax = its native fd, or CF set and eax =
; 0/1/2 for a console stream
stream_of:
    mov eax, esi
    sub eax, m__iob
    cmp eax, 3*FILE_SIZE
    jae .file
    shr eax, 5
    stc
    ret
.file:
    mov eax, [esi+16]
    clc
    ret

; esi = FILE*, al = character -> writes it. Keeps registers.
stream_putc:
    pushad
    mov dl, al
    call stream_of
    jnc .file
    movzx ebx, dl
    mov eax, SYS_PUTC
    int 0x80
    popad
    ret
.file:
    mov [onechar], dl
    mov ebx, eax
    mov eax, SYS_WRITE
    mov ecx, onechar
    mov edx, 1
    int 0x80
    popad
    ret

; size_t fwrite(buf, size, n, FILE*)
m_fwrite:
    push esi
    push edi
    push ebx
    mov esi, [esp+28]
    mov eax, [esp+20]
    mul dword [esp+24]
    mov ecx, eax                    ; bytes
    mov edi, [esp+16]
    call stream_of
    jnc .file
    xor edx, edx
.c:
    cmp edx, ecx
    jae .done
    mov al, [edi+edx]
    call stream_putc
    inc edx
    jmp .c
.file:
    mov ebx, eax
    mov eax, SYS_WRITE
    mov edx, ecx
    mov ecx, edi
    int 0x80
    cmp eax, -1
    jne .done
    xor eax, eax
.done:
    mov eax, [esp+24]               ; every item was written
    pop ebx
    pop edi
    pop esi
    ret

; size_t fread(buf, size, n, FILE*)
m_fread:
    push esi
    push ebx
    mov esi, [esp+24]
    call stream_of
    jc .none                        ; console input: use fgets/getchar
    mov ebx, eax
    mov eax, [esp+16]
    test eax, eax
    jz .none
    mul dword [esp+20]
    mov edx, eax
    mov eax, SYS_READ
    mov ecx, [esp+12]
    int 0x80
    cmp eax, -1
    je .none
    xor edx, edx
    div dword [esp+16]
    jmp .r
.none:
    xor eax, eax
.r:
    pop ebx
    pop esi
    ret

; int fputc(c, FILE*) / putc / _fputc_nolock
m_fputc:
m_putc:
    push esi
    mov esi, [esp+12]
    mov eax, [esp+8]
    call stream_putc
    movzx eax, al
    pop esi
    ret

; int putchar(c)
m_putchar:
    push esi
    mov esi, m__iob+FILE_SIZE
    mov eax, [esp+8]
    call stream_putc
    movzx eax, al
    pop esi
    ret

; int fputs(s, FILE*)
m_fputs:
    push esi
    push edi
    mov edi, [esp+12]
    mov esi, [esp+16]
.l:
    mov al, [edi]
    test al, al
    jz .r
    call stream_putc
    inc edi
    jmp .l
.r:
    xor eax, eax
    pop edi
    pop esi
    ret

; int puts(s): the string and a newline on stdout
m_puts:
    push dword m__iob+FILE_SIZE
    push dword [esp+8]
    call m_fputs
    add esp, 8
    push esi
    mov esi, m__iob+FILE_SIZE
    mov al, 10
    call stream_putc
    pop esi
    xor eax, eax
    ret

; int getchar(void) / fgetc(FILE*) / getc: console keys (echoed) or a file
m_getchar:
    push dword m__iob
    call m_fgetc
    add esp, 4
    ret
m_fgetc:
m_getc:
    push esi
    push ebx
    mov esi, [esp+12]
    call stream_of
    jnc .file
    mov eax, SYS_GETC
    int 0x80
    cmp eax, -1
    je .r
    push eax
    mov ebx, eax
    mov eax, SYS_PUTC
    int 0x80
    pop eax
    jmp .r
.file:
    mov ebx, eax
    mov eax, SYS_READ
    mov ecx, onechar
    mov edx, 1
    int 0x80
    cmp eax, 1
    mov eax, -1                     ; EOF
    jne .r
    movzx eax, byte [onechar]
.r:
    pop ebx
    pop esi
    ret

; char *fgets(buf, n, FILE*)
m_fgets:
    push esi
    push edi
    push ebx
    mov edi, [esp+16]
    mov ebx, [esp+20]
    dec ebx                         ; room for the NUL
    xor esi, esi
.l:
    cmp esi, ebx
    jge .end
    push dword [esp+24]
    call m_fgetc
    add esp, 4
    cmp eax, -1
    je .eof
    mov [edi+esi], al
    inc esi
    cmp al, 10
    jne .l
    jmp .end
.eof:
    test esi, esi
    jnz .end
    xor eax, eax
    jmp .r
.end:
    mov byte [edi+esi], 0
    mov eax, edi
.r:
    pop ebx
    pop edi
    pop esi
    ret

; FILE *fopen(name, mode): "r", "w", "a" (with optional b, +)
m_fopen:
    push ebx
    mov ebx, [esp+8]
    mov edx, [esp+12]
    xor ecx, ecx
    cmp byte [edx], 'w'
    jne .a
    mov ecx, O_CREATE|O_TRUNC
.a:
    cmp byte [edx], 'a'
    jne .o
    mov ecx, O_CREATE|O_APPEND
.o:
    mov eax, SYS_OPEN
    int 0x80
    cmp eax, -1
    je .no
    push eax
    push ebx
    mov ebx, FILE_SIZE
    call grow
    pop ebx
    pop ecx
    test eax, eax
    jz .no
    mov dword [eax+12], FILE_MAGIC
    mov [eax+16], ecx
    pop ebx
    ret
.no:
    mov dword [errno_v], 2          ; ENOENT
    xor eax, eax
    pop ebx
    ret

; int fclose(FILE*)
m_fclose:
    push esi
    push ebx
    mov esi, [esp+12]
    call stream_of
    jc .ok
    mov ebx, eax
    mov eax, SYS_CLOSE
    int 0x80
.ok:
    xor eax, eax
    pop ebx
    pop esi
    ret

; int fflush(FILE*) / setvbuf(...): nothing is buffered
m_fflush:
m_setvbuf:
    xor eax, eax
    ret

; --- printf family: %d %i %u %x %X %p %s %c %% with -, 0, width,
; .precision (strings) and the l/h/ll size letters (ll is read as 32 bit
; after taking both words) ---

m_printf:
    lea eax, [esp+8]
    push eax
    push dword [esp+8]
    push dword m__iob+FILE_SIZE
    call m_vfprintf
    add esp, 12
    ret
m_fprintf:
    lea eax, [esp+12]
    push eax
    push dword [esp+12]
    push dword [esp+12]
    call m_vfprintf
    add esp, 12
    ret
m_vprintf:
    push dword [esp+8]
    push dword [esp+8]
    push dword m__iob+FILE_SIZE
    call m_vfprintf
    add esp, 12
    ret
; int vfprintf(FILE*, fmt, va)
m_vfprintf:
    push esi
    push edi
    push ebp
    push ebx
    mov eax, [esp+20]
    mov [fmt_file], eax
    mov dword [fmt_sink], sink_file
    mov esi, [esp+24]
    mov ebp, [esp+28]
    call format
    pop ebx
    pop ebp
    pop edi
    pop esi
    ret
m_sprintf:
    lea eax, [esp+12]
    push eax
    push dword [esp+12]
    push dword [esp+12]
    call m_vsprintf
    add esp, 12
    ret
; int vsprintf(buf, fmt, va)
m_vsprintf:
    push esi
    push edi
    push ebp
    push ebx
    mov eax, [esp+20]
    mov [fmt_dst], eax
    mov dword [fmt_sink], sink_buf
    mov esi, [esp+24]
    mov ebp, [esp+28]
    call format
    mov ecx, [fmt_dst]
    mov byte [ecx], 0
    pop ebx
    pop ebp
    pop edi
    pop esi
    ret

sink_file:                          ; al -> the stream in fmt_file
    push esi
    mov esi, [fmt_file]
    call stream_putc
    pop esi
    ret
sink_buf:                           ; al -> fmt_dst++
    push ecx
    mov ecx, [fmt_dst]
    mov [ecx], al
    inc dword [fmt_dst]
    pop ecx
    ret

; esi = format, ebp = the arguments -> eax = characters written
format:
    xor edi, edi
.next:
    lodsb
    test al, al
    jz .end
    cmp al, '%'
    je .spec
.lit:
    call .emit
    jmp .next
.end:
    mov eax, edi
    ret
.emit:
    call [fmt_sink]
    inc edi
    ret
.spec:
    mov byte [f_pad], ' '
    mov byte [f_left], 0
    mov byte [f_long], 0
    mov dword [f_width], 0
    mov dword [f_prec], -1
.flag:
    lodsb
    cmp al, '-'
    jne .f0
    mov byte [f_left], 1
    jmp .flag
.f0:
    cmp al, '0'
    jne .wid
    mov byte [f_pad], '0'
    jmp .flag
.wid:
    cmp al, '*'
    jne .wd
    mov eax, [ebp]
    add ebp, 4
    mov [f_width], eax
    lodsb
    jmp .dot
.wd:
    movzx ecx, al
    sub ecx, '0'
    cmp ecx, 9
    ja .dot
    mov eax, [f_width]
    imul eax, 10
    add eax, ecx
    mov [f_width], eax
    lodsb
    jmp .wd
.dot:
    cmp al, '.'
    jne .size
    mov dword [f_prec], 0
    lodsb
    cmp al, '*'
    jne .pd
    mov eax, [ebp]
    add ebp, 4
    mov [f_prec], eax
    lodsb
    jmp .size
.pd:
    movzx ecx, al
    sub ecx, '0'
    cmp ecx, 9
    ja .size
    mov eax, [f_prec]
    imul eax, 10
    add eax, ecx
    mov [f_prec], eax
    lodsb
    jmp .pd
.size:
    cmp al, 'l'
    je .sz
    cmp al, 'h'
    je .sz0
    cmp al, 'I'                     ; I64 / I32
    je .szi
    jmp .conv
.sz:
    inc byte [f_long]
.sz0:
    lodsb
    jmp .size
.szi:
    lodsb                           ; '6' or '3'
    cmp al, '6'
    jne .szi2
    mov byte [f_long], 2
.szi2:
    lodsb                           ; '4' or '2'
    lodsb
    jmp .size
.conv:
    test al, al
    jz .end
    cmp al, 'd'
    je .sdec
    cmp al, 'i'
    je .sdec
    cmp al, 'u'
    je .udec
    cmp al, 'x'
    je .hexl
    cmp al, 'X'
    je .hexu
    cmp al, 'p'
    je .ptr
    cmp al, 's'
    je .str
    cmp al, 'c'
    je .chr
    jmp .lit                        ; %% and anything unknown: as is
.arg:                               ; -> eax = next argument (ll: low word)
    mov eax, [ebp]
    add ebp, 4
    cmp byte [f_long], 2
    jb .ar
    add ebp, 4
.ar:
    ret
.sdec:
    call .arg
    xor ecx, ecx                    ; sign
    test eax, eax
    jns .dec
    neg eax
    mov cl, '-'
    jmp .dec
.udec:
    call .arg
    xor ecx, ecx
.dec:
    mov ebx, 10
    jmp .num
.hexl:
    call .arg
    xor ecx, ecx
    mov ebx, 16
    mov byte [f_hexa], 'a'-10
    jmp .num
.ptr:
    mov dword [f_width], 8
    mov byte [f_pad], '0'
.hexu:
    call .arg
    xor ecx, ecx
    mov ebx, 16
    mov byte [f_hexa], 'A'-10
.num:                               ; eax = value, ebx = base, cl = sign or 0
    push edi
    mov edi, numbuf+12
    mov byte [edi], 0
.dig:
    xor edx, edx
    div ebx
    cmp dl, 10
    jb .dd
    add dl, [f_hexa]
    jmp .dput
.dd:
    add dl, '0'
.dput:
    dec edi
    mov [edi], dl
    test eax, eax
    jnz .dig
    test cl, cl
    jz .nosign
    cmp byte [f_pad], '0'
    je .zsign
    dec edi
    mov [edi], cl
.nosign:
    mov eax, edi
    pop edi
    mov dword [f_prec], -1
    jmp .put
.zsign:                             ; "-0042": the sign before the zeros
    mov eax, edi
    pop edi
    push eax
    mov al, cl
    call .emit
    pop eax
    dec dword [f_width]
    mov dword [f_prec], -1
    jmp .put
.chr:
    mov eax, [ebp]
    add ebp, 4
    mov [numbuf], al
    mov byte [numbuf+1], 0
    mov eax, numbuf
    mov dword [f_prec], -1
    jmp .put
.str:
    mov eax, [ebp]
    add ebp, 4
    test eax, eax
    jnz .put
    mov eax, s_null
.put:                               ; eax = text: pad, text, pad
    push esi
    mov esi, eax
    xor ecx, ecx                    ; its length, cut at the precision
.ln:
    cmp ecx, [f_prec]
    jae .lnz
    cmp byte [esi+ecx], 0
    je .lnz
    inc ecx
    jmp .ln
.lnz:
    mov edx, [f_width]
    sub edx, ecx                    ; padding
    cmp byte [f_left], 0
    jne .text
    call .pad
.text:
    jecxz .post
    lodsb
    call .emit
    dec ecx
    jmp .text
.post:
    cmp byte [f_left], 0
    je .pd2
    mov byte [f_pad], ' '
    call .pad
.pd2:
    pop esi
    jmp .next
.pad:                               ; edx copies of f_pad (if > 0)
    cmp edx, 0
    jle .pr
    mov al, [f_pad]
    call .emit
    dec edx
    jmp .pad
.pr:
    mov edx, 0
    ret

; --- the table and the data ---

%macro WINSHIM_TABLE 0
    K InitializeCriticalSection
    K InitializeCriticalSectionAndSpinCount
    K DeleteCriticalSection
    K EnterCriticalSection
    K LeaveCriticalSection
    K FreeLibrary
    K GetModuleHandleW
    K LoadLibraryA
    K LoadLibraryW
    K LoadLibraryExA
    K LoadLibraryExW
    K GetProcAddress
    K IsDBCSLeadByteEx
    K SetUnhandledExceptionFilter
    K Sleep
    K GetCurrentProcessId
    K GetCurrentThreadId
    K GetCurrentProcess
    K GetCurrentThread
    K GetTickCount
    K GetSystemTimeAsFileTime
    K QueryPerformanceCounter
    K GetStartupInfoA
    K GetEnvironmentVariableA
    K TlsAlloc
    K TlsFree
    K TlsGetValue
    K TlsSetValue
    K VirtualProtect
    K VirtualQuery
    K MultiByteToWideChar
    K WideCharToMultiByte
    K ExitThread
    K FlushFileBuffers
    K GetFileType
    K GetConsoleMode
    K SetConsoleMode
    K GetConsoleOutputCP
    K GetConsoleCP
    K GetACP
    K DeleteFileA
    M __getmainargs
    M __p___argc
    M __set_app_type
    M __setusermatherr
    M _lock
    M _unlock
    M _cexit
    M _c_exit
    M _fpreset
    M __p__commode
    M __p__fmode
    M __p__acmdln
    M _ismbblead
    M _errno
    M _initterm
    M _onexit
    M atexit
    M exit
    M _exit
    M _amsg_exit
    M abort
    M signal
    M setlocale
    M localeconv
    M malloc
    M calloc
    M free
    M realloc
    M strlen
    M wcslen
    M memcpy
    M memmove
    M memset
    M memcmp
    M strcmp
    M strncmp
    M strcpy
    M strcat
    M strchr
    M strerror
    M atoi
    M atol
    M fwrite
    M fread
    M fputc
    M putc
    M putchar
    M fputs
    M puts
    M getchar
    M fgetc
    M getc
    M fgets
    M fopen
    M fclose
    M fflush
    M setvbuf
    M printf
    M fprintf
    M vprintf
    M vfprintf
    M sprintf
    M vsprintf
    M _iob
    M __initenv
    M __mb_cur_max
    M _commode
    M _fmode
%endmacro

ARGV_MAX    equ 16
ATEXIT_MAX  equ 32

align 4
m__iob times 3*FILE_SIZE db 0       ; stdin, stdout, stderr
m___initenv dd env_tab              ; char **__initenv
m___mb_cur_max dd 1
m__commode dd 0
m__fmode dd 0
env_tab dd 0                        ; an empty environment
lconv_c dd s_dot
    times 11 dd s_empty
s_dot db '.', 0
s_empty db 0
s_C db 'C', 0
s_error db 'error', 0
s_null db '(null)', 0
m_aborted db 'winrun: the program aborted', 10, 0

%macro WINSHIM_BSS 0
alignb 4
tick_fake resd 1
acmdln resd 1
errno_v resd 1
argc_cache resd 1
natexit resd 1
atexit_tab resd ATEXIT_MAX
argv_tab resd ARGV_MAX+1
argbuf resb 96
tls_used resb 64
fmt_sink resd 1
fmt_file resd 1
fmt_dst resd 1
f_width resd 1
f_prec resd 1
f_pad resb 1
f_left resb 1
f_long resb 1
f_hexa resb 1
onechar resb 4
numbuf resb 16
%endmacro
