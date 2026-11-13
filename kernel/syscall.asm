; Squirrel-OS/2 — system call interface (0.1.1)
; Included from pm.asm. Original code.
;
; ABI (see documentation/kernel/syscalls.md):
;   int 0x80, eax = call number, ebx/ecx/edx = arguments
;   return value in eax; every other register is preserved
;   unknown call number returns SYS_ENOSYS (-1)

SYS_PUTC    equ 0           ; ebx = char            -> 0
SYS_PUTS    equ 1           ; ebx = ptr to ASCIIZ   -> length written
SYS_GETC    equ 2           ; (blocking)            -> ASCII code
SYS_YIELD   equ 3           ;                       -> 0
SYS_SPAWN   equ 4           ; ebx = entry, ecx = arg -> pid or -1
SYS_EXIT    equ 5           ; ebx = exit code       (does not return)
SYS_WAIT    equ 6           ; ebx = pid             -> exit code or -1
SYS_GETPID  equ 7           ;                       -> pid
SYS_BREAD   equ 8           ; ebx = LBA, ecx = buf, edx = drive -> 0 or -1
SYS_BWRITE  equ 9           ; ebx = LBA, ecx = buf (data disk only) -> 0 or -1
SYS_OPEN    equ 10          ; ebx = name, ecx = O_* flags -> fd or -1
SYS_READ    equ 11          ; ebx = fd, ecx = buf, edx = len -> bytes or -1
SYS_WRITE   equ 12          ; ebx = fd, ecx = buf, edx = len -> bytes or -1
SYS_CLOSE   equ 13          ; ebx = fd              -> 0 or -1
SYS_CREATE  equ 14          ; ebx = name            -> 0 or -1
SYS_DELETE  equ 15          ; ebx = name            -> 0 or -1
SYS_RENAME  equ 16          ; ebx = old, ecx = new  -> 0 or -1
SYS_EXEC    equ 17          ; ebx = file name, ecx = argument -> pid or LD_E* (< 0)
SYS_READDIR equ 18          ; ebx = cursor (0 first), ecx = 20-byte buf -> next cursor, 0 at end, -1 no disk
SYS_PALLOC  equ 19          ;                       -> zeroed 4 KB page or 0
SYS_PFREE   equ 20          ; ebx = page            -> 0 or -1
SYS_SBRK    equ 21          ; ebx = bytes (signed)   -> old break or -1
SYS_DEVFIND equ 22          ; ebx = name             -> handle or -1
SYS_DEVREAD equ 23          ; ebx = handle, ecx = buf, edx = count/sector -> bytes or -1
SYS_DEVWRITE equ 24         ; as SYS_DEVREAD
SYS_SEEK    equ 25          ; ebx = fd, ecx = offset, edx = 0 set / 1 cur / 2 end -> position or -1 (1.0.2)
SYS_FSERROR equ 26          ; ebx = buf, ecx = size -> why the last file call failed (FE_*), text in buf (1.0.3)
SYS_SEND    equ 27          ; ebx = pid, ecx = message dword -> 0, -1 no such process, -2 queue full (1.2)
SYS_RECV    equ 28          ; -> the oldest message in the caller's queue; waits while it is empty (1.2)
SYS_KEYEVENTS equ 29        ; ebx = 1 on / 0 off: keys also arrive as MSG_KEY | ASCII messages (1.2.1)
SYS_NETSENDTO equ 30        ; ebx = block -> bytes, or -1 (1.9.7)
SYS_NETRECVFROM equ 31      ; ebx = block -> bytes, -1 port taken, -2 nothing (1.9.7)
SYS_SETPRIO equ 32          ; ebx = 0..3 -> 0, or -1 (1.9.9)
SYS_DEVREG  equ 33          ; ebx = name -> register a null char device (1.9.12)
SYS_DEVUNREG equ 34         ; ebx = name -> remove a device SYS_DEVREG made (2.0.2)
SYS_GUI     equ 35          ; ebx = GUI_* op, ecx/edx = args: graphics for programs (appsys.asm)
SYS_SETTLS  equ 36          ; ebx = base of the FS/GS segment -> its selector (P.5)
SYS_WINOPEN  equ 37         ; ebx = block: x, y, w, h, title, flags -> window id or -1 (2.2-progwin)
SYS_WINCLOSE equ 38         ; ebx = id -> 0 or -1
SYS_WINMOVE  equ 39         ; ebx = id, ecx = x | y << 16, edx = w | h << 16 (0 keeps) -> 0 or -1
SYS_WINTITLE equ 40         ; ebx = id, ecx = title -> 0 or -1
SYS_WINDRAW  equ 41         ; ebx = id, ecx = 28-byte command -> 0, a colour (WD_PIXEL), or -1
SYS_WINFLUSH equ 42         ; ebx = id -> 0 or -1: what was drawn reaches the screen
SYS_WINEVENT equ 43         ; ebx = 16-byte buffer, ecx = 0 wait / 1 poll -> 0, or -1 nothing
SYS_WININFO  equ 44         ; ebx = id or -1, ecx = 16-byte buffer -> 0 or -1
SYS_COUNT   equ 45

