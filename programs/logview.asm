; Squirrel-OS/2 — Log Viewer (A.5, OS2-APPS). Original code.
; run logview [file]  |  run logview test
;
; Without a file it shows the kernel log (GUI_SYSINFO, kernel/
; sysinfo.asm): a line for the boot and for each program that starts,
; ends or crashes, "[seconds] what happened". With a file it shows that
; file's lines. Lines with "crashed" or "error" in them are drawn in red.
;
;   Up/Down, PgUp/PgDn, Home/End: scroll   Left/Right: sideways
;   /: a filter: type a word and Enter; only the lines with it in them
;      (capitals or not) stay, with the word marked. An empty filter
;      shows every line again.
;   F5: read the log (or file) again   F: follow: read it again every
;   second and stay at the end (on at first for the kernel log)
;   Esc: quit (or drop the filter being typed)
;
; "run logview test" reads the kernel log, filters it, reads a file of
; its own and a missing one, and prints "logview: PASS".
; See documentation/apps/logview.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"
%include "sysinfo.inc"

BUF_MAX     equ 32768           ; the text
LINES_MAX   equ 4000
COLS        equ 52
TX_X        equ 4
TX_Y        equ WIN_TITLE_H + 2
ROWS        equ 20
INFO_Y      equ TX_Y + ROWS * CELL_H + 2
STAT_Y      equ SCR_H - CELL_H - 2
FMAX        equ 24              ; a filter
K_F5        equ 0x3F

main:
    mov esi, [esp+4]
    mov [arg], esi
    mov eax, SYS_SBRK
    mov ebx, BUF_MAX + 1 + LINES_MAX * 8
    int 0x80
    cmp eax, -1
    je .nomem
    mov [buf], eax
    add eax, BUF_MAX + 1
    mov [lines], eax
    add eax, LINES_MAX * 4
    mov [shown], eax
    mov esi, [arg]
    test esi, esi
    jz .klog
    cmp dword [esi], 'test'
    jne .file
    cmp byte [esi+4], 0
    je selftest
.file:
    cmp byte [esi], 0
    je .klog
    mov edi, fname
    mov ecx, 60
.cp:
    lodsb
    cmp al, ' '
    jbe .cpd
    stosb
    loop .cp
.cpd:
    mov byte [edi], 0
    mov byte [source], 1
    jmp .open
.klog:
    mov byte [follow], 1
.open:
    call gui_open
    jc .nogfx
    call reload
    call to_end
.draw:
    call draw
.wait:
    xor ecx, ecx
    cmp byte [follow], 0
    je .ev
    mov ecx, 100
.ev:
    call gui_event
    test eax, eax
    jz .tick
    cmp eax, EV_CLICK
    je .wait
    test eax, EV_DRAG
    jnz .wait
    call key
    jnc .draw
    call gui_close
    xor eax, eax
    ret
.tick:                          ; follow: read it again, stay at the end
    mov eax, [nshown]
    sub eax, ROWS
    jns .t1
    xor eax, eax
.t1:
    cmp [top], eax
    setae bl
    push ebx
    call reload
    pop ebx
    test bl, bl
    jz .draw
    call to_end
    jmp .draw
.nogfx:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
    ret
.nomem:
    mov esi, m_nomem
    call gui_puts
    mov eax, 1
    ret

; eax = key -> CF to quit
key:
    pushad
    movzx ebx, ah
    cmp byte [typing], 0
    jne .typing
    cmp bl, K_ESC
    je .quit
    cmp bl, K_UP
    je .up
    cmp bl, K_DOWN
    je .down
    cmp bl, K_PGUP
    je .pgup
    cmp bl, K_PGDN
    je .pgdn
    cmp bl, K_HOME
    je .home
    cmp bl, K_END
    je .end
    cmp bl, K_LEFT
    je .left
    cmp bl, K_RIGHT
    je .right
    cmp bl, K_F5
    je .reload
    test eax, 1 << 16
    jnz .ok
    cmp al, '/'
    je .filter
    or al, 0x20
    cmp al, 'f'
    je .follow
    jmp .ok
