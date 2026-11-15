; Squirrel-OS/2 — Notepad (A.1, OS2-APPS)
; Original code. run notepad [file]
;
; A text editor in a window: the GUI counterpart of `edit`. Up to 16 KB of
; text; lines longer than the window scroll sideways with the cursor.
;
;   typing, Enter, Tab      insert            Backspace, Delete  remove
;   arrows, Home, End       move              PgUp, PgDn         a page
;   Ctrl+S or F2            save (asks for a name the first time)
;   Ctrl+O                  open another file (asks for its name)
;   Ctrl+N                  a new, empty text
;   Esc                     quit (asks first if there are unsaved changes)
;
; The status row shows the file name, line and column, and "*" while
; there are unsaved changes.
;
; Syntax highlighting (A.7) by the name's extension: .asm and .inc
; (comments, strings, numbers, labels, % directives, instructions and
; registers), .c and .h (// and /* */ comments, strings, numbers, #
; lines, keywords), .bas (REM and ' comments, strings, numbers,
; keywords). "run notepad -test" checks the colours and prints
; "notepad: PASS". See documentation/apps/gui-programs.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

TEXT_MAX    equ 16384
NAME_MAX    equ 63
WX          equ 0
WY          equ 0
WW          equ SCR_W
WH          equ SCR_H
TX          equ WX + 1 + 2              ; text area, inside the frame
TY          equ WY + 1 + WIN_TITLE_H + 2
TCOLS       equ (WW - 2 - 4) / CELL_W   ; 52
TROWS       equ (WH - 2 - WIN_TITLE_H - 4 - CELL_H - 4) / CELL_H  ; 21
STATUS_Y    equ WY + WH - 1 - CELL_H - 2

main:
    mov esi, [esp+4]
    call gui_open
    jc .nogfx
    cmp dword [esi], '-tes'
    jne .arg
    cmp word [esi+4], 't'
    je selftest
.arg:
    cmp byte [esi], 0
    je .edit
    mov edi, name
    call copy_name
    call load
.edit:
    call fix_view
    call draw
.key:
    call gui_getkey
    mov dword [msg], 0
    mov ebx, eax
    shr ebx, 8
    test eax, 1 << 16           ; Ctrl
    jz .plain
    and al, 0xDF                ; upper case
    cmp al, 'S'
    je .save
    cmp al, 'O'
    je .open
    cmp al, 'N'
    je .new
    jmp .key
.plain:
    cmp bl, K_ESC
    je .esc
    cmp bl, K_F2
    je .save
    cmp bl, K_BKSP
    je .bksp
    cmp bl, K_DEL
    je .del
    cmp bl, K_LEFT
    je .left
    cmp bl, K_RIGHT
    je .right
    cmp bl, K_UP
    je .up
    cmp bl, K_DOWN
    je .down
    cmp bl, K_HOME
    je .home
    cmp bl, K_END
    je .end
    cmp bl, K_PGUP
    je .pgup
    cmp bl, K_PGDN
    je .pgdn
    cmp bl, K_ENTER
    je .enter
    cmp bl, K_TAB
    je .tab
    and eax, 0xFF
    cmp al, ' '
    jb .key
    cmp al, '~'
    ja .key
    call insert
    jmp .show
.enter:
    mov al, 10
    call insert
    jmp .show
.tab:
    mov ecx, 4
.t:
    mov al, ' '
    call insert
    loop .t
    jmp .show
.bksp:
    mov eax, [pos]
    test eax, eax
    jz .key
    dec dword [pos]
    call remove
    jmp .show
.del:
    mov eax, [pos]
    cmp eax, [len]
    jae .key
    call remove
    jmp .show
.left:
    cmp dword [pos], 0
    je .key
    dec dword [pos]
    jmp .show
.right:
    mov eax, [pos]
    cmp eax, [len]
    jae .key
    inc dword [pos]
    jmp .show
.up:
    call line_up
    jmp .show
.down:
    call line_down
    jmp .show
.home:
    mov eax, [pos]
    call line_start
    mov [pos], eax
    jmp .show
.end:
    mov eax, [pos]
    call line_end_real
    mov [pos], eax
    jmp .show
