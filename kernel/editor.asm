; Squirrel-OS/2 — text editors: edit (normal) and vedit (verbose)
; Included from pm.asm. Original code.
;
; One full-screen editor engine; vedit adds line numbers, a full numeric
; status line and a message for every action. Files load from and save
; to SQFS. See documentation/apps/editors.md.

ED_CAP      equ 16384
ED_BUF      equ KSCRATCH+0x4000     ; 16 KB text buffer
; Text rows are txt_rows - 2; the status row and the message row follow.
; In a desktop window txt_rows and txt_cols are smaller (1.6.4).
ED_GUTTER   equ 6                   ; vedit line-number column width
ATTR_TEXT   equ 0x07
ATTR_DIM    equ 0x08
ATTR_STATUS equ 0x70

run_edit:
    mov byte [ed_verbose], 0
    jmp ed_main

run_vedit:
    mov byte [ed_verbose], 1
    ; fall through

ed_main:
    mov dword [ed_len], 0
    mov dword [ed_pos], 0
    mov dword [ed_top], 0
    mov dword [ed_hs], 0
    mov dword [ed_want], -1
    mov byte [ed_mod], 0
    mov byte [ed_ins], 1
    mov byte [ed_ctl], 0
    mov byte [kbd_ctrl], 0
    mov esi, run_arg
    mov edi, ed_name
    mov ecx, FS_PATHMAX
    rep movsb
    mov byte [run_arg], 0
    call ed_load
    call ed_undo_init
.loop:
    call ed_draw
    call fb_waitkey
    mov [ed_key], al
    cmp byte [kbd_ctrl], 0
    jne .ctrl
    cmp al, 0x01                ; Esc
    je .quit
    cmp al, 0x3C                ; F2
    je .save
    cmp al, 0x3D                ; F3: find the same text again
    je .again
    cmp al, 0x48
    je .up
    cmp al, 0x50
    je .down
    cmp al, 0x4B
    je .left
    cmp al, 0x4D
    je .right
    cmp al, 0x47
    je .home
    cmp al, 0x4F
    je .end
    cmp al, 0x49
    je .pgup
    cmp al, 0x51
    je .pgdn
    cmp al, 0x52                ; Insert
    je .insmode
    cmp al, 0x53                ; Delete
    je .del
    cmp al, 0x0E
    je .bs
    cmp al, 0x0F                ; Tab -> 4 spaces
    je .tab
    call kbd_ascii              ; Enter maps to 10
    test al, al
    jz .loop
    call ed_snap
    call ed_type
    jmp .loop
.ctrl:
    cmp al, 0x1F                ; Ctrl+S
    je .save
    cmp al, 0x10                ; Ctrl+Q
    je .quit
    cmp al, 0x21                ; Ctrl+F
    je .find
    cmp al, 0x2C                ; Ctrl+Z
    je .undo
    cmp al, 0x14                ; Ctrl+T: control characters (vedit)
    je .ctl
    jmp .loop
.ctl:
    cmp byte [ed_verbose], 0
    je .loop
    xor byte [ed_ctl], 1
    mov esi, ed_m_ctlon
    cmp byte [ed_ctl], 0
    jne .cm
    mov esi, ed_m_ctloff
.cm:
    call ed_msg
    jmp .loop
.undo:
    call ed_undo
    jmp .loop
.find:
    mov esi, ed_m_find
    mov edi, ed_find
    mov byte [ed_pany], 1       ; the text may contain spaces
    call ed_prompt
    mov byte [ed_pany], 0
    jc .loop
.again:
    call ed_search
    jmp .loop
.up:
    call ed_up
    jmp .moved
.down:
    call ed_down
    jmp .moved
.left:
    cmp dword [ed_pos], 0
    je .moved
    dec dword [ed_pos]
    mov dword [ed_want], -1
    jmp .moved
.right:
    mov eax, [ed_pos]
    cmp eax, [ed_len]
    jae .moved
    inc dword [ed_pos]
    mov dword [ed_want], -1
    jmp .moved
.home:
    mov eax, [ed_pos]
    call ed_line_start
    mov [ed_pos], eax
    mov dword [ed_want], -1
    jmp .moved
