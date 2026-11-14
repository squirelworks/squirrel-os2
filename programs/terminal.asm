; terminal — several shells in windows (A.3). Original code.
;
;   run terminal
;
; Up to four sessions, each a window with a shell of its own running on a
; tty (SYS_TTY, kernel/tty.asm): what a program started there prints
; appears in its window, and the keys typed there go to it. F1-F4 switch to
; (or open) session 1-4, F5 shows one window or all of them stacked, F10
; quits. In a session: a program name and its argument runs it; help,
; clear, echo, exit are built in. While a program runs, Ctrl+C ends it and
; Ctrl+D ends its input. See documentation/apps/terminal.md.
%include "sqx.inc"
%include "debug.inc"
SQX_HEADER main
%include "gui.inc"

TTY_OPEN    equ 0
TTY_CLOSE   equ 1
TTY_EXEC    equ 2
TTY_READ    equ 3
TTY_WRITE   equ 4
TTY_POLL    equ 5

SESS_MAX    equ 4
COLS        equ 52
ROWS        equ 23
TEXT_SIZE   equ COLS*ROWS
LINE_MAX    equ 60
K_F5        equ 0x3F
K_F10       equ 0x44

main:
    call gui_open
    jc .fail
    xor eax, eax
    call sess_open
    jc .quit
    mov dword [focus], 0
.loop:
    call pump                   ; output and ended programs, all sessions
    cmp byte [dirty], 0
    je .wait
    call draw
.wait:
    mov ecx, 2
    call gui_waitkey
    test eax, eax
    jz .loop
    call on_key
    cmp byte [quit], 0
    jne .quit
    jmp .loop
.quit:
    call close_all
    call gui_close
    xor eax, eax
    ret
.fail:
    mov eax, SYS_PUTS
    mov ebx, s_nogfx
    int 0x80
    mov eax, 1
    ret

; ---------- sessions ----------

; eax = session -> opens it (tty, banner, prompt); CF if no tty is free
sess_open:
    pushad
    mov ebx, eax
    cmp byte [s_open+ebx], 0
    jne .ok
    mov eax, SYS_TTY
    push ebx
    mov ebx, TTY_OPEN
    int 0x80
    pop ebx
    test eax, eax
    jle .no
    mov [s_tty+ebx*4], eax
    mov byte [s_open+ebx], 1
    mov dword [s_pid+ebx*4], 0
    mov dword [s_len+ebx*4], 0
    mov eax, ebx
    call t_clear
    mov esi, s_banner
    call t_puts
    lea eax, [ebx+'1']
    call t_putc
    mov esi, s_banner2
    call t_puts
    call prompt
    inc dword [nsess]
    mov byte [dirty], 1
.ok:
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; ebx = session: closes it; the last one closing quits
sess_close:
    pushad
    call kill_child
    mov eax, SYS_TTY
    mov ecx, [s_tty+ebx*4]
    shl ecx, 8
    or ecx, TTY_CLOSE
    xchg ebx, ecx
    int 0x80
    xchg ebx, ecx
    mov byte [s_open+ebx], 0
    dec dword [nsess]
    jnz .other
    mov byte [quit], 1
    jmp .r
.other:
    xor eax, eax                ; focus the first open one
.f: cmp byte [s_open+eax], 0
    jne .got
    inc eax
    jmp .f
.got:
    mov [focus], eax
.r: mov byte [dirty], 1
    popad
    ret

close_all:
    xor ebx, ebx
.l: cmp byte [s_open+ebx], 0
    je .n
    call kill_child
.n: inc ebx
    cmp ebx, SESS_MAX
    jb .l
    ret

; ebx = session: ends the program running in it (through SYS_DEBUG: the
; terminal attaches to it and kills it), waits for it
kill_child:
    pushad
    mov ecx, [s_pid+ebx*4]
    test ecx, ecx
    jz .r
    mov eax, SYS_DEBUG
    push ebx
    mov ebx, DBG_ATTACH
    int 0x80
    pop ebx
    test eax, eax
    jnz .r                      ; (cannot: leave it)
    mov eax, SYS_DEBUG
    push ebx
    mov ebx, DBG_KILL
    int 0x80
    mov eax, SYS_WAIT
    mov ebx, ecx
    int 0x80
    pop ebx
    mov dword [s_pid+ebx*4], 0