.pgup:
    mov ecx, TROWS - 1
.pu:
    call line_up
    loop .pu
    jmp .show
.pgdn:
    mov ecx, TROWS - 1
.pd:
    call line_down
    loop .pd
    jmp .show
.save:
    call save
    jmp .show
.open:
    call ask_unsaved
    jc .show
    mov esi, q_open
    call ask_name
    jc .show
    call load
    jmp .show
.new:
    call ask_unsaved
    jc .show
    call empty
    mov byte [name], 0
    jmp .show
.esc:
    call ask_unsaved
    jc .show
    call gui_close
    xor eax, eax
    ret
.show:
    call fix_view
    call draw
    jmp .key
.nogfx:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
    ret

; ---------- the text ----------
empty:
    xor eax, eax
    mov [len], eax
    mov [pos], eax
    mov [top], eax
    mov [left], eax
    mov [dirty], al
    ret

; al = character: inserted at pos, which moves past it.
insert:
    pushad
    mov ecx, [len]
    cmp ecx, TEXT_MAX
    jae .full
    mov esi, [pos]
    sub ecx, esi                ; bytes after the cursor
    lea edi, [text+esi]
    std
    lea esi, [edi+ecx-1]
    lea edi, [edi+ecx]
    rep movsb
    cld
    mov ebx, [pos]
    mov [text+ebx], al
    inc dword [pos]
    inc dword [len]
    mov byte [dirty], 1
    popad
    ret
.full:
    mov dword [msg], m_full
    popad
    ret

; Removes the character at pos.
remove:
    pushad
    mov edi, [pos]
    mov ecx, [len]
    sub ecx, edi
    dec ecx
    lea esi, [text+edi+1]
    add edi, text
    rep movsb
    dec dword [len]
    mov byte [dirty], 1
    popad
    ret

; eax = offset -> eax = the start of its line
line_start:
    test eax, eax
    jz .r
    cmp byte [text+eax-1], 10
    je .r
    dec eax
    jmp line_start
.r:
    ret

; Up and down keep the column where the line is long enough.
line_up:
    pushad
    mov eax, [pos]
    call line_start
    test eax, eax
    jz .r                       ; the first line
    mov ecx, [pos]
    sub ecx, eax                ; the column
    dec eax
    call line_start
    jmp col_on_line
.r:
    popad
    ret

line_down:
    pushad
    mov eax, [pos]
    call line_start
    mov ecx, [pos]
    sub ecx, eax
    mov eax, [pos]
    call line_end_real
    cmp eax, [len]
    jae .r                      ; the last line
    inc eax
    jmp col_on_line
.r:
    popad
    ret

; eax = a line's start, ecx = column: pos = that column or the line's end
col_on_line:
    mov ebx, eax
    call line_end_real
    add ebx, ecx
    cmp ebx, eax
    jbe .ok
    mov ebx, eax
.ok:
    mov [pos], ebx
    popad
    ret

; eax = offset -> eax = the newline that ends its line, or len
line_end_real:
    cmp eax, [len]
    jae .r
    cmp byte [text+eax], 10
    je .r
    inc eax
    jmp line_end_real
.r:
    ret

; Keeps the cursor inside the window: moves top (the first line shown)
; and left (the first column shown).
fix_view:
    pushad
    mov eax, [pos]
    call line_start
    mov ebx, eax                ; the cursor line's start
    cmp ebx, [top]
    jae .below
    mov [top], ebx              ; above the window: it becomes the first line
    jmp .cols
.below:
    ; count the lines from top to the cursor line
.again:
    mov esi, [top]
    xor ecx, ecx
.cnt:
    cmp esi, ebx
    jae .counted
    cmp byte [text+esi], 10
    jne .n
    inc ecx
.n:
    inc esi
    jmp .cnt
.counted:
    cmp ecx, TROWS
    jb .cols
    mov eax, [top]              ; one line further down
    call line_end_real
    inc eax
    mov [top], eax
    jmp .again
.cols:
    mov ecx, [pos]
    sub ecx, ebx                ; the cursor's column
    cmp ecx, [left]
    jae .r1
    mov [left], ecx
