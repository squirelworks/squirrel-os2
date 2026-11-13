; Squirrel-OS/2 — Linux personality, i386 subset (P.1, P.2)
; Included from pm.asm. Original code, written from the public i386 Linux
; syscall ABI (numbers, registers, -errno results). No Linux source used.
;
; A static ELF32 whose EI_OSABI byte is 3 (ELFOSABI_LINUX) is loaded by
; loader.asm as usual and then marked Linux: PCB_LINUX holds its entry.
; proc_enter_user hands such a process to lx_enter_user, which builds the
; Linux initial stack (argc, argv, envp, auxv) on its ring-3 stack and
; enters it there. While PCB_LINUX is non-zero,
; int 0x80 from that process goes to lx_isr instead of the native table:
;   eax = Linux call number, ebx/ecx/edx/esi/edi/ebp = arguments,
;   eax = result, or -errno; every other register is preserved.
; Unknown calls return -ENOSYS. See
; documentation/architecture/foreign-compatibility.md for the table.
;
; File descriptors: Linux 0/1/2 are the console (0 = keyboard or the
; redirected input, 1 and 2 = the console device); Linux fd n >= 3 is
; native SQFS fd n-3. Memory: brk and anonymous mmap both grow the native
; heap (SYS_SBRK, 0x40000000+), so they share one region; munmap is
; accepted and frees nothing until the process ends.
;
; Linux programs run in ring 3 like native ones (2.4). A call from ring 3
; has its pointer arguments checked first (the kind byte of each table
; entry, lx_uargs, on the native ua_range/ua_str); a bad one returns
; -EFAULT without running the call.

PCB_LINUX   equ 36              ; real entry of a Linux process, 0 = native

LX_ENOENT   equ -2
LX_EIO      equ -5
LX_EBADF    equ -9
LX_ENOMEM   equ -12
LX_EINVAL   equ -22
LX_ENODEV   equ -19
LX_ENOSYS   equ -38
LX_ENOTTY   equ -25
LX_ERANGE   equ -34
LX_EFAULT   equ -14
LX_EPERM    equ -1
LX_ESRCH    equ -3
LX_EINTR    equ -4
LX_AT_FDCWD equ -100

; Linux open() flags that have a native meaning
LX_O_CREAT  equ 0x40
LX_O_TRUNC  equ 0x200
LX_O_APPEND equ 0x400
LX_MAP_ANON equ 0x20

; ebx = PCB of a Linux process, edi = its argument text, already copied
; to its ring-3 stack (proc_enter_user). Builds, below that, a copy of the
; program name and the Linux initial stack, low to high: argc, argv[0]
; (the name), argv[1] (the argument text, if any), NULL, envp NULL,
; AT_NULL; then enters the program in ring 3 with edx = 0.
lx_enter_user:
    mov edx, edi                ; argv[1]
    sub edi, PROC_NAMELEN
    lea esi, [ebx+PCB_NAME]
    mov ecx, PROC_NAMELEN/4
    rep movsd
    lea ecx, [edi-PROC_NAMELEN] ; argv[0]
    and edi, -16
    sub edi, PROC_NAMELEN+16
    xor eax, eax
    mov [edi+12], eax           ; auxv: AT_NULL, 0
    mov [edi+8], eax
    mov [edi+4], eax            ; envp: empty
    mov [edi], eax              ; argv terminator
    inc eax                     ; argc = 1
    cmp byte [edx], 0
    je .name
    sub edi, 4
    mov [edi], edx              ; argv[1]
    inc eax
.name:
    mov [edi-4], ecx            ; argv[0]
    mov [edi-8], eax            ; argc
    sub edi, 8
    push dword USER_DS          ; ss
    push edi                    ; esp
    push dword 0x202            ; eflags: IF, IOPL 0
    push dword USER_CS
    push dword [ebx+PCB_LINUX]
    xor eax, eax
    xor ebx, ebx
    xor ecx, ecx
    xor edx, edx                ; no exit handler from a dynamic linker
    xor esi, esi
    xor edi, edi
    xor ebp, ebp
    iretd

; int 0x80 from a Linux process (syscall_isr jumps here)
lx_isr:
    push eax                    ; a FreeBSD process: its own convention
    mov eax, [proc_cur]         ; (P.10, bsd.asm)
    sub eax, proc_table
    shr eax, 6
    cmp byte [bsd_slot+eax], 0
    pop eax
    jne bsd_isr
    pushad
    mov esi, lx_calls
    cmp eax, 0xFFFF
    ja .nosys
.find:
    cmp esi, lx_calls_end
    jae .nosys
    cmp ax, [esi]
    je .hit
    add esi, 8
    jmp .find
.hit:
    test byte [esp+36], 3       ; the caller's CS: from ring 3, its
    jz .call                    ; pointers must be its own memory
    movzx eax, byte [esi+2]
    push esi
    mov esi, [esp+8]            ; the caller's esi
    call lx_uargs
    pop esi
    jc .efault
