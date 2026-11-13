; Squirrel-OS/2 — Write: a simple word processor (A.7, OS2-APPS)
; Original code. run write [file]   |   run write test
;
; Paragraphs wrap at word boundaries to the page's width (50 columns).
; Characters can be bold, italic and underlined; each paragraph is
; aligned left, centred or right.
;
;   typing, Enter         insert (a new paragraph keeps the alignment)
;   Backspace, Delete     remove (the selection, if there is one)
;   arrows, Home, End     move (Up/Down by wrapped line; Home/End of it)
;   PgUp, PgDn            a page          Ctrl+Home/End  the document
;   F3                    start a selection at the cursor; moving the
;                         cursor extends it (a mouse drag selects too)
;   Ctrl+B, Ctrl+I, Ctrl+U  bold, italic, underline: of the selection,
;                         or of what is typed next
;   Ctrl+L, Ctrl+E, Ctrl+R  align the paragraph left, centre, right
;   Ctrl+S save   Ctrl+O open   Ctrl+N new   Esc  drop the selection,
;                         or quit (asking if there are unsaved changes)
;
; Files: a name ending in .txt is plain text (styles are dropped);
; anything else is saved as SQWP: "SQWP1", the length, the text, then a
; style byte for each character. Opening a file that is not SQWP reads
; it as plain text. "run write test" checks wrapping, styles, alignment
; and both file forms, and prints "write: PASS".
; See documentation/apps/write.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

TEXT_MAX    equ 12000
LINES_MAX   equ 2400
COLS        equ 50
ROWS        equ 19
NAME_MAX    equ 60
LX          equ 10                      ; the page's left edge
TY          equ 15
LINE_H      equ CELL_H + 1
STAT_Y      equ SCR_H - CELL_H - 2
K_F3        equ 0x3D

A_BOLD      equ 1                       ; style bits of a character
A_ITAL      equ 2
A_UNDER     equ 4
A_ALIGN     equ 0x30                    ; of a paragraph's newline:
AL_LEFT     equ 0x00
AL_CENTRE   equ 0x10
AL_RIGHT    equ 0x20

main:
    mov esi, [esp+4]
    mov [arg], esi
    mov eax, SYS_SBRK           ; the file buffer
    mov ebx, 2 * TEXT_MAX + 16
    int 0x80
    cmp eax, -1
    je .nogfx
    mov [fbufp], eax
    call empty
    call gui_open
    jc .nogfx
    mov esi, [arg]
    test esi, esi
    jz .draw
    cmp dword [esi], 'test'
    jne .file
    cmp byte [esi+4], 0
    je selftest
.file:
    cmp byte [esi], 0
    je .draw
    mov edi, name
    call copy_name
    call load
.draw:
    call layout
    call draw
.key:
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .click
    test eax, EV_DRAG
    jnz .drag
    call key
    jnc .draw
    call gui_close
    xor eax, eax
    ret
.click:
    call pos_at_mouse
    jc .key
    mov [cur], eax
    mov dword [anchor], -1
    jmp .draw
.drag:
    call pos_at_mouse
    jc .key
    cmp dword [anchor], -1
    jne .d
    mov ecx, [cur]
    mov [anchor], ecx
.d:
    mov [cur], eax
    jmp .draw
.nogfx:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
    ret

; An empty document: one empty paragraph
empty:
    mov byte [text], 10
    mov byte [attr], 0
    mov dword [len], 1
    mov dword [cur], 0
    mov dword [anchor], -1
    mov dword [top], 0
    mov byte [tstyle], 0
    mov byte [dirty], 0
    ret

; eax = key -> CF to quit
key:
    pushad
    mov dword [msg], 0
    movzx ebx, ah
    test eax, 1 << 16
    jnz .ctrl
    cmp bl, K_ESC
    je .esc
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
    cmp bl, K_F3
    je .mark
    cmp bl, K_BKSP
    je .bksp
    cmp bl, K_DEL
    je .del
    cmp bl, K_ENTER
    je .enter
    cmp al, ' '
    jb .ok
    cmp al, '~'
    ja .ok
    call type_char
    jmp .ok