.end:
    mov eax, [ed_pos]
    call ed_line_end
    mov [ed_pos], eax
    mov dword [ed_want], -1
    jmp .moved
.pgup:
    call ed_rows
.pu:
    call ed_up
    loop .pu
    jmp .moved
.pgdn:
    call ed_rows
.pd:
    call ed_down
    loop .pd
    jmp .moved
.moved:
    mov esi, [lstr+LS_ED_M_MOVED*4]
    call ed_vmsg
    jmp .loop
.insmode:
    xor byte [ed_ins], 1
    mov esi, [lstr+LS_ED_M_INS*4]
    cmp byte [ed_ins], 0
    jne .im
    mov esi, [lstr+LS_ED_M_OVR*4]
.im:
    call ed_vmsg
    jmp .loop
.bs:
    mov eax, [ed_pos]
    test eax, eax
    jz .loop
    call ed_snap
    dec eax
    mov [ed_pos], eax
    call ed_delete_at
    jmp .loop
.del:
    mov eax, [ed_pos]
    cmp eax, [ed_len]
    jae .loop
    call ed_snap
    call ed_delete_at
    jmp .loop
.tab:
    call ed_snap                ; one undo takes back all four spaces
    mov ecx, 4
.t:
    mov al, ' '
    push ecx
    call ed_type
    pop ecx
    loop .t
    jmp .loop
.save:
    call ed_save
    jmp .loop
.quit:
    cmp byte [ed_mod], 0
    je .bye
    mov esi, [lstr+LS_ED_M_UNSAVED*4]
    call ed_msg
    call ed_draw
    call fb_waitkey
    cmp al, 0x1F                ; s: save, then quit if that worked
    je .savequit
    cmp al, 0x20                ; d: discard
    je .bye
    mov esi, [lstr+LS_ED_M_CANCEL*4]
    call ed_msg
    jmp .loop
.savequit:
    call ed_save
    cmp byte [ed_mod], 0
    jne .loop
.bye:
    call ed_undo_free
    call app_home
    xor eax, eax
    ret

; ---------- buffer primitives ----------

; al = character: insert (or overwrite in overwrite mode, except at a
; line end) at the cursor.
ed_type:
    pushad
    mov ebx, [ed_pos]
    cmp byte [ed_ins], 0
    jne .insert
    cmp ebx, [ed_len]
    jae .insert
    cmp byte [ED_BUF+ebx], 10
    je .insert
    cmp al, 10
    je .insert
    mov [ED_BUF+ebx], al
    jmp .done
.insert:
    mov ecx, [ed_len]
    cmp ecx, ED_CAP
    jae .full
    ; shift buf[pos..len) right by one, from the end
    push eax
    lea esi, [ED_BUF+ecx-1]
    lea edi, [ED_BUF+ecx]
    sub ecx, ebx
    std
    rep movsb
    cld
    pop eax
    mov [ED_BUF+ebx], al
    inc dword [ed_len]
.done:
    inc dword [ed_pos]
    mov byte [ed_mod], 1
    mov dword [ed_want], -1
    mov esi, [lstr+LS_ED_M_TYPED*4]
    call ed_keymsg
    popad
    ret
.full:
    mov esi, [lstr+LS_ED_M_FULL*4]
    call ed_msg
    popad
    ret

; eax = offset: removes that byte
ed_delete_at:
    pushad
    mov bl, [ED_BUF+eax]
    mov [ed_last], bl
    lea edi, [ED_BUF+eax]
    lea esi, [edi+1]
    mov ecx, [ed_len]
    sub ecx, eax
    dec ecx
    rep movsb
    dec dword [ed_len]
    mov byte [ed_mod], 1
    mov dword [ed_want], -1
    mov al, [ed_last]
    mov esi, [lstr+LS_ED_M_DELETED*4]
    call ed_keymsg
    popad
    ret

; eax = offset -> eax = start of its line
ed_line_start:
.l:
    test eax, eax
    jz .d
    cmp byte [ED_BUF+eax-1], 10
    je .d
    dec eax
    jmp .l
