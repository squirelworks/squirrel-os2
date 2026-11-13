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