.r1:
    mov eax, [left]
    add eax, TCOLS - 1
    cmp ecx, eax
    jbe .r
    sub ecx, TCOLS - 1
    mov [left], ecx
.r:
    popad
    ret

; ---------- drawing ----------
draw:
    pushad
    mov eax, WX
    mov ebx, WY
    mov ecx, WW
    mov edx, WH
    mov edi, line               ; "Notepad - name"
    mov esi, title
    call scopy
    cmp byte [name], 0
    je .t
    mov esi, s_dash
    call scopy
    mov esi, name
    call scopy
.t:
    mov byte [edi], 0
    mov esi, line
    call gui_window
    mov eax, TX - 1             ; the text area, white
    mov ebx, TY - 1
    mov ecx, TCOLS * CELL_W + 2
    mov edx, TROWS * CELL_H + 2
    mov byte [gui_ink], C_WHITE
    call gui_fill
    mov byte [gui_bg], C_WHITE
    call set_lang
    mov byte [lx_st], 0         ; the highlighting state at the view's top
    mov dword [lx_left], 0
    xor esi, esi
.pre:
    cmp esi, [top]
    jae .pred
    call lex
    inc esi
    jmp .pre
.pred:
    mov esi, [top]
    xor ebp, ebp                ; row
.row:
    cmp ebp, TROWS
    jae .status
    imul ebx, ebp, CELL_H
    add ebx, TY
    xor edi, edi                ; column in the line
.ch:
    cmp esi, [len]
    jae .eol
    mov dl, [text+esi]
    cmp dl, 10
    je .eol
    call lex
    mov [chcol], al
    call cell
    inc esi
    inc edi
    jmp .ch
.eol:
    call cell_cursor_end        ; the cursor after the last character
    cmp esi, [len]
    jae .nl
    call lex                    ; the newline ends comments and strings
.nl:
    inc esi                     ; past the newline
    inc ebp
    cmp esi, [len]
    jbe .row
.status:
    ; the status row: name, line and column, changes, message
    mov edi, line
    mov esi, name
    cmp byte [esi], 0
    jne .sn
    mov esi, s_untitled
.sn:
    call scopy
    cmp byte [dirty], 0
    je .clean
    mov al, '*'
    stosb
.clean:
    mov esi, s_line
    call scopy
    call where                  ; eax = line, ecx = column (from 1)
    call gui_utoa
    mov esi, s_col
    call scopy
    mov eax, ecx
    call gui_utoa
    mov ax, '  '
    stosw
    mov esi, [msg]
    test esi, esi
    jnz .m
    mov esi, s_help
.m:
    call scopy
    mov byte [edi], 0
    mov eax, TX
    mov ebx, STATUS_Y
    mov ecx, TCOLS * CELL_W
    mov esi, line
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_textn
    call gui_flip
    popad
    ret

; esi = text offset, edi = column, ebx = y, dl = character: draws it if
; the column is shown; inverted at the cursor.
cell:
    pushad
    sub edi, [left]
    jb .r
    cmp edi, TCOLS
    jae .r
    imul eax, edi, CELL_W
    add eax, TX
    mov cl, [chcol]
    mov [gui_ink], cl
    mov byte [gui_bg], C_WHITE
    cmp esi, [pos]
    jne .d
    mov byte [gui_ink], C_WHITE
    mov byte [gui_bg], C_BLACK
.d:
    call gui_char
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_WHITE
.r:
    popad
    ret

cell_cursor_end:
    cmp esi, [pos]
    jne .r
    push edx
    mov dl, ' '
    mov byte [chcol], C_BLACK
    call cell
    pop edx
.r:
    ret

; ---------- syntax highlighting ----------
L_NONE      equ 0
L_ASM       equ 1
L_C         equ 2
L_BAS       equ 3
LS_CODE     equ 0                       ; lexer states
LS_LINE     equ 1                       ; a comment to the line's end
LS_BLOCK    equ 2                       ; /* ... */
LS_STR      equ 3                       ; a string up to [lx_q]
COL_COMMENT equ C_GREEN
COL_STRING  equ C_MAGENTA
COL_NUMBER  equ C_RED
COL_KEYWORD equ C_BLUE
COL_DIRECT  equ C_CYAN
COL_LABEL   equ C_BROWN
COL_REG     equ C_BROWN