.d:
    ret

; eax = offset -> eax = offset of the line's newline (or ed_len)
ed_line_end:
.l:
    cmp eax, [ed_len]
    jae .d
    cmp byte [ED_BUF+eax], 10
    je .d
    inc eax
    jmp .l
.d:
    ret

; cursor -> ed_line (0-based), ed_col (0-based)
ed_where:
    pushad
    xor ebx, ebx                ; line
    xor ecx, ecx                ; col
    xor esi, esi
.l:
    cmp esi, [ed_pos]
    jae .d
    inc ecx
    cmp byte [ED_BUF+esi], 10
    jne .n
    inc ebx
    xor ecx, ecx
.n:
    inc esi
    jmp .l
.d:
    mov [ed_line], ebx
    mov [ed_col], ecx
    popad
    ret

; vertical moves keep the wanted column across short lines
ed_up:
    pushad
    call ed_want_col
    mov eax, [ed_pos]
    call ed_line_start
    test eax, eax
    jz .out                     ; already on the first line
    dec eax
    call ed_line_start
    call ed_goto_col
.out:
    popad
    ret

ed_down:
    pushad
    call ed_want_col
    mov eax, [ed_pos]
    call ed_line_end
    cmp eax, [ed_len]
    jae .out                    ; already on the last line
    inc eax
    call ed_goto_col
.out:
    popad
    ret

ed_want_col:
    cmp dword [ed_want], -1
    jne .k
    call ed_where
    mov eax, [ed_col]
    mov [ed_want], eax
.k:
    ret

; eax = line start -> ed_pos = min(start + want, line end)
ed_goto_col:
    mov ebx, eax
    call ed_line_end
    add ebx, [ed_want]
    cmp ebx, eax
    jbe .ok
    mov ebx, eax
.ok:
    mov [ed_pos], ebx
    ret

; ---------- load / save ----------

ed_load:
    cmp byte [ed_name], 0
    je .new
    cmp byte [fs_mounted], 0
    je .nodisk
    mov esi, ed_name
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .newfile
    mov ebx, eax
    mov edi, ED_BUF
    mov ecx, ED_CAP
    call fs_read
    mov edx, eax
    call fs_close
    cmp edx, -1
    je .err
    mov [ed_len], edx
    mov esi, ed_name
    call fs_lookup
    mov esi, [lstr+LS_ED_M_LOADED*4]
    cmp dword [edi+DE_SIZE], ED_CAP
    jbe .msg
    mov esi, [lstr+LS_ED_M_TRUNCATED*4]
.msg:
    call ed_msg
    ret
.newfile:
    call ed_open_why
    jc ed_msg
    mov byte [ed_name], 0       ; a directory, say: Ctrl+S asks for a name
    jmp ed_msg
.new:
    mov esi, [lstr+LS_ED_M_NEW*4]
    call ed_msg
    ret
.nodisk:
    mov esi, [lstr+LS_ED_M_NODISK*4]
    call ed_msg
    ret
.err:
    mov esi, [lstr+LS_ED_M_IOERR*4]
    call ed_msg
    ret

ed_save:
    pushad
    cmp byte [fs_mounted], 0
    je .nodisk
    cmp byte [ed_name], 0
    jne .named
    mov esi, [lstr+LS_ED_M_SAVEAS*4]
    mov edi, ed_name
    call ed_prompt
    jc .cancel
.named:
    mov esi, ed_name
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .openerr
    mov ebx, eax
    mov esi, ED_BUF
    mov ecx, [ed_len]
    call fs_write
    mov edx, eax
    call fs_close
    cmp edx, [ed_len]
    jne .err
    mov byte [ed_mod], 0
    mov byte [ed_umod], 1       ; the file now has the edit: undoing it is a change
    mov esi, [lstr+LS_ED_M_SAVED*4]
    call ed_msg
    popad
    ret
.cancel:
    mov byte [ed_name], 0
    mov esi, [lstr+LS_ED_M_CANCEL*4]
    jmp .m
.nodisk:
    mov esi, [lstr+LS_ED_M_NODISK*4]
    jmp .m
