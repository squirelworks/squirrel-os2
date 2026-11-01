; Squirrel-OS/2 — in-memory FS + apps
; Commands: ls, cat <name>, run <name>
; Editors: edit (normal), vedit (verbose) — basic buffer + insert
; Syscalls (0.1.1): int 0x80 gate, see syscall.asm; test with systest / keys
; Original code.
BITS 16
ORG 0x8000

; Memory map (see documentation/kernel/memory-map.md)
KSCRATCH equ 0x20000            ; 64 KB kernel scratch (driver/FS buffers)
stage2:
    cli
    xor ax, ax                  ; the boot sector may leave ES elsewhere
    mov ds, ax
    mov es, ax
    ; the CPU must have CPUID, an FPU and 4 MB pages (PSE): a Pentium or
    ; later (0.9.3). Say so instead of crashing later.
    pushfd
    pop eax
    mov ecx, eax
    xor eax, 1 << 21            ; ID flag: can it be changed?
    push eax
    popfd
    pushfd
    pop eax
    push ecx
    popfd
    xor eax, ecx
    jz .oldcpu
    mov eax, 1
    cpuid
    and edx, (1 << 0)|(1 << 3)  ; FPU, PSE
    cmp edx, (1 << 0)|(1 << 3)
    je .cpuok
.oldcpu:
    mov si, msg_oldcpu
.say:
    lodsb
    test al, al
    jz .stop
    mov ah, 0x0E
    xor bx, bx
    int 0x10
    jmp .say
.stop:
    hlt
    jmp .stop
.cpuok:
    ; A20 on (fast gate, port 0x92) so memory above 1 MB is reachable
    in al, 0x92
    or al, 2
    and al, 0xFE
    out 0x92, al
    ; BIOS memory map (int 0x15, E820) into E820_BUF for mm_init
    xor ebx, ebx
    mov di, E820_BUF
.e820:
    mov eax, 0xE820
    mov edx, 0x534D4150         ; 'SMAP'
    mov ecx, 24
    mov dword [di+20], 1
    int 0x15
    jc .e820done
    cmp eax, 0x534D4150
    jne .e820done
    add di, 24
    inc word [e820_count]
    test ebx, ebx
    jz .e820done
    cmp word [e820_count], E820_MAX
    jb .e820