; name -> lang, from its extension
set_lang:
    pushad
    mov byte [lang], L_NONE
    mov esi, name
    xor edi, edi                ; the last dot
.f:
    mov al, [esi]
    test al, al
    jz .ext
    cmp al, '.'
    jne .n
    mov edi, esi
.n:
    inc esi
    jmp .f
.ext:
    test edi, edi
    jz .r
    inc edi
    mov ebx, lang_ext
.e:
    movzx ecx, byte [ebx]       ; length, then the extension, then lang
    jecxz .r
    lea esi, [ebx+1]
    push edi
    call ci_eq
    pop edi
    jne .next
    cmp byte [edi+ecx], 0
    jne .next
    mov al, [ebx+ecx+1]
    mov [lang], al
    jmp .r
.next:
    lea ebx, [ebx+ecx+2]
    jmp .e
.r:
    popad
    ret

; esi, edi, ecx = length -> ZF if the same, letters in either case
ci_eq:
    push eax
    push ecx
    push esi
    push edi
.c:
    jecxz .yes
    mov al, [esi]
    mov ah, [edi]
    call lower2
    cmp al, ah
    jne .no
    inc esi
    inc edi
    dec ecx
    jmp .c
.yes:
    cmp eax, eax
.no:
    pop edi
    pop esi
    pop ecx
    pop eax
    ret

lower2:
    cmp al, 'A'
    jb .a
    cmp al, 'Z'
    ja .a
    or al, 0x20
.a:
    cmp ah, 'A'
    jb .b
    cmp ah, 'Z'
    ja .b
    or ah, 0x20
.b:
    ret

; al -> ZF if it can be part of a name (letters, digits, _ . $)
is_word:
    cmp al, '_'
    je .y
    cmp al, '.'
    je .y
    cmp al, '$'
    je .y
    cmp al, '0'
    jb .n
    cmp al, '9'
    jbe .y
    push eax
    or al, 0x20
    cmp al, 'a'
    jb .n2
    cmp al, 'z'
    ja .n2
    pop eax
.y:
    cmp al, al
    ret
.n2:
    pop eax
.n:
    test esp, esp
    ret

; esi = text offset -> al = the colour of that character; moves the
; lexer on. Keeps the other registers.
lex:
    push ebx
    push ecx
    push edx
    push edi
    mov bl, [text+esi]
    mov al, C_BLACK
    cmp byte [lang], L_NONE
    je .r
    cmp bl, 10
    jne .notnl
    cmp byte [lx_st], LS_BLOCK
    je .nl
    mov byte [lx_st], LS_CODE
.nl:
    mov dword [lx_left], 0
    jmp .r
.notnl:
    cmp dword [lx_left], 0      ; the rest of a token already judged
    je .st
    dec dword [lx_left]
    mov al, [lx_col]
    jmp .r
.st:
    mov bh, [text+esi+1]        ; the next character
    cmp esi, [len]
    jb .nx
    xor bh, bh
.nx:
    mov cl, [lx_st]
    cmp cl, LS_LINE
    je .comment
    cmp cl, LS_BLOCK
    je .block
    cmp cl, LS_STR
    je .string
    ; code
    mov al, [lang]
    cmp al, L_ASM
    jne .c1
    cmp bl, ';'
    je .tocomment
    cmp bl, "'"
    je .tostring
    cmp bl, '%'
    je .word
    jmp .q
.c1:
    cmp al, L_C
    jne .b1
    cmp bl, '#'
    je .word
    cmp bl, '/'
    jne .q
    cmp bh, '/'
    je .tocomment
    cmp bh, '*'
    jne .q
    mov byte [lx_st], LS_BLOCK
    mov dword [lx_left], 1
    mov byte [lx_col], COL_COMMENT
    mov al, COL_COMMENT
    jmp .r
.b1:
    cmp bl, "'"
    je .tocomment