.openerr:
    mov byte [ed_name], 0       ; the next save asks for another name
.err:
    movzx eax, byte [fs_errno]
    call fs_errstr
.m:
    call ed_msg
    popad
    ret

; After fs_open failed while loading: esi = the message to show.
; CF if the file just does not exist yet (a new file under that name).
ed_open_why:
    mov esi, [lstr+LS_ED_M_NEWFILE*4]
    cmp byte [fs_errno], FE_NOTFOUND
    stc
    je .r
    push eax
    movzx eax, byte [fs_errno]
    call fs_errstr
    pop eax
    clc
.r:
    ret

; esi = prompt, edi = FS_PATHMAX-byte destination: reads a path on the message
; row. CF set on Esc or empty input.
ed_prompt:
    pushad
    mov [ed_pdst], edi
    xor ecx, ecx
.l:
    mov byte [edi+ecx], 0
    push esi
    call sb_reset
    call sb_str
    mov esi, [ed_pdst]
    call sb_str
    mov ebx, [txt_rows]
    dec ebx                     ; the message row
    mov ah, ATTR_TEXT
    call sb_row
    pop esi
    call fb_waitkey
    cmp al, 0x01
    je .esc
    cmp al, 0x1C
    je .enter
    cmp al, 0x0E
    je .bs
    call kbd_ascii
    cmp al, ' '
    ja .ch
    jb .l
    cmp byte [ed_pany], 0       ; a space only where the caller allows it
    je .l
.ch:
    cmp ecx, FS_PATHMAX-1
    jae .l
    mov [edi+ecx], al
    inc ecx
    jmp .l
.bs:
    jecxz .l
    dec ecx
    jmp .l
.enter:
    test ecx, ecx
    jz .esc
    popad
    clc
    ret
.esc:
    popad
    stc
    ret

; Finds ed_find after the cursor, wrapping to the start, and moves the
; cursor there (1.0.9). Case-sensitive. The message line says where.
ed_search:
    pushad
    mov esi, ed_find
    xor ecx, ecx                ; ecx = length of the text
.len:
    cmp byte [esi+ecx], 0
    je .gotlen
    inc ecx
    jmp .len
.gotlen:
    test ecx, ecx               ; F3 before any Ctrl+F
    jz .none
    mov edx, [ed_len]
    sub edx, ecx                ; last start that fits
    jl .notfound
    mov ebx, [ed_pos]
    xor ebp, ebp                ; starts tried
.try:
    inc ebx
    cmp ebx, edx
    jbe .cmp
    xor ebx, ebx                ; wrap to the start of the buffer
.cmp:
    push ecx
    lea edi, [ED_BUF+ebx]
    mov esi, ed_find
    repe cmpsb
    pop ecx
    je .found
    inc ebp
    cmp ebp, edx
    jbe .try                    ; every start (edx+1 of them) tried once
.notfound:
    call sb_reset
    mov esi, ed_m_notfound
    call sb_str
    mov esi, ed_find
    call sb_str
    jmp .show
.found:
    mov [ed_pos], ebx
    mov dword [ed_want], -1
    call ed_where
    call sb_reset
    mov esi, ed_m_found
    call sb_str
    mov esi, ed_find
    call sb_str
    mov esi, ed_m_atline
    call sb_str
    mov eax, [ed_line]
    inc eax
    call sb_num
    mov esi, ed_m_atcol
    call sb_str
    mov eax, [ed_col]
    inc eax
    call sb_num
.show:
    mov esi, ed_sb
    mov edi, ed_msgbuf
    mov ecx, 80
    rep movsb
    mov dword [ed_msgp], ed_msgbuf
    popad
    ret
.none:
    mov dword [ed_msgp], ed_m_nofind
    popad
    ret

; al = a control character -> al = the cell drawn for it. Normally '.';
; with vedit's Ctrl+T on, a tab is '>' and any other control is '^'
; (1.0.12). Line ends are drawn by ed_draw. The buffer never changes.
ed_ctlglyph:
    cmp byte [ed_ctl], 0
    je .dot
    cmp al, 9
    mov al, '>'
    je .r
    mov al, '^'
    ret