.r: popad
    ret

; the ttys' output into the windows; prompts after programs that ended
pump:
    xor ebx, ebx
.s: cmp byte [s_open+ebx], 0
    je .n
.read:
    mov eax, SYS_TTY
    mov ecx, [s_tty+ebx*4]
    shl ecx, 8
    or ecx, TTY_READ
    push ebx
    mov ebx, ecx
    mov ecx, iobuf
    mov edx, 256
    int 0x80
    pop ebx
    test eax, eax
    jle .poll
    mov ecx, eax
    mov esi, iobuf
.c: movzx edx, byte [esi]
    mov eax, ebx
    call t_putc_sess
    inc esi
    loop .c
    mov byte [dirty], 1
    jmp .read
.poll:
    mov ecx, [s_pid+ebx*4]
    test ecx, ecx
    jz .n
    mov eax, SYS_TTY
    mov edx, [s_tty+ebx*4]
    shl edx, 8
    or edx, TTY_POLL
    push ebx
    mov ebx, edx
    mov edx, exitcode
    int 0x80
    pop ebx
    test eax, eax
    jz .n                       ; still running
    mov dword [s_pid+ebx*4], 0
    cmp eax, 1
    jne .pr
    mov eax, [exitcode]
    test eax, eax
    jz .pr
    push eax
    mov eax, ebx
    mov esi, s_exit
    call t_puts_sess
    pop eax
    call t_dec
    mov eax, ']'
    call t_putc
    mov eax, 10
    call t_putc
.pr:
    call prompt
    mov byte [dirty], 1
.n: inc ebx
    cmp ebx, SESS_MAX
    jb .s
    ret

; ---------- keys ----------

; eax = key (ASCII | scancode << 8 | Ctrl << 16)
on_key:
    mov ebx, [focus]
    mov ecx, eax
    shr ecx, 8
    and ecx, 0xFF               ; scancode
    cmp ecx, K_F1
    jb .notf
    cmp ecx, K_F1+3
    jbe .fn
    cmp ecx, K_F5
    je .layout
    cmp ecx, K_F10
    jne .notf
    mov byte [quit], 1
    ret
.fn:
    sub ecx, K_F1
    mov eax, ecx
    call sess_open
    jc .r
    mov [focus], ecx
    mov byte [dirty], 1
    ret
.layout:
    xor byte [split], 1
    mov byte [dirty], 1
    ret
.notf:
    mov byte [dirty], 1
    cmp dword [s_pid+ebx*4], 0
    jne .child
    jmp shell_key
.child:                         ; a program runs: the key is its input
    test eax, 1 << 16
    jz .plain
    cmp ecx, 0x2E               ; Ctrl+C
    je .ctrlc
    cmp ecx, 0x20               ; Ctrl+D
    jne .r
    mov al, 4                   ; end of input
    jmp .send
.ctrlc:
    mov esi, s_ctrlc
    mov eax, ebx
    call t_puts_sess
    call kill_child
    call prompt
    ret
.plain:
    test al, al
    jz .r
.send:
    mov [tmpch], al
    mov eax, SYS_TTY
    mov ecx, [s_tty+ebx*4]
    shl ecx, 8
    or ecx, TTY_WRITE
    push ebx
    mov ebx, ecx
    mov ecx, tmpch
    mov edx, 1
    int 0x80
    pop ebx
.r: ret

; ebx = session, eax = key: the session's own command line
shell_key:
    test eax, 1 << 16
    jnz .r                      ; Ctrl+ keys: nothing here
    cmp al, 10
    je .enter
    cmp al, 13
    je .enter
    cmp al, 8
    je .bs
    cmp al, ' '
    jb .r
    cmp al, '~'
    ja .r
    mov ecx, [s_len+ebx*4]
    cmp ecx, LINE_MAX
    jae .r
    mov edx, ebx
    imul edx, LINE_MAX+1
    mov [s_line+edx+ecx], al
    inc dword [s_len+ebx*4]
    movzx eax, al
    call t_putc