.call:
    mov eax, [esi+4]
    mov esi, [esp+4]            ; the caller's esi again
    call eax
    jmp .ret
.efault:
    mov eax, LX_EFAULT
    jmp .ret
.nosys:
    mov eax, LX_ENOSYS
.ret:
    mov [esp+28], eax
    test byte [esp+36], 3       ; back to ring 3: a pending signal first
    jz .out
    call lx_deliver
.out:
    popad
    iretd

; what each call's pointer arguments are (lx_uargs)
LK_NONE     equ 0
LK_BZ       equ 1               ; ebx -> string
LK_BZ_CZ    equ 2               ; ebx, ecx -> strings
LK_C_D      equ 3               ; ecx -> edx bytes
LK_B_C      equ 4               ; ebx -> ecx bytes
LK_BZ_C96   equ 5               ; ebx -> string, ecx -> 96 bytes (stat64)
LK_C96      equ 6               ; ecx -> 96 bytes
LK_B390     equ 7               ; ebx -> 390 bytes (utsname)
LK_IOV      equ 8               ; ecx -> edx iovecs, and each buffer
LK_B16      equ 9               ; ebx -> 16 bytes
LK_D20      equ 10              ; edx -> 20 bytes, or 0
LK_D8       equ 11              ; edx -> 8 bytes, or 0
LK_B4       equ 12              ; ebx -> 4 bytes, or 0
LK_B8       equ 13              ; ebx -> 8 bytes, or 0
LK_C8       equ 14              ; ecx -> 8 bytes
LK_S8       equ 15              ; esi -> 8 bytes
LK_CZ       equ 16              ; ecx -> string
LK_IOCTL    equ 17              ; edx -> 36 (TCGETS) or 8 (TIOCGWINSZ) bytes
LK_B24      equ 18              ; ebx -> 24 bytes
LK_C20_D20  equ 19              ; ecx -> 20 bytes or 0, edx -> 20 bytes or 0
LK_C8_D8    equ 20              ; ecx -> 8 bytes or 0, edx -> 8 bytes or 0

%macro LXCALL 2-3 LK_NONE       ; number, handler, kind
    dw %1
    db %3, 0
    dd %2
%endmacro

; eax = kind, ebx/ecx/edx/esi = the caller's arguments -> CF if a pointer
; is not the caller's memory. Keeps every register.
lx_uargs:
    pushad
    jmp [.kinds+eax*4]
.kinds:
    dd .ok, .bz, .bz_cz, .c_d, .b_c, .bz_c96, .c96, .b390, .iov, .b16
    dd .d20, .d8, .b4, .b8, .c8, .s8, .cz, .ioctl, .b24, .c20_d20, .c8_d8
.c20_d20:
    mov eax, 20
    jmp .cd
.c8_d8:
    mov eax, 8
.cd:                            ; ecx and edx -> eax bytes each, 0 allowed
    mov esi, ecx
    mov ecx, eax
    test esi, esi
    jz .cd2
    call ua_range
    jc .bad
.cd2:
    mov esi, edx
    jmp .opt
.bz_cz:
    mov esi, ecx
    call ua_str
    jc .bad
.bz:
    mov esi, ebx
    jmp .str
.cz:
    mov esi, ecx
.str:
    call ua_str
    jc .bad
    jmp .ok
.c_d:
    mov esi, ecx
    mov ecx, edx
    jmp .range
.b_c:
    mov esi, ebx
    jmp .range
.bz_c96:
    mov esi, ebx
    call ua_str
    jc .bad
.c96:
    mov esi, ecx
    mov ecx, 96
    jmp .range
.b390:
    mov esi, ebx
    mov ecx, 6*65
    jmp .range
.b16:
    mov esi, ebx
    mov ecx, 16
    jmp .range
.b24:
    mov esi, ebx
    mov ecx, 24
    jmp .range
.d20:
    mov ecx, 20
    jmp .dopt
.d8:
    mov ecx, 8
.dopt:
    mov esi, edx
    jmp .opt
.b4:
    mov ecx, 4
    jmp .bopt
.b8:
    mov ecx, 8
.bopt:
    mov esi, ebx
.opt:
    test esi, esi
    jz .ok
    jmp .range
.c8:
    mov esi, ecx
    mov ecx, 8
    jmp .range
.s8:
    mov ecx, 8
    jmp .range
.ioctl:
    mov esi, edx
    cmp ecx, 0x5413
    mov ecx, 8
    je .range
    cmp dword [esp+24], 0x5401  ; the caller's ecx (pushad frame)
    jne .ok
    mov ecx, 36
    jmp .range
.iov:
    mov esi, ecx
    cmp edx, 1024
    ja .bad
    lea ecx, [edx*8]
    call ua_range
    jc .bad
    mov ebx, esi
    mov edi, edx
.iv:
    test edi, edi
    jz .ok
    mov esi, [ebx]
    mov ecx, [ebx+4]
    call ua_range
    jc .bad
    add ebx, 8
    dec edi
    jmp .iv
