; lxfile — Linux i386 file and memory calls (P.2). Original code.
; open(O_CREAT|O_TRUNC) + write + close, open + read + lseek + close,
; brk to grow and shrink the heap, an anonymous mmap2, and checks the
; -errno results of a missing file and a bad descriptor.
; Prints "lxfile: PASS" or "lxfile: FAIL n" (n = the failed step).
%include "lxelf.inc"
LX_ELF_HEADER _start

%macro STEP 1
    mov byte [step], %1
%endmacro

_start:
    STEP 'a'                        ; create and write a file
    mov eax, LX_OPEN
    mov ebx, fname
    mov ecx, LX_O_WRONLY|LX_O_CREAT|LX_O_TRUNC
    mov edx, 0644o
    int 0x80
    cmp eax, 3
    jl fail
    mov ebp, eax
    mov eax, LX_WRITE
    mov ebx, ebp
    mov ecx, text
    mov edx, text_len
    int 0x80
    cmp eax, text_len
    jne fail
    STEP 'b'
    mov eax, LX_CLOSE
    mov ebx, ebp
    int 0x80
    test eax, eax
    jnz fail
    STEP 'c'                        ; read it back from offset 6
    mov eax, LX_OPEN
    mov ebx, fname
    mov ecx, LX_O_RDONLY
    int 0x80
    cmp eax, 3
    jl fail
    mov ebp, eax
    mov eax, LX_LSEEK
    mov ebx, ebp
    mov ecx, 6
    xor edx, edx
    int 0x80
    cmp eax, 6
    jne fail
    STEP 'd'
    mov eax, LX_READ
    mov ebx, ebp
    mov ecx, buf
    mov edx, 64
    int 0x80
    cmp eax, text_len-6
    jne fail
    mov esi, buf
    mov edi, text+6
    mov ecx, text_len-6
    repe cmpsb
    jne fail
    mov eax, LX_CLOSE
    mov ebx, ebp
    int 0x80
    STEP 'e'                        ; errors are -errno
    mov eax, LX_OPEN
    mov ebx, missing
    xor ecx, ecx
    int 0x80
    cmp eax, -2                     ; ENOENT
    jne fail
    mov eax, LX_CLOSE
    mov ebx, ebp                    ; already closed
    int 0x80
    cmp eax, -9                     ; EBADF
    jne fail
    STEP 'f'                        ; brk: query, grow 8 KB, use, shrink
    mov eax, LX_BRK
    xor ebx, ebx
    int 0x80
    test eax, eax
    jz fail
    mov esi, eax
    lea ebx, [eax+8192]
    mov eax, LX_BRK
    int 0x80
    lea ebx, [esi+8192]
    cmp eax, ebx
    jne fail
    cmp dword [esi+8188], 0         ; new memory reads as zero
    jne fail
    mov dword [esi+8188], 0x51515151
    mov eax, LX_BRK
    mov ebx, esi
    int 0x80
    cmp eax, esi
    jne fail
    STEP 'g'                        ; anonymous mmap2, page aligned
    mov eax, LX_MMAP2
    xor ebx, ebx
    mov ecx, 5000
    mov edx, LX_PROT_RW
    mov esi, LX_MAP_PRIVATE_ANON
    mov edi, -1
    xor ebp, ebp
    int 0x80
    cmp eax, -4096
    jae fail
    test eax, 0xFFF
    jnz fail
    mov dword [eax+4996], 0x12345678
    cmp dword [eax+4996], 0x12345678
    jne fail
    mov ebx, eax
    mov eax, LX_MUNMAP
    mov ecx, 5000
    int 0x80
    test eax, eax
    jnz fail
    STEP 'h'                        ; file-backed mmap is not offered
    mov eax, LX_MMAP2
    xor ebx, ebx
    mov ecx, 4096
    mov edx, LX_PROT_RW
    mov esi, 2                      ; MAP_PRIVATE, no MAP_ANONYMOUS
    mov edi, 3
    xor ebp, ebp
    int 0x80
    cmp eax, -19                    ; ENODEV
    jne fail
    mov eax, LX_WRITE
    mov ebx, 1
    mov ecx, pass
    mov edx, pass_len
    int 0x80
    mov eax, LX_EXIT
    xor ebx, ebx
    int 0x80
fail:
    mov eax, LX_WRITE
    mov ebx, 1
    mov ecx, failmsg
    mov edx, failmsg_len
    int 0x80
    mov eax, LX_EXIT
    mov ebx, 1
    int 0x80

fname db 'lxfile.txt', 0
missing db 'nosuchfile', 0
text db 'Linux wrote this', 10
text_len equ $ - text
pass db 'lxfile: PASS', 10
pass_len equ $ - pass
failmsg db 'lxfile: FAIL '
step db '?', 10
failmsg_len equ $ - failmsg
LX_ELF_BSS
buf resb 64
LX_ELF_END