.ctrl:
    cmp bl, K_HOME
    je .dtop
    cmp bl, K_END
    je .dend
    and al, 0xDF
    cmp al, 'B'
    je .bold
    cmp al, 'I'
    je .ital
    cmp al, 'U'
    je .under
    cmp al, 'L'
    je .al
    cmp al, 'E'
    je .ac
    cmp al, 'R'
    je .ar
    cmp al, 'S'
    je .save
    cmp al, 'O'
    je .open
    cmp al, 'N'
    je .new
    jmp .ok
.bold:
    mov al, A_BOLD
    jmp .style
.ital:
    mov al, A_ITAL
    jmp .style
.under:
    mov al, A_UNDER
.style:
    call toggle_style
    jmp .ok
.al:
    mov al, AL_LEFT
    jmp .align
.ac:
    mov al, AL_CENTRE
    jmp .align
.ar:
    mov al, AL_RIGHT
.align:
    call set_align
    jmp .ok
.save:
    call save
    jmp .ok
.open:
    call ask_unsaved
    jc .ok
    mov esi, q_open
    call ask_name
    jc .ok
    call load
    jmp .ok
.new:
    call ask_unsaved
    jc .ok
    call empty
    mov byte [name], 0
    jmp .ok
.esc:
    cmp dword [anchor], -1
    je .quit
    mov dword [anchor], -1
    jmp .ok
.quit:
    call ask_unsaved
    jc .ok
    popad
    stc
    ret
.left:
    cmp dword [cur], 0
    je .ok
    dec dword [cur]
    jmp .ok
.right:
    mov eax, [cur]
    inc eax
    cmp eax, [len]
    jae .ok
    mov [cur], eax
    jmp .ok
.up:
    mov ecx, -1
    jmp .vert
.down:
    mov ecx, 1
    jmp .vert
.pgup:
    mov ecx, -ROWS
    jmp .vert
.pgdn:
    mov ecx, ROWS
.vert:
    call move_lines
    jmp .ok
.home:
    call cur_line
    mov eax, [lstart+eax*4]
    mov [cur], eax
    jmp .ok
.end:
    call cur_line
    mov ecx, [lstart+eax*4]
    add ecx, [llen+eax*4]
    mov [cur], ecx
    jmp .ok
.dtop:
    mov dword [cur], 0
    jmp .ok
.dend:
    mov eax, [len]
    dec eax
    mov [cur], eax
    jmp .ok
.mark:
    mov eax, [cur]
    mov [anchor], eax
    jmp .ok
.bksp:
    call delete_selection
    jnc .ok
    cmp dword [cur], 0
    je .ok
    dec dword [cur]
    mov eax, [cur]
    mov ecx, 1
    call remove
    jmp .ok
.del:
    call delete_selection
    jnc .ok
    mov eax, [cur]
    inc eax
    cmp eax, [len]              ; the last newline stays
    jae .ok
    dec eax
    mov ecx, 1
    call remove
    jmp .ok
.enter:
    call delete_selection
    call para_end               ; the new paragraph's alignment
    mov ah, [attr+eax]
    and ah, A_ALIGN
    mov al, 10
    call insert
.ok:
    call layout
    popad
    clc
    ret

; al = character: replaces the selection, typed in the typing style
type_char:
    push eax
    call delete_selection
    pop eax
    mov ah, [tstyle]
    jmp insert

; al = character, ah = its style: inserted at the cursor
insert:
    pushad
    mov ecx, [len]
    cmp ecx, TEXT_MAX
    jae .full
    sub ecx, [cur]              ; the characters from the cursor move up
    mov esi, [len]
    dec esi
.mv:
    jecxz .put
    mov dl, [text+esi]
    mov [text+esi+1], dl
    mov dl, [attr+esi]
    mov [attr+esi+1], dl
    dec esi
    dec ecx
    jmp .mv
.put:
    mov ebx, [cur]
    mov [text+ebx], al
    mov [attr+ebx], ah
    inc dword [len]
    inc dword [cur]
    mov byte [dirty], 1
    popad
    ret
.full:
    mov dword [msg], m_full
    popad
    ret

; eax = position, ecx = count: removed (the cursor and anchor follow)
remove:
    pushad
    mov esi, eax
    add esi, ecx
    mov edi, eax
.mv:
    cmp esi, [len]
    jae .done
    mov dl, [text+esi]
    mov [text+edi], dl
    mov dl, [attr+esi]
    mov [attr+edi], dl
    inc esi
    inc edi
    jmp .mv
