; Squirrel-OS/2 — Linux personality, i386 subset (P.1, P.2)
; Included from pm.asm. Original code, written from the public i386 Linux
; syscall ABI (numbers, registers, -errno results). No Linux source used.
;
; A static ELF32 whose EI_OSABI byte is 3 (ELFOSABI_LINUX) is loaded by
; loader.asm as usual and then marked Linux: PCB_LINUX holds its real entry
; and the process starts in lx_start, which builds the Linux initial stack
; (argc, argv, envp, auxv) and jumps there. While PCB_LINUX is non-zero,
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
; Programs still run in ring 0 like native ones; the table moves behind the
; ring-3 gate unchanged when 2.4 lands.

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
LX_AT_FDCWD equ -100

; Linux open() flags that have a native meaning
LX_O_CREAT  equ 0x40
LX_O_TRUNC  equ 0x200
LX_O_APPEND equ 0x400
LX_MAP_ANON equ 0x20

; First code of a Linux process (proc_trampoline calls it as entry(arg)).
; Stack on entry to the program, low to high: argc, argv[0] (the program
; name), argv[1] (the argument text, if any), NULL, envp NULL, AT_NULL.
lx_start:
    mov esi, [esp+4]            ; argument text
    mov ebx, [proc_cur]
    xor eax, eax
    push eax                    ; auxv: AT_NULL, 0
    push eax
    push eax                    ; envp: empty
    push eax                    ; argv terminator
    inc eax                     ; argc = 1
    cmp byte [esi], 0
    je .name
    push esi                    ; argv[1]
    inc eax
.name:
    lea ecx, [ebx+PCB_NAME]
    push ecx                    ; argv[0]
    push eax                    ; argc
    xor edx, edx                ; no exit handler from a dynamic linker
    jmp [ebx+PCB_LINUX]

; int 0x80 from a Linux process (syscall_isr jumps here)
lx_isr:
    pushad
    mov esi, lx_calls
.find:
    cmp esi, lx_calls_end
    jae .nosys
    cmp eax, [esi]
    je .hit
    add esi, 8
    jmp .find
.hit:
    mov eax, [esi+4]
    mov esi, [esp+4]            ; the caller's esi again
    call eax
    jmp .ret
.nosys:
    mov eax, LX_ENOSYS
.ret:
    mov [esp+28], eax
    popad
    iretd

lx_calls:
    dd 1,   proc_exit           ; exit(code)
    dd 252, proc_exit           ; exit_group(code)
    dd 3,   lx_read
    dd 4,   lx_write
    dd 5,   lx_open
    dd 6,   lx_close
    dd 19,  lx_lseek
    dd 20,  sys_getpid
    dd 45,  lx_brk
    dd 90,  lx_mmap_old
    dd 91,  lx_ok               ; munmap: nothing is freed before exit
    dd 192, lx_mmap2
    ; P.2 continued: what small static C programs (musl-style start-up,
    ; stdio through writev, isatty through ioctl) ask for
    dd 10,  lx_unlink
    dd 13,  lx_time
    dd 24,  lx_ok               ; getuid: everybody is root (0)
    dd 33,  lx_access
    dd 38,  lx_rename
    dd 39,  lx_mkdir
    dd 40,  lx_unlink           ; rmdir: SQFS deletes empty directories the same way
    dd 47,  lx_ok               ; getgid
    dd 49,  lx_ok               ; geteuid
    dd 50,  lx_ok               ; getegid
    dd 54,  lx_ioctl
    dd 78,  lx_gettimeofday
    dd 122, lx_uname
    dd 125, lx_ok               ; mprotect: all program memory is RWX
    dd 140, lx_llseek
    dd 145, lx_readv
    dd 146, lx_writev
    dd 162, lx_nanosleep
    dd 174, lx_sigaction
    dd 175, lx_sigprocmask
    dd 183, lx_getcwd
    dd 195, lx_stat64
    dd 196, lx_stat64           ; lstat64: no links
    dd 197, lx_fstat64
    dd 199, lx_ok               ; getuid32
    dd 200, lx_ok               ; getgid32
    dd 201, lx_ok               ; geteuid32
    dd 202, lx_ok               ; getegid32
    dd 219, lx_ok               ; madvise
    dd 224, sys_getpid          ; gettid: one thread per process
    dd 243, lx_set_thread_area
    dd 258, sys_getpid          ; set_tid_address -> the tid
    dd 265, lx_clock_gettime
    dd 295, lx_openat
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

; rt_sigaction(sig, act, oldact, size) / rt_sigprocmask(how, set, old, size):
; no signals are delivered; old values read as "default, nothing blocked"
lx_sigaction:
    mov edi, edx
    mov ecx, 20/4
    jmp lx_zero_out
lx_sigprocmask:
    mov edi, edx
    mov ecx, 8/4
lx_zero_out:                    ; edi = buffer or 0, ecx dwords
    xor eax, eax
    test edi, edi
    jz .r
    rep stosd
.r:
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