.range:
    call ua_range
    jc .bad
.ok:
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

lx_calls:
    LXCALL 1, proc_exit             ; exit(code)
    LXCALL 252, proc_exit           ; exit_group(code)
    LXCALL 3, lx_read, LK_C_D
    LXCALL 4, lx_write, LK_C_D
    LXCALL 5, lx_open, LK_BZ
    LXCALL 6, lx_close
    LXCALL 19, lx_lseek
    LXCALL 20, sys_getpid
    LXCALL 45, lx_brk
    LXCALL 90, lx_mmap_old, LK_B24
    LXCALL 91, lx_ok                ; munmap: nothing is freed before exit
    LXCALL 192, lx_mmap2
    ; P.2 continued: what small static C programs (musl-style start-up,
    ; stdio through writev, isatty through ioctl) ask for
    LXCALL 10, lx_unlink, LK_BZ
    LXCALL 13, lx_time, LK_B4
    LXCALL 24, lx_ok                ; getuid: everybody is root (0)
    LXCALL 33, lx_access, LK_BZ
    LXCALL 38, lx_rename, LK_BZ_CZ
    LXCALL 39, lx_mkdir, LK_BZ
    LXCALL 40, lx_unlink, LK_BZ     ; rmdir: SQFS deletes empty directories the same way
    LXCALL 47, lx_ok                ; getgid
    LXCALL 49, lx_ok                ; geteuid
    LXCALL 50, lx_ok                ; getegid
    LXCALL 54, lx_ioctl, LK_IOCTL
    LXCALL 78, lx_gettimeofday, LK_B8
    LXCALL 122, lx_uname, LK_B390
    LXCALL 125, lx_ok               ; mprotect: all program memory is RWX
    LXCALL 140, lx_llseek, LK_S8
    LXCALL 145, lx_readv, LK_IOV
    LXCALL 146, lx_writev, LK_IOV
    LXCALL 162, lx_nanosleep
    LXCALL 174, lx_sigaction, LK_C20_D20
    LXCALL 175, lx_sigprocmask, LK_C8_D8
    LXCALL 37, lx_kill              ; kill(pid, sig)
    LXCALL 238, lx_kill             ; tkill(tid, sig): one thread per process
    LXCALL 270, lx_tgkill           ; tgkill(tgid, tid, sig)
    LXCALL 119, lx_sigreturn
    LXCALL 173, lx_rt_sigreturn
    LXCALL 176, lx_sigpending, LK_B8
    LXCALL 29, lx_pause
    LXCALL 64, lx_getppid
    LXCALL 183, lx_getcwd, LK_B_C
    LXCALL 195, lx_stat64, LK_BZ_C96
    LXCALL 196, lx_stat64, LK_BZ_C96; lstat64: no links
    LXCALL 197, lx_fstat64, LK_C96
    LXCALL 199, lx_ok               ; getuid32
    LXCALL 200, lx_ok               ; getgid32
    LXCALL 201, lx_ok               ; geteuid32
    LXCALL 202, lx_ok               ; getegid32
    LXCALL 219, lx_ok               ; madvise
    LXCALL 224, sys_getpid          ; gettid: one thread per process
    LXCALL 243, lx_set_thread_area, LK_B16
    LXCALL 258, sys_getpid          ; set_tid_address -> the tid
    LXCALL 265, lx_clock_gettime, LK_C8
    LXCALL 295, lx_openat, LK_CZ
lx_calls_end:

; fd >= 3 -> CF clear and ebx = native fd; fd 0..2 -> CF set
lx_fd:
    sub ebx, 3
    ret

; -1 from a native call -> the given -errno in eax
lx_err_badf:
    cmp eax, -1
    jne .r
    mov eax, LX_EBADF
.r:
    ret

lx_ok:
    xor eax, eax
    ret

; write(fd, buf, len)
lx_write:
    call lx_fd
    jnc .file
    cmp ebx, 1-3
    jb .badf                    ; stdin is not writable
    mov esi, ecx
    mov ecx, edx
    mov ebx, dev_con
    jmp dev_write
.file:
    call sys_write
    jmp lx_err_badf
.badf:
    mov eax, LX_EBADF
    ret

; read(fd, buf, len): fd 0 reads a line (up to len bytes, newline
; included) from the keyboard or the redirected input, echoing keys
lx_read:
    call lx_fd
    jnc .file
    cmp ebx, 0-3
    jne lx_write.badf
    mov edi, ecx
    xor ebp, ebp                ; bytes read
.key:
    cmp ebp, edx
    jae .done
    push edx
    push edi
    push ebp
    call sys_getc
    cmp eax, -1
    je .eof                     ; end of redirected input
    cmp byte [in_on], 0
    jne .noecho
    push eax
    call putc
    pop eax
.noecho:
    pop ebp
    pop edi
    pop edx
    mov [edi+ebp], al
    inc ebp
    cmp al, 10
    jne .key
.done:
    mov eax, ebp
    ret