.done:
    sub [len], ecx
    mov [cur], eax
    mov dword [anchor], -1
    mov byte [dirty], 1
    popad
    ret

; -> eax, ecx = the selection's start and end (end not included), or CF
selection:
    mov eax, [anchor]
    cmp eax, -1
    je .no
    mov ecx, [cur]
    cmp eax, ecx
    je .no
    jb .ok
    xchg eax, ecx
.ok:
    clc
    ret
.no:
    stc
    ret

; The selection removed (CF clear), or CF if there was none. The final
; newline stays.
delete_selection:
    call selection
    jc .r
    mov edx, [len]
    dec edx
    cmp ecx, edx
    jbe .c
    mov ecx, edx
.c:
    sub ecx, eax
    jz .none
    call remove
    clc
    ret
.none:
    mov dword [anchor], -1
    clc
.r:
    ret

; al = style bit: toggled on the selection (set unless all have it), or
; on the typing style
toggle_style:
    pushad
    mov dl, al
    call selection
    jc .typing
    mov esi, eax
.all:                           ; do they all have it?
    cmp esi, ecx
    jae .clear
    cmp byte [text+esi], 10
    je .an
    test [attr+esi], dl
    jz .set
.an:
    inc esi
    jmp .all
.clear:
    not dl
.cl:
    cmp eax, ecx
    jae .done
    cmp byte [text+eax], 10
    je .cn
    and [attr+eax], dl
.cn:
    inc eax
    jmp .cl
.set:
    cmp eax, ecx
    jae .done
    cmp byte [text+eax], 10
    je .sn
    or [attr+eax], dl
.sn:
    inc eax
    jmp .set
.done:
    mov byte [dirty], 1
    popad
    ret
.typing:
    xor [tstyle], dl
    popad
    ret

; al = alignment: of the paragraphs from the cursor's (or the
; selection's start) to the selection's end
set_align:
    pushad
    mov dl, al
    call selection
    jnc .range
    mov eax, [cur]
    mov ecx, eax
.range:
    mov esi, ecx                ; the last paragraph's newline
.f:
    cmp byte [text+esi], 10
    je .got
    inc esi
    jmp .f
.got:
.n:
    cmp eax, esi
    ja .done
    cmp byte [text+eax], 10
    jne .s
    and byte [attr+eax], ~A_ALIGN
    or [attr+eax], dl
.s:
    inc eax
    jmp .n
.done:
    mov byte [dirty], 1
    popad
    ret

; -> eax = the newline that ends the cursor's paragraph
para_end:
    mov eax, [cur]
.f:
    cmp byte [text+eax], 10
    je .r
    inc eax
    jmp .f
.r:
    ret

; ---------- layout ----------
; The text -> lines: lstart, llen (shown characters), lalign; nlines.
; A paragraph breaks after the last space that fits in COLS, or at COLS
; inside a longer word. The view follows the cursor.
layout:
    pushad
    xor ebx, ebx                ; line
    xor esi, esi                ; paragraph start
.para:
    cmp esi, [len]
    jae .done
    mov edi, esi                ; its newline
.nl:
    cmp byte [text+edi], 10
    je .gotnl
    inc edi
    jmp .nl
.gotnl:
    mov al, [attr+edi]
    and al, A_ALIGN
    mov [palign], al
.line:
    cmp ebx, LINES_MAX
    jae .done
    mov [lstart+ebx*4], esi
    mov al, [palign]
    mov [lalign+ebx], al
    mov ecx, edi
    sub ecx, esi                ; what is left of the paragraph
    cmp ecx, COLS
    ja .wrap
    mov [llen+ebx*4], ecx
    inc ebx
    lea esi, [edi+1]
    jmp .para
.wrap:
    lea edx, [esi+COLS]         ; the last space at or before COLS
.sp:
    cmp edx, esi
    je .hard
    cmp byte [text+edx], ' '
    je .soft
    dec edx
    jmp .sp
.soft:
    mov ecx, edx
    sub ecx, esi
    mov [llen+ebx*4], ecx
    inc ebx
    lea esi, [edx+1]
    jmp .line
.hard:
    mov dword [llen+ebx*4], COLS
    inc ebx
    add esi, COLS
    jmp .line
.done:
    mov [nlines], ebx
    call cur_line               ; the view on the cursor
    cmp eax, [top]
    jae .b
    mov [top], eax