.e820done:
    cli
    lgdt [gdt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:pm

; The GDT stays in the first 32 KB: real mode reaches it with a 16-bit offset.
align 8
gdt:
    dq 0
    dw 0xFFFF,0,0x9A00,0x00CF
    dw 0xFFFF,0,0x9200,0x00CF
gdt_tss_main:                   ; 0x18: the TSS of everything that normally runs
    dw TSS_SIZE-1,0,0x8900,0    ; (base filled in by tss_init, KB-17)
gdt_tss_df:                     ; 0x20: the double-fault task
    dw TSS_SIZE-1,0,0x8900,0
gdt_desc:
    dw $-gdt-1
    dd gdt
e820_count dw 0                 ; written in real mode, so also below 32 KB
msg_oldcpu db 'Squirrel-OS/2 needs a Pentium-class CPU (CPUID, FPU, 4 MB pages).', 13, 10, 0

BITS 32
pm:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, SHELL_STACK

    ; IDT (timer + keyboard)
    mov edi, idt
    mov ecx, 256
.fill:
    mov eax, default_isr
    call set_gate
    add edi, 8
    loop .fill
    ; CPU exceptions 0..31 report and halt instead of looping
    mov edi, idt
    mov esi, exc_stubs
    mov ecx, 32
.exc:
    mov eax, esi
    call set_gate
    add edi, 8
    add esi, EXC_STUB_SIZE
    loop .exc
    mov edi, idt+0x20*8
    mov eax, timer_isr
    call set_gate
    mov edi, idt+0x21*8
    mov eax, kbd_isr
    call set_gate
    call syscall_init
    lidt [idt_desc]
    call fpu_init
    call proc_init
    call mm_init
    call vm_init
    call tss_init               ; double faults get their own stack (KB-17)
    call ata_init
    call mouse_init             ; polled PS/2 mouse (1.9.10)
    call dev_init

    ; PIC + PIT
    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 4
    out 0x21, al
    mov al, 2
    out 0xA1, al
    mov al, 1
    out 0x21, al
    out 0xA1, al
    mov al, 0xFC
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al
    mov al, 0x36
    out 0x43, al
    mov ax, 11932
    out 0x40, al
    mov al, ah
    out 0x40, al

    xor eax, eax                ; English until "lang" says otherwise
    call lang_select
    call cls
    call show_banner
    cmp dword [0x8000+KERNEL_SIZE-4], KERNEL_SIG
    je .whole
    mov esi, msg_partial
    call puts
.whole:
    call fs_mount_boot
    call ins_mount_system       ; no data disk: an installed system's partition (I.4)
    call hist_load
    mov byte [shell_up], 1      ; from here a crash can restart the shell
    sti                         ; autoexec.bat may run apps that need keys
    call bat_autoexec
    call sh_prompt
    sti

.cmdloop:
    ; keyboard IRQ only queues scancodes; they are handled here, outside
    ; interrupt context, so commands may block in syscalls such as getc
    cli
    call kbd_dequeue
    jnc .key
    sti
    call proc_idle
    jmp .cmdloop
.key:
    sti
    call kbd_dispatch
    jmp .cmdloop

; ---------- file system ----------
; Flat table: name (8 bytes), data ptr, length
; Built-in (ROM) files, used when no data disk is mounted and to seed
; a freshly formatted one.
rom_list:
    mov esi, [lstr+LS_FILES*4]
    call lputs_nl
    mov ecx, [file_count]
    mov ebx, file_table
.l:
    mov esi, ebx
    call puts
    mov al, 10
    call putc
    add ebx, 16
    loop .l
    ret

rom_cat:                      ; esi = name
    call rom_find
    test eax, eax
    jz .nf
    mov esi, [eax+8]          ; data ptr
    call puts
    ret
.nf:
    mov esi, [lstr+LS_NOTFOUND*4]
    jmp lputs_nl

rom_find:                     ; esi = name, returns eax = entry or 0
    push ecx
    push ebx
    mov ecx, [file_count]
    mov ebx, file_table
.s:
    mov edi, ebx
    call streq
    je .found
    add ebx, 16
    loop .s
    xor eax, eax
    jmp .out
.found:
    mov eax, ebx
.out:
    pop ebx
    pop ecx
    ret

; ---------- apps ----------
run_topo:
    mov esi, topo_banner
    call puts
    mov esi, topo_stub
    call puts
    ret

; itoa: eax = number, writes to num_buf (null terminated)
itoa:                         ; signed
    push ebx
    push ecx
    push edx
    mov edi, num_buf
    mov ecx, 0
    test eax, eax
    jns .nonneg
    mov byte [edi], '-'
    inc edi
    neg eax
.nonneg:
    test eax, eax
    jnz .pos
    mov byte [edi], '0'
    mov byte [edi+1], 0
    jmp .idone
.pos:
    ; reverse digits
    mov ebx, 10
.il:
    xor edx, edx
    div ebx
    add dl, '0'
    push edx
    inc ecx
    test eax, eax
    jnz .il
.ip:
    pop edx
    mov [edi], dl
    inc edi
    loop .ip
    mov byte [edi], 0
.idone:
    pop edx
    pop ecx
    pop ebx
    ret

; edi = ASCIIZ -> run_arg (truncated to a path's length)
set_run_arg:
    push ecx
    push esi
    push edi
    mov esi, edi
    mov edi, run_arg
    mov ecx, FS_PATHMAX-1
.c:
    lodsb
    test al, al
    jz .z
    stosb
    loop .c
.z:
    mov byte [edi], 0
    pop edi
    pop esi
    pop ecx
    ret

; ---------- command processor ----------
; Runs one simple command (esi = text, no pipes or redirections); the
; pipeline driver do_command in shell.asm calls it for each stage.
run_simple:
    cmp byte [esi], 0
    je .empty
    ; ls
    mov edi, cmd_ls
    call streq
    je .ls
    mov edi, cmd_cd
    call streq
    je .cd
    mov edi, cmd_pwd
    call streq
    je .pwd
    mov edi, cmd_lang
    call streq
    je .lang
    ; cat
    mov edi, cmd_cat
    call streq_prefix
    je .cat
    ; systest
    mov edi, cmd_systest
    call streq
    je .systest
    ; trap (diagnostic: raises #UD to show the exception report)
    mov edi, cmd_trap
    call streq
    jne .notrap
    ud2
.notrap:
    ; overflow (diagnostic: the shell runs off its own stack, KB-17)
    mov edi, cmd_overflow
    call streq
    jne .nooverflow
.recurse:
    call .recurse
.nooverflow:
    ; disk
    mov edi, cmd_disk
    call streq
    je .disk
    ; install, install part / format / ls (installer I.1, I.2)
    mov edi, cmd_install
    call streq
    je .install
    mov edi, cmd_install_part
    call streq
    je .install_part
    mov edi, cmd_install_format
    call streq
    je .install_format
    mov edi, cmd_install_ls
    call streq
    je .install_ls
    mov edi, cmd_install_copy
    call streq
    je .install_copy
    mov edi, cmd_install_boot
    call streq
    je .install_boot
    ; blktest
    mov edi, cmd_blktest
    call streq
    je .blktest
    ; gfxtest (1.3)
    mov edi, cmd_gfxtest
    call streq
    je .gfxtest
    mov edi, cmd_gfxprim
    call streq
    je .gfxprim
    mov edi, cmd_gfxtext
    call streq
    je .gfxtext
    mov edi, cmd_desktop
    call streq
    je .desktop
    mov edi, cmd_listtest
    call streq
    je .listtest
    mov edi, cmd_drawpx         ; 1.6.5
    call streq
    je .drawpx
    mov edi, cmd_objtest        ; 1.7.0
    call streq
    je .objtest
    mov edi, cmd_nettest        ; 1.9.3
    call streq
    je .nettest
    mov edi, cmd_mousetest      ; 1.9.10
    call streq
    je .mousetest
    mov edi, cmd_ifconfig       ; 1.9.11 bare
    call streq
    je .ifconfig
    mov edi, cmd_objs           ; 1.7.2
    call streq
    je .objs
    mov edi, cmd_fieldtest
    call streq
    je .fieldtest
    mov edi, cmd_buttontest
    call streq
    je .buttontest
    mov edi, cmd_labeltest
    call streq
    je .labeltest
    mov edi, cmd_winfocus
    call streq
    je .winfocus
    mov edi, cmd_winmove
    call streq
    je .winmove
    mov edi, cmd_wintest
    call streq
    je .wintest
    ; format
    mov edi, cmd_format
    call streq
    je .format
    ; fstest
    mov edi, cmd_fstest
    call streq
    je .fstest
    ; ps
    mov edi, cmd_ps
    call streq
    je .ps
    mov edi, cmd_mem
    call streq
    je .mem
    mov edi, cmd_memtest
    call streq
    je .memtest
    mov edi, cmd_devices
    call streq
    je .devices
    ; proctest
    mov edi, cmd_proctest
    call streq
    je .proctest
    ; keys
    mov edi, cmd_keys
    call streq
    je .keys
    ; run
    mov edi, cmd_run
    call streq_prefix
    je .run
    ; commands taking arguments: "<word> <args>"
    mov ebx, arg_cmds
.argc:
    mov edi, [ebx]
    test edi, edi
    jz .unknown
    call streq_prefix
    je .arggo
    add ebx, 8
    jmp .argc
.arggo:
    push esi
    mov esi, edi
    call strlen
    pop esi
    add esi, eax
    call [ebx+4]
    jmp .empty
.unknown:
    call sh_usage               ; a command word without its arguments?
    jnc .empty
    mov esi, [lstr+LS_UNKNOWN*4]
    call lputs_nl
    jmp .empty
.format:
    call cmd_format_run
    jmp .empty
.fstest:
    call cmd_fstest_run
    jmp .empty
.ls:
    call fs_list
    jmp .empty
.cd:
    add esi, 2                  ; "cd" alone: back to the root
    call cmd_cd_run
    jmp .empty
.pwd:
    call cmd_pwd_run
    jmp .empty
.lang:
    add esi, 4
    call cmd_lang_run
    jmp .empty
.systest:
    call cmd_systest_run
    jmp .empty
.keys:
    call cmd_keys_run
    jmp .empty
.cat:
    ; skip "cat "
    add esi, 4
    call fs_cat
    jmp .empty
.run:
    add esi, 4
    call next_word              ; esi = app name, edi = argument (may be empty)
    mov [run_rest], edi
    call set_run_arg
    mov ebx, run_table
.rfind:
    mov edi, [ebx]
    test edi, edi
    jz .rnone
    call streq
    je .rgo
    add ebx, 8
    jmp .rfind
.rnone:
    ; a .bat file is queued as a batch script (0.5.2)
    call strlen
    cmp eax, 4
    jbe .notbat
    cmp dword [esi+eax-4], '.bat'
    jne .notbat
    call bat_start
    jmp .empty
.notbat:
    ; not built in: load it from the data disk (0.4.0 program loader)
    mov ebx, esi
    mov ecx, [run_rest]
    mov eax, SYS_EXEC
    int SYSCALL_VEC
    test eax, eax
    jns .rwait
    call ld_perror
    jmp .empty
.rgo:
    ; the app runs as its own process; the shell waits for it
    mov ecx, [ebx+4]
    mov esi, [ebx]              ; its name, for ps and crash reports
    mov ebx, app_host
    mov eax, SYS_SPAWN
    int SYSCALL_VEC
    cmp eax, -1
    je .rfull
    push eax
    mov ebx, eax
    call proc_find
    call proc_set_name
    pop eax
.rwait:
    mov ebx, eax
    mov eax, SYS_WAIT
    int SYSCALL_VEC
    jmp .empty
.rfull:
    mov esi, proc_full
    call puts
    jmp .empty
.ps:
    call cmd_ps_run
    jmp .empty
.mem:
    call cmd_mem_run
    jmp .empty
.devices:
    call cmd_devices_run
    jmp .empty
.memtest:
    call cmd_memtest_run
    jmp .empty
.disk:
    call cmd_disk_run
    jmp .empty
.install:
    call cmd_install_run
    jmp .empty
.install_part:
    call cmd_install_part_run
    jmp .empty
.install_format:
    call cmd_install_format_run
    jmp .empty
.install_ls:
    call cmd_install_ls_run
    jmp .empty
.install_copy:
    call cmd_install_copy_run
    jmp .empty
.install_boot:
    call cmd_install_boot_run
    jmp .empty
.blktest:
    call cmd_blktest_run
    jmp .empty
.gfxtest:
    call cmd_gfxtest_run
    jmp .empty
.gfxprim:
    call cmd_gfxprim_run
    jmp .empty
.gfxtext:
    call cmd_gfxtext_run
    jmp .empty
.desktop:
    call cmd_desktop_run
    jmp .empty
.drawpx:
    call cmd_drawpx_run
    jmp .empty
.objtest:
    call cmd_objtest_run
    jmp .empty
.nettest:
    call cmd_nettest_run
    jmp .empty
.mousetest:
    call cmd_mousetest_run
    jmp .empty
.ifconfig:
    call cmd_ifconfig_show
    jmp .empty
.objs:
    call cmd_objs_run
    jmp .empty
.listtest:
    call cmd_listtest_run
    jmp .empty
.fieldtest:
    call cmd_fieldtest_run
    jmp .empty
.buttontest:
    call cmd_buttontest_run
    jmp .empty
.labeltest:
    call cmd_labeltest_run
    jmp .empty
.winfocus:
    call cmd_winfocus_run
    jmp .empty
.winmove:
    call cmd_winmove_run
    jmp .empty
.wintest:
    call cmd_wintest_run
    jmp .empty
.proctest:
    call cmd_proctest_run
    jmp .empty
.empty:
    ret

streq:                        ; esi, edi
    push esi
    push edi
.l:
    lodsb
    mov ah, [edi]
    inc edi
    cmp al, ah
    jne .ne
    or al, al
    jnz .l
    pop edi
    pop esi
    xor eax, eax
    ret
.ne:
    pop edi
    pop esi
    or eax, 1
    ret

streq_prefix:
    push esi
    push edi
.p:
    mov al, [edi]
    or al, al
    jz .yes
    cmp al, [esi]
    jne .no
    inc esi
    inc edi
    jmp .p
.yes:
    pop edi
    pop esi
    xor eax, eax
    ret
.no:
    pop edi
    pop esi
    or eax, 1
    ret

; ---------- console ----------
set_gate:
    mov [edi], ax
    mov word [edi+2], 0x08
    mov byte [edi+4], 0
    mov byte [edi+5], 0x8E
    shr eax, 16
    mov [edi+6], ax
    ret

cls:
    cmp byte [cap_on], 0        ; keep the screen while output is redirected
    jne .r
    mov edi, [txt_base]
    mov ecx, 80*25
    mov ax, 0x0720
    rep stosw
    mov dword [cur], 0
    mov byte [txt_dirty], 1
    call cursor_sync
.r:
    ret

puts:
    lodsb
    or al, al
    jz .d
    call putc
    jmp puts
.d:
    ret

putc:                         ; al = char; preserves all registers
    cmp byte [cap_on], 0
    jne cap_putc                ; output redirected (shell.asm)
    push eax
    push ebx
    push edx
    cmp al, 10
    je .nl
    cmp al, 8
    je .bs
    mov ebx, [cur]
    mov ah, 0x07
    mov edx, [txt_base]
    mov [edx+ebx*2], ax
    inc dword [cur]
    jmp .wrap
.nl:
    mov eax, [cur]
    xor edx, edx
    mov ebx, 80
    div ebx
    inc eax
    mul ebx
    mov [cur], eax
    jmp .wrap
.bs:
    mov ebx, [cur]
    test ebx, ebx
    jz .r
    dec ebx
    mov [cur], ebx
    mov edx, [txt_base]
    mov word [edx+ebx*2], 0x0720
    jmp .r
.wrap:
    cmp dword [cur], 80*25
    jb .r
    call scroll_up
.r:
    mov byte [txt_dirty], 1
    call cursor_sync
    pop edx
    pop ebx
    pop eax
    ret

; Moves the text screen up one row and blanks the last row.
scroll_up:
    inc dword [scroll_count]
    push ecx
    push esi
    push edi
    mov edi, [txt_base]
    lea esi, [edi+160]
    mov ecx, 80*24/2
    rep movsd
    mov eax, 0x07200720
    mov ecx, 80/2
    rep stosd
    sub dword [cur], 80
    pop edi
    pop esi
    pop ecx
    ret

; Puts the blinking hardware cursor at [cur].
cursor_sync:
    push eax
    push edx
    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al
    inc dx
    mov al, [cur]
    out dx, al
    dec dx
    mov al, 0x0E
    out dx, al
    inc dx
    mov al, [cur+1]
    out dx, al
    pop edx
    pop eax
    ret

; ---------- ISRs ----------
timer_isr:
    push eax
    inc dword [ticks]
    mov al, 0x20
    out 0x20, al
    ; preemption (1.1): once the slice is used up, the first tick that
    ; lands in a loaded program's code switches to the next READY
    ; process. Kernel code is never interrupted this way (it is not
    ; reentrant), so the check waits for the next tick instead.
    dec dword [sched_left]
    jg .out
    mov eax, [esp+4]            ; interrupted EIP
    cmp eax, PROG_BASE
    jb .out
    cmp eax, PROG_BASE+PROG_MAX
    jae .out
    call proc_preempt
.out:
    pop eax
    iretd

; IRQ1: queue the raw scancode (dropped if the ring is full), and post
; a key event if a process asked for them (msg.asm)
kbd_isr:
    push eax
    push ebx
    push ecx
    in al, 0x60
    mov ebx, [kbd_head]
    lea ecx, [ebx+1]
    and ecx, KBD_RING_SIZE-1
    cmp ecx, [kbd_tail]
    je .full
    mov [kbd_ring+ebx], al
    mov [kbd_head], ecx
.full:
    pushad
    call key_event              ; and a key event for SYS_KEYEVENTS (1.2.1)
    popad
    mov al, 0x20
    out 0x20, al
    pop ecx
    pop ebx
    pop eax
    iretd

; Pops one scancode into al; CF set if the ring is empty. Clobbers ebx.
; Call with interrupts disabled.
kbd_dequeue:
    mov ebx, [kbd_tail]
    cmp ebx, [kbd_head]
    je .empty
    mov al, [kbd_ring+ebx]
    inc ebx
    and ebx, KBD_RING_SIZE-1
    mov [kbd_tail], ebx
    clc
    ret
.empty:
    stc
    ret

; Tracks Shift and Ctrl. Returns ZF set if al was a modifier make/break code
; (the caller should then ignore it).
kbd_shift_track:
    cmp al, 0x1D
    je .cdown
    cmp al, 0x9D
    je .cup
    cmp al, 0x2A
    je .down
    cmp al, 0x36
    je .down
    cmp al, 0xAA
    je .up
    cmp al, 0xB6
    je .up
    ret                       ; ZF clear: not a shift key
.down:
    mov byte [kbd_shift], 1
    cmp al, al
    ret
.up:
    mov byte [kbd_shift], 0
    cmp al, al
    ret
.cdown:
    mov byte [kbd_ctrl], 1
    ret                       ; ZF set by the compare
.cup:
    mov byte [kbd_ctrl], 0
    ret

; al = make code -> al = ASCII (0 if unmapped), honouring Shift.
kbd_ascii:
    push ebx
    movzx ebx, al
    and ebx, 0x7F
    cmp byte [kbd_shift], 0
    jne .sh
    mov al, [scancode_map+ebx]
    pop ebx
    ret
.sh:
    mov al, [scancode_map_shift+ebx]
    pop ebx
    ret

; Handles one scancode (al) for the shell or the active app.
kbd_dispatch:
    pushad
    call kbd_shift_track
    je .e
    cmp al, 0x80
    jae .e
    call sh_key                 ; line editing and history (lineedit.asm)
.e:
    popad
    ret

default_isr:
    iretd

; ---------- data ----------
banner db 'Squirrel-OS/2'          ; (the "help" file: the English banner)
banner_rest db ' 1.9.11', 10  ; OS version: here only (see releases/PROCESS.md)
       db 'Commands: ls | cat <f> | run <app|file> | put <f> <text> | mk <f> | rm <f>', 10
       db '          mv <f> <new> | mkdir <d> | cd <d> | pwd | echo | batch <f> | format', 10
       db '          ps | disk | mem | devices | lang <en|la|tlh> | desktop | install', 10
       db '          objcat', 10
       db 'Tests: systest | proctest | blktest | fstest | memtest | keys', 10
       db '       gfxtest | gfxprim | gfxtext | wintest | winmove | winfocus | nettest', 10
       db '       labeltest | buttontest | fieldtest | listtest | drawpx | objtest | objs', 10
       db 'Apps: files, calc, sci, graph, matrix, diff, edit, vedit, draw   (planned: topo)', 10, 0
msg_partial db 'Warning: kernel image only partly loaded', 10, 0
cmd_ls db 'ls', 0
cmd_cat db 'cat ', 0
cmd_run db 'run ', 0
cmd_systest db 'systest', 0
cmd_keys db 'keys', 0
cmd_trap db 'trap', 0
cmd_overflow db 'overflow', 0

; argument for the next app started with run (e.g. run edit notes)
run_arg times 64 db 0           ; FS_PATHMAX
run_rest dd 0                   ; whole argument text, for loaded programs
cmd_ps db 'ps', 0
cmd_mem db 'mem', 0
cmd_memtest db 'memtest', 0
cmd_devices db 'devices', 0
cmd_format db 'format', 0
cmd_fstest db 'fstest', 0
cmd_put db 'put ', 0
cmd_mk db 'mk ', 0
cmd_rm db 'rm ', 0
cmd_mv db 'mv ', 0
cmd_ls_arg db 'ls ', 0
cmd_cd_arg db 'cd ', 0
cmd_mkdir db 'mkdir ', 0
cmd_cd db 'cd', 0
cmd_pwd db 'pwd', 0
cmd_lang db 'lang', 0
cmd_lang_arg db 'lang ', 0
cmd_echo db 'echo ', 0
cmd_batch db 'batch ', 0
; esi = command line: a command that needs arguments typed alone
; prints how to use it ("echo" alone prints an empty line) -> CF if not
sh_usage:
    mov ebx, usage_cmds
.l:
    mov edi, [ebx]
    test edi, edi
    jz .no
    call streq
    je .hit
    add ebx, 12
    jmp .l
.hit:
    mov esi, [ebx+4]
    cmp byte [esi], 0
    je .nl                      ; echo: just an empty line
    mov eax, [ebx+8]            ; a hint after the syntax, or -1
    push eax
    push esi
    mov esi, [lstr+LS_USAGE*4]  ; "Usage:" in the current language (1.0.5)
    call puts
    mov al, ' '
    call putc
    pop esi
    call puts
    pop eax
    test eax, eax
    js .nl
    mov esi, [lstr+eax*4]
    push esi
    mov esi, u_gap
    call puts
    pop esi
    call puts
.nl:
    mov al, 10
    call putc
    clc
    ret
.no:
    stc
    ret

usage_cmds:                     ; command, syntax, hint key or -1
    dd u_put, u_put_t, LS_USAGE_PUT, u_mk, u_mk_t, -1, u_rm, u_rm_t, -1
    dd u_mv, u_mv_t, -1, u_mkdir, u_mkdir_t, -1, u_cat, u_cat_t, -1
    dd u_objcat, u_objcat_t, -1
    dd u_arp, u_arp_t, -1
    dd u_ping, u_ping_t, -1
    dd u_fetch, u_fetch_t, -1
    dd u_run, u_run_t, LS_USAGE_RUN, u_batch, u_batch_t, -1, u_echo, u_echo_t, -1, 0
u_put db 'put', 0
u_mk db 'mk', 0
u_rm db 'rm', 0
u_mv db 'mv', 0
u_mkdir db 'mkdir', 0
u_cat db 'cat', 0
u_objcat db 'objcat', 0
u_run db 'run', 0
u_batch db 'batch', 0
u_arp db 'arp', 0
u_ping db 'ping', 0
u_fetch db 'fetch', 0
u_echo db 'echo', 0
u_put_t db 'put <file> <text>', 0
u_mk_t db 'mk <file>', 0
u_rm_t db 'rm <file|dir>', 0
u_mv_t db 'mv <old> <new|dir>', 0
u_mkdir_t db 'mkdir <dir>', 0
u_cat_t db 'cat <file>', 0
u_objcat_t db 'objcat <file>', 0
u_run_t db 'run <app|file> [text]', 0
u_batch_t db 'batch <file>', 0
u_arp_t db 'arp <ip>', 0
u_ping_t db 'ping <ip>', 0
u_fetch_t db 'fetch <ip> <port> <path>', 0
u_echo_t db 0
u_gap db '   ', 0

arg_cmds:
    dd cmd_put, cmd_put_run
    dd cmd_mk, cmd_mk_run
    dd cmd_rm, cmd_rm_run
    dd cmd_mv, cmd_mv_run
    dd cmd_ls_arg, cmd_ls_run
    dd cmd_cd_arg, cmd_cd_run
    dd cmd_mkdir, cmd_mkdir_run
    dd cmd_lang_arg, cmd_lang_run
    dd cmd_echo, cmd_echo_run
    dd cmd_batch, cmd_batch_run
    dd cmd_objcat, cmd_objcat_run
    dd cmd_arp, cmd_arp_run
    dd cmd_ping, cmd_ping_run
    dd cmd_fetch, cmd_fetch_run
    dd cmd_ifconfig_arg, cmd_ifconfig_run
    dd 0, 0
cmd_disk db 'disk', 0
cmd_blktest db 'blktest', 0
cmd_gfxtest db 'gfxtest', 0
cmd_gfxprim db 'gfxprim', 0
cmd_gfxtext db 'gfxtext', 0
cmd_wintest db 'wintest', 0
cmd_winmove db 'winmove', 0
cmd_winfocus db 'winfocus', 0
cmd_labeltest db 'labeltest', 0
cmd_buttontest db 'buttontest', 0
cmd_fieldtest db 'fieldtest', 0
cmd_listtest db 'listtest', 0
cmd_drawpx db 'drawpx', 0
cmd_objtest db 'objtest', 0
cmd_nettest db 'nettest', 0
cmd_mousetest db 'mousetest', 0
cmd_ifconfig db 'ifconfig', 0
cmd_objs db 'objs', 0
cmd_objcat db 'objcat ', 0
cmd_arp db 'arp ', 0
cmd_ping db 'ping ', 0
cmd_fetch db 'fetch ', 0
cmd_ifconfig_arg db 'ifconfig ', 0
cmd_desktop db 'desktop', 0
cmd_proctest db 'proctest', 0
proc_full db 'Too many processes', 10, 0

; run <name>: app start routines, each hosted in its own process
run_table:
    dd name_calc, run_calc
    dd name_sci, run_sci
    dd name_graph, run_graph
    dd name_matrix, run_matrix
    dd name_diff, run_diff
    dd name_topo, run_topo
    dd name_edit, run_edit
    dd name_vedit, run_vedit
    dd name_draw, run_draw
    dd name_files, fb_main
    dd name_install, run_install    ; installer I.5
    dd 0, 0
name_calc db 'calc', 0
name_edit db 'edit', 0
name_vedit db 'vedit', 0
name_draw db 'draw', 0
name_files db 'files', 0
files_desc db 'File browser. Open it with: run files', 10, 0
name_sci db 'sci', 0
name_graph db 'graph', 0
name_matrix db 'matrix', 0
name_diff db 'diff', 0
name_topo db 'topo', 0
name_install db 'install', 0

topo_banner db 'Topology Calculator', 10, 0
topo_stub db 'Scaffolded. Simplicial homology sketches (long-term).', 10, 'See documentation/apps/calculators.md', 10, 0
edit_sample db 'Hello from Squirrel-OS/2', 10, 0
vedit_sample db 'Line 1, col 1, byte 0, char 0x48 ', 39, 'H', 39, 10
             db 'Insert mode, unmodified, size 0/4096', 10, 0
draw_art db '  *  ', 10, ' *** ', 10, '*****', 10, 0

file_count dd 11
file_table:
    db 'calc', 0, 0, 0, 0
    dd calc_help
    dd 70
    db 'sci', 0, 0, 0, 0, 0
    dd sci_help
    dd sci_help_len
    db 'graph', 0, 0, 0
    dd graph_help
    dd graph_help_len
    db 'matrix', 0, 0
    dd mx_help
    dd mx_help_len
    db 'diff', 0, 0, 0, 0
    dd diff_help
    dd diff_help_len
    db 'topo', 0, 0, 0, 0
    dd topo_stub
    dd 70
    db 'edit', 0, 0, 0, 0
    dd edit_sample
    dd 24
    db 'vedit', 0, 0, 0
    dd vedit_sample
    dd 62
    db 'draw', 0, 0, 0, 0
    dd draw_art
    dd 18
    db 'help', 0, 0, 0, 0
    dd banner
    dd 80
    db 'files', 0, 0, 0
    dd files_desc
    dd 0

KBD_RING_SIZE equ 64
kbd_ring times KBD_RING_SIZE db 0
kbd_head dd 0
kbd_tail dd 0
cmdline times 128 db 0         ; SH_LINE (shell.asm)
cmdpos dd 0                     ; cursor position in cmdline
scroll_count dd 0               ; rows scrolled so far (line editor)
cur dd 0
txt_base dd 0xB8000             ; the text screen putc, cls and scroll_up write
                                ; (a window's buffer while the desktop runs a
                                ; text program in it, 1.6.1)
txt_dirty db 0                  ; set by every write there
txt_cols dd 80                  ; columns and rows of it a program can see:
txt_rows dd 25                  ; less in a desktop window (1.6.4)
ticks dd 0
num_buf times 16 db 0

kbd_shift db 0
kbd_ctrl db 0

; Set-1 make codes 0x00..0x7F. Keypad * - + are mapped; other keypad
; keys stay 0 so arrows (0x48/0x4B/0x4D/0x50) remain free for apps.
scancode_map:
    db 0,0,'1','2','3','4','5','6','7','8','9','0','-','=',0,0
    db 'q','w','e','r','t','y','u','i','o','p','[',']',10,0
    db 'a','s','d','f','g','h','j','k','l',';',39,'`',0,'\'
    db 'z','x','c','v','b','n','m',',','.','/',0,'*',0,' '
    times 0x4A-($-scancode_map) db 0
    db '-',0,0,0,'+'
    times 128-($-scancode_map) db 0
scancode_map_shift:
    db 0,0,'!','@','#','$','%','^','&','*','(',')','_','+',0,0
    db 'Q','W','E','R','T','Y','U','I','O','P','{','}',10,0
    db 'A','S','D','F','G','H','J','K','L',':','"','~',0,'|'
    db 'Z','X','C','V','B','N','M','<','>','?',0,'*',0,' '
    times 0x4A-($-scancode_map_shift) db 0
    db '-',0,0,0,'+'
    times 128-($-scancode_map_shift) db 0

; ---------- CPU exceptions ----------
; One fixed-size stub per vector pushes its number and jumps to the
; report in crash.asm (0.8.2).
EXC_STUB_SIZE equ 8
exc_stubs:
%assign v 0
%rep 32
    push dword v
    jmp exc_report
    times exc_stubs+(v+1)*EXC_STUB_SIZE-$ nop
%assign v v+1
%endrep

; eax -> 8 hex digits on the console
puthex:
    push ecx
    push edx
    mov edx, eax
    mov ecx, 8
.h:
    rol edx, 4
    mov al, dl
    and al, 0x0F
    add al, '0'
    cmp al, '9'
    jbe .d
    add al, 'A'-'9'-1
.d:
    call putc
    loop .h
    pop edx
    pop ecx
    ret


%include "syscall.asm"
%include "proc.asm"
%include "msg.asm"
%include "gfx.asm"
%include "ata.asm"
%include "fs.asm"
%include "install.asm"
%include "shell.asm"
%include "lineedit.asm"
%include "batch.asm"
%include "mm.asm"
%include "vm.asm"
%include "dev.asm"
%include "chardev.asm"
%include "lang.asm"
%include "crash.asm"
%include "browser.asm"
%include "calc.asm"
%include "editor.asm"
%include "draw.asm"
%include "drawpx.asm"
%include "loader.asm"
%include "sci.asm"
%include "matrix.asm"
%include "diff.asm"
%include "graph.asm"
%include "wm.asm"
%include "widget.asm"
%include "desktop.asm"
%include "object.asm"
%include "net.asm"
%include "ne2k.asm"
%include "arp.asm"
%include "ip.asm"
%include "udp.asm"
%include "tcp.asm"
%include "mouse.asm"

align 8
idt: times 256 dq 0
idt_desc:
    dw 256*8-1
    dd idt
KERNEL_SIZE equ 98304           ; boot.asm loads 192 sectors (0x8000-0x1FFFF)
KERNEL_SIG equ 0x4B4F3253       ; 'S2OK'
%if $-$$ > KERNEL_SIZE-4
%error kernel image is larger than KERNEL_SIZE
%endif
times KERNEL_SIZE-4-($-$$) db 0
dd KERNEL_SIG                   ; checked at boot: the whole image arrived