.r: ret
.bs:
    cmp dword [s_len+ebx*4], 0
    je .r
    dec dword [s_len+ebx*4]
    mov eax, 8
    jmp t_putc
.enter:
    mov eax, 10
    call t_putc
    mov ecx, [s_len+ebx*4]
    mov edx, ebx
    imul edx, LINE_MAX+1
    mov byte [s_line+edx+ecx], 0
    mov dword [s_len+ebx*4], 0
    lea esi, [s_line+edx]
    jmp run_line

; ebx = session, esi = the command line
run_line:
    call skipsp
    cmp byte [esi], 0
    je prompt
    mov edi, w_run              ; "run prog" works as "prog"
    call word_is
    jc .norun
    call skipsp
.norun:
    mov edi, w_help
    call word_is
    jnc .help
    mov edi, w_clear
    call word_is
    jnc .clear
    mov edi, w_exit
    call word_is
    jnc .exit
    mov edi, w_echo
    call word_is
    jnc .echo
    ; a program: the name, then the argument
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
    mov edx, esi                ; the argument
    mov eax, SYS_TTY
    mov ecx, [s_tty+ebx*4]
    shl ecx, 8
    or ecx, TTY_EXEC
    push ebx
    mov ebx, ecx
    mov ecx, progname
    int 0x80
    pop ebx
    test eax, eax
    jle .fail
    mov [s_pid+ebx*4], eax
    mov esi, progname           ; for the title
    mov edi, ebx
    shl edi, 4
    add edi, s_prog
    mov ecx, 16
    rep movsb
    ret
.fail:
    mov esi, s_unknown
    cmp eax, -1
    je .say
    mov esi, s_cannot
.say:
    mov eax, ebx
    call t_puts_sess
    jmp prompt
.help:
    mov esi, s_help
    mov eax, ebx
    call t_puts_sess
    jmp prompt
.clear:
    mov eax, ebx
    call t_clear
    jmp prompt
.echo:
    mov eax, ebx
    call t_puts_sess
    mov eax, 10
    call t_putc
    jmp prompt
.exit:
    jmp sess_close

; ebx = session: "N> "
prompt:
    push eax
    lea eax, [ebx+'1']
    call t_putc
    mov eax, '>'
    call t_putc
    mov eax, ' '
    call t_putc
    pop eax
    ret

; ---------- the text of a session ----------
; Every t_* routine keeps all registers. t_putc/t_puts/t_dec write to
; session ebx; the _sess forms take it in eax.

; eax = character, ebx = session
t_putc:
    push edx
    push eax
    mov edx, eax
    mov eax, ebx
    call t_putc_sess
    pop eax
    pop edx
    ret

; esi = string, ebx = session
t_puts:
    push eax
    mov eax, ebx
    call t_puts_sess
    pop eax
    ret

; eax = session, esi = string
t_puts_sess:
    push edx
    push esi
.l: movzx edx, byte [esi]
    test edx, edx
    jz .r
    call t_putc_sess
    inc esi
    jmp .l
.r: pop esi
    pop edx
    ret

; eax = signed number, ebx = session
t_dec:
    pushad
    mov edi, numbuf+15
    mov byte [edi], 0
    xor ecx, ecx
    test eax, eax
    jns .p
    neg eax
    inc ecx
.p: mov esi, 10
.d: xor edx, edx
    div esi
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
    call t_puts
    popad
    ret

; eax = session, dl = character: into its text, at its cursor
t_putc_sess:
    pushad
    mov ebx, eax
    imul edi, ebx, TEXT_SIZE
    add edi, s_text
    cmp dl, 10
    je .nl
    cmp dl, 13
    je .cr
    cmp dl, 8
    je .bs
    cmp dl, 9
    je .tab
    cmp dl, 12
    je .ff
    cmp dl, ' '
    jb .r
    mov eax, [s_cy+ebx*4]
    imul eax, COLS
    add eax, [s_cx+ebx*4]
    mov [edi+eax], dl
    inc dword [s_cx+ebx*4]
    cmp dword [s_cx+ebx*4], COLS
    jb .r