.b:
    sub eax, ROWS - 1
    jbe .r
    cmp eax, [top]
    jbe .r
    mov [top], eax
.r:
    popad
    ret

; -> eax = the line holding the cursor
cur_line:
    push ecx
    push edx
    mov edx, [cur]
    xor eax, eax
.f:
    lea ecx, [eax+1]
    cmp ecx, [nlines]
    jae .r
    cmp [lstart+ecx*4], edx
    ja .r
    mov eax, ecx
    jmp .f
.r:
    pop edx
    pop ecx
    ret

; ecx = lines to move (signed): the cursor keeps its column
move_lines:
    call cur_line
    mov edx, [cur]
    sub edx, [lstart+eax*4]     ; the column
    add eax, ecx
    jns .lo
    xor eax, eax
.lo:
    mov ecx, [nlines]
    dec ecx
    cmp eax, ecx
    jbe .hi
    mov eax, ecx
.hi:
    cmp edx, [llen+eax*4]
    jbe .c
    mov edx, [llen+eax*4]
.c:
    add edx, [lstart+eax*4]
    mov [cur], edx
    ret

; eax = line -> ecx = the x of its first character
line_x:
    push eax
    push edx
    mov edx, COLS
    sub edx, [llen+eax*4]
    mov cl, [lalign+eax]
    cmp cl, AL_CENTRE
    je .c
    cmp cl, AL_RIGHT
    je .r
    xor edx, edx
    jmp .x
.c:
    shr edx, 1
    jmp .x
.r:
.x:
    imul ecx, edx, CELL_W
    add ecx, LX
    pop edx
    pop eax
    ret

; gui_mx, gui_my -> eax = the text position there, or CF
pos_at_mouse:
    mov eax, [gui_my]
    sub eax, TY
    js .no
    xor edx, edx
    mov ecx, LINE_H
    div ecx
    cmp eax, ROWS
    jae .no
    add eax, [top]
    cmp eax, [nlines]
    jb .in
    mov eax, [nlines]
    dec eax
.in:
    call line_x
    mov edx, [gui_mx]
    sub edx, ecx
    jns .p
    xor edx, edx
.p:
    add edx, CELL_W / 2         ; the nearest gap between characters
    push eax
    mov eax, edx
    xor edx, edx
    mov ecx, CELL_W
    div ecx
    mov edx, eax
    pop eax
    cmp edx, [llen+eax*4]
    jbe .c
    mov edx, [llen+eax*4]
.c:
    add edx, [lstart+eax*4]
    mov eax, edx
    clc
    ret
.no:
    stc
    ret

; ---------- drawing ----------
draw:
    pushad
    mov edi, line               ; "Write - name"
    mov esi, s_title
    call scopy
    cmp byte [name], 0
    je .t
    mov esi, s_dash
    call scopy
    mov esi, name
    call scopy
.t:
    xor eax, eax
    xor ebx, ebx
    mov ecx, SCR_W
    mov edx, SCR_H
    mov esi, line
    call gui_window
    mov eax, 2                  ; the page
    mov ebx, TY - 2
    mov ecx, SCR_W - 4
    mov edx, ROWS * LINE_H + 3
    mov byte [gui_ink], C_WHITE
    call gui_fill
    call selection
    jnc .sel
    mov eax, -1
    mov ecx, -1
.sel:
    mov [sel0], eax
    mov [sel1], ecx
    xor ebp, ebp
.row:
    mov eax, [top]
    add eax, ebp
    cmp eax, [nlines]
    jae .rows
    mov [dline], eax
    imul ebx, ebp, LINE_H
    add ebx, TY
    mov [dy_], ebx
    call line_x
    mov [dx_], ecx
    mov esi, [lstart+eax*4]
    mov edi, [llen+eax*4]
    add edi, esi
.ch:
    cmp esi, edi
    jae .nr
    call glyph
    add dword [dx_], CELL_W
    inc esi
    jmp .ch
.nr:
    inc ebp
    cmp ebp, ROWS
    jb .row
.rows:
    call draw_cursor
    call status
    call gui_flip
    popad
    ret

