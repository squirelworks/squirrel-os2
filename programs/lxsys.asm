; lxsys — more Linux i386 calls (P.2): writev, ioctl (isatty), uname,
; stat64/fstat64, _llseek, openat, access, rename, unlink, mkdir, rmdir,
; getcwd, time/clock_gettime, the uid calls, rt_sigaction/sigprocmask,
; set_thread_area with a GS-relative read, and -EFAULT for kernel
; pointers from ring 3. Original code.
; Prints "lxsys: uname Linux i686" and "lxsys: PASS", or "lxsys: FAIL x".
%include "lxelf.inc"
LX_ELF_HEADER _start

%macro STEP 1
    mov byte [step], %1
%endmacro
%macro SYS 1-4
    mov eax, %1
%if %0 > 1
    mov ebx, %2
%endif
%if %0 > 2
    mov ecx, %3
%endif
%if %0 > 3
    mov edx, %4
%endif
    int 0x80
%endmacro

_start:
    STEP 'a'                        ; writev: two pieces, one call
    SYS 146, 1, iov, 2
    cmp eax, part1_len + part2_len
    jne fail
    STEP 'b'                        ; isatty: the console is, a file is not
    SYS 54, 1, 0x5401, termios
    test eax, eax
    jnz fail
    SYS 54, 1, 0x5413, winsz
    test eax, eax
    jnz fail
    cmp word [winsz+2], 80
    jne fail
    STEP 'c'                        ; uname
    SYS 122, uts
    test eax, eax
    jnz fail
    cmp dword [uts], 'Linu'
    jne fail
    SYS 4, 1, unamemsg, unamemsg_len
    SYS 4, 1, uts, 5                ; sysname
    SYS 4, 1, space, 1
    SYS 4, 1, uts+4*65, 4           ; machine
    SYS 4, 1, nl, 1
    STEP 'd'                        ; a file through openat, then stat64
    mov esi, 0644o
    SYS 295, -100, fname, 0x241     ; AT_FDCWD, O_WRONLY|O_CREAT|O_TRUNC
    cmp eax, 3
    jl fail
    mov ebp, eax
    SYS 4, ebp, text, text_len
    SYS 6, ebp
    SYS 195, fname, statbuf
    test eax, eax
    jnz fail
    cmp dword [statbuf+44], text_len     ; st_size
    jne fail
    cmp word [statbuf+16], 0x81A4        ; S_IFREG | 0644
    jne fail
    STEP 'e'                        ; fstat64 on a file and the console
    SYS 5, fname, 0
    mov ebp, eax
    SYS 197, ebp, statbuf
    test eax, eax
    jnz fail
    cmp dword [statbuf+44], text_len
    jne fail
    SYS 197, 1, statbuf
    cmp word [statbuf+16], 0x2190        ; S_IFCHR: the console
    jne fail
    SYS 54, ebp, 0x5401, termios    ; a file is not a terminal
    cmp eax, -25
    jne fail
    STEP 'f'                        ; _llseek to the end, 64-bit result
    mov eax, 140
    mov ebx, ebp
    xor ecx, ecx
    xor edx, edx
    mov esi, pos64
    mov edi, 2                      ; SEEK_END
    int 0x80
    test eax, eax
    jnz fail
    cmp dword [pos64], text_len
    jne fail
    SYS 6, ebp
    STEP 'g'                        ; rename, access, unlink, mkdir
    SYS 38, fname, fname2
    test eax, eax
    jnz fail
    SYS 33, fname, 0
    cmp eax, -2                     ; the old name is gone
    jne fail
    SYS 33, fname2, 0
    test eax, eax
    jnz fail
    SYS 10, fname2
    test eax, eax
    jnz fail
    SYS 10, fname2
    cmp eax, -2
    jne fail
    SYS 39, dname, 0755o
    test eax, eax
    jnz fail
    SYS 40, dname                   ; rmdir, so the next run starts clean
    test eax, eax
    jnz fail
    STEP 'h'                        ; getcwd, time, clock, ids, signals
    SYS 183, cwdbuf, 16
    cmp eax, 2
    jne fail
    cmp word [cwdbuf], '/'
    jne fail
    SYS 13, 0
    test eax, eax
    js fail
    SYS 265, 1, ts                  ; CLOCK_MONOTONIC
    test eax, eax
    jnz fail
    cmp dword [ts+4], 1000000000
    jae fail
    SYS 199
    test eax, eax
    jnz fail
    mov dword [oldmask], -1
    SYS 175, 0, 0, oldmask
    test eax, eax
    jnz fail
    cmp dword [oldmask], 0
    jne fail
    STEP 'i'                        ; TLS: set_thread_area, then read via GS
    mov dword [udesc], -1
    mov dword [udesc+4], tlsblock
    mov dword [udesc+8], 0xFFFFF
    mov dword [udesc+12], 0x51      ; seg_32bit, limit_in_pages, useable
    SYS 243, udesc
    test eax, eax
    jnz fail
    mov eax, [udesc]                ; the entry it gave
    shl eax, 3
    or eax, 3
    mov gs, ax
    mov eax, [gs:4]
    cmp eax, 0x7E57AB1E
    jne fail
    STEP 'j'                        ; ring 3: kernel pointers are refused
    SYS 4, 1, 0x8000, 16            ; write from the kernel image
    cmp eax, -14                    ; EFAULT
    jne fail
    SYS 122, 0x100000               ; uname into the high kernel image
    cmp eax, -14
    jne fail
    SYS 146, 1, iov_bad, 1          ; an iovec pointing into the kernel
    cmp eax, -14
    jne fail
    SYS 4, 1, pass, pass_len
    SYS 252, 0
fail:
    SYS 4, 1, failmsg, failmsg_len
    SYS 1, 1

iov dd part1, part1_len, part2, part2_len
iov_bad dd 0x8000, 16
part1 db 'lxsys: writev '
part1_len equ $ - part1
part2 db 'joins two pieces', 10
part2_len equ $ - part2
unamemsg db 'lxsys: uname '
unamemsg_len equ $ - unamemsg
space db ' '
nl db 10
fname db 'lxsys.txt', 0
fname2 db 'lxsys.ren', 0
dname db 'lxsysdir', 0
text db 'twelve bytes'
text_len equ $ - text
tlsblock dd 0, 0x7E57AB1E
pass db 'lxsys: PASS', 10
pass_len equ $ - pass
failmsg db 'lxsys: FAIL '
step db '?', 10
failmsg_len equ $ - failmsg
LX_ELF_BSS
termios resb 64
winsz resb 8
uts resb 6*65
alignb 4
statbuf resb 96
pos64 resd 2
cwdbuf resb 16
ts resd 2
oldmask resd 2
udesc resd 4
LX_ELF_END