.dot:
    mov al, '.'
.r:
    ret

; ---------- one-level undo (1.0.11) ----------
; Before each edit (a typed key, Enter, Backspace, Delete, Tab) the whole
; buffer is copied to ED_UNDO_PAGES pages from pg_alloc; Ctrl+Z copies it
; back once. The pages are taken at start and given back on exit. Without
; them, undo says so and the editor works as before.

ED_UNDO_PAGES equ ED_CAP / 4096     ; (PAGE_SIZE: mm.asm comes later)

ed_undo_init:
    pushad
    mov byte [ed_uok], 0
    xor ebx, ebx
.a:
    call pg_alloc
    mov [ed_upages+ebx*4], eax
    test eax, eax
    jz .fail
    inc ebx
    cmp ebx, ED_UNDO_PAGES
    jb .a
    popad
    ret
.fail:
    popad
    jmp ed_undo_free            ; frees what was taken; undo is off

ed_undo_free:
    pushad
    xor ebx, ebx
.f:
    mov eax, [ed_upages+ebx*4]
    mov dword [ed_upages+ebx*4], 0
    test eax, eax
    jz .n
    call pg_free
.n:
    inc ebx
    cmp ebx, ED_UNDO_PAGES
    jb .f
    popad
    ret

; Remembers the buffer, cursor and modified flag as they are now.
ed_snap:
    pushad
    cmp dword [ed_upages+(ED_UNDO_PAGES-1)*4], 0
    je .r
    mov eax, [ed_len]
    mov [ed_ulen], eax
    mov eax, [ed_pos]
    mov [ed_upos], eax
    mov al, [ed_mod]
    mov [ed_umod], al
    mov byte [ed_uok], 1
    xor edx, edx                ; 0: buffer -> pages
    call ed_ucopy
.r:
    popad
    ret

; Ctrl+Z: puts back the state before the last edit. A second Ctrl+Z
; finds nothing more to undo.
ed_undo:
    pushad
    mov esi, ed_m_noundo
    cmp dword [ed_upages+(ED_UNDO_PAGES-1)*4], 0
    je .m
    mov esi, ed_m_nothing
    cmp byte [ed_uok], 0
    je .m
    mov eax, [ed_ulen]
    mov [ed_len], eax
    mov eax, [ed_upos]
    mov [ed_pos], eax
    mov al, [ed_umod]
    mov [ed_mod], al
    mov byte [ed_uok], 0
    mov dword [ed_want], -1
    mov edx, 1                  ; pages -> buffer
    call ed_ucopy
    mov esi, ed_m_undone
.m:
    call ed_msg
    popad
    ret

; Copies ed_ulen bytes between ED_BUF and the undo pages, page by page.
; edx = 0: buffer to pages, 1: pages to buffer.
ed_ucopy:
    mov ebp, [ed_ulen]
    xor ebx, ebx
.page:
    test ebp, ebp
    jz .d
    mov ecx, PAGE_SIZE
    cmp ebp, ecx
    jae .full
    mov ecx, ebp
.full:
    sub ebp, ecx
    mov esi, ebx
    shl esi, 12
    add esi, ED_BUF
    mov edi, [ed_upages+ebx*4]
    test edx, edx
    jz .go
    xchg esi, edi
.go:
    rep movsb
    inc ebx
    jmp .page
.d:
    ret

; ---------- messages ----------

; esi = message for the message row (both editors)
ed_msg:
    mov [ed_msgp], esi
    ret

; esi = message shown only by vedit
ed_vmsg:
    cmp byte [ed_verbose], 0
    je .d
    mov [ed_msgp], esi
.d:
    ret

; esi = verb, al = character: vedit message "verb 'c' 0xNN (N)"
ed_keymsg:
    cmp byte [ed_verbose], 0
    je .d
    push eax
    call sb_reset
    call sb_str
    pop eax
    call sb_charinfo
    mov esi, ed_sb
    mov edi, ed_msgbuf
    mov ecx, 80
    rep movsb
    mov dword [ed_msgp], ed_msgbuf
.d:
    ret

; ---------- drawing ----------