SYS_ENOSYS  equ -1
SYSCALL_VEC equ 0x80

; Install the gate: 32-bit trap gate, DPL 3, so IF is left as the caller
; had it and ring-3 code (2.4) may call it.
syscall_init:
    mov edi, idt+SYSCALL_VEC*8
    mov eax, syscall_isr
    call set_gate
    mov byte [edi+5], 0xEF
    ret

syscall_isr:
    KSEGS
    push esi                    ; a Linux process uses its own table (P.1)
    mov esi, [proc_cur]
    cmp dword [esi+PCB_LINUX], 0
    pop esi
    jne lx_isr
    cmp eax, SYS_COUNT
    jae .bad
    pushad
    test byte [esp+36], 3   ; the caller's CS: from ring 3 (2.4) ...
    jz .call
    call sys_uargs          ; ... its pointers must be its own memory
    jc .efault
.call:
    call [syscall_table+eax*4]
.ret:
    mov [esp+28], eax       ; overwrite saved eax so popad returns it
    popad
    iretd
.efault:
    mov eax, SYS_EFAULT
    jmp .ret
.bad:
    mov eax, SYS_ENOSYS
    iretd

; ---------- ring-3 pointer checks (2.4) ----------
; For a call from ring 3, every pointer argument must lie in memory that
; belongs to the program: its program area, its heap up to the break, or
; the ring-3 stack windows. Otherwise the call returns SYS_EFAULT (-1)
; without running. Strings must end inside the same region. SYS_PALLOC
; and SYS_PFREE hand out physical pages, so they are kernel-only.
; See documentation/kernel/ring3.md.

; one byte per call: what to check, from these
UA_NONE     equ 0
UA_BZ       equ 1           ; ebx -> string
UA_BZ_CZ    equ 2           ; ebx, ecx -> strings
UA_BZ_CZ0   equ 3           ; ebx -> string, ecx -> string or 0
UA_C_D      equ 4           ; ecx -> edx bytes
UA_B_C      equ 5           ; ebx -> ecx bytes
UA_C_512    equ 6           ; ecx -> a sector
UA_C_20     equ 7           ; ecx -> 20 bytes
UA_DEV      equ 8           ; ecx -> edx bytes (char) or a sector (block)
UA_NETSEND  equ 9           ; ebx -> 16-byte block, its +8 -> its +12 bytes
UA_NETRECV  equ 10          ; ebx -> 20-byte block, its +4 -> its +8 bytes
UA_KERNEL   equ 11          ; refused from ring 3
UA_GUI      equ 12          ; per GUI_* operation (gui_uargs, appsys.asm)

SYS_EFAULT  equ -1