.eof:
    pop ebp
    pop edi
    pop edx
    jmp .done
.file:
    call sys_read
    jmp lx_err_badf

; open(path, flags, mode) -> fd (native + 3) or -ENOENT
lx_open:
    xor edx, edx
    test ecx, LX_O_CREAT
    jz .t
    or edx, O_CREATE
.t:
    test ecx, LX_O_TRUNC
    jz .a
    or edx, O_TRUNC
.a:
    test ecx, LX_O_APPEND
    jz .go
    or edx, O_APPEND
.go:
    mov ecx, edx
    call sys_open
    cmp eax, -1
    je .no
    add eax, 3
    ret
.no:
    mov eax, LX_ENOENT
    ret

; close(fd)
lx_close:
    call lx_fd
    jc lx_ok                    ; the console stays open
    call sys_close
    jmp lx_err_badf

; lseek(fd, offset, whence): SEEK_SET/CUR/END are 0/1/2 in both ABIs
lx_lseek:
    call lx_fd
    jc .spipe
    call fs_seek
    cmp eax, -1
    jne .r
    mov eax, LX_EINVAL
.r:
    ret
.spipe:
    mov eax, -29                ; ESPIPE: the console cannot seek
    ret

; brk(addr) -> the new break, or the current one if addr is 0 or the
; heap cannot move there
lx_brk:
    mov eax, [proc_cur]
    mov eax, [eax+PCB_AS]
    test eax, eax
    jz .r
    mov ecx, eax
    mov eax, [eax+AS_BRK]
    test ebx, ebx
    jz .r
    push ebx
    sub ebx, eax                ; bytes to add (or give back)
    call sys_sbrk
    pop ebx
    cmp eax, -1
    je .old
    mov eax, ebx
.r:
    ret
.old:
    mov eax, [ecx+AS_BRK]       ; refused: report the unchanged break
    ret

; old_mmap(struct *args): the six arguments in memory
lx_mmap_old:
    mov ecx, [ebx+4]
    mov esi, [ebx+12]
    mov ebx, [ebx]
    ; fall through
; mmap2(addr, len, prot, flags, fd, pgoff): anonymous memory only, taken
; from the heap on a page boundary; the address hint is ignored
lx_mmap2:
    test esi, LX_MAP_ANON
    jz .nodev
    test ecx, ecx
    jz .inval
    push ecx
    mov eax, [proc_cur]
    mov eax, [eax+PCB_AS]
    test eax, eax
    jz .nomem1
    mov ebx, [eax+AS_BRK]       ; round the break up to a page first
    neg ebx
    and ebx, PAGE_SIZE-1
    call sys_sbrk
    cmp eax, -1
    je .nomem1
    pop ebx
    add ebx, PAGE_SIZE-1
    and ebx, -PAGE_SIZE
    call sys_sbrk               ; old break = the new mapping
    cmp eax, -1
    je .nomem
    ret
.nomem1:
    pop ecx
.nomem:
    mov eax, LX_ENOMEM
    ret
.inval:
    mov eax, LX_EINVAL
    ret
.nodev:
    mov eax, LX_ENODEV
    ret

; ---------- P.2 continued ----------

; unlink(path) / rename(old, new) / mkdir(path, mode)
lx_unlink:
    call sys_delete
    jmp lx_err_noent
lx_rename:
    call sys_rename
    jmp lx_err_noent
lx_mkdir:
    mov esi, ebx
    call fs_mkdir
    ; fall through
lx_err_noent:                   ; -1 -> -ENOENT
    cmp eax, -1
    jne .r
    mov eax, LX_ENOENT
.r:
    ret

; access(path, mode): exists -> 0, else -ENOENT
lx_access:
    xor ecx, ecx
    call sys_open
    cmp eax, -1
    je lx_err_noent
    mov ebx, eax
    call sys_close
    xor eax, eax
    ret

; openat(dirfd, path, flags, mode): only AT_FDCWD (or an absolute path)
lx_openat:
    cmp ebx, LX_AT_FDCWD
    je .cwd
    cmp byte [ecx], '/'
    je .cwd
    mov eax, LX_EBADF
    ret
.cwd:
    mov ebx, ecx
    mov ecx, edx
    jmp lx_open

; _llseek(fd, high, low, *result, whence): files are small, high must be 0
lx_llseek:
    test ecx, ecx
    jnz .inval
    push esi
    mov ecx, edx
    mov edx, edi
    call lx_lseek
    pop esi
    test eax, eax
    js .r
    mov [esi], eax
    mov dword [esi+4], 0
    xor eax, eax
.r:
    ret
.inval:
    mov eax, LX_EINVAL
    ret

; writev(fd, iov, n) / readv: each {base, len} in turn; stops early on a
; short transfer and returns the total (or the first error)
lx_writev:
    mov ebp, lx_write
    jmp lx_iov
lx_readv:
    mov ebp, lx_read
lx_iov:
    push esi
    push edi
    mov esi, ecx                ; iov
    mov edi, edx                ; count
    xor eax, eax
    push eax                    ; total