ed_draw:
    pushad
    call ed_where
    ; keep the cursor line on screen
    mov eax, [ed_line]
    cmp eax, [ed_top]
    jae .t1
    mov [ed_top], eax
.t1:
    call ed_rows
    mov ebx, [ed_top]
    add ebx, ecx
    cmp eax, ebx
    jb .t2
    sub eax, ecx
    inc eax
    mov [ed_top], eax
.t2:
    ; text width and horizontal scroll
    mov edx, [txt_cols]
    cmp byte [ed_verbose], 0
    je .w
    sub edx, ED_GUTTER
.w:
    mov [ed_width], edx
    mov eax, [ed_col]
    cmp eax, [ed_hs]
    jae .h1
    mov [ed_hs], eax
.h1:
    mov ebx, [ed_hs]
    add ebx, edx
    cmp eax, ebx
    jb .h2
    sub eax, edx
    inc eax
    mov [ed_hs], eax
.h2:
    ; find the first visible line
    xor esi, esi
    mov ecx, [ed_top]
.skip:
    jecxz .rows
.sk:
    cmp esi, [ed_len]
    jae .rows
    inc esi
    cmp byte [ED_BUF+esi-1], 10
    jne .sk
    loop .skip
.rows:
    xor ebx, ebx                ; screen row
    mov byte [ed_more], 1
.row:
    mov edi, ebx
    imul edi, 160
    add edi, [txt_base]
    cmp byte [ed_verbose], 0
    je .text
    ; gutter: line number or blank
    push esi
    call sb_reset
    cmp byte [ed_more], 0
    je .gblank
    mov eax, [ed_top]
    add eax, ebx
    inc eax
    call sb_num_right5
.gblank:
    mov esi, ed_sb
    mov ecx, ED_GUTTER
    mov ah, ATTR_DIM
    call vga_text
    pop esi
.text:
    mov ecx, [ed_width]
    cmp byte [ed_more], 0
    jne .line
    mov ax, (ATTR_DIM<<8)|'~'
    stosw
    dec ecx
    jmp .pad
.line:
    ; skip ed_hs columns of this line
    mov edx, [ed_hs]
.hs:
    test edx, edx
    jz .chars
    cmp esi, [ed_len]
    jae .chars
    cmp byte [ED_BUF+esi], 10
    je .chars
    inc esi
    dec edx
    jmp .hs
.chars:
    cmp esi, [ed_len]
    jae .eof
    mov al, [ED_BUF+esi]
    cmp al, 10
    je .eol
    inc esi
    jecxz .chars                ; clipped on the right
    cmp al, ' '
    jae .pr
    call ed_ctlglyph            ; control characters
.pr:
    mov ah, ATTR_TEXT
    stosw
    dec ecx
    jmp .chars
.eol:
    inc esi
    cmp byte [ed_ctl], 0        ; vedit Ctrl+T: show the line end as '$'
    je .pad
    test edx, edx               ; the line ended before ed_hs: its end is
    jnz .pad                    ; off the screen to the left
    jecxz .pad
    mov ax, (ATTR_DIM<<8)|'$'
    stosw
    dec ecx
    jmp .pad
.eof:
    mov byte [ed_more], 0
.pad:
    mov ax, (ATTR_TEXT<<8)|' '
    rep stosw
    inc ebx
    call ed_rows
    cmp ebx, ecx
    jb .row
    call ed_status
    ; message row
    call sb_reset
    mov esi, [ed_msgp]
    test esi, esi
    jz .nomsg
    call sb_str
.nomsg:
    mov ebx, [txt_rows]
    dec ebx                     ; the message row
    mov ah, ATTR_TEXT
    call sb_row
    ; hardware cursor
    mov eax, [ed_line]
    sub eax, [ed_top]
    imul eax, 80
    add eax, [ed_col]
    sub eax, [ed_hs]
    cmp byte [ed_verbose], 0
    je .cur
    add eax, ED_GUTTER
.cur:
    mov [cur], eax
    call cursor_sync
    mov byte [txt_dirty], 1     ; a desktop window shows the new screen
    popad
    ret