.q:
    cmp bl, '"'
    je .tostring
    mov al, bl                  ; a name or a number starts here?
    call is_word
    jne .black
    test esi, esi
    jz .word
    mov al, [text+esi-1]
    call is_word
    je .black                   ; inside one (not reached normally)
.word:
    mov edi, esi                ; its length
    inc edi
.wl:
    cmp edi, [len]
    jae .wd
    mov al, [text+edi]
    call is_word
    jne .wd
    inc edi
    jmp .wl
.wd:
    mov ecx, edi
    sub ecx, esi                ; ecx = length
    lea edx, [ecx-1]
    mov [lx_left], edx
    mov al, COL_NUMBER
    cmp bl, '0'
    jb .name
    cmp bl, '9'
    jbe .set
.name:
    mov al, COL_DIRECT
    cmp bl, '%'
    je .set
    cmp bl, '#'
    je .set
    cmp byte [lang], L_ASM      ; a label: from the line's start, then ':'
    jne .kw
    test esi, esi
    jz .lab
    cmp byte [text+esi-1], 10
    jne .kw
.lab:
    cmp edi, [len]
    jae .kw
    cmp byte [text+edi], ':'
    jne .kw
    mov [lx_left], ecx          ; the colon too
    mov al, COL_LABEL
    jmp .set
.kw:
    movzx eax, byte [lang]
    mov edx, [kw_lists+eax*4]
    call in_list
    jne .reg
    cmp byte [lang], L_BAS      ; REM: a comment
    jne .kwc
    cmp ecx, 3
    jne .kwc
    mov al, [text+esi]
    mov ah, 'r'
    call lower2
    cmp al, ah
    jne .kwc
    mov dword [lx_left], 0
    jmp .tocomment
.kwc:
    mov al, COL_KEYWORD
    jmp .set
.reg:
    cmp byte [lang], L_ASM
    jne .plain
    mov edx, asm_regs
    call in_list
    jne .plain
    mov al, COL_REG
    jmp .set
.plain:
    mov al, C_BLACK
.set:
    mov [lx_col], al
    jmp .r
.tocomment:
    mov byte [lx_st], LS_LINE
.comment:
    mov al, COL_COMMENT
    jmp .r
.block:
    mov al, COL_COMMENT
    cmp bl, '*'
    jne .r
    cmp bh, '/'
    jne .r
    mov byte [lx_st], LS_CODE
    mov dword [lx_left], 1
    mov byte [lx_col], COL_COMMENT
    jmp .r
.tostring:
    mov byte [lx_st], LS_STR
    mov [lx_q], bl
    mov al, COL_STRING
    jmp .r
.string:
    mov al, COL_STRING
    cmp byte [lang], L_C
    jne .sq
    cmp bl, '\'
    jne .sq
    mov dword [lx_left], 1      ; an escape: the next character too
    mov byte [lx_col], COL_STRING
    jmp .r
.sq:
    cmp bl, [lx_q]
    jne .r
    mov byte [lx_st], LS_CODE
    jmp .r
.black:
    mov al, C_BLACK
.r:
    pop edi
    pop edx
    pop ecx
    pop ebx
    ret

; text+esi, ecx = length, edx = list (words, zero after each, an empty
; word ends it) -> ZF if the word is in it (C: exact case, else any)
in_list:
    push eax
    push edi
    push edx
.w:
    cmp byte [edx], 0
    je .no
    mov edi, edx                ; the list word's length
    xor eax, eax
.l:
    cmp byte [edi+eax], 0
    je .len
    inc eax
    jmp .l
.len:
    cmp eax, ecx
    jne .next
    push esi
    lea esi, [text+esi]
    cmp byte [lang], L_C
    je .exact
    call ci_eq
    jmp .cmp
.exact:
    push ecx
    push edi
    repe cmpsb
    pop edi
    pop ecx
.cmp:
    pop esi
    je .yes
.next:
    lea edx, [edx+eax+1]
    jmp .w
.no:
    test esp, esp
    jmp .r
.yes:
    cmp eax, eax
.r:
    pop edx
    pop edi
    pop eax
    ret

; -> eax = the cursor's line, ecx = its column (both from 1)
where:
    push esi
    xor esi, esi
    mov eax, 1
    mov ecx, 1