sys_uarg_kind:
    db UA_NONE, UA_BZ, UA_NONE, UA_NONE         ; putc puts getc yield
    db UA_NONE, UA_NONE, UA_NONE, UA_NONE       ; spawn exit wait getpid
    db UA_C_512, UA_C_512, UA_BZ, UA_C_D        ; bread bwrite open read
    db UA_C_D, UA_NONE, UA_BZ, UA_BZ            ; write close create delete
    db UA_BZ_CZ, UA_BZ_CZ0, UA_C_20, UA_KERNEL  ; rename exec readdir palloc
    db UA_KERNEL, UA_NONE, UA_BZ, UA_DEV        ; pfree sbrk devfind devread
    db UA_DEV, UA_NONE, UA_B_C, UA_NONE         ; devwrite seek fserror send
    db UA_NONE, UA_NONE, UA_NETSEND, UA_NETRECV ; recv keyevents netsendto netrecvfrom
    db UA_NONE, UA_BZ, UA_BZ                    ; setprio devreg devunreg
    db UA_GUI                                   ; gui
    db UA_NONE                                  ; settls
    times 8 db UA_NONE                          ; 37-44 windows: checked in winsys.asm
%if $-sys_uarg_kind != SYS_COUNT
%error sys_uarg_kind needs one byte per system call
%endif

; eax = call number, ebx/ecx/edx = its arguments -> CF if a pointer is
; not the caller's. Keeps every register.
sys_uargs:
    pushad
    movzx eax, byte [sys_uarg_kind+eax]
    cmp eax, UA_GUI
    ja .ok
    jmp [.kinds+eax*4]
.kinds:
    dd .ok, .bz, .bz_cz, .bz_cz0, .c_d, .b_c, .c_512, .c_20, .dev, .netsend, .netrecv, .bad, .gui
.gui:
    call gui_uargs
    jc .bad
    jmp .ok
.bz_cz0:
    test ecx, ecx
    jz .bz
.bz_cz:
    mov esi, ecx
    call ua_str
    jc .bad
.bz:
    mov esi, ebx
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
.c_512:
    mov esi, ecx
    mov ecx, SECTOR_SIZE
    jmp .range
.c_20:
    mov esi, ecx
    mov ecx, 20
    jmp .range
.dev:
    mov esi, ecx
    mov ecx, edx
    call dev_handle
    test ebx, ebx
    jz .ok                  ; no such device: the call itself says so
    cmp dword [ebx+DEV_TYPE], DEV_BLOCK
    jne .range
    mov ecx, SECTOR_SIZE
    jmp .range
.netsend:
    mov esi, ebx
    mov ecx, 16
    call ua_range
    jc .bad
    mov esi, [ebx+8]
    mov ecx, [ebx+12]
    jmp .range
.netrecv:
    mov esi, ebx
    mov ecx, 20
    call ua_range
    jc .bad
    mov esi, [ebx+4]
    mov ecx, [ebx+8]
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

; esi = address -> eax = the end of the caller's region that holds it,
; or CF. Keeps the other registers.
ua_region:
    push ebx
    mov ebx, [proc_cur]
    mov ebx, [ebx+PCB_AS]
    test ebx, ebx
    jz .no
    mov eax, PROG_BASE+PROG_MAX
    cmp esi, PROG_BASE
    jb .no
    cmp esi, eax
    jb .yes
    mov eax, [ebx+AS_BRK]
    cmp esi, HEAP_BASE
    jb .no
    cmp esi, eax
    jb .yes
    mov eax, USTACK_BASE+PROC_MAX*USTACK_SIZE
    cmp esi, USTACK_BASE
    jb .no
    cmp esi, eax
    jb .yes
.no:
    pop ebx
    stc
    ret
.yes:
    pop ebx
    clc
    ret

; esi = address, ecx = bytes -> CF unless [esi, esi+ecx) is the caller's
ua_range:
    push eax
    push edx
    call ua_region
    jc .r
    mov edx, esi
    add edx, ecx
    jc .bad                 ; wraps around
    cmp edx, eax
    ja .bad
    push esi                ; every page of it must be safe to touch
    and esi, -PAGE_SIZE
.pg:
    call ua_page_ok
    jc .badpg
    add esi, PAGE_SIZE
    cmp esi, edx
    jb .pg
    pop esi
    clc
    jmp .r