ed_status:
    call sb_reset
    mov al, ' '
    call sb_char
    cmp byte [ed_verbose], 0
    jne .verbose
    mov esi, [lstr+LS_EDIT*4]   ; title in the current language (1.0.6)
    call sb_str
    mov esi, ed_s_sep
    call sb_str
    mov esi, ed_name
    cmp byte [esi], 0
    jne .n
    mov esi, [lstr+LS_ED_S_NONAME*4]
.n:
    call sb_str
    cmp byte [ed_mod], 0
    je .nm
    mov esi, [lstr+LS_ED_S_MOD*4]
    call sb_str
.nm:
    mov eax, [txt_cols]
    sub eax, 34                 ; the key reminder ends at the last column
    mov ebx, [sb_p]
    sub ebx, ed_sb
    cmp ebx, eax
    jae .out                    ; no room for it (a desktop window, 1.6.4)
    call sb_pad
    mov esi, [lstr+LS_ED_S_KEYS*4]
    call sb_str
    jmp .out
.verbose:
    mov esi, ed_s_line
    call sb_str
    mov eax, [ed_line]
    inc eax
    call sb_num
    mov esi, ed_s_col
    call sb_str
    mov eax, [ed_col]
    inc eax
    call sb_num
    mov esi, ed_s_off
    call sb_str
    mov eax, [ed_pos]
    call sb_num
    mov esi, ed_s_char
    call sb_str
    mov eax, [ed_pos]
    cmp eax, [ed_len]
    jb .ch
    mov esi, ed_s_eof
    call sb_str
    jmp .mode
.ch:
    mov al, [ED_BUF+eax]
    call sb_charinfo
.mode:
    mov esi, ed_s_ins
    cmp byte [ed_ins], 0
    jne .md
    mov esi, ed_s_ovr
.md:
    call sb_str
    mov esi, ed_s_modv
    cmp byte [ed_mod], 0
    jne .mv
    mov esi, ed_s_clean
.mv:
    call sb_str
    mov eax, [ed_len]
    call sb_num
    mov al, '/'
    call sb_char
    mov eax, ED_CAP
    call sb_num
    mov al, ' '
    call sb_char
    mov esi, ed_name
    call sb_str
.out:
    call ed_rows
    mov ebx, ecx                ; the status row follows the text
    mov ah, ATTR_STATUS
    call sb_row
    ret

; ---------- string builder (ed_sb) and VGA helpers ----------

sb_reset:
    mov dword [sb_p], ed_sb
    mov byte [ed_sb], 0
    ret

sb_char:                        ; al
    push edi
    mov edi, [sb_p]
    cmp edi, ed_sb+80
    jae .full
    mov [edi], al
    inc edi
    mov byte [edi], 0
    mov [sb_p], edi
.full:
    pop edi
    ret

sb_str:                         ; esi = ASCIIZ, or up to a newline (esi preserved)
    push eax
    push esi
.l:
    lodsb
    test al, al
    jz .d
    cmp al, 10
    je .d
    call sb_char
    jmp .l
.d:
    pop esi
    pop eax
    ret

sb_num:                         ; eax, signed decimal
    push esi
    push edi
    call itoa
    mov esi, num_buf
    call sb_str
    pop edi
    pop esi
    ret

sb_num_right5:                  ; eax right-aligned in 5 columns + space
    push eax
    push esi
    push edi
    call itoa
    mov esi, num_buf
    call strlen
    mov ecx, 5
    sub ecx, eax
    jbe .n
.sp:
    mov al, ' '
    call sb_char
    loop .sp
.n:
    call sb_str
    mov al, ' '
    call sb_char
    pop edi
    pop esi
    pop eax
    ret

sb_pad:                         ; eax = column to pad to with spaces
    push eax
    push ebx
    mov ebx, eax
.l:
    mov eax, [sb_p]
    sub eax, ed_sb
    cmp eax, ebx
    jae .d
    mov al, ' '
    call sb_char
    jmp .l
.d:
    pop ebx
    pop eax
    ret

sb_hex2:                        ; al -> two hex digits
    push eax
    push ecx
    mov ah, al
    mov ecx, 2