.nl:
    mov dword [s_cx+ebx*4], 0
    inc dword [s_cy+ebx*4]
    cmp dword [s_cy+ebx*4], ROWS
    jb .r
    dec dword [s_cy+ebx*4]      ; scroll up one line
    lea esi, [edi+COLS]
    mov ecx, TEXT_SIZE-COLS
    rep movsb
    mov ecx, COLS
    mov al, ' '
    rep stosb
    jmp .r
.cr:
    mov dword [s_cx+ebx*4], 0
    jmp .r
.bs:
    cmp dword [s_cx+ebx*4], 0
    je .r
    dec dword [s_cx+ebx*4]
    mov eax, [s_cy+ebx*4]
    imul eax, COLS
    add eax, [s_cx+ebx*4]
    mov byte [edi+eax], ' '
    jmp .r
.tab:
    mov dl, ' '
    mov eax, ebx
    call t_putc_sess
    test dword [s_cx+ebx*4], 7
    jnz .tab
    jmp .r
.ff:
    mov eax, ebx
    call t_clear
.r: popad
    ret

; eax = session: blank text, cursor home
t_clear:
    pushad
    imul edi, eax, TEXT_SIZE
    add edi, s_text
    mov ecx, TEXT_SIZE
    push eax
    mov al, ' '
    rep stosb
    pop eax
    mov dword [s_cx+eax*4], 0
    mov dword [s_cy+eax*4], 0
    popad
    ret

; ---------- drawing ----------

; one window (the focused session) or all of them stacked
draw:
    mov byte [dirty], 0
    mov al, C_DGREY
    call gui_clear
    cmp byte [split], 0
    jne .split
    mov ebx, [focus]
    xor eax, eax
    xor ecx, ecx                ; y
    mov edx, SCR_H
    call draw_sess
    jmp .flip
.split:
    mov eax, SCR_H
    xor edx, edx
    div dword [nsess]
    mov edx, eax                ; height of each
    xor ecx, ecx
    xor ebx, ebx
.l: cmp byte [s_open+ebx], 0
    je .n
    call draw_sess
    add ecx, edx
.n: inc ebx
    cmp ebx, SESS_MAX
    jb .l
.flip:
    jmp gui_flip

; ebx = session, ecx = y, edx = height: its window, full width
draw_sess:
    pushad
    ; the title: "Terminal N" and the program running there
    mov edi, title
    mov esi, s_title
.t: lodsb
    stosb
    test al, al
    jnz .t
    dec edi
    lea eax, [ebx+'1']
    stosb
    cmp dword [s_pid+ebx*4], 0
    je .tz
    mov esi, s_dash
.t2: lodsb
    stosb
    test al, al
    jnz .t2
    dec edi
    mov esi, ebx
    shl esi, 4
    add esi, s_prog
.t3: lodsb
    stosb
    test al, al
    jnz .t3
    dec edi
.tz:
    mov byte [edi], 0
    xor eax, eax
    push ebx
    mov ebx, ecx
    mov ecx, SCR_W
    mov esi, title
    call gui_window
    pop ebx
    cmp ebx, [focus]
    je .focused
    pushad                      ; not focused: a grey title bar
    mov eax, [gui_cx]
    mov ebx, [gui_cy]
    sub ebx, WIN_TITLE_H
    mov ecx, [gui_cw]
    mov edx, WIN_TITLE_H
    mov byte [gui_ink], C_DGREY
    call gui_fill
    add eax, 2
    inc ebx
    sub ecx, 4
    mov byte [gui_ink], C_LGREY
    mov byte [gui_bg], C_DGREY
    mov esi, title
    call gui_textn
    popad