.badpg:
    pop esi
.bad:
    stc
.r:
    pop edx
    pop eax
    ret

; esi = an address in one of the caller's regions -> CF if the kernel
; must not touch its page: a ring-3 stack page that is not mapped and is
; not in the calling thread's own window above its guard page (there a
; kernel access just grows the stack, as a ring-3 one would). The
; program area and the heap up to the break are always mapped. Without
; this a string or buffer on another thread's untouched stack page, or
; on a guard page, would fault in the kernel and end the caller instead
; of failing the call. Keeps every register.
ua_page_ok:
    cmp esi, USTACK_BASE
    jb .ok
    pushad
    mov edi, [proc_cur]
    mov ebx, [edi+PCB_AS]
    mov ebx, [ebx+AS_PD]
    mov eax, [ebx+USTACK_PDE*4]
    test eax, eax
    jz .own
    and eax, -PAGE_SIZE
    mov edx, esi
    shr edx, 12
    and edx, 1023
    test dword [eax+edx*4], PG_P
    jnz .yes                ; mapped
.own:
    call vm_ustack_top      ; eax = top of the caller's own window
    cmp esi, eax
    jae .no
    sub eax, USTACK_SIZE-PAGE_SIZE ; above its guard page
    cmp esi, eax
    jb .no
.yes:
    popad
.ok:
    clc
    ret
.no:
    popad
    stc
    ret

; esi = string -> CF unless it starts and ends (zero byte) in one of the
; caller's regions
ua_str:
    push eax
    push esi
    call ua_region
    jc .r
    call ua_page_ok
    jc .r
.s:
    cmp esi, eax
    jae .bad
    test esi, PAGE_SIZE-1   ; each new page must be safe to touch too
    jnz .rd
    call ua_page_ok
    jc .r
.rd:
    cmp byte [esi], 0
    je .ok
    inc esi
    jmp .s
.ok:
    clc
    jmp .r
.bad:
    stc
.r:
    pop esi
    pop eax
    ret

syscall_table:
    dd sys_putc
    dd sys_puts
    dd sys_getc
    dd sys_yield
    dd sys_spawn
    dd sys_exit
    dd sys_wait
    dd sys_getpid
    dd sys_bread
    dd sys_bwrite
    dd sys_open
    dd sys_read
    dd sys_write
    dd sys_close
    dd sys_create
    dd sys_delete
    dd sys_rename
    dd sys_exec
    dd sys_readdir
    dd sys_palloc
    dd sys_pfree
    dd sys_sbrk
    dd sys_devfind
    dd sys_devread
    dd sys_devwrite
    dd fs_seek
    dd fs_error_text
    dd sys_send
    dd sys_recv
    dd sys_keyevents
    dd sys_netsendto
    dd sys_netrecvfrom
    dd sys_setprio
    dd sys_devreg
    dd sys_devunreg
    dd sys_gui
    dd sys_settls
    dd sys_winopen, sys_winclose, sys_winmove, sys_wintitle   ; 2.2-progwin
    dd sys_windraw, sys_winflush, sys_winevent, sys_wininfo
%if $-syscall_table != SYS_COUNT*4
%error syscall_table and SYS_COUNT disagree
%endif

; ---------- handlers: args in ebx/ecx/edx, result in eax ----------
sys_putc:
    mov al, bl
    call putc
    xor eax, eax
    ret

sys_puts:                   ; through the console device (0.7.1)
    mov esi, ebx
    call strlen
    mov ecx, eax
    mov ebx, dev_con
    jmp dev_write

; Waits for a key press and returns its ASCII code.
; Enter -> 10, Backspace -> 8, Esc -> 27; releases and unmapped keys are skipped.
sys_getc:
    cmp byte [in_on], 0
    jne in_getc                 ; input redirected (shell.asm): -1 at the end
    push eax                    ; one byte from the keyboard device (0.7.1)
    mov edi, esp
    mov ecx, 1
    mov ebx, dev_kbd
    call dev_read
    pop eax
    movzx eax, al
    ret

