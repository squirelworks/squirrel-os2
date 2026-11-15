; bsdhello — a FreeBSD i386 static ELF32 (EI_OSABI 9), hand-written (P.10).
; Original code. Calls go FreeBSD's way: number in eax, arguments on the
; stack above a return address, errors as CF set with a positive errno.
; Checks write, open (BSD flag bits), lseek with a 64-bit result, read,
; unlink, break, anonymous mmap, the isatty ioctl, __getcwd, EFAULT,
; ENOENT and ENOSYS. Prints "bsdhello: PASS" or "bsdhello: FAIL x".
%include "lxelf.inc"
LX_ELF_HEADER _start, 9

%macro STEP 1
    mov byte [step], %1
%endmacro
; BSD nr, args...: push the arguments right to left, call the stub
%macro BSD 1-*
%assign n %0-1
%rep %0-1
%rotate -1
    push dword %1
%endrep
%rotate -1
    mov eax, %1
    call kcall
%if n > 0
    lea esp, [esp+n*4]           ; keeps CF
%endif
%endmacro

_start:
    STEP 'a'                        ; write
    BSD 4, 1, hello, hello_len
    jc fail
    cmp eax, hello_len
    jne fail
    STEP 'b'                        ; a missing file: CF and ENOENT
    BSD 5, missing, 0, 0
    jnc fail
    cmp eax, 2
    jne fail
    STEP 'c'                        ; create with FreeBSD's O_CREAT|O_TRUNC
    BSD 5, fname, 0x601, 0644o
    jc fail
    mov ebp, eax
    BSD 4, ebp, text, text_len
    jc fail
    BSD 6, ebp
    jc fail
    STEP 'd'                        ; read it back from offset 3
    BSD 5, fname, 0, 0
    jc fail
    mov ebp, eax
    mov edx, -1
    BSD 478, ebp, 3, 0, 0           ; lseek(fd, 3 (64-bit), SEEK_SET)
    jc fail
    cmp eax, 3
    jne fail
    test edx, edx
    jnz fail
    BSD 3, ebp, buf, 64
    jc fail
    cmp eax, text_len - 3
    jne fail
    cmp dword [buf], 'en t'
    jne fail
    BSD 6, ebp
    BSD 10, fname
    jc fail
    STEP 'e'                        ; break, then anonymous memory
    BSD 17, 0x40002000              ; the heap starts at 0x40000000 here
    jc fail
    test eax, eax
    jnz fail
    mov byte [0x40001FFF], 1
    BSD 477, 0, 8192, 3, 0x1002, -1, 0, 0   ; MAP_ANON|MAP_PRIVATE
    jc fail
    mov dword [eax+8188], 0xACE
    STEP 'f'                        ; isatty: TIOCGETA on stdout
    BSD 54, 1, 0x402C7413, termios
    jc fail
    STEP 'g'                        ; __getcwd
    BSD 326, cwdbuf, 16
    jc fail
    test eax, eax
    jnz fail
    cmp byte [cwdbuf], '/'
    jne fail
    STEP 'h'                        ; kernel memory: EFAULT; unknown: ENOSYS
    BSD 4, 1, 0x8000, 4
    jnc fail
    cmp eax, 14
    jne fail
    BSD 999
    jnc fail
    cmp eax, 78
    jne fail
    BSD 20                          ; getpid
    jc fail
    test eax, eax
    jz fail
    BSD 4, 1, pass, pass_len
    BSD 1, 0

kcall:
    int 0x80
    ret

fail:
    BSD 4, 1, failmsg, failmsg_len
    BSD 1, 1

hello db 'Hello from FreeBSD land!', 10
hello_len equ $ - hello
missing db 'nosuchfile', 0
fname db 'bsd.txt', 0
text db 'seven tens', 10
text_len equ $ - text
pass db 'bsdhello: PASS', 10
pass_len equ $ - pass
failmsg db 'bsdhello: FAIL '
step db '?', 10
failmsg_len equ $ - failmsg
LX_ELF_BSS
buf resb 64
termios resb 64
cwdbuf resb 16
LX_ELF_END