.c:
    cmp esi, [pos]
    jae .r
    inc ecx
    cmp byte [text+esi], 10
    jne .n
    inc eax
    mov ecx, 1
.n:
    inc esi
    jmp .c
.r:
    pop esi
    ret

; esi -> edi without the zero
scopy:
    lodsb
    test al, al
    jz .r
    stosb
    jmp scopy
.r:
    ret

; ---------- files ----------
load:
    pushad
    call empty
    mov eax, SYS_OPEN
    mov ebx, name
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .new
    mov ebx, eax
    mov eax, SYS_READ
    mov ecx, text
    mov edx, TEXT_MAX
    int 0x80
    test eax, eax
    jns .got
    xor eax, eax
.got:
    mov [len], eax
    mov eax, SYS_CLOSE
    int 0x80
    mov dword [msg], m_loaded
    popad
    ret
.new:
    mov dword [msg], m_newfile
    popad
    ret

save:
    pushad
    cmp byte [name], 0
    jne .go
    mov esi, q_save
    call ask_name
    jc .r
.go:
    mov eax, SYS_OPEN
    mov ebx, name
    mov ecx, O_CREATE | O_TRUNC
    int 0x80
    test eax, eax
    js .fail
    mov ebx, eax
    mov eax, SYS_WRITE
    mov ecx, text
    mov edx, [len]
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    int 0x80
    pop eax
    cmp eax, [len]
    jne .fail
    mov byte [dirty], 0
    mov dword [msg], m_saved
.r:
    popad
    ret
.fail:
    mov dword [msg], m_failed
    popad
    ret

; With unsaved changes: "Save changes? y/n" (y saves, n drops them,
; Esc goes back). CF to go back.
ask_unsaved:
    cmp byte [dirty], 0
    je .ok
    mov dword [msg], q_unsaved
    call draw
.k:
    call gui_getkey
    cmp ah, K_ESC
    je .back
    or al, 0x20
    cmp al, 'n'
    je .ok
    cmp al, 'y'
    jne .k
    call save
    cmp byte [dirty], 0
    jne .back
.ok:
    mov dword [msg], 0
    clc
    ret
.back:
    stc
    ret

; esi = question: a file name typed on the status row into name.
; CF if Esc or nothing typed.
ask_name:
    pushad
    mov [ask_q], esi
    mov edi, ask_buf
    xor ecx, ecx
.draw:
    mov byte [ask_buf+ecx], 0
    push ecx
    mov edi, line
    mov esi, [ask_q]
    call scopy
    mov esi, ask_buf
    call scopy
    mov al, '_'
    stosb
    mov byte [edi], 0
    mov eax, TX                 ; the status row only
    mov ebx, STATUS_Y
    mov ecx, TCOLS * CELL_W
    mov edx, CELL_H
    mov byte [gui_ink], C_LGREY
    call gui_fill
    mov esi, line
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_textn
    call gui_flip
    pop ecx
.k:
    call gui_getkey
    cmp ah, K_ESC
    je .no
    cmp ah, K_ENTER
    je .done
    cmp ah, K_BKSP
    je .bs
    cmp al, ' '
    jbe .k
    cmp al, '~'
    ja .k
    cmp ecx, NAME_MAX
    jae .k
    mov [ask_buf+ecx], al
    inc ecx
    jmp .draw
.bs:
    jecxz .k
    dec ecx
    jmp .draw
.done:
    jecxz .no
    mov esi, ask_buf
    mov edi, name
    call copy_name
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; esi = name -> edi, at most NAME_MAX characters, up to a space or zero
copy_name:
    push ecx
    mov ecx, NAME_MAX
.c:
    lodsb
    cmp al, ' '
    jbe .e
    stosb
    loop .c
.e:
    mov byte [edi], 0
    pop ecx
    ret

; ---------- self-check ----------
; ecx = text offset of a character on the first rows (no scrolling):
; CF unless its cell holds a pixel of colour dl
cell_has:
    pushad
    xor eax, eax                ; its row and column
    xor ebx, ebx
    xor esi, esi