; Lets the next READY process run; if there is none, sleeps until the
; next interrupt.
sys_yield:
    call proc_idle
    xor eax, eax
    ret

sys_spawn:
    jmp proc_spawn

sys_exit:
    jmp proc_exit

sys_wait:
    jmp proc_wait

sys_getpid:
    mov eax, [proc_cur]
    mov eax, [eax+PCB_PID]
    ret

sys_setprio:
    jmp proc_setprio

; ebx = ASCIIZ name (up to 7 characters): registers a present null
; character device under that name (1.9.12). eax = 0, or -1.
sys_devreg:
    jmp dev_reg_null

; ebx = ASCIIZ name of a device SYS_DEVREG registered: removes it and
; frees its slot (2.0.2). eax = 0, or -1 (no such run-time device).
sys_devunreg:
    jmp dev_unreg_null

; Raw sector access. Writes are limited to the data disk (drive 1) so a
; program cannot overwrite the boot image.
; Both go through the hd0/hd1 block devices (0.7.2).
sys_bread:
    mov edi, ecx
    mov ecx, ebx
    xor ebx, ebx                ; drive numbers other than 0/1: no device
    cmp edx, 1
    ja .dev
    mov ebx, [ata_devs+edx*4]
.dev:
    call dev_bread
    jmp sys_cf_result

sys_bwrite:
    mov esi, ecx
    mov ecx, ebx
    mov ebx, dev_hd1
    call dev_bwrite
    ; fall through
sys_cf_result:                  ; CF -> eax = -1, else 0
    mov eax, 0
    jnc .ok
    dec eax
.ok:
    ret

; file system (0.2.2): thin register shuffles onto fs.asm
sys_open:
    mov esi, ebx
    jmp fs_open

sys_read:
    mov edi, ecx
    mov ecx, edx
    jmp fs_read

sys_write:
    mov esi, ecx
    mov ecx, edx
    jmp fs_write

sys_close:
    jmp fs_close

sys_create:
    mov esi, ebx
    jmp fs_create

sys_delete:
    mov esi, ebx
    jmp fs_delete

sys_rename:
    mov esi, ebx
    mov edi, ecx
    jmp fs_rename

; Directory listing, one entry per call: copies the 16-byte name and the
; size (dword) of the next entry of the current directory at or after
; the cursor into the buffer and returns the cursor for the next call.
; A subdirectory's size reads as -1 (0.8.0).
sys_readdir:
    mov eax, -1
    cmp byte [fs_mounted], 0
    je .r
.l:
    xor eax, eax
    cmp ebx, FS_MAXFILES
    jae .r
    mov esi, ebx
    shl esi, 5                  ; * FS_DIRENT
    add esi, FS_DIR
    inc ebx
    cmp byte [esi], 0
    je .l
    mov dl, [fs_cwd]
    cmp [esi+DE_PARENT], dl
    jne .l
    mov edi, ecx
    mov edx, [esi+DE_SIZE]
    cmp byte [esi+DE_KIND], DK_DIR
    jne .copy
    mov edx, -1
.copy:
    push ecx
    mov ecx, FS_NAMELEN/4
    rep movsd
    pop ecx
    mov [edi], edx
    mov eax, ebx
.r:
    ret