.l:
    test edi, edi
    jz .done
    push ebx
    push ebp
    push esi
    push edi
    mov ecx, [esi]
    mov edx, [esi+4]
    call ebp
    pop edi
    pop esi
    pop ebp
    pop ebx
    test eax, eax
    js .err
    add [esp], eax
    cmp eax, [esi+4]
    jne .done
    add esi, 8
    dec edi
    jmp .l
.err:
    cmp dword [esp], 0
    jne .done                   ; something moved: report that
    mov [esp], eax
.done:
    pop eax
    pop edi
    pop esi
    ret

; ioctl(fd, request, arg): the console answers TCGETS (a zeroed termios)
; and TIOCGWINSZ (25 x 80), so isatty() is true for fds 0-2 only
lx_ioctl:
    cmp ebx, 3
    jae .notty
    cmp ecx, 0x5401             ; TCGETS
    je .tcgets
    cmp ecx, 0x5413             ; TIOCGWINSZ
    je .winsz
    cmp ecx, 0x5402             ; TCSETS and friends: accepted
    jb .notty
    cmp ecx, 0x5404
    jbe lx_ok
.notty:
    mov eax, LX_ENOTTY
    ret
.tcgets:
    mov edi, edx
    mov ecx, 36/4
    xor eax, eax
    rep stosd
    ret
.winsz:
    mov dword [edx], 25 | (80 << 16)    ; rows, columns
    mov dword [edx+4], 0
    xor eax, eax
    ret

; time(*t): seconds since boot (there is no clock call yet)
lx_time:
    mov eax, [ticks]
    xor edx, edx
    mov ecx, 100
    div ecx
    test ebx, ebx
    jz .r
    mov [ebx], eax
.r:
    ret

; gettimeofday(*tv, *tz) / clock_gettime(clock, *ts): since boot
lx_gettimeofday:
    mov ecx, 10000              ; microseconds per tick
    jmp lx_clock
lx_clock_gettime:
    mov ebx, ecx
    mov ecx, 10000000           ; nanoseconds per tick
lx_clock:
    test ebx, ebx
    jz lx_ok
    push ecx
    mov eax, [ticks]
    xor edx, edx
    mov ecx, 100
    div ecx
    mov [ebx], eax              ; seconds
    mov eax, edx
    pop ecx
    mul ecx
    mov [ebx+4], eax            ; micro- or nanoseconds
    xor eax, eax
    ret

; nanosleep(req, rem): gives the processor away once
lx_nanosleep:
    call sys_yield
    xor eax, eax
    ret

; getcwd(buf, size): "/" (programs are found from the root)
lx_getcwd:
    cmp ecx, 2
    jb .range
    mov word [ebx], '/'
    mov eax, 2
    ret
.range:
    mov eax, LX_ERANGE
    ret

; uname(*utsname): six 65-byte fields
lx_uname:
    mov edi, ebx
    mov ecx, 6*65
    xor eax, eax
    rep stosb
    mov esi, lx_uts
.f:
    lodsb
    cmp al, 0xFF
    je lx_ok
    movzx edi, al               ; field number
    imul edi, 65
    add edi, ebx
.c:
    lodsb
    stosb
    test al, al
    jnz .c
    jmp .f

; stat64(path, *st) / fstat64(fd, *st): mode and size (struct stat64,
; the i386 layout: st_mode at 16, st_size at 44, st_blksize at 56)
lx_stat64:
    push ecx
    xor ecx, ecx
    call sys_open
    pop edi
    cmp eax, -1
    je lx_err_noent
    push edi
    push eax                    ; the fd
    mov ebx, eax
    call lx_fsize
    pop ebx
    push eax                    ; the size
    call sys_close
    pop eax
    pop edi
    jmp lx_fill_reg
lx_fstat64:
    mov edi, ecx
    call lx_fd
    jnc .file
    call lx_stat_clear
    mov dword [edi+16], 0x2190  ; S_IFCHR | 0620: the console
    mov dword [edi+56], 1024
    xor eax, eax
    ret
.file:
    call lx_fsize
    cmp eax, -1
    jne lx_fill_reg
    mov eax, LX_EBADF
    ret
lx_fill_reg:                    ; edi = stat64, eax = size
    push eax
    call lx_stat_clear
    pop eax
    mov dword [edi+16], 0x81A4  ; S_IFREG | 0644
    mov dword [edi+20], 1       ; st_nlink
    mov [edi+44], eax           ; st_size (low dword)
    mov dword [edi+56], 512     ; st_blksize
    add eax, 511
    shr eax, 9
    mov [edi+64], eax           ; st_blocks
    xor eax, eax
    ret
lx_stat_clear:                  ; zero the 96-byte stat64 at edi
    push edi
    mov ecx, 96/4
    xor eax, eax
    rep stosd
    pop edi
    ret