.f:
    cmp esi, ecx
    jae .got
    inc eax
    cmp byte [text+esi], 10
    jne .n
    inc ebx
    xor eax, eax
.n:
    inc esi
    jmp .f
.got:
    imul eax, CELL_W
    add eax, TX
    imul ebx, CELL_H
    add ebx, TY
    mov esi, CELL_H
.y:
    mov edi, CELL_W
.x:
    push ecx
    call gui_peek
    cmp cl, dl
    pop ecx
    je .yes
    inc eax
    dec edi
    jnz .x
    sub eax, CELL_W
    inc ebx
    dec esi
    jnz .y
    popad
    stc
    ret
.yes:
    popad
    clc
    ret

selftest:
    mov ebp, st_cases
.case:
    mov esi, [ebp]              ; name, text, then offset / colour pairs
    test esi, esi
    jz .pass
    mov edi, name
    call copy_name
    mov esi, [ebp+4]
    mov edi, text
    xor ecx, ecx
.copy:
    lodsb
    test al, al
    jz .copied
    stosb
    inc ecx
    jmp .copy
.copied:
    mov [len], ecx
    mov dword [pos], 0x7FFF     ; no cursor on the checked cells
    mov dword [top], 0
    mov dword [left], 0
    call draw
    lea ebx, [ebp+8]
.chk:
    mov ecx, [ebx]
    cmp ecx, -1
    je .nextcase
    mov edx, [ebx+4]
    call cell_has
    jc .fail
    add ebx, 8
    jmp .chk
.nextcase:
    lea ebp, [ebx+4]
    jmp .case
.pass:
    call gui_close
    mov esi, s_pass
    call gui_puts
    xor eax, eax
    ret
.fail:
    mov [s_bad], cl             ; the offset that failed, as a letter
    add byte [s_bad], 'A'
    call gui_close
    mov esi, s_fail
    call gui_puts
    mov esi, [ebp]
    call gui_puts
    mov esi, s_bad
    call gui_puts
    mov eax, 1
    ret

st_cases:
    ;    0123456789012345678
    dd t_asm1, x_asm1           ; "start: mov eax, 5 ; go"
    dd 0, COL_LABEL, 7, COL_KEYWORD, 11, COL_REG, 16, COL_NUMBER
    dd 18, COL_COMMENT, 21, COL_COMMENT, -1
    dd t_c1, x_c1               ; "#include x\nint a = 1; /* c\nd */ \"s\""
    dd 0, COL_DIRECT, 11, COL_KEYWORD, 19, COL_NUMBER, 22, COL_COMMENT
    dd 27, COL_COMMENT, 33, COL_STRING, -1
    dd t_b1, x_b1               ; "10 PRINT \"hi\"\n20 REM no"
    dd 0, COL_NUMBER, 3, COL_KEYWORD, 9, COL_STRING, 17, COL_COMMENT
    dd 21, COL_COMMENT, -1
    dd 0
t_asm1 db 'a.asm', 0
x_asm1 db 'start: mov eax, 5 ; go', 0
t_c1 db 'b.c', 0
x_c1 db '#include x', 10, 'int a = 1; /* c', 10, 'd */ "s"', 0
t_b1 db 'c.bas', 0
x_b1 db '10 PRINT "hi"', 10, '20 REM no', 0
s_pass db 'notepad: PASS', 10, 0
s_fail db 'notepad: FAIL ', 0
s_bad db '?', 10, 0

lang_ext db 3, 'asm', L_ASM, 3, 'inc', L_ASM, 1, 'c', L_C, 1, 'h', L_C
         db 3, 'bas', L_BAS, 0
