; Squirrel-OS/2 — Hex editor (A.7, OS2-APPS). Original code.
; run hexedit <file>   |   run hexedit test
;
; Shows a file 8 bytes a row: the offset, the bytes in hex and as text.
; Changed bytes are red until saved. Files up to 128 KB; a name that does
; not exist yet starts an empty file.
;
;   arrows, PgUp, PgDn    move (Home / End: the row's start / end,
;                         Ctrl+Home / Ctrl+End: the file's)
;   0-9 a-f               in the hex column: the next half of the byte
;   any character         in the text column: the byte
;   Tab                   hex column <-> text column
;   Insert                a 0 byte before the cursor
;   Delete                removes the byte under the cursor
;   Ctrl+G                go to an offset (typed in hex)
;   Ctrl+S                save
;   Esc                   quit (asks first if there are unsaved changes)
;
; Typing at the end of the file adds bytes. "run hexedit test" writes a
; file of the bytes 0 to 255, edits, inserts, deletes, saves and reads
; it back, and prints "hexedit: PASS". See documentation/apps/hexedit.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

MAXF        equ 128 * 1024
PER         equ 8                       ; bytes a row
ROWS        equ 19
TY          equ 14
ROW_H       equ CELL_H + 1
OFF_X       equ 4
HEX_X       equ OFF_X + 7 * CELL_W
TXT_X       equ HEX_X + PER * 3 * CELL_W + CELL_W
STAT_Y      equ SCR_H - CELL_H - 2
NAME_MAX    equ 60
K_INSERT    equ 0x52
SC_S        equ 0x1F
SC_G        equ 0x22

main:
    mov esi, [esp+4]
    mov [arg], esi
    test esi, esi
    jz .usage
    cmp byte [esi], 0
    je .usage
    mov eax, SYS_SBRK           ; the file and its changed marks
    mov ebx, 2 * MAXF
    int 0x80
    cmp eax, -1
    je .nomem
    mov [data], eax
    add eax, MAXF
    mov [marks], eax
    mov esi, [arg]
    cmp dword [esi], 'test'
    jne .open
    cmp byte [esi+4], 0
    je selftest
.open:
    mov edi, name
    call copy_name
    call load
    call gui_open
    jc .nogfx
.draw:
    call draw
.key:
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .click
    test eax, EV_DRAG
    jnz .key
    call key
    jnc .draw
    call gui_close
    xor eax, eax
    ret
.click:
    call click
    jmp .draw
.usage:
    mov esi, m_usage
    call gui_puts
    mov eax, 1
    ret
.nomem:
    mov esi, m_nomem
    call gui_puts
    mov eax, 1
    ret
.nogfx:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
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
    cmp bl, K_PGUP
    je .pgup
    cmp bl, K_PGDN
    je .pgdn
    cmp bl, K_HOME
    je .home
    cmp bl, K_END
    je .end
    cmp bl, K_TAB
    je .tab
    cmp bl, K_INSERT
    je .ins
    cmp bl, K_DEL
    je .del
    cmp byte [pane], 0
    jne .text
    call hexdigit               ; the hex column: a digit 0-f
    jc .ok
    call put_nibble
    jmp .ok
.text:
    cmp al, ' '
    jb .ok
    cmp al, '~'
    ja .ok
    call put_byte
    jmp .ok
.ctrl:
    cmp bl, SC_S
    je .save
    cmp bl, SC_G
    je .goto
    cmp bl, K_HOME
    je .top
    cmp bl, K_END
    je .bottom
    jmp .ok
.save:
    call save
    jmp .ok
.goto:
    call goto_offset
    jmp .ok
.top:
    mov dword [cur], 0
    jmp .moved
.bottom:
    mov eax, [size]
    mov [cur], eax
    jmp .moved
.esc:
    cmp byte [dirty], 0
    je .quit
    mov esi, q_save
    call ask
    jc .ok                      ; Esc: stay
    or al, 0x20
    cmp al, 'n'
    je .quit
    cmp al, 'y'
    jne .ok
    call save
    jc .ok
.quit:
    popad
    stc
    ret
.left:
    cmp dword [cur], 0
    je .ok
    dec dword [cur]
    jmp .moved
.right:
    inc dword [cur]
    jmp .moved
.up:
    sub dword [cur], PER
    jmp .moved
.down:
    add dword [cur], PER
    jmp .moved
.pgup:
    sub dword [cur], PER * ROWS
    jmp .moved
.pgdn:
    add dword [cur], PER * ROWS
    jmp .moved
.home:
    and dword [cur], -PER
    jmp .moved
.end:
    or dword [cur], PER - 1
    jmp .moved
.tab:
    xor byte [pane], 1
    mov byte [nib], 0
    jmp .ok
.ins:
    call insert_byte
    jmp .ok
.del:
    call delete_byte
    jmp .ok
.moved:
    mov byte [nib], 0
.ok:
    call clamp
    popad
    clc
    ret

; al = character -> eax = its value 0-15, or CF
hexdigit:
    or al, 0x20
    cmp al, '0'
    jb .no
    cmp al, '9'
    jbe .d
    cmp al, 'a'
    jb .no
    cmp al, 'f'
    ja .no
    sub al, 'a' - 10
    movzx eax, al
    clc
    ret
.d:
    sub al, '0'
    movzx eax, al
    clc
    ret
.no:
    stc
    ret

; cur within 0 .. size (signed: a move above 0 stops at 0), the view on it
clamp:
    mov eax, [cur]
    test eax, eax
    jns .p
    xor eax, eax
.p:
    cmp eax, [size]
    jbe .s
    mov eax, [size]
.s:
    mov [cur], eax
    shr eax, 3                  ; its row
    mov ecx, [top]
    cmp eax, ecx
    jae .b
    mov [top], eax
    ret
.b:
    sub eax, ROWS - 1
    jbe .r
    cmp eax, [top]
    jbe .r
    mov [top], eax
.r:
    ret

; -> CF if the cursor is at the end and the file is full (else the byte
; there exists, made at the end if needed)
make_room:
    mov eax, [cur]
    cmp eax, [size]
    jb .ok
    cmp eax, MAXF
    jae .full
    mov ecx, [data]
    mov byte [ecx+eax], 0
    inc dword [size]
.ok:
    clc
    ret
.full:
    mov dword [msg], m_full
    stc
    ret

; eax = 0-15: the next half of the byte under the cursor
put_nibble:
    push eax
    call make_room
    pop eax
    jc .r
    mov ebx, [data]
    add ebx, [cur]
    mov cl, [ebx]
    cmp byte [nib], 0
    jne .low
    and cl, 0x0F
    shl al, 4
    or cl, al
    mov [ebx], cl
    mov byte [nib], 1
    jmp .mark
.low:
    and cl, 0xF0
    or cl, al
    mov [ebx], cl
    mov byte [nib], 0
    call .mark
    inc dword [cur]
.r:
    ret
.mark:
    mov ebx, [marks]
    add ebx, [cur]
    mov byte [ebx], 1
    mov byte [dirty], 1
    ret

; al = byte: under the cursor, then the cursor moves on
put_byte:
    push eax
    call make_room
    pop eax
    jc .r
    mov ebx, [data]
    add ebx, [cur]
    mov [ebx], al
    mov ebx, [marks]
    add ebx, [cur]
    mov byte [ebx], 1
    mov byte [dirty], 1
    inc dword [cur]
.r:
    ret

insert_byte:
    pushad
    mov ecx, [size]
    cmp ecx, MAXF
    jae .full
    sub ecx, [cur]              ; bytes from the cursor on move up one
    mov esi, [data]
    call .shift
    mov esi, [marks]
    call .shift
    mov ebx, [cur]
    mov eax, [data]
    mov byte [eax+ebx], 0
    mov eax, [marks]
    mov byte [eax+ebx], 1
    inc dword [size]
    mov byte [dirty], 1
    popad
    ret
.full:
    mov dword [msg], m_full
    popad
    ret
.shift:                         ; esi = area: [cur, size) up by one
    push ecx
    add esi, [size]
    lea edi, [esi]
    dec esi
    std
    rep movsb
    cld
    pop ecx
    ret

delete_byte:
    pushad
    mov ecx, [size]
    sub ecx, [cur]
    jbe .r
    dec ecx                     ; bytes after the cursor move down one
    mov esi, [data]
    call .shift
    mov esi, [marks]
    call .shift
    dec dword [size]
    mov byte [dirty], 1
.r:
    popad
    ret
.shift:
    push ecx
    add esi, [cur]
    lea edi, [esi]
    inc esi
    rep movsb
    pop ecx
    ret

; Ctrl+G: an offset in hex
goto_offset:
    pushad
    mov esi, q_goto
    call ask_line
    jc .r
    xor edx, edx
    mov esi, ask_buf
.d:
    lodsb
    test al, al
    jz .go
    call hexdigit
    jc .bad
    shl edx, 4
    or edx, eax
    jmp .d
.go:
    mov [cur], edx
    mov byte [nib], 0
    jmp .r
.bad:
    mov dword [msg], m_badhex
.r:
    popad
    ret

; A click on a byte (either column) moves there
click:
    pushad
    mov eax, [gui_my]
    sub eax, TY
    js .r
    xor edx, edx
    mov ecx, ROW_H
    div ecx
    cmp eax, ROWS
    jae .r
    add eax, [top]
    shl eax, 3
    mov ebx, eax                ; the row's first offset
    mov eax, [gui_mx]
    cmp eax, TXT_X
    jae .txt
    sub eax, HEX_X
    js .r
    xor edx, edx
    mov ecx, 3 * CELL_W
    div ecx
    mov byte [pane], 0
    jmp .col
.txt:
    sub eax, TXT_X
    xor edx, edx
    mov ecx, CELL_W
    div ecx
    mov byte [pane], 1
.col:
    cmp eax, PER
    jae .r
    add eax, ebx
    mov [cur], eax
    mov byte [nib], 0
    call clamp
.r:
    popad
    ret

; ---------- drawing ----------
draw:
    pushad
    mov edi, line               ; title "Hex: name"
    mov esi, s_title
    call scopy
    mov esi, name
    call scopy
    xor eax, eax
    xor ebx, ebx
    mov ecx, SCR_W
    mov edx, SCR_H
    mov esi, line
    call gui_window
    mov eax, 2
    mov ebx, TY - 1
    mov ecx, SCR_W - 4
    mov edx, ROWS * ROW_H + 1
    mov byte [gui_ink], C_WHITE
    call gui_fill
    xor ebp, ebp
.row:
    mov eax, [top]
    add eax, ebp
    shl eax, 3
    mov [roff], eax
    cmp eax, [size]
    ja .next                    ; past the end (the end itself shows)
    imul ebx, ebp, ROW_H
    add ebx, TY
    mov [ry], ebx
    mov edi, line               ; the offset
    mov ecx, 5
    call hexn
    mov al, ':'
    stosb
    mov byte [edi], 0
    mov esi, line
    mov eax, OFF_X
    mov byte [gui_ink], C_DGREY
    mov byte [gui_bg], C_WHITE
    call gui_text
    xor edx, edx                ; each byte
.b:
    mov eax, [roff]
    add eax, edx
    mov [boff], eax
    cmp eax, [size]
    ja .next
    call cell                   ; the hex cell and the text cell
    inc edx
    cmp edx, PER
    jb .b
.next:
    inc ebp
    cmp ebp, ROWS
    jb .row
    call status
    call gui_flip
    popad
    ret

; boff (edx = column, ry = row's y): its two cells, the cursor's
; highlighted (the active column's more strongly)
cell:
    pushad
    mov byte [gui_bg], C_WHITE
    mov byte [gui_ink], C_BLACK
    mov eax, [boff]
    cmp eax, [size]
    je .endcell
    mov ecx, [marks]
    cmp byte [ecx+eax], 0
    je .plain
    mov byte [gui_ink], C_RED
.plain:
    mov ecx, [data]
    movzx eax, byte [ecx+eax]
    mov [bval], eax
    mov edi, line
    mov ecx, 2
    call hexn
    jmp .hexout
.endcell:                       ; the end of the file: where typing adds
    mov dword [bval], -1
    mov word [line], '__'
    mov byte [line+2], 0
    mov byte [gui_ink], C_LGREY
.hexout:
    imul eax, edx, 3 * CELL_W   ; the hex cell
    add eax, HEX_X
    mov [cx_], eax
    mov eax, [boff]
    cmp eax, [cur]
    jne .h
    mov al, C_LCYAN
    cmp byte [pane], 0
    jne .hc
    mov al, C_YELLOW
.hc:
    call .bg
.h:
    mov esi, line
    mov eax, [cx_]
    mov ebx, [ry]
    call gui_text
    imul eax, edx, CELL_W       ; the text cell
    add eax, TXT_X
    mov [cx_], eax
    mov byte [gui_bg], C_WHITE
    mov eax, [boff]
    cmp eax, [cur]
    jne .t
    mov al, C_LCYAN
    cmp byte [pane], 1
    jne .tc
    mov al, C_YELLOW
.tc:
    call .bg1
.t:
    mov eax, [bval]
    cmp eax, -1
    je .r
    cmp al, ' '
    jb .dot
    cmp al, '~'
    jbe .ch
.dot:
    mov al, '.'
.ch:
    mov [line], al
    mov byte [line+1], 0
    mov esi, line
    mov eax, [cx_]
    mov ebx, [ry]
    call gui_text
.r:
    popad
    ret
.bg:                            ; al = colour behind two characters
    push edx
    mov [gui_bg], al
    mov ah, [gui_ink]
    push eax
    mov [gui_ink], al
    mov eax, [cx_]
    mov ebx, [ry]
    mov ecx, 2 * CELL_W
    mov edx, CELL_H
    call gui_fill
    pop eax
    mov [gui_ink], ah
    pop edx
    ret
.bg1:                           ; behind one
    push edx
    mov [gui_bg], al
    mov ah, [gui_ink]
    push eax
    mov [gui_ink], al
    mov eax, [cx_]
    mov ebx, [ry]
    mov ecx, CELL_W
    mov edx, CELL_H
    call gui_fill
    pop eax
    mov [gui_ink], ah
    pop edx
    ret

; The status row: a message, or the cursor's offset and byte and the size
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
    mov edi, line               ; "@00012 = 41 65  size 256 *"
    mov al, '@'
    stosb
    mov eax, [cur]
    mov ecx, 5
    call hexn
    mov eax, [cur]
    cmp eax, [size]
    je .size
    mov esi, s_eq
    call scopy
    mov eax, [cur]
    mov ecx, [data]
    movzx eax, byte [ecx+eax]
    push eax
    mov ecx, 2
    call hexn
    mov al, ' '
    stosb
    pop eax
    call gui_utoa
.size:
    mov esi, s_size
    call scopy
    mov eax, [size]
    call gui_utoa
    cmp byte [dirty], 0
    je .keys
    mov ax, ' *'
    stosw
    mov byte [edi], 0
.keys:
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

; eax = number, ecx = digits -> edi: that many hex digits, edi after them
hexn:
    push eax
    push ebx
    push ecx
    push edx
    mov edx, eax
    mov ebx, ecx
.d:
    dec ebx
    js .r
    mov eax, edx
    lea ecx, [ebx*4]
    shr eax, cl
    and eax, 15
    mov al, [hexdig+eax]
    stosb
    jmp .d
.r:
    mov byte [edi], 0
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; esi = question -> ask_buf typed on the status row (Enter), CF on Esc
ask_line:
    pushad
    mov [ask_q], esi
    xor ecx, ecx
.draw:
    mov byte [ask_buf+ecx], 0
    push ecx
    mov edi, line
    mov esi, [ask_q]
    call scopy
    mov esi, ask_buf
    call scopy
    mov ax, '_'
    stosw
    call .show
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
    cmp ecx, 16
    jae .k
    mov [ask_buf+ecx], al
    inc ecx
    jmp .draw
.bs:
    test ecx, ecx
    jz .k
    dec ecx
    jmp .draw
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
.show:
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
    ret

; esi = question -> al = the key pressed (CF on Esc)
ask:
    pushad
    mov edi, line
    call scopy
    call ask_line.show
    call gui_getkey
    cmp ah, K_ESC
    je .no
    mov [esp+28], eax
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; ---------- files ----------
; name -> data, size (a new file if it does not exist)
load:
    pushad
    mov dword [size], 0
    mov byte [dirty], 0
    mov eax, SYS_OPEN
    mov ebx, name
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .new
    mov ebx, eax
    mov eax, SYS_READ
    mov ecx, [data]
    mov edx, MAXF
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    int 0x80
    pop eax
    test eax, eax
    jns .got
    xor eax, eax
.got:
    mov [size], eax
    mov edi, [marks]            ; nothing changed yet
    mov ecx, MAXF / 4
    xor eax, eax
    rep stosd
    mov dword [msg], 0
    cmp dword [size], MAXF
    jb .r
    mov dword [msg], m_cut
.r:
    popad
    ret
.new:
    mov dword [msg], m_newfile
    popad
    ret

save:
    pushad
    mov eax, SYS_OPEN
    mov ebx, name
    mov ecx, O_CREATE | O_TRUNC
    int 0x80
    test eax, eax
    js .fail
    mov ebx, eax
    mov eax, SYS_WRITE
    mov ecx, [data]
    mov edx, [size]
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    int 0x80
    pop eax
    cmp eax, [size]
    jne .fail
    mov edi, [marks]
    mov ecx, MAXF / 4
    xor eax, eax
    rep stosd
    mov byte [dirty], 0
    mov dword [msg], m_saved
    popad
    clc
    ret
.fail:
    mov dword [msg], m_nosave
    popad
    stc
    ret

; esi -> edi: a file name (up to NAME_MAX, ends at a space)
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
; esi = keys (one byte each, 0 ends; 0xE0 then a scancode for others)
type_keys:
    pushad
.k:
    movzx eax, byte [esi]
    test eax, eax
    jz .r
    inc esi
    cmp al, 0xE0
    jne .ch
    movzx eax, byte [esi]
    inc esi
    shl eax, 8
    jmp .send
.ch:
    mov ah, 0                   ; a character key: no scancode needed
.send:
    push esi
    call key
    pop esi
    jmp .k
.r:
    popad
    ret

selftest:
    mov byte [bad], 'w'         ; a file of the bytes 0 to 255
    xor ecx, ecx
    mov edi, [data]
.fill:
    mov [edi+ecx], cl
    inc ecx
    cmp ecx, 256
    jb .fill
    mov dword [size], 256
    mov esi, s_testfile
    mov edi, name
    call copy_name
    call save
    jc .fail
    mov byte [bad], 'l'         ; read back
    mov edi, [data]
    mov ecx, 256 / 4
    xor eax, eax
    rep stosd
    call load
    cmp dword [size], 256
    jne .fail
    mov eax, [data]
    cmp dword [eax+0x40], 0x43424140
    jne .fail
    call gui_open
    jc .fail
    mov byte [bad], 'h'         ; at 0x10, hex "ab", text "Z"
    mov dword [cur], 0x10
    mov esi, keys1
    call type_keys
    mov eax, [data]
    cmp word [eax+0x10], 'Z' << 8 | 0xAB
    jne .fail
    cmp dword [cur], 0x12
    jne .fail
    mov byte [bad], 'i'         ; Insert at 0, Delete at 0x20, End
    mov byte [pane], 0
    mov dword [cur], 0
    mov esi, keys2
    call type_keys
    cmp dword [size], 256
    jne .fail
    mov eax, [data]
    cmp dword [eax], 0x02010000 ; 00 00 01 02 ...
    jne .fail
    cmp byte [eax+0x20], 0x20   ; byte 0x1F (now at 0x20) was deleted:
    jne .fail                   ; 0x20 moved back in
    mov byte [bad], 'a'         ; typing at the end adds a byte
    mov eax, [size]
    mov [cur], eax
    mov esi, keys3
    call type_keys
    cmp dword [size], 257
    jne .fail
    mov eax, [data]
    cmp byte [eax+256], 0x7E
    jne .fail
    mov byte [bad], 'd'         ; drawn: the changed byte (now at 0x11,
    mov dword [cur], 0          ; row 2, column 1) is red
    call clamp
    call draw
    mov eax, HEX_X + 3 * CELL_W
    mov ebx, TY + 2 * ROW_H
    xor ecx, ecx                ; any red pixel in that cell
.px:
    push ecx
    call gui_peek
    cmp cl, C_RED
    pop ecx
    je .red
    inc eax
    inc ecx
    cmp ecx, 2 * CELL_W
    jb .px
    add ebx, 1
    sub eax, 2 * CELL_W
    xor ecx, ecx
    cmp ebx, TY + 2 * ROW_H + CELL_H
    jb .px
    jmp .fail
.red:
    mov byte [bad], 's'         ; save and read back
    call save
    jc .fail
    mov eax, [data]
    mov byte [eax+0x10], 0
    call load
    cmp dword [size], 257
    jne .fail
    mov eax, [data]
    cmp word [eax+0x11], 'Z' << 8 | 0xAB
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
hexdig db '0123456789ABCDEF'
s_title db 'Hex: ', 0
s_eq db ' = ', 0
s_size db '  size ', 0
s_keys db '  Tab ^G ^S Esc', 0
s_testfile db 'htest.bin', 0
q_save db 'Save changes? y/n ', 0
q_goto db 'Go to offset (hex): ', 0
m_usage db 'usage: run hexedit <file>', 10, 0
m_nomem db 'hexedit: no memory', 10, 0
m_nogfx db 'hexedit: no graphics', 10, 0
m_full db 'The file is at its largest (128 KB)', 0
m_cut db 'Only the first 128 KB are shown', 0
m_newfile db 'New file', 0
m_saved db 'Saved', 0
m_nosave db 'Could not save', 0
m_badhex db 'Not a hex number', 0
; at 0x10: 'a' 'b' (hex), Tab, 'Z'
keys1 db 'a', 'b', 0xE0, K_TAB, 'Z', 0
; Insert at 0, 0x20 Right, Delete
keys2 db 0xE0, K_INSERT
      times 0x20 db 0xE0, K_RIGHT
      db 0xE0, K_DEL, 0
; at the end: Tab to text, '~'
keys3 db 0xE0, K_TAB, '~', 0
pass db 'hexedit: PASS', 10, 0
fail db 'hexedit: FAIL ', 0
bad db '?', 10, 0

SQX_BSS
GUI_BSS
alignb 4
arg resd 1
data resd 1
marks resd 1
size resd 1
cur resd 1
top resd 1
msg resd 1
roff resd 1
boff resd 1
bval resd 1
ry resd 1
cx_ resd 1
ask_q resd 1
pane resb 1
nib resb 1
dirty resb 1
alignb 4
name resb NAME_MAX + 4
ask_buf resb 20
line resb 96
SQX_END