; ---------- shell commands exercising the gate ----------
; systest: calls each non-blocking syscall and checks results and
; register preservation. Prints PASS or FAIL.
cmd_systest_run:
    mov dword [st_fail], 0
    mov esi, 0x5A5A1234     ; sentinels that must survive every call
    mov edi, 0xA5A54321

    mov eax, SYS_PUTS
    mov ebx, st_puts_msg
    int SYSCALL_VEC
    cmp eax, st_puts_len
    call st_check

    mov eax, SYS_PUTC
    mov ebx, 'o'
    int SYSCALL_VEC
    test eax, eax
    call st_check
    mov eax, SYS_PUTC
    mov ebx, 'k'
    int SYSCALL_VEC
    mov eax, SYS_PUTC
    mov ebx, 10
    int SYSCALL_VEC

    mov eax, SYS_YIELD
    int SYSCALL_VEC
    test eax, eax
    call st_check

    mov eax, SYS_GETPID     ; the shell is pid 0
    int SYSCALL_VEC
    test eax, eax
    call st_check

    test dword [dev_hd0+DEV_FLAGS], DEVF_UP
    jz .nohd0               ; booted from a floppy: no hard disk 0 (0.9.3)
    mov eax, SYS_BREAD      ; boot sector of drive 0 ends in 0xAA55
    xor ebx, ebx
    mov ecx, KSCRATCH+0x600
    xor edx, edx
    int SYSCALL_VEC
    test eax, eax
    call st_check
    cmp word [KSCRATCH+0x600+510], 0xAA55
    call st_check
.nohd0:

    mov eax, SYS_BWRITE     ; past the end of any disk -> -1
    mov ebx, 0x0FFFFFFF
    mov ecx, KSCRATCH+0x600
    int SYSCALL_VEC
    cmp eax, -1
    call st_check

    cmp byte [fs_mounted], 0
    je .nofs
    mov eax, SYS_CREATE     ; file round trip through the syscalls
    mov ebx, st_file
    int SYSCALL_VEC
    test eax, eax
    call st_check
    mov eax, SYS_OPEN
    mov ebx, st_file
    mov ecx, O_APPEND
    int SYSCALL_VEC
    mov ebx, eax
    mov eax, SYS_WRITE
    mov ecx, st_puts_msg
    mov edx, 7
    int SYSCALL_VEC
    cmp eax, 7
    call st_check
    mov eax, SYS_CLOSE
    int SYSCALL_VEC
    mov eax, SYS_OPEN
    mov ebx, st_file
    xor ecx, ecx
    int SYSCALL_VEC
    mov ebx, eax
    mov eax, SYS_READ
    mov ecx, KSCRATCH+0x600
    mov edx, 100
    int SYSCALL_VEC
    cmp eax, 7
    call st_check
    cmp dword [KSCRATCH+0x600], 'sysc'
    call st_check
    mov eax, SYS_CLOSE
    int SYSCALL_VEC
    mov eax, SYS_DELETE
    mov ebx, st_file
    int SYSCALL_VEC
    test eax, eax
    call st_check
    mov eax, SYS_OPEN       ; gone now, and no O_CREATE -> -1
    mov ebx, st_file
    xor ecx, ecx
    int SYSCALL_VEC
    cmp eax, -1
    call st_check
.nofs:

    mov eax, SYS_COUNT      ; first unused number
    int SYSCALL_VEC
    cmp eax, SYS_ENOSYS
    call st_check

    cmp esi, 0x5A5A1234
    call st_check
    cmp edi, 0xA5A54321
    call st_check

    mov esi, [lstr+LS_SYSTEST_PASS*4]
    cmp dword [st_fail], 0
    je .out
    mov esi, [lstr+LS_SYSTEST_FAIL*4]
.out:
    jmp lputs_nl

st_check:                   ; counts a failure unless ZF is set
    je .ok
    inc dword [st_fail]
.ok:
    ret

; keys: echoes typed characters through getc/putc until Enter.
cmd_keys_run:
    mov eax, SYS_PUTS
    mov ebx, [lstr+LS_KEYS*4]
    int SYSCALL_VEC
    mov eax, SYS_PUTC
    mov ebx, 10
    int SYSCALL_VEC
.loop:
    mov eax, SYS_GETC
    int SYSCALL_VEC
    cmp eax, 10
    je .done
    mov ebx, eax
    mov eax, SYS_PUTC
    int SYSCALL_VEC
    jmp .loop
.done:
    mov eax, SYS_PUTC
    mov ebx, 10
    int SYSCALL_VEC
    ret

st_puts_msg db 'syscall puts: ok', 10, 0
st_puts_len equ $ - st_puts_msg - 1
st_file db 'systest.tmp', 0
st_fail dd 0