.h:
    rol ah, 4
    mov al, ah
    and al, 0x0F
    add al, '0'
    cmp al, '9'
    jbe .d
    add al, 'A'-'9'-1
.d:
    call sb_char
    loop .h
    pop ecx
    pop eax
    ret

; al = byte -> "'c' 0xNN (N)" (newline shown as \n)
sb_charinfo:
    push eax
    push esi
    movzx esi, al
    mov al, 39
    call sb_char
    mov eax, esi
    cmp al, 10
    je .nl
    cmp al, ' '
    jae .pr
    mov al, '.'
.pr:
    call sb_char
    jmp .q
.nl:
    mov al, '\'
    call sb_char
    mov al, 'n'
    call sb_char
.q:
    mov al, 39
    call sb_char
    mov al, ' '
    call sb_char
    mov al, '0'
    call sb_char
    mov al, 'x'
    call sb_char
    mov eax, esi
    call sb_hex2
    mov al, ' '
    call sb_char
    mov al, '('
    call sb_char
    mov eax, esi
    call sb_num
    mov al, ')'
    call sb_char
    pop esi
    pop eax
    ret

; -> ecx = text rows on screen (txt_rows less the status and message rows)
ed_rows:
    mov ecx, [txt_rows]
    sub ecx, 2
    ret

; ebx = screen row, ah = attribute: writes ed_sb padded to txt_cols columns
sb_row:
    pushad
    mov edi, ebx
    imul edi, 160
    add edi, [txt_base]         ; the screen, or a desktop window's (1.6.3)
    mov esi, ed_sb
    mov ecx, [txt_cols]
    call vga_text
    mov byte [txt_dirty], 1
    popad
    ret

; esi = ASCIIZ, edi = VGA address, ecx = width, ah = attribute.
; Writes the text clipped/padded to the width; edi advances.
vga_text:
    push esi
.l:
    jecxz .d
    lodsb
    test al, al
    jz .pad
    stosw
    dec ecx
    jmp .l
.pad:
    mov al, ' '
    rep stosw
.d:
    pop esi
    ret

ed_verbose db 0
ed_mod db 0
ed_ins db 1
ed_more db 0
ed_key db 0
ed_last db 0
ed_len dd 0
ed_pos dd 0
ed_top dd 0
ed_hs dd 0
ed_want dd -1
ed_line dd 0
ed_col dd 0
ed_width dd 80
ed_msgp dd 0
ed_pdst dd 0
sb_p dd ed_sb
ed_name times FS_PATHMAX db 0
ed_sb times 82 db 0
ed_msgbuf times 82 db 0
ed_find times FS_PATHMAX db 0   ; last Ctrl+F text, kept for F3
ed_upages times ED_UNDO_PAGES dd 0   ; undo copy of the buffer
ed_ulen dd 0
ed_upos dd 0
ed_umod db 0
ed_ctl db 0                     ; 1: vedit shows control characters (Ctrl+T)
ed_uok db 0                     ; 1: Ctrl+Z has something to undo
ed_pany db 0                    ; 1: ed_prompt accepts spaces
ed_s_sep db ': ', 0
ed_s_line db 'L', 0
ed_s_col db ' C', 0
ed_s_off db ' off ', 0
ed_s_char db ' ', 0
ed_s_eof db 'EOF', 0
ed_s_ins db ' INS', 0
ed_s_ovr db ' OVR', 0
ed_s_modv db ' MOD ', 0
ed_s_clean db ' --- ', 0
ed_m_find db 'Find (Esc cancels): ', 0
ed_m_undone db 'Undone.', 0
ed_m_ctlon db 'Control characters shown: $ line end, > tab, ^ other.', 0
ed_m_ctloff db 'Control characters hidden.', 0
ed_m_nothing db 'Nothing to undo.', 0
ed_m_noundo db 'Undo unavailable: no free memory.', 0
ed_m_found db 'Found ', 0
ed_m_atline db ' at line ', 0
ed_m_atcol db ', column ', 0
ed_m_notfound db 'Not found: ', 0
ed_m_nofind db 'Nothing to find again: Ctrl+F first', 0