; The cursor: a two-pixel bar before its character
draw_cursor:
    pushad
    call cur_line
    mov ebx, eax
    sub ebx, [top]
    js .r
    cmp ebx, ROWS
    jae .r
    imul ebx, LINE_H
    add ebx, TY - 1
    call line_x
    mov edx, [cur]
    sub edx, [lstart+eax*4]
    imul edx, CELL_W
    lea eax, [ecx+edx-1]
    mov ecx, 2
    mov edx, LINE_H
    mov byte [gui_ink], C_BLACK
    call gui_fill
.r:
    popad
    ret

; esi = text position at dx_, dy_: the character in its style, on the
; selection colour if selected
glyph:
    pushad
    cmp esi, [sel0]
    jb .nosel
    cmp esi, [sel1]
    jae .nosel
    mov eax, [dx_]
    mov ebx, [dy_]
    dec ebx
    mov ecx, CELL_W
    mov edx, LINE_H
    mov byte [gui_ink], C_LCYAN
    call gui_fill
.nosel:
    mov bl, [attr+esi]
    mov [gstyle], bl
    movzx eax, byte [text+esi]
    cmp eax, FONT_FIRST
    jb .r
    cmp eax, FONT_LAST
    ja .r
    sub eax, FONT_FIRST
    imul eax, FONT_H
    lea esi, [gui_font+eax]
    xor ebp, ebp                ; row
.row:
    movzx edx, byte [esi+ebp]
    mov edi, [dx_]
    test byte [gstyle], A_ITAL  ; italic: the top rows lean right
    jz .noit
    cmp ebp, 3
    jae .noit
    inc edi
.noit:
    mov ebx, [dy_]
    add ebx, ebp
    mov ecx, 5                  ; columns 0..4: bits 4..0
.col:
    test edx, 1 << 4
    jz .nb
    mov eax, edi
    push ecx
    mov cl, C_BLACK
    call gui_pset
    test byte [gstyle], A_BOLD
    jz .nob
    inc eax
    call gui_pset
.nob:
    pop ecx
.nb:
    shl edx, 1
    inc edi
    loop .col
    inc ebp
    cmp ebp, FONT_H
    jb .row
    test byte [gstyle], A_UNDER
    jz .r
    mov eax, [dx_]
    mov ebx, [dy_]
    add ebx, FONT_H
    mov ecx, eax
    add ecx, CELL_W - 1
    mov edx, ebx
    mov byte [gui_ink], C_BLACK
    call gui_line
.r:
    popad
    ret

; The status row: a message, or the styles, alignment, counts, name
status:
    pushad
    mov eax, 2
    mov ebx, STAT_Y
    mov ecx, SCR_W - 4
    mov edx, CELL_H
    mov byte [gui_ink], C_LGREY
    call gui_fill
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    mov esi, [msg]
    test esi, esi
    jnz .out
    mov edi, line
    mov al, [tstyle]            ; "B I U" for the typing style
    mov ah, 'B'
    test al, A_BOLD
    jnz .b
    mov ah, '-'
.b:
    mov [edi], ah
    mov ah, 'I'
    test al, A_ITAL
    jnz .i
    mov ah, '-'
.i:
    mov [edi+1], ah
    mov ah, 'U'
    test al, A_UNDER
    jnz .u
    mov ah, '-'
.u:
    mov [edi+2], ah
    add edi, 3
    call para_end               ; the paragraph's alignment
    movzx eax, byte [attr+eax]
    and eax, A_ALIGN
    shr eax, 4
    mov esi, [align_name+eax*4]
    call scopy
    mov esi, s_words
    call scopy
    call count_words
    call gui_utoa
    mov esi, s_chars
    call scopy
    mov eax, [len]
    dec eax
    call gui_utoa
    cmp byte [dirty], 0
    je .k
    mov ax, ' *'
    stosw
    mov byte [edi], 0
.k:
    mov esi, s_keys
    call scopy
    mov esi, line
.out:
    mov eax, 2
    mov ebx, STAT_Y
    mov ecx, SCR_W - 4
    call gui_textn
    popad
    ret

; -> eax = words: runs of characters other than space and newline
count_words:
    push ecx
    push edx
    xor eax, eax
    xor ecx, ecx
    xor edx, edx                ; inside a word
.c:
    cmp ecx, [len]
    jae .r
    mov dl, [text+ecx]
    cmp dl, ' '
    je .gap
    cmp dl, 10
    je .gap
    cmp dh, 0
    jne .n
    inc eax
    mov dh, 1
    jmp .n
.gap:
    mov dh, 0
