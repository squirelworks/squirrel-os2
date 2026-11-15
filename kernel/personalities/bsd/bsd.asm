; Squirrel-OS/2 — FreeBSD i386 personality (P.10)
; Included from pm.asm after the Linux personality. Original code,
; written from the public FreeBSD i386 system call numbers and calling
; convention; no BSD code.
;
; A static ELF32 with EI_OSABI 9 (ELFOSABI_FREEBSD) is loaded like a Linux
; one (same initial stack) and marked BSD in bsd_slot. Its int 0x80 goes
; through lx_isr to bsd_isr: the call number is in eax and the arguments
; are on the user stack above a return address (the libc stub's call), as
; FreeBSD passes them. Most calls reuse the Linux handlers after a small
; translation; a result comes back FreeBSD's way: eax = value with CF
; clear, or eax = errno (positive) with CF set. 64-bit results (lseek)
; use edx for the high half. See
; documentation/architecture/foreign-compatibility.md.

BSD_OSABI   equ 9
BSD_O_APPEND equ 0x0008
BSD_O_CREAT equ 0x0200
BSD_O_TRUNC equ 0x0400
BSD_MAP_ANON equ 0x1000
BSD_TIOCGETA equ 0x402C7413
BSD_TIOCGWINSZ equ 0x40087468

; edi = PCB just loaded, eax = 1 for a BSD program, else 0
bsd_mark:
    push edx
    mov edx, edi
    sub edx, proc_table
    shr edx, 6
    mov [bsd_slot+edx], al
    pop edx
    ret

; int 0x80 from a BSD process (lx_isr sends it here)
bsd_isr:
    pushad
    mov esi, bsd_calls
.find:
    cmp esi, bsd_calls_end
    jae .nosys
    cmp ax, [esi]
    jne .next
    cmp eax, 0xFFFF
    jbe .hit
.next:
    add esi, 8
    jmp .find
.hit:
    ; the arguments: six dwords above the return address
    push esi
    mov esi, [esp+4+44]         ; the user stack
    add esi, 4
    mov ecx, 8*4
    call ua_range
    mov edi, esi
    pop esi
    jc .efault
    mov ebx, [edi]
    mov ecx, [edi+4]
    mov edx, [edi+8]
    movzx eax, byte [esi+2]     ; the pointer checks, as for Linux
    push esi
    mov esi, [edi+12]
    call lx_uargs
    pop esi
    jc .efault
    mov eax, [esi+4]
    mov esi, [edi+12]
    mov ebp, [edi+20]
    mov edi, [edi+16]
    call eax
    jmp .ret
.efault:
    mov eax, -14
    jmp .ret
.nosys:
    mov eax, -78                ; FreeBSD's ENOSYS
.ret:
    and dword [esp+40], ~1      ; CF clear: a value
    cmp eax, -4095
    jb .val
    neg eax                     ; -errno -> errno, CF set
    cmp eax, 11
    jne .e1
    mov eax, 35                 ; EAGAIN
.e1:
    cmp eax, 38
    jne .e2
    mov eax, 78                 ; ENOSYS
.e2:
    cmp eax, 36
    jne .e3
    mov eax, 63                 ; ENAMETOOLONG
.e3:
    cmp eax, 39
    jne .e4
    mov eax, 66                 ; ENOTEMPTY
.e4:
    or dword [esp+40], 1
.val:
    mov [esp+28], eax
    popad
    iretd

; open(path, flags, mode): FreeBSD flag bits to Linux ones
bsd_open:
    mov edx, ecx
    and ecx, 3                  ; access mode: the same
    test edx, BSD_O_CREAT
    jz .t
    or ecx, LX_O_CREAT
.t:
    test edx, BSD_O_TRUNC
    jz .a
    or ecx, LX_O_TRUNC
.a:
    test edx, BSD_O_APPEND
    jz .go
    or ecx, LX_O_APPEND
.go:
    jmp lx_open

; break(addr): 0, or ENOMEM
bsd_break:
    push ebx
    call lx_brk
    pop ebx
    cmp eax, ebx
    jne .no
    xor eax, eax
    ret
.no:
    mov eax, LX_ENOMEM
    ret

; mmap(addr, len, prot, flags, fd, pos...) (477, and 197 with a pad
; before pos): anonymous memory only
bsd_mmap:
    test esi, BSD_MAP_ANON
    jz .nodev
    mov esi, LX_MAP_ANON | 2
    jmp lx_mmap2
.nodev:
    mov eax, LX_ENODEV
    ret

; lseek(fd, off_lo, off_hi, whence) (478), or with a pad after fd (199):
; a 64-bit result, the high half in edx
bsd_lseek_pad:
    mov ecx, edx                ; off_lo
    mov edx, edi                ; whence (fifth argument)
    jmp bsd_lseek_go
bsd_lseek:
    mov edx, esi                ; whence (fourth argument)
bsd_lseek_go:
    call lx_lseek
    mov dword [esp+4+20], 0     ; bsd_isr's pushad frame: edx = 0
    ret

; ioctl(fd, request, arg): the terminal queries isatty() makes
bsd_ioctl:
    cmp ecx, BSD_TIOCGETA
    jne .w
    mov ecx, 0x5401
    jmp .go
.w:
    cmp ecx, BSD_TIOCGWINSZ
    jne .notty
    mov ecx, 0x5413
.go:
    mov eax, LK_IOCTL           ; checked again with the Linux request
    call lx_uargs
    jc .fault
    jmp lx_ioctl
.notty:
    mov eax, LX_ENOTTY
    ret
.fault:
    mov eax, LX_EFAULT
    ret

; __getcwd(buf, len): 0 when it fits
bsd_getcwd:
    call lx_getcwd
    test eax, eax
    js .r
    xor eax, eax
.r:
    ret

bsd_calls:
    LXCALL 1, proc_exit             ; exit(code)
    LXCALL 3, lx_read, LK_C_D
    LXCALL 4, lx_write, LK_C_D
    LXCALL 5, bsd_open, LK_BZ
    LXCALL 6, lx_close
    LXCALL 10, lx_unlink, LK_BZ
    LXCALL 17, bsd_break            ; break
    LXCALL 20, sys_getpid
    LXCALL 24, lx_ok                ; getuid
    LXCALL 25, lx_ok                ; geteuid
    LXCALL 33, lx_access, LK_BZ
    LXCALL 43, lx_ok                ; getegid
    LXCALL 47, lx_ok                ; getgid
    LXCALL 54, bsd_ioctl
    LXCALL 73, lx_ok                ; munmap
    LXCALL 74, lx_ok                ; mprotect
    LXCALL 75, lx_ok                ; madvise
    LXCALL 116, lx_gettimeofday, LK_B8
    LXCALL 120, lx_readv, LK_IOV
    LXCALL 121, lx_writev, LK_IOV
    LXCALL 128, lx_rename, LK_BZ_CZ
    LXCALL 136, lx_mkdir, LK_BZ
    LXCALL 137, lx_unlink, LK_BZ    ; rmdir
    LXCALL 197, bsd_mmap            ; mmap with the pad (FreeBSD 6)
    LXCALL 199, bsd_lseek_pad       ; lseek with the pad (FreeBSD 6)
    LXCALL 232, lx_clock_gettime, LK_C8
    LXCALL 240, lx_nanosleep
    LXCALL 253, lx_ok               ; issetugid: no
    LXCALL 326, bsd_getcwd, LK_B_C  ; __getcwd
    LXCALL 431, proc_exit           ; thr_exit: one thread per process
    LXCALL 477, bsd_mmap
    LXCALL 478, bsd_lseek
bsd_calls_end:

bsd_slot times PROC_MAX db 0