.focused:
    ; the client area: black, with the last rows of the text that fit
    mov eax, [gui_cx]
    mov ebx, [gui_cy]
    mov ecx, [gui_cw]
    mov edx, [gui_ch]
    mov byte [gui_ink], C_BLACK
    call gui_fill
    mov byte [gui_ink], C_LGREY
    mov byte [gui_bg], C_BLACK
    mov eax, [gui_ch]
    xor edx, edx
    mov ecx, CELL_H
    div ecx
    cmp eax, ROWS
    jbe .vr
    mov eax, ROWS
.vr: mov [vrows], eax
    mov eax, [esp+16]           ; the session (saved ebx)
    mov ecx, [s_cy+eax*4]
    inc ecx
    sub ecx, [vrows]
    jns .first
    xor ecx, ecx
.first:
    mov [vfirst], ecx
    imul esi, eax, TEXT_SIZE
    add esi, s_text
    mov eax, [vfirst]
    imul eax, COLS
    add esi, eax
    mov ebx, [gui_cy]
    mov ecx, [vrows]
.row:
    push ecx
    mov edi, rowbuf
    push esi
    mov ecx, COLS
    rep movsb
    pop esi
    mov byte [edi], 0
    push esi
    mov esi, rowbuf
    mov eax, [gui_cx]
    add eax, 2
    mov ecx, [gui_cw]
    sub ecx, 2
    call gui_textn
    pop esi
    add esi, COLS
    add ebx, CELL_H
    pop ecx
    loop .row
    ; the cursor of the focused session: a bar under its cell
    mov eax, [esp+16]
    cmp eax, [focus]
    jne .r
    mov ecx, [s_cy+eax*4]
    sub ecx, [vfirst]
    imul ebx, ecx, CELL_H
    add ebx, [gui_cy]
    add ebx, CELL_H-1
    mov eax, [s_cx+eax*4]
    imul eax, CELL_W
    add eax, [gui_cx]
    add eax, 2
    mov ecx, CELL_W-1
    mov edx, 1
    mov byte [gui_ink], C_WHITE
    call gui_fill
.r: popad
    ret

; ---------- text helpers ----------
skipsp:
.l: cmp byte [esi], ' '
    jne .r
    inc esi
    jmp .l
.r: ret

; esi = text, edi = word: CF clear and esi past it when the text starts
; with the word and a blank or the end
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
    call skipsp
    clc
    jmp .r
.no:
    mov esi, edx
    stc
.r: pop edi
    pop edx
    pop eax
    ret

w_run db 'run', 0
w_help db 'help', 0
w_clear db 'clear', 0
w_exit db 'exit', 0
w_echo db 'echo', 0
s_nogfx db 'terminal: no graphics', 10, 0
s_banner db 'Squirrel-OS/2 Terminal ', 0
s_banner2 db '. help lists the commands.', 10, 0
s_title db 'Terminal ', 0
s_dash db ' - ', 0
s_exit db '[exit code ', 0
s_ctrlc db '^C', 10, 0
s_unknown db 'Unknown command or program', 10, 0
s_cannot db 'Cannot run it', 10, 0
s_help:
    db '<program> [argument]  runs a program from the disk', 10
    db 'help  clear  echo <text>  exit', 10
    db 'F1-F4 sessions, F5 one/all windows, F10 quit', 10
    db 'Ctrl+C ends the program, Ctrl+D ends its input', 10, 0

SQX_BSS
GUI_BSS
focus resd 1
nsess resd 1
vrows resd 1
vfirst resd 1
exitcode resd 1
dirty resb 1
quit resb 1
split resb 1
tmpch resb 1
s_open resb SESS_MAX
alignb 4
s_tty resd SESS_MAX
s_pid resd SESS_MAX
s_len resd SESS_MAX
s_cx resd SESS_MAX
s_cy resd SESS_MAX
s_prog resb 16*SESS_MAX
s_line resb (LINE_MAX+1)*SESS_MAX
s_text resb TEXT_SIZE*SESS_MAX
progname resb 16
title resb 40
rowbuf resb COLS+1
iobuf resb 256
numbuf resb 16
SQX_END