; ebx = native fd -> eax = its size (the position is kept), or -1
lx_fsize:
    push edi
    push ebx
    xor ecx, ecx
    mov edx, 1                  ; SEEK_CUR: where it is now
    call fs_seek
    cmp eax, -1
    je .r
    push eax
    mov ebx, [esp+4]
    xor ecx, ecx
    mov edx, 2                  ; SEEK_END
    call fs_seek
    pop ecx
    push eax
    mov ebx, [esp+4]
    xor edx, edx
    call fs_seek                ; back
    pop eax
.r:
    pop ebx
    pop edi
    ret

; set_thread_area(*user_desc): the per-process TLS segment (tls.asm)
; is the one entry; entry_number -1 asks for it, and it is 7 (GS = 0x3B)
lx_set_thread_area:
    cmp dword [ebx], -1
    je .any
    cmp dword [ebx], TLS_SEL >> 3
    jne .inval
.any:
    mov dword [ebx], TLS_SEL >> 3
    push ebx
    mov ebx, [ebx+4]            ; base_addr
    call sys_settls
    pop ebx
    xor eax, eax
    ret
.inval:
    mov eax, LX_EINVAL
    ret

lx_uts:                         ; field number, text; 0xFF ends
    db 0, 'Linux', 0            ; sysname: what Linux programs check for
    db 1, 'squirrel', 0         ; nodename
    db 2, '2.6.32-squirrel', 0  ; release
    db 3, 'Squirrel-OS/2 Linux personality', 0
    db 4, 'i686', 0             ; machine
    db 0xFF

; ---------- signals (P.2) ----------
; Per slot: 32 actions of 16 bytes (handler, flags, restorer, mask), the
; blocked mask and the pending set, both with bit n-1 for signal n. A
; signal is delivered when its process returns from int 0x80 to ring 3:
; lx_deliver builds a frame on the user stack (return address, signal
; number, siginfo, ucontext with the i386 sigcontext and the old mask,
; and a sigreturn stub) and resumes the process at its handler.
; rt_sigreturn/sigreturn reload the registers from that frame. Only
; signals 1..32 exist; a process blocked inside a call sees a signal
; when the call returns.
LX_SIGKILL  equ 9
LX_SIGSEGV  equ 11
LX_SIGSTOP  equ 19
LX_SA_SIGINFO  equ 4
LX_SA_RESTORER equ 0x04000000
LX_SA_NODEFER  equ 0x40000000
LX_SA_RESETHAND equ 0x80000000
LX_UNBLOCKABLE equ (1 << (LX_SIGKILL-1)) | (1 << (LX_SIGSTOP-1))
LX_FRAME    equ 272             ; bytes of a signal frame
LXF_INFO    equ 16              ; siginfo, 128 bytes
LXF_UC      equ 144             ; ucontext: flags, link, stack (12)
LXF_MC      equ 164             ; sigcontext: gs fs es ds edi esi ebp esp
                                ; ebx edx ecx eax trapno err eip cs eflags
                                ; esp_at_signal ss fpstate oldmask cr2
LXF_MASK    equ 252             ; uc_sigmask (8)
LXF_STUB    equ 260             ; mov eax, 173 / int 0x80

; -> eax = the current slot
lx_slot:
    mov eax, [proc_cur]
    sub eax, proc_table
    shr eax, 6
    ret

; edi = PCB of a new process (proc_spawn): default actions, nothing
; blocked or pending
lx_sig_clear:
    pushad
    mov eax, edi
    sub eax, proc_table
    shr eax, 6
    mov dword [lx_sig_mask+eax*4], 0
    mov dword [lx_sig_pend+eax*4], 0
    shl eax, 9
    lea edi, [lx_sig_act+eax]
    mov ecx, 512/4
    xor eax, eax
    rep stosd
    popad
    ret

; rt_sigaction(sig, act, oact, sigsetsize)
lx_sigaction:
    lea eax, [ebx-1]
    cmp eax, 31
    ja .inval
    push eax
    call lx_slot
    shl eax, 9
    pop edi
    shl edi, 4
    lea edi, [lx_sig_act+eax+edi]
    test ecx, ecx               ; read the new action before writing the
    jz .old                     ; old one: they may be the same buffer
    cmp ebx, LX_SIGKILL
    je .inval
    cmp ebx, LX_SIGSTOP
    je .inval
    push dword [ecx]            ; handler
    push dword [ecx+4]          ; flags
    push dword [ecx+8]          ; restorer
    push dword [ecx+12]         ; mask, low word
.old:
    test edx, edx
    jz .new
    mov eax, [edi]
    mov [edx], eax
    mov eax, [edi+4]
    mov [edx+4], eax
    mov eax, [edi+8]
    mov [edx+8], eax
    mov eax, [edi+12]
    mov [edx+12], eax
    mov dword [edx+16], 0
.new:
    test ecx, ecx
    jz .ok
    pop dword [edi+12]
    pop dword [edi+8]
    pop dword [edi+4]
    pop dword [edi]
    and dword [edi+12], ~LX_UNBLOCKABLE
.ok:
    xor eax, eax
    ret