.n:
    inc ecx
    jmp .c
.r:
    pop edx
    pop ecx
    ret

; ---------- files ----------
; -> ZF if name ends in ".txt"
is_txt:
    push eax
    push esi
    mov esi, name
.e:
    cmp byte [esi], 0
    je .end
    inc esi
    jmp .e
.end:
    sub esi, 4
    cmp esi, name
    jb .no
    mov eax, [esi]
    or eax, 0x20202000
    cmp eax, '.txt'
    jmp .r
.no:
    test esp, esp
.r:
    pop esi
    pop eax
    ret

load:
    pushad
    mov ebp, [fbufp]
    call empty
    mov eax, SYS_OPEN
    mov ebx, name
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .new
    mov ebx, eax
    mov eax, SYS_READ
    mov ecx, ebp
    mov edx, 2 * TEXT_MAX + 16
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    int 0x80
    pop ecx
    test ecx, ecx
    jns .got
    xor ecx, ecx
.got:
    cmp ecx, 9
    jb .plain
    cmp dword [ebp], 'SQWP'
    jne .plain
    cmp byte [ebp+4], '1'
    jne .plain
    mov eax, [ebp+5]           ; SQWP: the length, the text, the styles
    cmp eax, TEXT_MAX
    ja .plain
    lea edx, [eax*2+9]
    cmp ecx, edx
    jb .plain
    mov [len], eax
    mov ecx, eax
    lea esi, [ebp+9]
    mov edi, text
    rep movsb
    mov ecx, eax
    mov edi, attr
    rep movsb
    jmp .fix
.plain:                         ; plain text: no styles, no returns
    xor esi, esi
    xor edi, edi
.p:
    cmp esi, ecx
    jae .pd
    cmp edi, TEXT_MAX - 1
    jae .pd
    mov al, [ebp+esi]
    inc esi
    cmp al, 13
    je .p
    cmp al, 9
    jne .nt
    mov al, ' '
.nt:
    mov [text+edi], al
    mov byte [attr+edi], 0
    inc edi
    jmp .p
.pd:
    mov [len], edi
.fix:                           ; the text ends with a newline
    mov eax, [len]
    test eax, eax
    jz .addnl
    cmp byte [text+eax-1], 10
    je .ok
.addnl:
    mov byte [text+eax], 10
    mov byte [attr+eax], 0
    inc dword [len]
.ok:
    mov dword [cur], 0
    mov byte [dirty], 0
    mov dword [msg], m_opened
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
    mov ebp, [fbufp]
    call is_txt
    je .txt
    mov dword [ebp], 'SQWP'
    mov byte [ebp+4], '1'
    mov ecx, [len]
    mov [ebp+5], ecx
    mov esi, text
    lea edi, [ebp+9]
    rep movsb
    mov ecx, [len]
    mov esi, attr
    rep movsb
    mov ecx, [len]
    lea ecx, [ecx*2+9]
    jmp .write
.txt:
    mov ecx, [len]
    mov esi, text
    mov edi, ebp
    rep movsb
    mov ecx, [len]
.write:
    mov [flen], ecx
    mov eax, SYS_OPEN
    mov ebx, name
    mov ecx, O_CREATE | O_TRUNC
    int 0x80
    test eax, eax
    js .fail
    mov ebx, eax
    mov eax, SYS_WRITE
    mov ecx, ebp
    mov edx, [flen]
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    int 0x80
    pop eax
    cmp eax, [flen]
    jne .fail
    mov byte [dirty], 0
    mov dword [msg], m_saved
.r:
    popad
    clc
    ret
.fail:
    mov dword [msg], m_nosave
    popad
    stc
    ret

; -> CF to stay: with unsaved changes asks; y saves, n goes on
ask_unsaved:
    cmp byte [dirty], 0
    je .go
    mov esi, q_unsaved
    mov byte [ask_one], 1       ; one key answers
    call ask_line
    mov byte [ask_one], 0
    jc .stay
    mov al, [ask_buf]
    or al, 0x20
    cmp al, 'n'
    je .go
    cmp al, 'y'
    jne .stay
    call save
    jc .stay
.go:
    clc
    ret
.stay:
    stc
    ret

; esi = question -> name from what is typed, or CF
ask_name:
    call ask_line
    jc .r
    pushad
    mov esi, ask_buf
    mov edi, name
    call copy_name
    popad
    clc
