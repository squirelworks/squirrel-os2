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
; there are unsaved changes. See documentation/apps/gui-programs.md.

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
    mov byte [msg], 0
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
    call cell
    inc esi
    inc edi
    jmp .ch
.eol:
    call cell_cursor_end        ; the cursor after the last character
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
    mov byte [gui_ink], C_BLACK
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
    call cell
    pop edx
.r:
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
name resb NAME_MAX + 1
ask_buf resb NAME_MAX + 1
line resb 128
text resb TEXT_MAX + 1
SQX_END