.inval:
    mov eax, LX_EINVAL
    ret

; rt_sigprocmask(how, set, oset, sigsetsize)
lx_sigprocmask:
    call lx_slot
    lea edi, [lx_sig_mask+eax*4]
    mov esi, [edi]              ; the old mask
    test ecx, ecx
    jz .old
    mov eax, [ecx]
    cmp ebx, 0                  ; SIG_BLOCK
    jne .unblock
    or eax, esi
    jmp .set
.unblock:
    cmp ebx, 1                  ; SIG_UNBLOCK
    jne .setmask
    not eax
    and eax, esi
    jmp .set
.setmask:
    cmp ebx, 2                  ; SIG_SETMASK
    jne .inval
.set:
    and eax, ~LX_UNBLOCKABLE
    mov [edi], eax
.old:
    test edx, edx
    jz .r
    mov [edx], esi
    mov dword [edx+4], 0
.r:
    xor eax, eax
    ret
.inval:
    mov eax, LX_EINVAL
    ret

; rt_sigpending(set): blocked signals that wait
lx_sigpending:
    call lx_slot
    mov ecx, [lx_sig_pend+eax*4]
    and ecx, [lx_sig_mask+eax*4]
    mov [ebx], ecx
    mov dword [ebx+4], 0
    xor eax, eax
    ret

; tgkill(tgid, tid, sig)
lx_tgkill:
    mov ebx, ecx
    mov ecx, edx
    ; fall through
; kill(pid, sig): pid 0, -1 or our own is this process; another pid must
; be a Linux process. Signal 0 only asks whether the process exists.
lx_kill:
    cmp ecx, 32
    ja .inval
    mov edi, [proc_cur]
    test ebx, ebx
    jz .found
    cmp ebx, -1
    je .found
    cmp ebx, [edi+PCB_PID]
    je .found
    test ebx, ebx
    js .srch
    call proc_find
    test edi, edi
    jz .srch
    cmp dword [edi+PCB_STATE], P_ZOMBIE
    je .srch
    cmp dword [edi+PCB_LINUX], 0
    je .perm                    ; native programs take no signals
.found:
    jecxz .ok
    mov eax, edi
    sub eax, proc_table
    shr eax, 6
    dec ecx
    lock bts dword [lx_sig_pend+eax*4], ecx
.ok:
    xor eax, eax
    ret
.inval:
    mov eax, LX_EINVAL
    ret
.srch:
    mov eax, LX_ESRCH
    ret
.perm:
    mov eax, LX_EPERM
    ret

; pause(): waits until a signal can be delivered, then -EINTR
lx_pause:
    call lx_slot
    mov ecx, [lx_sig_mask+eax*4]
    not ecx
    test [lx_sig_pend+eax*4], ecx
    jnz .intr
    call proc_idle
    jmp lx_pause
.intr:
    mov eax, LX_EINTR
    ret

; getppid()
lx_getppid:
    mov eax, [proc_cur]
    mov eax, [eax+PCB_PARENT]
    ret

; [esp+4] = lx_isr's pushad frame, from a ring-3 call: delivers one
; pending, unblocked signal. A default action ends the process (exit
; code 128 + signal) or ignores the signal.
lx_deliver:
    lea ebp, [esp+4]
    call lx_slot
    mov ebx, eax
.again:
    mov eax, [lx_sig_mask+ebx*4]
    not eax
    and eax, [lx_sig_pend+ebx*4]
    jz .r
    bsf ecx, eax
    lock btr dword [lx_sig_pend+ebx*4], ecx
    mov esi, ebx
    shl esi, 9
    shl ecx, 4
    lea esi, [lx_sig_act+esi+ecx]
    shr ecx, 4
    inc ecx                     ; the signal number
    cmp ecx, LX_SIGKILL
    je lx_sig_term
    mov eax, [esi]
    cmp eax, 1                  ; SIG_IGN
    je .again
    test eax, eax
    jnz .handler
    ; SIG_DFL: ignored for SIGCHLD, SIGCONT, the stop signals (no job
    ; control here), SIGURG and SIGWINCH; the end of the process otherwise
    mov eax, 1
    shl eax, cl
    shr eax, 1
    test eax, (1 << 16) | (1 << 17) | (1 << 18) | (1 << 19) | (1 << 20) | (1 << 21) | (1 << 22) | (1 << 27)
    jnz .again
    jmp lx_sig_term
.r:
    ret
.handler:
    mov edi, [ebp+44]           ; the user stack
    sub edi, LX_FRAME
    and edi, -16
    sub edi, 4                  ; (esp + 4) % 16 == 0 at the handler
    push esi
    push ecx
    mov esi, edi
    mov ecx, LX_FRAME
    call ua_range
    pop ecx
    pop esi
    jc .segv
    push esi
    push ecx
    ; siginfo and ucontext start out zero
    push edi
    xor eax, eax
    mov ecx, LX_FRAME/4
    rep stosd
    pop edi
    pop ecx
    pop esi
    mov eax, [esi+8]            ; return address: the restorer, or the stub
    test dword [esi+4], LX_SA_RESTORER
    jnz .ret
    lea eax, [edi+LXF_STUB]