.r:
    ret

; esi = question -> ask_buf typed on the status row (Enter), CF on Esc
ask_line:
    pushad
    mov [ask_q], esi
    xor ecx, ecx
.show:
    mov byte [ask_buf+ecx], 0
    push ecx
    mov edi, line
    mov esi, [ask_q]
    call scopy
    mov esi, ask_buf
    call scopy
    mov ax, '_'
    stosw
    mov eax, 2
    mov ebx, STAT_Y
    mov ecx, SCR_W - 4
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
    je .yes
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
    cmp byte [ask_one], 0
    jne .yes
    jmp .show
.bs:
    test ecx, ecx
    jz .k
    dec ecx
    jmp .show
.yes:
    test ecx, ecx
    jz .no
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; esi -> edi: a name (up to NAME_MAX, ends at a space or zero)
copy_name:
    mov ecx, NAME_MAX
.c:
    lodsb
    cmp al, ' '
    jbe .e
    stosb
    loop .c
.e:
    mov byte [edi], 0
    ret

; esi -> edi, edi ends on the zero
scopy:
    lodsb
    stosb
    test al, al
    jnz scopy
    dec edi
    ret

; ---------- self-check ----------
; esi = keys: characters, or 0xE0 and a scancode, or 0xE1 and a Ctrl
; letter, or 0xE2 and a scancode with Ctrl; 0 ends
feed:
    pushad
.k:
    movzx eax, byte [esi]
    test eax, eax
    jz .r
    inc esi
    cmp al, 0xE0
    je .scan
    cmp al, 0xE1
    je .ctl
    cmp al, 0xE2
    je .cscan
    jmp .send
.cscan:
    movzx eax, byte [esi]
    inc esi
    shl eax, 8
    or eax, 1 << 16
    jmp .send
.scan:
    movzx eax, byte [esi]
    inc esi
    shl eax, 8
    jmp .send
.ctl:
    movzx eax, byte [esi]
    inc esi
    or eax, 1 << 16
.send:
    push esi
    call key
    pop esi
    jmp .k
.r:
    popad
    ret

; eax = text position on the screen (its line drawn) -> ecx = the black
; pixels in its cell
ink_in:
    pushad
    mov [tmp], eax
    xor ebx, ebx                ; its line
.f:
    lea ecx, [ebx+1]
    cmp ecx, [nlines]
    jae .got
    cmp [lstart+ecx*4], eax
    ja .got
    mov ebx, ecx
    jmp .f
.got:
    mov eax, ebx
    call line_x
    mov edx, [tmp]
    sub edx, [lstart+ebx*4]
    imul edx, CELL_W
    add ecx, edx
    mov eax, ecx                ; the cell's left
    sub ebx, [top]
    imul ebx, LINE_H
    add ebx, TY
    xor edi, edi                ; count
    mov esi, LINE_H - 1
.y:
    mov ebp, CELL_W
    push eax
.x:
    push ecx
    call gui_peek
    cmp cl, C_BLACK
    pop ecx
    jne .w
    inc edi
.w:
    inc eax
    dec ebp
    jnz .x
    pop eax
    inc ebx
    dec esi
    jnz .y
    mov [esp+24], edi           ; ecx
    popad
    ret