.up:
    mov eax, -1
    jmp .move
.down:
    mov eax, 1
    jmp .move
.pgup:
    mov eax, -(ROWS - 1)
    jmp .move
.pgdn:
    mov eax, ROWS - 1
.move:
    add eax, [top]
    call set_top
    jmp .ok
.home:
    mov dword [top], 0
    mov dword [hcol], 0
    jmp .ok
.end:
    call to_end
    jmp .ok
.left:
    sub dword [hcol], 8
    jns .ok
    mov dword [hcol], 0
    jmp .ok
.right:
    add dword [hcol], 8
    cmp dword [hcol], 200
    jbe .ok
    mov dword [hcol], 200
    jmp .ok
.reload:
    call reload
    jmp .ok
.follow:
    xor byte [follow], 1
    jz .ok
    call reload
    call to_end
    jmp .ok
.filter:
    mov byte [typing], 1
    mov edi, ftyped
    mov esi, filt
    call scopy
    jmp .ok
.typing:                        ; the filter on the info row
    mov ecx, ftyped
    call strlen_c
    cmp bl, K_ESC
    je .tesc
    cmp bl, K_ENTER
    je .tenter
    cmp bl, K_BKSP
    je .tbs
    test eax, 1 << 16
    jnz .ok
    cmp al, ' '
    jb .ok
    cmp al, '~'
    ja .ok
    cmp ecx, FMAX
    jae .ok
    mov [ftyped+ecx], al
    mov byte [ftyped+ecx+1], 0
    jmp .ok
.tbs:
    test ecx, ecx
    jz .ok
    mov byte [ftyped+ecx-1], 0
    jmp .ok
.tesc:
    mov byte [typing], 0
    jmp .ok
.tenter:
    mov byte [typing], 0
    mov esi, ftyped
    mov edi, filt
    call scopy
    call apply_filter
    mov dword [top], 0
    mov dword [hcol], 0
.ok:
    popad
    clc
    ret
.quit:
    popad
    stc
    ret

; eax = wanted first row -> top, within the lines
set_top:
    mov edx, [nshown]
    sub edx, ROWS
    jns .m
    xor edx, edx
.m:
    cmp eax, edx
    jle .lo
    mov eax, edx
.lo:
    test eax, eax
    jns .s
    xor eax, eax
.s:
    mov [top], eax
    ret
to_end:
    mov eax, [nshown]
    jmp set_top

; ---------- reading ----------
; the kernel log or the file -> buf, lines, then the filter again;
; CF (and an empty text) if the file cannot be read
reload:
    pushad
    mov byte [nofile], 0
    cmp byte [source], 0
    jne .file
    mov eax, SYS_GUI
    mov ebx, GUI_SYSINFO
    mov edx, SI_PART_LOG
    mov ecx, [buf]
    int 0x80
    test eax, eax
    jns .len
    xor eax, eax
    jmp .len
.file:
    mov eax, SYS_OPEN
    mov ebx, fname
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .missing
    mov ebx, eax
    mov eax, SYS_READ
    mov ecx, [buf]
    mov edx, BUF_MAX
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    int 0x80
    pop eax
    test eax, eax
    jns .len
.missing:
    mov byte [nofile], 1
    xor eax, eax
.len:
    mov [blen], eax
    mov esi, [buf]
    mov byte [esi+eax], 0
    call split_lines
    call apply_filter
    mov eax, [top]
    call set_top
    popad
    cmp byte [nofile], 1
    cmc                         ; CF when missing
    ret