.ret:
    mov [edi], eax
    mov [edi+4], ecx
    lea eax, [edi+LXF_INFO]
    mov [edi+8], eax
    lea eax, [edi+LXF_UC]
    mov [edi+12], eax
    mov [edi+LXF_INFO], ecx     ; si_signo; si_code 0 = SI_USER
    mov eax, [proc_cur]
    mov eax, [eax+PCB_PID]
    mov [edi+LXF_INFO+12], eax  ; si_pid
    mov dword [edi+LXF_STUB], 0x0000ADB8    ; mov eax, 173
    mov dword [edi+LXF_STUB+4], 0x9080CD00  ; int 0x80
    ; sigcontext: the segments, then pushad's order edi..eax
    mov eax, gs
    mov [edi+LXF_MC], eax
    mov eax, fs
    mov [edi+LXF_MC+4], eax
    mov dword [edi+LXF_MC+8], USER_DS
    mov dword [edi+LXF_MC+12], USER_DS
    push esi
    push edi
    push ecx
    mov esi, ebp
    add edi, LXF_MC+16
    mov ecx, 8
    rep movsd
    pop ecx
    pop edi
    pop esi
    mov eax, [ebp+44]
    mov [edi+LXF_MC+28], eax    ; esp
    mov [edi+LXF_MC+68], eax    ; esp_at_signal
    mov eax, [ebp+32]
    mov [edi+LXF_MC+56], eax    ; eip
    mov eax, [ebp+36]
    mov [edi+LXF_MC+60], eax    ; cs
    mov eax, [ebp+40]
    mov [edi+LXF_MC+64], eax    ; eflags
    mov eax, [ebp+48]
    mov [edi+LXF_MC+72], eax    ; ss
    mov eax, [lx_sig_mask+ebx*4]
    mov [edi+LXF_MC+80], eax    ; oldmask
    mov [edi+LXF_MASK], eax
    ; the handler runs with its mask added, and its own signal unless
    ; SA_NODEFER
    or eax, [esi+12]
    test dword [esi+4], LX_SA_NODEFER
    jnz .mask
    lea edx, [ecx-1]
    bts eax, edx
.mask:
    and eax, ~LX_UNBLOCKABLE
    mov [lx_sig_mask+ebx*4], eax
    mov edx, [esi]              ; the handler
    test dword [esi+4], LX_SA_RESETHAND
    jz .go
    mov dword [esi], 0
.go:
    mov [ebp+32], edx           ; eip
    mov [ebp+44], edi           ; esp
    and dword [ebp+40], ~0x500  ; TF and DF clear
    mov [ebp+28], ecx           ; eax = sig, edx = siginfo, ecx = ucontext
    lea eax, [edi+LXF_INFO]
    mov [ebp+20], eax
    lea eax, [edi+LXF_UC]
    mov [ebp+24], eax
    ret
.segv:
    mov ecx, LX_SIGSEGV
    ; fall through
; ecx = signal: the process ends with 128 + signal
lx_sig_term:
    push ecx
    mov esi, lx_m_sig
    call puts
    pop eax
    push eax
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    pop ebx
    add ebx, 128
    jmp proc_exit

; rt_sigreturn(): the frame's return address has been popped
lx_rt_sigreturn:
    mov esi, [esp+4+44]
    sub esi, 4
    jmp lx_sigret
; sigreturn(): the restorer popped the signal number as well
lx_sigreturn:
    mov esi, [esp+4+44]
    sub esi, 8
; esi = the frame -> the registers from its sigcontext; eax as it was
lx_sigret:
    lea ebp, [esp+4]
    mov ecx, LX_FRAME
    call ua_range
    jnc .ok
    mov ecx, LX_SIGSEGV
    jmp lx_sig_term
.ok:
    lea edx, [esi+LXF_MC+16]
    mov edi, ebp
    mov ecx, 8
.cp:
    mov eax, [edx]
    mov [edi], eax
    add edx, 4
    add edi, 4
    loop .cp
    mov eax, [esi+LXF_MC+56]
    mov [ebp+32], eax           ; eip
    mov eax, [esi+LXF_MC+28]
    mov [ebp+44], eax           ; esp
    mov eax, [esi+LXF_MC+64]    ; only the arithmetic flags and DF
    and eax, 0xCD5
    and dword [ebp+40], ~0xCD5
    or [ebp+40], eax
    call lx_slot
    mov edx, [esi+LXF_MASK]
    and edx, ~LX_UNBLOCKABLE
    mov [lx_sig_mask+eax*4], edx
    mov eax, [ebp+28]
    ret

lx_m_sig db 'Program ended by signal ', 0
lx_sig_act times PROC_MAX*512 db 0
lx_sig_mask times PROC_MAX dd 0
lx_sig_pend times PROC_MAX dd 0