kw_lists dd kw_none, kw_asm, kw_c, kw_bas
kw_none db 0
kw_asm db 'mov', 0, 'movzx', 0, 'movsx', 0, 'lea', 0, 'add', 0, 'sub', 0
       db 'adc', 0, 'sbb', 0, 'inc', 0, 'dec', 0, 'neg', 0, 'not', 0
       db 'and', 0, 'or', 0, 'xor', 0, 'test', 0, 'cmp', 0, 'shl', 0
       db 'shr', 0, 'sar', 0, 'rol', 0, 'ror', 0, 'mul', 0, 'imul', 0
       db 'div', 0, 'idiv', 0, 'jmp', 0, 'je', 0, 'jne', 0, 'jz', 0
       db 'jnz', 0, 'ja', 0, 'jae', 0, 'jb', 0, 'jbe', 0, 'jg', 0
       db 'jge', 0, 'jl', 0, 'jle', 0, 'js', 0, 'jns', 0, 'jc', 0
       db 'jnc', 0, 'jecxz', 0, 'loop', 0, 'call', 0, 'ret', 0, 'push', 0
       db 'pop', 0, 'pushad', 0, 'popad', 0, 'int', 0, 'iretd', 0, 'xchg', 0
       db 'rep', 0, 'movsb', 0, 'movsd', 0, 'stosb', 0, 'stosd', 0
       db 'lodsb', 0, 'cld', 0, 'std', 0, 'cli', 0, 'sti', 0, 'hlt', 0
       db 'nop', 0, 'in', 0, 'out', 0, 'db', 0, 'dw', 0, 'dd', 0, 'dq', 0
       db 'resb', 0, 'resw', 0, 'resd', 0, 'resq', 0, 'equ', 0
       db 'times', 0, 'org', 0, 'bits', 0, 'section', 0, 'align', 0
       db 'byte', 0, 'word', 0, 'dword', 0, 'qword', 0, 0
asm_regs db 'eax', 0, 'ebx', 0, 'ecx', 0, 'edx', 0, 'esi', 0, 'edi', 0
         db 'ebp', 0, 'esp', 0, 'ax', 0, 'bx', 0, 'cx', 0, 'dx', 0
         db 'si', 0, 'di', 0, 'bp', 0, 'sp', 0, 'al', 0, 'ah', 0, 'bl', 0
         db 'bh', 0, 'cl', 0, 'ch', 0, 'dl', 0, 'dh', 0, 'cs', 0, 'ds', 0
         db 'es', 0, 'ss', 0, 'fs', 0, 'gs', 0, 0
kw_c db 'int', 0, 'char', 0, 'void', 0, 'if', 0, 'else', 0, 'while', 0
     db 'for', 0, 'do', 0, 'return', 0, 'struct', 0, 'union', 0, 'enum', 0
     db 'const', 0, 'unsigned', 0, 'signed', 0, 'long', 0, 'short', 0
     db 'static', 0, 'extern', 0, 'switch', 0, 'case', 0, 'default', 0
     db 'break', 0, 'continue', 0, 'goto', 0, 'sizeof', 0, 'typedef', 0
     db 'float', 0, 'double', 0, 'volatile', 0, 0
kw_bas db 'print', 0, 'input', 0, 'if', 0, 'then', 0, 'else', 0, 'for', 0
       db 'to', 0, 'step', 0, 'next', 0, 'goto', 0, 'gosub', 0, 'return', 0
       db 'end', 0, 'let', 0, 'dim', 0, 'while', 0, 'wend', 0, 'and', 0
       db 'or', 0, 'not', 0, 'rem', 0, 0

title db 'Notepad', 0
s_dash db ' - ', 0
s_untitled db '(untitled)', 0
s_line db '  Ln ', 0
s_col db ' Col ', 0
s_help db '^S save ^O open Esc quit', 0
m_full db 'Full (16 KB)', 0
m_loaded db 'Opened', 0
m_newfile db 'New file', 0
m_saved db 'Saved', 0
m_failed db 'Not saved!', 0
q_unsaved db 'Save changes? y/n', 0
q_save db 'Save as: ', 0
q_open db 'Open: ', 0
m_nogfx db 'notepad: no graphics', 10, 0

SQX_BSS
GUI_BSS
pos resd 1
len resd 1
top resd 1
left resd 1
msg resd 1
ask_q resd 1
dirty resb 1
lang resb 1
lx_st resb 1
lx_q resb 1
lx_col resb 1
chcol resb 1
alignb 4
lx_left resd 1
name resb NAME_MAX + 1
ask_buf resb NAME_MAX + 1
line resb 128
text resb TEXT_MAX + 1
SQX_END