; buf -> lines (offsets of each line's start; newlines become zeros)
split_lines:
    pushad
    mov esi, [buf]
    mov edi, [lines]
    xor ebx, ebx                ; offset
    xor edx, edx                ; lines
    mov ecx, [blen]
    test ecx, ecx
    jz .done
.start:
    cmp edx, LINES_MAX
    jae .done
    mov [edi+edx*4], ebx
    inc edx
.c:
    cmp ebx, ecx
    jae .done
    mov al, [esi+ebx]
    inc ebx
    cmp al, 13
    jne .c1
    mov byte [esi+ebx-1], 0
.c1:
    cmp al, 10
    jne .c
    mov byte [esi+ebx-1], 0
    cmp ebx, ecx                ; a last newline ends the last line
    jb .start
.done:
    mov [nlines], edx
    popad
    ret

; filt -> shown: the lines with it in them (all if it is empty)
apply_filter:
    pushad
    mov edi, [shown]
    xor ebx, ebx
    xor edx, edx
.l:
    cmp ebx, [nlines]
    jae .done
    cmp byte [filt], 0
    je .keep
    mov eax, ebx
    call line_ptr
    mov edi, filt
    call find_ci
    mov edi, [shown]
    jc .n
.keep:
    mov [edi+edx*4], ebx
    inc edx
.n:
    inc ebx
    jmp .l
.done:
    mov [nshown], edx
    popad
    ret

; eax = line -> esi = its text
line_ptr:
    mov esi, [lines]
    mov esi, [esi+eax*4]
    add esi, [buf]
    ret

; esi = text, edi = word -> eax = where it starts (offset), or CF.
; Capitals or not.
find_ci:
    push ebx
    push ecx
    push edx
    xor eax, eax
.s:
    cmp byte [esi+eax], 0
    je .no
    xor ecx, ecx
.c:
    mov dl, [edi+ecx]
    test dl, dl
    jz .yes
    lea ebx, [esi+eax]
    mov dh, [ebx+ecx]
    test dh, dh
    jz .no
    call lower2
    cmp dl, dh
    jne .nx
    inc ecx
    jmp .c
.nx:
    inc eax
    jmp .s
.yes:
    pop edx
    pop ecx
    pop ebx
    clc
    ret
.no:
    pop edx
    pop ecx
    pop ebx
    stc
    ret
; dl, dh -> both in small letters
lower2:
    cmp dl, 'A'
    jb .d
    cmp dl, 'Z'
    ja .d
    or dl, 0x20
.d:
    cmp dh, 'A'
    jb .r
    cmp dh, 'Z'
    ja .r
    or dh, 0x20
.r:
    ret

; ---------- drawing ----------
draw:
    pushad
    xor eax, eax
    xor ebx, ebx
    mov ecx, SCR_W
    mov edx, SCR_H
    mov esi, s_klog
    cmp byte [source], 0
    je .t
    mov esi, fname
.t:
    call gui_window
    mov eax, TX_X - 2
    mov ebx, TX_Y
    mov ecx, SCR_W - 2 * (TX_X - 2)
    mov edx, ROWS * CELL_H + 1
    mov byte [gui_ink], C_WHITE
    call gui_fill
    xor ebp, ebp
.r:
    cmp ebp, ROWS
    jae .info
    mov eax, [top]
    add eax, ebp
    cmp eax, [nshown]
    jae .info
    mov ecx, [shown]
    mov eax, [ecx+eax*4]
    call line_ptr
    call draw_line
    inc ebp
    jmp .r
.info:
    call draw_info
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    mov esi, s_keys
    mov eax, TX_X
    mov ebx, STAT_Y
    call gui_text
    call gui_flip
    popad
    ret

; esi = the line's text, ebp = the row
draw_line:
    pushad
    mov byte [gui_bg], C_WHITE
    mov byte [lcol], C_BLACK
    mov edi, w_crashed
    call find_ci
    jnc .red
    mov edi, w_error
    call find_ci
    jc .black
.red:
    mov byte [lcol], C_RED
.black:
    mov dword [mstart], -1      ; the filter word, marked
    mov dword [mend], -1
    cmp byte [filt], 0
    je .nomark
    mov edi, filt
    call find_ci
    jc .nomark
    mov [mstart], eax
    mov ecx, filt
    call strlen_c
    add eax, ecx
    mov [mend], eax
.nomark:
    mov ecx, [hcol]             ; skip the columns scrolled past
    xor edx, edx                ; column in the text
.skip:
    cmp edx, ecx
    jae .draw
    cmp byte [esi+edx], 0
    je .out
    inc edx
    jmp .skip
.draw:
    imul ebx, ebp, CELL_H
    add ebx, TX_Y + 1
    mov eax, TX_X
.c:
    mov cl, [esi+edx]
    test cl, cl
    jz .out
    cmp eax, TX_X + COLS * CELL_W
    jae .out
    push edx
    mov bl, [lcol]
    mov [gui_ink], bl
    mov byte [gui_bg], C_WHITE
    cmp edx, [mstart]
    jl .pl
    cmp edx, [mend]
    jge .pl
    mov byte [gui_ink], C_WHITE
    mov byte [gui_bg], C_BLUE
.pl:
    imul ebx, ebp, CELL_H       ; (bl was the colour)
    add ebx, TX_Y + 1
    mov dl, cl
    cmp dl, 9                   ; tabs as spaces
    jne .ch
    mov dl, ' '
.ch:
    call gui_char
    pop edx
    inc edx
    add eax, CELL_W
    jmp .c
.out:
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    popad
    ret

; "Lines 1-20 of 57   filter: word (12)   follow"  or the filter being typed
draw_info:
    pushad
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    mov edi, ibuf
    cmp byte [typing], 0
    je .info
    mov esi, s_filter_in
    call scopy
    mov esi, ftyped
    call scopy
    mov byte [edi], '_'
    mov byte [edi+1], 0
    jmp .show
.info:
    cmp byte [nofile], 0
    je .lines
    mov esi, m_missing
    call scopy
    jmp .show
.lines:
    mov esi, s_lines
    call scopy
    mov eax, [nshown]
    test eax, eax
    jz .none
    mov eax, [top]
    inc eax
    call gui_utoa
    mov byte [edi], '-'
    inc edi
    mov eax, [top]
    add eax, ROWS
    cmp eax, [nshown]
    jbe .l2
    mov eax, [nshown]
.l2:
    call gui_utoa
    jmp .of
.none:
    mov byte [edi], '0'
    inc edi
.of:
    mov esi, s_of
    call scopy
    mov eax, [nlines]
    call gui_utoa
    cmp byte [filt], 0
    je .fol
    mov esi, s_filter
    call scopy
    mov esi, filt
    call scopy
.fol:
    cmp byte [follow], 0
    je .show
    mov esi, s_follow
    call scopy
.show:
    mov esi, ibuf
    mov eax, TX_X
    mov ebx, INFO_Y
    mov ecx, SCR_W - 2 * TX_X
    call gui_textn
    popad
    ret

; esi -> edi (edi ends at the zero)
scopy:
    push eax
.c:
    lodsb
    stosb
    test al, al
    jnz .c
    dec edi
    pop eax
    ret
; ecx = string -> ecx = its length
strlen_c:
    push eax
    mov eax, ecx
.c:
    cmp byte [eax], 0
    je .d
    inc eax
    jmp .c
.d:
    sub eax, ecx
    mov ecx, eax
    pop eax
    ret

; ---------- self-test ----------
selftest:
    mov byte [bad], 'a'         ; a: the kernel log, as lines
    call reload
    jc fail
    cmp dword [nlines], 2
    jb fail
    xor eax, eax
    call line_ptr
    mov edi, w_boot
    call find_ci
    jc fail
    cmp eax, 1                  ; after "[seconds] "
    jb fail
    mov esi, w_me
    call any_line
    jc fail
    inc byte [bad]              ; b: a filter keeps only its lines
    mov esi, w_started
    mov edi, filt
    call scopy
    call apply_filter
    mov eax, [nshown]
    cmp eax, 1
    jb fail
    cmp eax, [nlines]
    jae fail                    ; (the boot line has no "started ")
    xor ebx, ebx
.b:
    cmp ebx, [nshown]
    jae .bd
    mov eax, [shown]
    mov eax, [eax+ebx*4]
    call line_ptr
    mov edi, filt
    call find_ci
    jc fail
    inc ebx
    jmp .b
.bd:
    inc byte [bad]              ; c: a file, a filter in capitals
    mov eax, SYS_OPEN
    mov ebx, t_name
    mov ecx, O_CREATE | O_TRUNC
    int 0x80
    test eax, eax
    js fail
    mov ebx, eax
    mov eax, SYS_WRITE
    mov ecx, t_text
    mov edx, t_text_len
    int 0x80
    mov eax, SYS_CLOSE
    int 0x80
    mov byte [source], 1
    mov esi, t_name
    mov edi, fname
    call scopy
    mov byte [filt], 0
    call reload
    jc fail
    cmp dword [nlines], 5
    jne fail
    mov eax, 2                  ; the empty line
    call line_ptr
    cmp byte [esi], 0
    jne fail
    mov eax, 4                  ; no newline at the end: still a line
    call line_ptr
    cmp dword [esi], 'last'
    jne fail
    mov esi, w_gamma
    mov edi, filt
    call scopy
    call apply_filter
    cmp dword [nshown], 2
    jne fail
    mov eax, [shown]
    cmp dword [eax], 1
    jne fail
    cmp dword [eax+4], 3
    jne fail
    inc byte [bad]              ; d: scrolling stays within the lines
    mov byte [filt], 0
    call apply_filter
    mov eax, 50
    call set_top
    cmp dword [top], 0          ; 5 lines fit on the screen
    jne fail
    mov eax, SYS_DELETE
    mov ebx, t_name
    int 0x80
    inc byte [bad]              ; e: a missing file
    call reload
    jnc fail
    cmp dword [nlines], 0
    jne fail
    mov esi, pass
    call gui_puts
    xor eax, eax
    ret
fail:
    mov esi, failm
    call gui_puts
    mov eax, 1
    ret

; esi = word -> CF if no line has it
any_line:
    push ebx
    mov edi, esi
    xor ebx, ebx
.l:
    cmp ebx, [nlines]
    jae .no
    mov eax, ebx
    push edi
    call line_ptr
    pop edi
    call find_ci
    jnc .yes
    inc ebx
    jmp .l
.yes:
    pop ebx
    clc
    ret
.no:
    pop ebx
    stc
    ret

; ---------- data ----------
s_klog db 'Kernel log', 0
s_keys db '/: filter  F5: again  F: follow  Esc: quit', 0
s_lines db 'Lines ', 0
s_of db ' of ', 0
s_filter db '   filter: ', 0
s_filter_in db 'Filter: ', 0
s_follow db '   following', 0
m_missing db 'That file cannot be read', 0
w_crashed db 'crashed', 0
w_error db 'error', 0
w_boot db 'Squirrel-OS/2 started', 0
w_me db 'started logview', 0
w_started db 'started ', 0
w_gamma db 'GAMMA', 0
t_name db 'lvtest.txt', 0
t_text db 'alpha', 10, 'beta gamma', 13, 10, 10, 'Gamma delta', 10, 'last line'
t_text_len equ $ - t_text
m_nogfx db 'logview: no graphics', 10, 0
m_nomem db 'logview: no memory', 10, 0
pass db 'logview: PASS', 10, 0
failm db 'logview: FAIL '
bad db '?', 10, 0

SQX_BSS
GUI_BSS
arg resd 1
buf resd 1
lines resd 1
shown resd 1
blen resd 1
nlines resd 1
nshown resd 1
top resd 1
hcol resd 1
mstart resd 1
mend resd 1
source resb 1
follow resb 1
typing resb 1
nofile resb 1
lcol resb 1
fname resb 64
filt resb FMAX + 2
ftyped resb FMAX + 2
ibuf resb 128
SQX_END