selftest:
    mov byte [bad], 'w'         ; wrapping: 13 words of 4 + space
    mov esi, keys_long
    call feed
    cmp dword [nlines], 2
    jne .fail
    cmp dword [llen], 49        ; "abcd " x 10, less the last space
    jne .fail
    cmp dword [lstart+4], 50
    jne .fail
    call count_words
    cmp eax, 13
    jne .fail
    mov byte [bad], 's'         ; bold: "abcd" at 0 selected, Ctrl+B
    mov dword [cur], 0
    mov esi, keys_bold
    call feed
    test byte [attr], A_BOLD
    jz .fail
    test byte [attr+3], A_BOLD
    jz .fail
    test byte [attr+4], A_BOLD  ; not the space after it
    jnz .fail
    mov byte [bad], 'd'         ; drawn bold: more ink than plain
    mov dword [anchor], -1
    call draw
    xor eax, eax
    call ink_in
    mov ebx, ecx
    mov eax, 5                  ; the next "abcd" starts plain
    call ink_in
    cmp ebx, ecx
    jbe .fail
    mov byte [bad], 'u'         ; underline typed: "x" with Ctrl+U
    mov esi, keys_under
    call feed
    mov eax, [len]
    test byte [attr+eax-2], A_UNDER
    jz .fail
    mov byte [bad], 'c'         ; centred: the first line moves right
    mov dword [cur], 0
    mov esi, keys_centre
    call feed
    mov eax, 1                  ; the second line ("abcd abcd abcd x")
    call line_x
    cmp ecx, LX + ((COLS - 16) / 2) * CELL_W
    jne .fail
    mov byte [bad], 'f'         ; SQWP: save, empty, open
    mov esi, s_testfile
    mov edi, name
    call copy_name
    call save
    jc .fail
    mov eax, [len]
    mov [tmp2], eax
    call empty
    call load
    call layout
    mov eax, [len]
    cmp eax, [tmp2]
    jne .fail
    test byte [attr], A_BOLD
    jz .fail
    mov eax, [len]
    mov al, [attr+eax-1]
    and al, A_ALIGN
    cmp al, AL_CENTRE
    jne .fail
    mov byte [bad], 't'         ; plain text: no styles
    mov esi, s_testtxt
    mov edi, name
    call copy_name
    call save
    jc .fail
    call empty
    call load
    mov eax, [len]
    cmp eax, [tmp2]
    jne .fail
    cmp byte [attr], 0
    jne .fail
    cmp dword [text], 'abcd'
    jne .fail
    mov byte [bad], 'e'         ; a selection is replaced by typing
    mov dword [cur], 0
    mov esi, keys_replace
    call feed
    cmp dword [text], 'Zd a'
    jne .fail
    call gui_close
    mov esi, pass
    call gui_puts
    xor eax, eax
    ret
.fail:
    call gui_close
    mov esi, fail
    call gui_puts
    mov esi, bad
    call gui_puts
    mov eax, 1
    ret

; ---------- data ----------
s_title db 'Write', 0
s_dash db ' - ', 0
s_words db '  words ', 0
s_chars db '  chars ', 0
s_keys db '  ^B^I^U ^L^E^R F3 ^S', 0
align_name dd s_left, s_centre, s_right, s_left
s_left db ' left', 0
s_centre db ' centre', 0
s_right db ' right', 0
s_testfile db 'wtest.swp', 0
s_testtxt db 'wtest.txt', 0
q_unsaved db 'Save changes? y/n ', 0
q_save db 'Save as: ', 0
q_open db 'Open: ', 0
m_full db 'The document is full', 0
m_opened db 'Opened', 0
m_newfile db 'New file', 0
m_saved db 'Saved', 0
m_nosave db 'Could not save', 0
m_nogfx db 'write: no graphics', 10, 0
keys_long:
    times 12 db 'abcd '
    db 'abcd', 0
; F3 at 0, Right x 4, Ctrl+B
keys_bold db 0xE0, K_F3
          times 4 db 0xE0, K_RIGHT
          db 0xE1, 'b', 0
; Ctrl+End, Ctrl+U, " x"
keys_under db 0xE2, K_END, 0xE1, 'u', ' ', 'x', 0
; Ctrl+E (centre)
keys_centre db 0xE1, 'e', 0
; F3, Right x 3, "Z": "abc" becomes "Z", leaving "Zd abcd ..."
keys_replace db 0xE0, K_F3
             times 3 db 0xE0, K_RIGHT
             db 'Z', 0
pass db 'write: PASS', 10, 0
fail db 'write: FAIL ', 0
bad db '?', 10, 0

SQX_BSS
GUI_BSS
alignb 4
arg resd 1
fbufp resd 1
len resd 1
cur resd 1
anchor resd 1
top resd 1
nlines resd 1
msg resd 1
dline resd 1
dx_ resd 1
dy_ resd 1
sel0 resd 1
sel1 resd 1
flen resd 1
tmp resd 1
tmp2 resd 1
ask_q resd 1
lstart resd LINES_MAX
llen resd LINES_MAX
lalign resb LINES_MAX
tstyle resb 1
dirty resb 1
ask_one resb 1
palign resb 1
gstyle resb 1
name resb NAME_MAX + 4
ask_buf resb NAME_MAX + 4
line resb 96
text resb TEXT_MAX + 4
attr resb TEXT_MAX + 4
SQX_END
