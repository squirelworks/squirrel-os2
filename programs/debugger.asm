; debugger — a debugger for loaded programs (A.4). Original code.
;
;   run debugger <program> [argument]   start it, stopped at its entry
;   run debugger <pid>                  attach to a running program
;   run debugger                        no program yet (run, attach)
;
; Line commands (help lists them): r, s [n], n, c, g, b <where>, bl,
; bd <n>, u [where] [n], x [where] [n], set <reg> <value>, bt, sym [text],
; ps, run, attach, detach, kill, q. <where> is a hex address (0x is
; optional), a symbol, or symbol+hex. Symbols come from <program>.sym
; (tools/mksym.py makes it from NASM's map file) or from an ELF
; program's .symtab. See documentation/apps/debugger.md and
; documentation/kernel/debug.md (SYS_DEBUG).
%include "sqx.inc"
%include "debug.inc"
SQX_HEADER main

%define DIS_SYMBOLS
%include "disasm.inc"

SYS_GUI     equ 35
GUI_KEY     equ 4
GUI_SYSINFO equ 12
BP_MAX      equ 16              ; breakpoints, and one more for "n"
BP_TEMP     equ BP_MAX
SYM_MAX     equ 400
SYM_SIZE    equ 32              ; address, then a 28-byte name
SYM_NAMEMAX equ SYM_SIZE-5
LINE_MAX    equ 72
FILE_MAX    equ 0x10000

main:
    mov esi, [esp+4]
    call skipsp
    cmp byte [esi], 0
    je .prompt
    mov al, [esi]
    sub al, '0'
    cmp al, 9
    ja .exec
    call parse_dec
    jc .exec
    call do_attach_pid
    jmp .prompt
.exec:
    call do_run_args
.prompt:
    call cmd_loop
    call do_quit
    xor eax, eax
    ret

; ---------- the command loop ----------
cmd_loop:
.l: mov esi, s_prompt
    call puts
    call readline
    cmp eax, -1
    je .r
    mov esi, line
    call skipsp
    cmp byte [esi], 0
    je .l
    mov edi, cmds
.find:
    cmp dword [edi], 0
    je .unknown
    push edi
    mov edi, [edi]
    call word_is
    pop edi
    jnc .run
    add edi, 8
    jmp .find
.run:
    call skipsp
    cmp dword [edi+4], 0
    je .r                       ; q
    call [edi+4]
    jmp .l
.unknown:
    mov esi, s_unknown
    call puts
    jmp .l
.r: ret

cmds:
    dd w_help, cmd_help, w_h, cmd_help, w_r, cmd_regs, w_s, cmd_step
    dd w_n, cmd_next, w_c, cmd_cont, w_g, cmd_go, w_b, cmd_break
    dd w_bl, cmd_blist, w_bd, cmd_bdel, w_u, cmd_unasm, w_x, cmd_dump
    dd w_set, cmd_set, w_bt, cmd_bt, w_sym, cmd_sym, w_ps, cmd_ps
    dd w_run, cmd_run, w_attach, cmd_attach, w_detach, cmd_detach
    dd w_kill, cmd_kill, w_q, 0, w_quit, 0
    dd 0

cmd_help:
    mov esi, s_help
    jmp puts

; needs a stopped program: CF (and a message) if there is none
need_stopped:
    cmp dword [pid], 0
    jne .ok
    mov esi, s_noprog
    call puts
    stc
    ret
.ok:
    clc
    ret

; ---------- starting and ending ----------

; esi = "program [argument]"
do_run_args:
    call need_none
    jc .r
    mov edi, progname
    mov ecx, 15
.c: lodsb
    cmp al, ' '
    je .e
    test al, al
    jz .e0
    stosb
    loop .c
.e: call skipsp
    jmp .z
.e0:
    dec esi
.z: mov byte [edi], 0
    mov edi, progarg
    mov ecx, 63
.a: lodsb
    stosb
    test al, al
    jz .ad
    loop .a
    mov byte [edi], 0
.ad:
    mov eax, SYS_DEBUG
    mov ebx, DBG_EXEC
    mov ecx, progname
    mov edx, progarg
    int 0x80
    test eax, eax
    jg .ok
    mov esi, s_noload
    call puts
    neg eax
    call putdec
    call nl
.r: ret
.ok:
    mov [pid], eax
    mov byte [started], 1
    call load_symbols
    call wait_stop
    ret

; CF and a message if a program is already being debugged
need_none:
    cmp dword [pid], 0
    je .ok
    push esi
    mov esi, s_already
    call puts
    pop esi
    stc
    ret
.ok:
    clc
    ret

; eax = pid
do_attach_pid:
    call need_none
    jc .r
    mov ecx, eax
    mov eax, SYS_DEBUG
    mov ebx, DBG_ATTACH
    int 0x80
    test eax, eax
    jz .ok
    mov esi, s_noattach
    jmp puts
.ok:
    mov [pid], ecx
    mov byte [started], 0
    mov byte [progname], 0
    mov dword [nsyms], 0
    mov eax, SYS_DEBUG          ; stop it where it is
    mov ebx, DBG_STOP
    int 0x80
    call wait_stop
.r: ret

cmd_run:
    jmp do_run_args

cmd_attach:
    call parse_dec
    jc .bad
    jmp do_attach_pid
.bad:
    mov esi, s_usage_pid
    jmp puts

cmd_detach:
    call need_stopped
    jc .r
    call bp_remove_all
    mov eax, SYS_DEBUG
    mov ebx, DBG_DETACH
    mov ecx, [pid]
    int 0x80
    mov esi, s_detached
    call puts
    call forget
.r: ret

cmd_kill:
    call need_stopped
    jc .r
    call kill_it
.r: ret

kill_it:
    mov eax, SYS_DEBUG
    mov ebx, DBG_KILL
    mov ecx, [pid]
    int 0x80
    jmp wait_stop               ; reports the end

; q: a program the debugger started is ended, an attached one let go
do_quit:
    cmp dword [pid], 0
    je .r
    cmp byte [started], 0
    jne .kill
    jmp cmd_detach
.kill:
    jmp kill_it
.r: ret

forget:
    mov dword [pid], 0
    mov dword [nsyms], 0
    mov edi, bp_addr
    mov ecx, BP_END-bp_addr
    xor al, al
    rep stosb
    ret

; ---------- running ----------

; Waits until the program stops or ends and says what happened.
; (While it runs and [listen] is set, Esc stops it.)
wait_stop:
    mov byte [stopped_ok], 0
.w: mov eax, SYS_DEBUG
    mov ebx, DBG_WAIT
    mov ecx, [pid]
    movzx edx, byte [listen]
    int 0x80
    cmp eax, DBG_RUNNING
    jne .got
    mov eax, SYS_GUI            ; listening: Esc stops it
    mov ebx, GUI_KEY
    int 0x80
    cmp al, 27
    jne .y
    mov eax, SYS_DEBUG
    mov ebx, DBG_STOP
    mov ecx, [pid]
    int 0x80
.y: mov eax, SYS_YIELD
    int 0x80
    jmp .w
.got:
    cmp eax, DBG_ENDED
    je .ended
    cmp eax, -1
    je .ended
    mov [reason], eax
    call bp_remove_all
    call get_regs
    mov byte [stopped_ok], 1
    mov eax, [reason]
    cmp eax, DBG_R_STEP
    je .here
    cmp eax, DBG_R_BREAK
    je .brk
    cmp eax, DBG_R_ENTRY
    je .entry
    cmp eax, DBG_R_STOP
    je .stop
    ; a CPU exception
    call say_pid
    mov esi, s_exc
    call puts
    mov eax, [reason]
    call putdec
    cmp dword [reason], 14
    jne .exc2
    mov esi, s_cr2
    call puts
    mov eax, [regs+DR_CR2]
    call puthex8
.exc2:
    call nl
    jmp .here
.entry:
    call say_pid
    mov esi, s_entry
    call puts
    jmp .here
.stop:
    call say_pid
    mov esi, s_stopped
    call puts
    jmp .here
.brk:
    mov eax, [regs+DR_EIP]      ; after the INT3: one of ours?
    dec eax
    call bp_find
    jc .int3
    mov [regs+DR_EIP], eax      ; run the real instruction next
    call set_regs
    cmp ebx, BP_TEMP
    je .here                    ; "n" arrived
    push ebx
    call say_pid
    mov esi, s_hitbp
    call puts
    pop eax
    inc eax
    call putdec
    call nl
    jmp .here
.int3:
    call say_pid
    mov esi, s_int3
    call puts
.here:
    mov byte [bp_used+BP_TEMP], 0
    mov eax, [regs+DR_EIP]
    mov ecx, 1
    jmp unasm_n
.ended:
    call say_pid
    mov esi, s_ended
    call puts
    cmp byte [started], 0
    je .e2
    mov eax, SYS_WAIT           ; ours: its exit code
    mov ebx, [pid]
    int 0x80
    push eax
    mov esi, s_code
    call puts
    pop eax
    call putdec
    mov al, ')'
    call putc
.e2:
    call nl
    jmp forget

say_pid:
    mov esi, s_pid
    call puts
    mov eax, [pid]
    call putdec
    mov al, ' '
    jmp putc

get_regs:
    mov eax, SYS_DEBUG
    mov ebx, DBG_GETREGS
    mov ecx, [pid]
    mov edx, regs
    int 0x80
    ret
set_regs:
    pushad
    mov eax, SYS_DEBUG
    mov ebx, DBG_SETREGS
    mov ecx, [pid]
    mov edx, regs
    int 0x80
    popad
    ret

; one instruction; CF if it did not stop after it (ended, or something
; else stopped it: already reported)
step_one:
    mov byte [listen], 0
    mov eax, SYS_DEBUG
    mov ebx, DBG_CONT
    mov ecx, [pid]
    mov edx, 1
    int 0x80
    mov eax, SYS_DEBUG
    mov ebx, DBG_WAIT
    mov ecx, [pid]
    xor edx, edx
    int 0x80
    cmp eax, DBG_R_STEP
    jne .other
    mov [reason], eax
    call get_regs
    clc
    ret
.other:                         ; let wait_stop report it (it is ready)
    mov byte [listen], 0
    call wait_stop
    stc
    ret

; s [n]
cmd_step:
    call need_stopped
    jc .r
    mov ecx, 1
    call parse_num
    jc .go
    mov ecx, eax
    test ecx, ecx
    jz .r
.go:
    push ecx
    call step_one
    pop ecx
    jc .r
    loop .go
    mov eax, [regs+DR_EIP]
    mov ecx, 1
    call unasm_n
.r: ret

; n: steps over a call (a breakpoint after it), else as s
cmd_next:
    call need_stopped
    jc .r
    call read_insn              ; eax = length, dis at eip
    mov esi, dis_text
    mov edi, w_call
    call word_is
    jc .step
    mov eax, [regs+DR_EIP]
    add eax, [insn_len]
    mov ebx, BP_TEMP
    mov [bp_addr+ebx*4], eax
    mov byte [bp_used+ebx], 1
    mov byte [listen], 1
    jmp resume
.step:
    mov ecx, 1
    jmp cmd_step.go
.r: ret

; c: runs until a breakpoint or a fault; Esc stops it
cmd_cont:
    call need_stopped
    jc .r
    mov byte [listen], 1
    jmp resume
.r: ret

; g: as c, but the keyboard stays the program's
cmd_go:
    call need_stopped
    jc .r
    mov byte [listen], 0
    jmp resume
.r: ret

; leaves a breakpoint at eip by one step, plants the breakpoints, runs
resume:
    mov eax, [regs+DR_EIP]
    call bp_find
    jc .plant
    cmp ebx, BP_TEMP
    je .plant
    mov al, [listen]
    push eax
    call step_one
    pop eax
    jc .r
    mov [listen], al
.plant:
    call bp_insert_all
    mov eax, SYS_DEBUG
    mov ebx, DBG_CONT
    mov ecx, [pid]
    xor edx, edx
    int 0x80
    jmp wait_stop
.r: ret

; ---------- breakpoints ----------
; per breakpoint (BP_MAX, and BP_TEMP for n): bp_addr, bp_used, bp_saved
; (the byte under its INT3), bp_in (1 while the INT3 is in the program)

; eax = address -> ebx = breakpoint number (BP_TEMP for n's), CF if none
bp_find:
    xor ebx, ebx
.l: cmp byte [bp_used+ebx], 0
    je .n
    cmp [bp_addr+ebx*4], eax
    je .y
.n: inc ebx
    cmp ebx, BP_MAX
    jbe .l
    stc
    ret
.y: clc
    ret

bp_insert_all:
    pushad
    xor ebx, ebx
.l: cmp byte [bp_used+ebx], 0
    je .n
    mov eax, [bp_addr+ebx*4]
    lea edx, [bp_saved+ebx]
    mov ecx, 1
    call mem_read
    cmp eax, 1
    jne .n
    mov eax, [bp_addr+ebx*4]
    mov edx, b_int3
    mov ecx, 1
    call mem_write
    mov byte [bp_in+ebx], 1
.n: inc ebx
    cmp ebx, BP_MAX
    jbe .l
    popad
    ret

bp_remove_all:
    pushad
    xor ebx, ebx
.l: cmp byte [bp_in+ebx], 0
    je .n
    mov eax, [bp_addr+ebx*4]
    lea edx, [bp_saved+ebx]
    mov ecx, 1
    call mem_write
    mov byte [bp_in+ebx], 0
.n: inc ebx
    cmp ebx, BP_MAX
    jbe .l
    popad
    ret

; b <where>
cmd_break:
    call need_stopped
    jc .r
    call parse_where
    jc .bad
    push eax
    mov ecx, 1                  ; must be readable
    mov edx, scratch
    call mem_read
    cmp eax, 1
    pop eax
    jne .bad
    xor ebx, ebx
.f: cmp byte [bp_used+ebx], 0
    je .got
    inc ebx
    cmp ebx, BP_MAX
    jb .f
    mov esi, s_bpfull
    jmp puts
.got:
    mov [bp_addr+ebx*4], eax
    mov byte [bp_used+ebx], 1
    mov byte [bp_in+ebx], 0
    push eax
    mov esi, s_bp
    call puts
    lea eax, [ebx+1]
    call putdec
    mov esi, s_at
    call puts
    pop eax
    call put_addr_sym
    jmp nl
.bad:
    mov esi, s_badwhere
    jmp puts
.r: ret

cmd_blist:
    xor ebx, ebx
    xor edx, edx
.l: cmp byte [bp_used+ebx], 0
    je .n
    inc edx
    mov esi, s_bp
    call puts
    lea eax, [ebx+1]
    call putdec
    mov esi, s_at
    call puts
    mov eax, [bp_addr+ebx*4]
    call put_addr_sym
    call nl
.n: inc ebx
    cmp ebx, BP_MAX
    jb .l
    test edx, edx
    jnz .r
    mov esi, s_nobp
    call puts
.r: ret

cmd_bdel:
    call parse_dec
    jc .bad
    dec eax
    cmp eax, BP_MAX
    jae .bad
    cmp byte [bp_used+eax], 0
    je .bad
    mov byte [bp_used+eax], 0
    mov esi, s_deleted
    jmp puts
.bad:
    mov esi, s_badbp
    jmp puts

; ---------- looking at it ----------

cmd_regs:
    call need_stopped
    jc .r
    mov esi, regnames
    mov edi, regorder
    mov ecx, 8
.l: call puts_fixed3
    mov al, '='
    call putc
    movzx eax, byte [edi]
    mov eax, [regs+eax]
    call puthex8
    inc edi
    mov al, ' '
    cmp ecx, 5
    jne .sp
    mov al, 10
.sp: call putc
    loop .l
    call nl
    mov esi, s_eip
    call puts
    mov eax, [regs+DR_EIP]
    call put_addr_sym
    mov esi, s_flags
    call puts
    mov eax, [regs+DR_EFLAGS]
    call puthex8
    mov esi, flagnames
.f: lodsd
    test eax, eax
    jz .fe
    test [regs+DR_EFLAGS], eax
    jz .fs
    mov al, ' '
    call putc
    call puts
.fs:
    add esi, 3
    jmp .f
.fe:
    jmp nl
.r: ret

; esi = 3-character name: prints it, esi past it
puts_fixed3:
    mov al, [esi]
    call putc
    mov al, [esi+1]
    call putc
    mov al, [esi+2]
    call putc
    add esi, 3
    ret

; u [where] [n]
cmd_unasm:
    call need_stopped
    jc .r
    mov eax, [regs+DR_EIP]
    cmp byte [esi], 0
    je .d
    call parse_where
    jc .bad
.d: push eax
    mov ecx, 8
    call parse_num
    jc .n
    mov ecx, eax
.n: pop eax
    jmp unasm_n
.bad:
    mov esi, s_badwhere
    jmp puts
.r: ret

; eax = address, ecx = instructions: one line each, a "name:" line
; where a symbol starts
unasm_n:
    test ecx, ecx
    jz .r
    push ecx
    mov [ua_addr], eax
    call sym_exact
    test esi, esi
    jz .nolabel
    call puts
    mov al, ':'
    call putc
    call nl
.nolabel:
    mov eax, [ua_addr]
    mov edx, codebuf
    mov ecx, 16
    call mem_read
    test eax, eax
    jz .unreadable
    mov edi, codebuf            ; pad what could not be read
    add edi, eax
    mov ecx, 16
    sub ecx, eax
    mov al, 0
    rep stosb
    mov esi, codebuf
    mov ebx, [ua_addr]
    call dis_one
    mov [insn_len], eax
    mov eax, [ua_addr]
    call puthex8
    mov al, ' '
    call putc
    call putc
    mov ecx, [insn_len]
    mov esi, codebuf
    mov edx, 8                  ; bytes shown, at most 8
.b: cmp edx, 0
    je .bd
    lodsb
    call puthex2
    dec edx
    loop .b
.bd:
    lea ecx, [edx*2+2]
    call spaces
    mov esi, dis_text
    call puts
    call nl
    mov eax, [ua_addr]
    add eax, [insn_len]
    pop ecx
    dec ecx
    jmp unasm_n
.unreadable:
    pop ecx
    mov esi, s_noread
    call puts
.r: ret

; disassembles the instruction at eip -> [insn_len], dis_text
read_insn:
    mov eax, [regs+DR_EIP]
    mov edx, codebuf
    mov ecx, 16
    call mem_read
    mov esi, codebuf
    mov ebx, [regs+DR_EIP]
    call dis_one
    mov [insn_len], eax
    ret

; x [where] [n]: hex and characters, 16 bytes a line
cmd_dump:
    call need_stopped
    jc .r
    mov eax, [regs+DR_ESP]
    cmp byte [esi], 0
    je .d
    call parse_where
    jc .bad
.d: mov [ua_addr], eax
    mov ecx, 64
    call parse_num
    jc .n
    mov ecx, eax
.n: cmp ecx, 256
    jbe .l
    mov ecx, 256
.l: test ecx, ecx
    jz .r
    push ecx
    mov eax, [ua_addr]
    mov edx, codebuf
    cmp ecx, 16
    jbe .c
    mov ecx, 16
.c: mov [x_n], ecx
    call mem_read
    test eax, eax
    jz .unread
    mov [x_n], eax
    mov eax, [ua_addr]
    call puthex8
    mov al, ' '
    call putc
    mov esi, codebuf
    mov ecx, [x_n]
.h: mov al, ' '
    call putc
    lodsb
    call puthex2
    loop .h
    mov ecx, 16
    sub ecx, [x_n]
    imul ecx, 3
    add ecx, 2
    call spaces
    mov esi, codebuf
    mov ecx, [x_n]
.a: lodsb
    cmp al, ' '
    jb .dot
    cmp al, '~'
    jbe .ch
.dot:
    mov al, '.'
.ch: call putc
    loop .a
    call nl
    mov eax, [x_n]
    add [ua_addr], eax
    pop ecx
    sub ecx, eax
    jbe .r
    jmp .l
.unread:
    pop ecx
    mov esi, s_noread
    jmp puts
.bad:
    mov esi, s_badwhere
    jmp puts
.r: ret

; set <reg> <value>
cmd_set:
    call need_stopped
    jc .r
    mov edi, regnames
    xor ecx, ecx
.f: push esi
    mov eax, [esi]
    and eax, 0x00FFFFFF
    mov edx, [edi]
    and edx, 0x00FFFFFF
    cmp eax, edx
    jne .n
    cmp byte [esi+3], ' '
    jne .n
    add esp, 4
    add esi, 3
    call parse_where            ; a number or a symbol
    jc .bad
    movzx edx, byte [regorder+ecx]
    mov [regs+edx], eax
    call set_regs
    jmp cmd_regs
.n: pop esi
    add edi, 3
    inc ecx
    cmp ecx, 10
    jb .f
.bad:
    mov esi, s_badset
    jmp puts
.r: ret

; bt: return addresses up the ebp chain
cmd_bt:
    call need_stopped
    jc .r
    mov eax, [regs+DR_EIP]
    call bt_line
    ; at a function's first instruction (push ebp) its frame is not made
    ; yet: the return address is on top of the stack
    mov eax, [regs+DR_EIP]
    mov edx, codebuf
    mov ecx, 1
    call mem_read
    cmp eax, 1
    jne .chain
    cmp byte [codebuf], 0x55
    jne .chain
    mov eax, [regs+DR_ESP]
    mov edx, codebuf
    mov ecx, 4
    call mem_read
    cmp eax, 4
    jne .chain
    mov eax, [codebuf]
    call bt_line
.chain:
    mov eax, [regs+DR_EBP]
    mov ecx, 16
.l: test eax, eax
    jz .r
    mov [ua_addr], eax
    push ecx
    mov edx, codebuf
    mov ecx, 8
    call mem_read
    pop ecx
    cmp eax, 8
    jne .r
    mov eax, [codebuf+4]        ; return address
    call bt_line
    mov eax, [codebuf]          ; the caller's ebp
    cmp eax, [ua_addr]
    jbe .r                      ; frames go up the stack
    loop .l
.r: ret
bt_line:
    push eax
    mov esi, s_btat
    call puts
    pop eax
    call put_addr_sym
    jmp nl

; sym [text]: symbols whose name starts with text
cmd_sym:
    mov ebx, symtab
    mov ecx, [nsyms]
    xor edx, edx
.l: test ecx, ecx
    jz .e
    lea edi, [ebx+4]
    push esi
.c: mov al, [esi]
    cmp al, ' '
    jbe .m
    cmp al, [edi]
    jne .no
    inc esi
    inc edi
    jmp .c
.m: pop esi
    inc edx
    mov eax, [ebx]
    call puthex8
    mov al, ' '
    call putc
    push esi
    lea esi, [ebx+4]
    call puts
    pop esi
    call nl
    jmp .n
.no:
    pop esi
.n: add ebx, SYM_SIZE
    dec ecx
    jmp .l
.e: test edx, edx
    jnz .r
    mov esi, s_nosym
    call puts
.r: ret

; ps: the process table (GUI_SYSINFO, kernel/sysinfo.asm)
SI_PART_PROCS equ 1
SI_PID      equ 0
SI_STATE    equ 4
SI_NAME     equ 24
SI_ROW      equ 40
cmd_ps:
    mov eax, SYS_GUI
    mov ebx, GUI_SYSINFO
    mov ecx, procbuf
    mov edx, SI_PART_PROCS
    int 0x80
    test eax, eax
    jz .ok
    mov esi, s_nops
    jmp puts
.ok:
    mov esi, s_pshead
    call puts
    mov ebx, procbuf
    mov ecx, 8
.l: mov eax, [ebx+SI_STATE]
    test eax, eax
    jz .n
    mov eax, [ebx+SI_PID]
    call putdec
    mov al, 9
    call putc
    mov eax, [ebx+SI_STATE]
    cmp eax, 5
    jbe .s
    xor eax, eax
.s: mov esi, [statenames+eax*4]
    call puts
    mov al, 9
    call putc
    lea esi, [ebx+SI_NAME]
    call puts
    call nl
.n: add ebx, SI_ROW
    loop .l
    ret

; ---------- memory of the program ----------

; eax = address, edx = buffer, ecx = bytes -> eax = bytes read
mem_read:
    push ebx
    push ecx
    push edx
    mov [xfer], eax
    mov [xfer+4], edx
    mov [xfer+8], ecx
    mov eax, SYS_DEBUG
    mov ebx, DBG_READ
    mov ecx, [pid]
    mov edx, xfer
    int 0x80
    pop edx
    pop ecx
    pop ebx
    ret
mem_write:
    push ebx
    push ecx
    push edx
    mov [xfer], eax
    mov [xfer+4], edx
    mov [xfer+8], ecx
    mov eax, SYS_DEBUG
    mov ebx, DBG_WRITE
    mov ecx, [pid]
    mov edx, xfer
    int 0x80
    pop edx
    pop ecx
    pop ebx
    ret

; ---------- symbols ----------

; loads <progname>.sym, or the .symtab of an ELF program
load_symbols:
    mov dword [nsyms], 0
    mov esi, progname
    mov edi, symfile
.c: lodsb
    stosb
    test al, al
    jnz .c
    dec edi
    mov dword [edi], '.sym'
    mov byte [edi+4], 0
    mov ebx, symfile
    call read_file
    jc .elf
    call parse_symfile
    jmp .say
.elf:
    mov ebx, progname
    call read_file
    jc .r
    cmp dword [ecx], 0x464C457F
    jne .r
    call parse_elf_syms
.say:
    mov eax, [nsyms]
    test eax, eax
    jz .r
    call putdec
    mov esi, s_symsloaded
    call puts
.r: ret

; ebx = file name -> ecx = buffer, eax = length, CF if it cannot be read
read_file:
    push ebx
    cmp dword [filebuf], 0
    jne .have0
    mov eax, SYS_SBRK
    mov ebx, FILE_MAX
    int 0x80
    cmp eax, -1
    je .nomem
    mov [filebuf], eax
.have0:
    pop ebx
.have:
    mov eax, SYS_OPEN
    xor ecx, ecx
    int 0x80
    cmp eax, -1
    je .no
    mov ebx, eax
    mov eax, SYS_READ
    mov ecx, [filebuf]
    mov edx, FILE_MAX-1
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    int 0x80
    pop eax
    cmp eax, -1
    je .no
    mov ecx, [filebuf]
    mov byte [ecx+eax], 0
    clc
    ret
.nomem:
    pop ebx
.no:
    stc
    ret

; ecx = text of "XXXXXXXX name" lines, eax = its length
parse_symfile:
    mov esi, ecx
.line:
    call skipsp
    cmp byte [esi], 0
    je .r
    call parse_hex
    jc .skip
    call skipsp
    call sym_add
.skip:
    lodsb
    test al, al
    jz .r
    cmp al, 10
    jne .skip
    jmp .line
.r: ret

; eax = address, esi = name (ends at a blank, newline or zero): appends
; it. esi is left at the end of the name.
sym_add:
    mov edx, [nsyms]
    cmp edx, SYM_MAX
    jae .skip
    shl edx, 5
    lea edi, [symtab+edx]
    stosd
    mov ecx, SYM_NAMEMAX
.c: mov al, [esi]
    cmp al, ' '
    jbe .e
    stosb
    inc esi
    loop .c
.e: mov byte [edi], 0
    inc dword [nsyms]
.skip:
.s2: mov al, [esi]
    cmp al, ' '
    jbe .r
    inc esi
    jmp .s2
.r: ret

; ecx = an ELF32 file: symbols from every SHT_SYMTAB section
parse_elf_syms:
    mov ebp, ecx
    mov ebx, [ebp+0x20]         ; e_shoff
    test ebx, ebx
    jz .r
    movzx ecx, word [ebp+0x30]  ; e_shnum
    movzx edx, word [ebp+0x2E]  ; e_shentsize
.sec:
    test ecx, ecx
    jz .r
    cmp ebx, FILE_MAX-40
    ja .r
    cmp dword [ebp+ebx+4], 2    ; SHT_SYMTAB
    jne .next
    pushad
    mov esi, [ebp+ebx+0x10]     ; sh_offset
    mov ecx, [ebp+ebx+0x14]     ; sh_size
    lea eax, [esi+ecx]
    cmp eax, FILE_MAX
    ja .symd                    ; not all in the file: ignored
    mov eax, [ebp+ebx+0x18]     ; sh_link: its string table
    imul eax, edx
    add eax, [ebp+0x20]
    cmp eax, FILE_MAX-40
    ja .symd
    mov edi, [ebp+eax+0x10]     ; that section's offset
    cmp edi, FILE_MAX
    jae .symd
    add edi, ebp
    add esi, ebp
    shr ecx, 4                  ; 16-byte entries
.sym:
    test ecx, ecx
    jz .symd
    mov eax, [esi]              ; st_name
    test eax, eax
    jz .sn
    cmp word [esi+14], 0        ; st_shndx: undefined
    je .sn
    mov dl, [esi+12]
    and dl, 15                  ; type: notype, object, func
    cmp dl, 2
    ja .sn
    push esi
    push ecx
    push edi
    mov ebx, [esi+4]            ; st_value
    lea esi, [edi+eax]
    mov eax, ebx
    call sym_add
    pop edi
    pop ecx
    pop esi
.sn: add esi, 16
    dec ecx
    jmp .sym
.symd:
    popad
.next:
    add ebx, edx
    dec ecx
    jmp .sec
.r: ret

; eax = address -> esi = name of the symbol at exactly it, or 0
sym_exact:
    push ebx
    push ecx
    mov ebx, symtab
    mov ecx, [nsyms]
.l: test ecx, ecx
    jz .no
    cmp [ebx], eax
    je .y
    add ebx, SYM_SIZE
    dec ecx
    jmp .l
.y: lea esi, [ebx+4]
    pop ecx
    pop ebx
    ret
.no:
    xor esi, esi
    pop ecx
    pop ebx
    ret

; eax = address -> esi = the nearest symbol at or below it (within 64 KB),
; edx = the offset from it; esi = 0 if none
sym_near:
    push ebx
    push ecx
    xor esi, esi
    mov edx, 0x10000
    mov ebx, symtab
    mov ecx, [nsyms]
.l: test ecx, ecx
    jz .r
    push eax
    sub eax, [ebx]
    jb .n
    cmp eax, edx
    jae .n
    mov edx, eax
    lea esi, [ebx+4]
.n: pop eax
    add ebx, SYM_SIZE
    dec ecx
    jmp .l
.r: pop ecx
    pop ebx
    ret

; for disasm.inc: eax = branch target -> esi = name or 0 ("name" or
; "name+off" in symtext)
dis_symname:
    push eax
    push edx
    push edi
    call sym_near
    test esi, esi
    jz .r
    mov edi, symtext
.c: lodsb
    stosb
    test al, al
    jnz .c
    test edx, edx
    jz .d
    dec edi
    mov byte [edi], '+'
    inc edi
    mov eax, edx
    call hex_to_edi
    mov byte [edi], 0
.d: mov esi, symtext
.r: pop edi
    pop edx
    pop eax
    ret

; eax = address: "0003001C <name+4>"
put_addr_sym:
    push eax
    push esi
    call puthex8
    call dis_symname
    test esi, esi
    jz .r
    push esi
    mov esi, s_lt
    call puts
    pop esi
    call puts
    mov al, '>'
    call putc
.r: pop esi
    pop eax
    ret

; eax -> lower-case hex digits, no leading zeros, at edi
hex_to_edi:
    push ecx
    push edx
    mov edx, eax
    mov ecx, 8
.s: cmp ecx, 1
    je .d
    test edx, 0xF0000000
    jnz .d
    shl edx, 4
    dec ecx
    jmp .s
.d: rol edx, 4
    mov al, dl
    and al, 15
    add al, '0'
    cmp al, '9'
    jbe .o
    add al, 'a'-'9'-1
.o: stosb
    loop .d
    pop edx
    pop ecx
    ret

; ---------- parsing ----------

; esi -> <where>: hex number, symbol or symbol+hex -> eax, esi past it,
; CF if neither
parse_where:
    call skipsp
    push esi
    call parse_hex
    jnc .num
    pop esi
    push esi
    ; a symbol: its name runs to a blank, '+' or the end
    mov ebx, symtab
    mov ecx, [nsyms]
.s: test ecx, ecx
    jz .no
    mov esi, [esp]
    lea edi, [ebx+4]
.c: mov al, [esi]
    cmp al, ' '
    jbe .end
    cmp al, '+'
    je .end
    cmp al, [edi]
    jne .n
    inc esi
    inc edi
    jmp .c
.end:
    cmp byte [edi], 0
    jne .n
    mov eax, [ebx]
    cmp byte [esi], '+'
    jne .num
    inc esi
    push eax
    call parse_hex
    pop edx
    jc .no
    add eax, edx
    jmp .num
.n: add ebx, SYM_SIZE
    dec ecx
    jmp .s
.num:
    add esp, 4
    clc
    ret
.no:
    pop esi
    stc
    ret

; esi -> hex number ("0x" optional) ending at a blank, '+' or the end ->
; eax, esi past it; CF and esi unchanged if it is not one
parse_hex:
    push ebx
    push ecx
    push edx
    mov edx, esi
    cmp word [esi], '0x'
    jne .s
    add esi, 2
.s: xor eax, eax
    xor ebx, ebx                ; digits
.l: movzx ecx, byte [esi]
    cmp cl, ' '
    jbe .e
    cmp cl, '+'
    je .e
    or cl, 0x20
    sub cl, '0'
    cmp cl, 9
    jbe .dig
    sub cl, 'a'-'0'
    cmp cl, 5
    ja .no
    add cl, 10
.dig:
    shl eax, 4
    or eax, ecx
    inc esi
    inc ebx
    jmp .l
.e: test ebx, ebx
    jz .no
    pop edx
    pop ecx
    pop ebx
    clc
    ret
.no:
    mov esi, edx
    pop edx
    pop ecx
    pop ebx
    stc
    ret

; esi -> decimal number -> eax, esi past it, CF if none
parse_dec:
    call skipsp
    push ebx
    push ecx
    xor eax, eax
    xor ebx, ebx
.l: movzx ecx, byte [esi]
    sub ecx, '0'
    cmp ecx, 9
    ja .e
    imul eax, 10
    add eax, ecx
    inc esi
    inc ebx
    jmp .l
.e: test ebx, ebx
    jz .no
    pop ecx
    pop ebx
    clc
    ret
.no:
    pop ecx
    pop ebx
    stc
    ret

; a count (decimal), as parse_dec but keeps ecx
parse_num:
    push ecx
    call parse_dec
    pop ecx
    ret

skipsp:
.l: cmp byte [esi], ' '
    jne .r
    inc esi
    jmp .l
.r: ret

; esi = text, edi = word: CF clear and esi past it when the text starts
; with the word followed by a blank or the end
word_is:
    push eax
    push edx
    push edi
    mov edx, esi
.l: mov al, [edi]
    test al, al
    jz .end
    cmp al, [esi]
    jne .no
    inc esi
    inc edi
    jmp .l
.end:
    cmp byte [esi], ' '
    ja .no
    clc
    jmp .r
.no:
    mov esi, edx
    stc
.r: pop edi
    pop edx
    pop eax
    ret

; ---------- console ----------

putc:                           ; al
    push eax
    push ebx
    movzx ebx, al
    mov eax, SYS_PUTC
    int 0x80
    pop ebx
    pop eax
    ret
puts:                           ; esi
    push eax
    push ebx
    mov ebx, esi
    mov eax, SYS_PUTS
    int 0x80
    pop ebx
    pop eax
    ret
nl:
    push eax
    mov al, 10
    call putc
    pop eax
    ret
spaces:                         ; ecx
    push eax
    push ecx
    mov al, ' '
.l: test ecx, ecx
    jz .r
    call putc
    dec ecx
    jmp .l
.r: pop ecx
    pop eax
    ret
puthex8:
    push eax
    shr eax, 16
    call puthex4
    pop eax
puthex4:
    push eax
    shr eax, 8
    call puthex2
    pop eax
puthex2:
    push eax
    shr al, 4
    call puthex1
    pop eax
puthex1:
    push eax
    and al, 15
    add al, '0'
    cmp al, '9'
    jbe .d
    add al, 'A'-'9'-1
.d: call putc
    pop eax
    ret
putdec:                         ; eax, signed
    pushad
    mov edi, numbuf+15
    mov byte [edi], 0
    xor ecx, ecx
    test eax, eax
    jns .p
    neg eax
    inc ecx
.p: mov ebx, 10
.d: xor edx, edx
    div ebx
    add dl, '0'
    dec edi
    mov [edi], dl
    test eax, eax
    jnz .d
    test ecx, ecx
    jz .o
    dec edi
    mov byte [edi], '-'
.o: mov esi, edi
    call puts
    popad
    ret

; one line into line (echoed; Backspace edits) -> eax = length, -1 at
; the end of redirected input
readline:
    push ecx
    push edi
    mov edi, line
    xor ecx, ecx
.k: mov eax, SYS_GETC
    int 0x80
    cmp eax, -1
    je .eof
    cmp al, 10
    je .done
    cmp al, 13
    je .done
    cmp al, 8
    je .bs
    cmp al, ' '
    jb .k
    cmp ecx, LINE_MAX
    jae .k
    mov [edi+ecx], al
    inc ecx
    call putc
    jmp .k
.bs:
    test ecx, ecx
    jz .k
    dec ecx
    call putc
    jmp .k
.eof:
    mov byte [edi+ecx], 0
    call nl
    mov eax, -1
    jmp .r
.done:
    mov byte [edi+ecx], 0
    call nl
    mov eax, ecx
.r: pop edi
    pop ecx
    ret

; ---------- data ----------
w_help db 'help', 0
w_h db 'h', 0
w_r db 'r', 0
w_s db 's', 0
w_n db 'n', 0
w_c db 'c', 0
w_g db 'g', 0
w_b db 'b', 0
w_bl db 'bl', 0
w_bd db 'bd', 0
w_u db 'u', 0
w_x db 'x', 0
w_set db 'set', 0
w_bt db 'bt', 0
w_sym db 'sym', 0
w_ps db 'ps', 0
w_run db 'run', 0
w_attach db 'attach', 0
w_detach db 'detach', 0
w_kill db 'kill', 0
w_q db 'q', 0
w_quit db 'quit', 0
w_call db 'call', 0

regnames db 'eaxebxecxedxesiediebpespeipefl'
regorder db DR_EAX, DR_EBX, DR_ECX, DR_EDX, DR_ESI, DR_EDI, DR_EBP, DR_ESP, DR_EIP, DR_EFLAGS
flagnames:
    dd 0x001
    db 'CF', 0
    dd 0x004
    db 'PF', 0
    dd 0x010
    db 'AF', 0
    dd 0x040
    db 'ZF', 0
    dd 0x080
    db 'SF', 0
    dd 0x100
    db 'TF', 0
    dd 0x200
    db 'IF', 0
    dd 0x400
    db 'DF', 0
    dd 0x800
    db 'OF', 0
    dd 0
statenames dd st_free, st_ready, st_running, st_waiting, st_zombie, st_stopped
st_free db 'free', 0
st_ready db 'ready', 0
st_running db 'running', 0
st_waiting db 'waiting', 0
st_zombie db 'zombie', 0
st_stopped db 'stopped', 0
b_int3 db 0xCC

s_prompt db 'dbg> ', 0
s_unknown db 'Unknown command (help lists them)', 10, 0
s_noprog db 'No program: run <program> or attach <pid>', 10, 0
s_already db 'Already debugging a program (detach or kill it first)', 10, 0
s_noload db 'Cannot start it: loader error -', 0
s_noattach db 'Cannot attach to that process', 10, 0
s_usage_pid db 'attach <pid>', 10, 0
s_detached db 'Detached', 10, 0
s_pid db 'pid ', 0
s_exc db 'stopped by CPU exception ', 0
s_cr2 db ' at address ', 0
s_entry db 'stopped at its entry', 10, 0
s_stopped db 'stopped', 10, 0
s_hitbp db 'hit breakpoint ', 0
s_int3 db 'ran an INT3 of its own', 10, 0
s_ended db 'ended', 0
s_code db ' (exit code ', 0
s_bp db 'breakpoint ', 0
s_at db ' at ', 0
s_bpfull db 'No free breakpoint', 10, 0
s_badwhere db 'Not an address or symbol here', 10, 0
s_nobp db 'No breakpoints', 10, 0
s_deleted db 'Deleted', 10, 0
s_badbp db 'bd <number from bl>', 10, 0
s_eip db 'eip=', 0
s_flags db '  eflags=', 0
s_noread db '(cannot read there)', 10, 0
s_badset db 'set <eax..edi|ebp|esp|eip|efl> <value>', 10, 0
s_btat db '  at ', 0
s_nosym db 'No symbols', 10, 0
s_nops db 'ps needs GUI_SYSINFO (the system monitor', 39, 's call)', 10, 0
s_pshead db 'PID', 9, 'STATE', 9, 'NAME', 10, 0
s_symsloaded db ' symbols loaded', 10, 0
s_lt db ' <', 0
s_help:
    db 'run <prog> [arg]  attach <pid>  detach  kill  q(uit)  ps', 10
    db 'r  registers         set <reg> <value>     bt  backtrace', 10
    db 's [n]  step   n  step over a call   c  continue (Esc stops)', 10
    db 'g  continue, keys to the program', 10
    db 'b <where>  breakpoint   bl  list   bd <n>  delete', 10
    db 'u [where] [n]  disassemble   x [where] [n]  memory   sym [text]', 10
    db '<where>: hex address, symbol, or symbol+hex', 10, 0

pid dd 0
filebuf dd 0
started db 0
listen db 0
stopped_ok db 0

SQX_BSS
reason resd 1
insn_len resd 1
ua_addr resd 1
x_n resd 1
xfer resd 3
regs resb DBG_REGS_SIZE
bp_addr resd BP_MAX+1
bp_used resb BP_MAX+1
bp_saved resb BP_MAX+1
bp_in resb BP_MAX+1
BP_END:
nsyms resd 1
symtab resb SYM_MAX*SYM_SIZE
symtext resb 48
symfile resb 24
progname resb 16
progarg resb 64
line resb LINE_MAX+2
codebuf resb 16
scratch resb 4
numbuf resb 16
procbuf resb 8*SI_ROW
SQX_END
