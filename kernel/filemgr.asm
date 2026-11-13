; Squirrel-OS/2 — File Manager (2.3-filemgr). Original code.
;
; filemgr: one window, two panes. Left, the directory tree of the data
; disk; right, the chosen directory's entries (directories first). The
; left and right arrows choose the pane, up and down the row; in the tree
; the list follows the row. Enter opens a directory in the list,
; Backspace goes up. c copies, m moves, r renames, n makes a directory
; (each asks on the status line; a name is in the shown directory, a path
; starting with / is absolute, and a directory as the target keeps the
; name), Delete deletes after y. A file dragged from the list onto a
; directory in the tree moves there (copies with Ctrl held). Esc quits.
; Starts in the shell's current directory. See documentation/apps/filemgr.md.

FM_MAXT     equ 32              ; tree rows
FM_MAXL     equ FS_MAXFILES     ; list rows
FM_ROW      equ 11              ; a row: the window face and a margin
FM_INDENT   equ 8               ; per tree level
FM_INMAX    equ 40              ; characters typed on the status line
FM_PATH     equ 80

FMO_COPY    equ 'c'
FMO_MOVE    equ 'm'
FMO_REN     equ 'r'
FMO_MKDIR   equ 'n'
FMO_DEL     equ 'd'

cmd_filemgr_run:
    cmp byte [fs_mounted], 0
    jne .fs
    mov byte [fs_errno], FE_NOFS
    jmp fs_why
.fs:
    call wm_screen
    jnc .ok
    mov esi, dk_nomem
    jmp puts
.ok:
    movzx eax, byte [fs_cwd]
    mov [fm_cur], eax
    mov dword [fm_pane], 1
    mov dword [fm_lsel], 0
    mov byte [fm_op], 0
    mov dword [fm_stat], fm_s_help
    mov dword [fm_drag], -1
    mov dword [fm_last], -1
    call fm_scan
    cmp dword [gfx_width], 640
    jb .small
    mov eax, 20
    mov ebx, 20
    mov ecx, 600
    mov edx, 440
    jmp .win
.small:
    xor eax, eax
    xor ebx, ebx
    mov ecx, GFX_W
    mov edx, GFX_H
.win:
    mov esi, fm_title
    call wm_create
    mov [fm_win], eax
    cmp eax, -1
    je .quit
    mov [dk_win], eax           ; Alt+F4 / Close quit (dk_wmreply)
    imul edi, eax, WIN_SIZE
    mov dword [wm_table+edi+WIN_PAINT], fm_paint
    mov byte [dk_quit], 0
.draw:
    call wm_redraw
    call ptr_show
.key:
    call mouse_poll
    call fm_wm                  ; CF: quit
    jc .quit
    call ptr_show
    cmp byte [fm_dirty], 0
    je .k
    mov byte [fm_dirty], 0
    jmp .draw
.k:
    call dk_trykey
    jc .menu
    cmp byte [dk_quit], 0
    jne .quit
    cmp byte [fm_op], 0
    jne .prompt
    cmp al, 27
    je .quit
    call fm_key
    jmp .draw
.prompt:
    call fm_pkey
    jmp .draw
.menu:                          ; a File menu item chosen (key or mouse)
    mov eax, [dk_menu]
    test eax, eax
    jz .key
    mov dword [dk_menu], 0
    mov al, [fm_mkeys+eax-1]
    cmp byte [fm_op], 0
    jne .draw
    call fm_key
    jmp .draw
.quit:
    mov eax, [fm_win]
    cmp eax, -1
    je .gone
    call wm_close
.gone:
    call gfx_text
    mov esi, fm_bye
    jmp puts

; ---------- the panes' contents ----------

; Rebuilds the tree and the list of [fm_cur]; keeps the choices in range.
fm_scan:
    pushad
    mov dword [fm_tn], 0
    xor edx, edx                ; the root, depth 0
    xor ecx, ecx
    call fm_tadd
    mov dword [fm_tsel], 0      ; the tree row of the shown directory
    xor ecx, ecx
.t:
    cmp ecx, [fm_tn]
    jae .list
    mov eax, [fm_tid+ecx*4]
    cmp eax, [fm_cur]
    je .tfound
    inc ecx
    jmp .t
.tfound:
    mov [fm_tsel], ecx
.list:
    mov dword [fm_ln], 0
    mov bl, DK_DIR              ; directories first, then files
    call fm_ladd
    mov bl, DK_FILE
    call fm_ladd
    mov eax, [fm_ln]
    cmp [fm_lsel], eax
    jb .r
    dec eax
    jns .s
    xor eax, eax
.s:
    mov [fm_lsel], eax
.r:
    mov byte [fm_dirty], 1
    popad
    ret

; edx = a directory id, ecx = its depth: it and the directories under it
; (depth first, in table order) go on the tree
fm_tadd:
    pushad
    mov eax, [fm_tn]
    cmp eax, FM_MAXT
    jae .r
    mov [fm_tid+eax*4], edx
    mov [fm_tdep+eax*4], ecx
    inc dword [fm_tn]
    xor ebx, ebx
.e:
    cmp ebx, FS_MAXFILES
    jae .r
    mov esi, ebx
    shl esi, 5
    add esi, FS_DIR
    cmp byte [esi], 0
    je .n
    cmp byte [esi+DE_KIND], DK_DIR
    jne .n
    cmp [esi+DE_PARENT], dl
    jne .n
    push edx
    push ecx
    lea edx, [ebx+1]            ; its id
    inc ecx
    call fm_tadd
    pop ecx
    pop edx
.n:
    inc ebx
    jmp .e
.r:
    popad
    ret

; bl = DK_DIR or DK_FILE: the entries of that kind in [fm_cur] go on the list
fm_ladd:
    pushad
    mov edx, [fm_cur]
    xor ecx, ecx
.e:
    cmp ecx, FS_MAXFILES
    jae .r
    mov esi, ecx
    shl esi, 5
    add esi, FS_DIR
    cmp byte [esi], 0
    je .n
    cmp [esi+DE_KIND], bl
    jne .n
    cmp [esi+DE_PARENT], dl
    jne .n
    mov eax, [fm_ln]
    mov [fm_lent+eax*4], ecx
    inc dword [fm_ln]
.n:
    inc ecx
    jmp .e
.r:
    popad
    ret

; edx = a directory id, edi = buffer -> its absolute path ("/" for the
; root), edi at the terminating zero
fm_dirpath:
    push eax
    push ecx
    push edx
    push esi
    xor ecx, ecx                ; ids from the directory up to the root
.up:
    test edx, edx
    jz .emit
    cmp ecx, 16
    jae .emit
    mov [fm_chain+ecx*4], edx
    inc ecx
    lea esi, [edx-1]
    shl esi, 5
    movzx edx, byte [FS_DIR+esi+DE_PARENT]
    jmp .up
.emit:
    test ecx, ecx
    jnz .parts
    mov byte [edi], '/'
    inc edi
    jmp .end
.parts:
    dec ecx
    mov byte [edi], '/'
    inc edi
    mov esi, [fm_chain+ecx*4]
    dec esi
    shl esi, 5
    add esi, FS_DIR
    call fm_cpyname
    test ecx, ecx
    jnz .parts
.end:
    mov byte [edi], 0
    pop esi
    pop edx
    pop ecx
    pop eax
    ret

; esi = an entry: its name to edi (at most 15 characters), edi past it
fm_cpyname:
    push eax
    push ecx
    push esi
    mov ecx, FS_NAMELEN - 1
.c:
    lodsb
    test al, al
    jz .r
    stosb
    loop .c
.r:
    pop esi
    pop ecx
    pop eax
    ret

; eax = an entry's index, edi = buffer -> its absolute path
fm_entpath:
    push eax
    push edx
    push esi
    mov esi, eax
    shl esi, 5
    add esi, FS_DIR
    movzx edx, byte [esi+DE_PARENT]
    call fm_dirpath
    cmp byte [edi-1], '/'
    je .name
    mov byte [edi], '/'
    inc edi
.name:
    call fm_cpyname
    mov byte [edi], 0
    pop esi
    pop edx
    pop eax
    ret

; esi = what was typed, edi = buffer: an absolute path as typed, or the
; shown directory's path and the name
fm_resolve:
    push edx
    cmp byte [esi], '/'
    je .copy
    mov edx, [fm_cur]
    call fm_dirpath
    cmp byte [edi-1], '/'
    je .copy
    mov byte [edi], '/'
    inc edi
.copy:
    push esi
.c:
    lodsb
    stosb
    test al, al
    jnz .c
    pop esi
    pop edx
    ret

; -> eax = the chosen list entry's index, CF set if the list is empty
fm_chosen:
    mov eax, [fm_lsel]
    cmp eax, [fm_ln]
    jae .no
    mov eax, [fm_lent+eax*4]
    clc
    ret
.no:
    stc
    ret

; ---------- keys ----------

; al = a key in the normal mode
fm_key:
    cmp al, WK_LEFT
    je .left
    cmp al, WK_RIGHT
    je .right
    cmp al, WK_UP
    je .up
    cmp al, WK_DOWN
    je .down
    cmp al, 10
    je .enter
    cmp al, 8
    je .back
    cmp al, WK_DEL
    je .del
    cmp al, FMO_COPY
    je .withfile
    cmp al, FMO_MOVE
    je .withfile
    cmp al, FMO_REN
    je .withfile
    cmp al, FMO_MKDIR
    je .ask
    cmp al, 'f'
    je fm_menu
    ret
.left:
    mov dword [fm_pane], 0
    mov byte [fm_dirty], 1
    ret
.right:
    mov dword [fm_pane], 1
    mov byte [fm_dirty], 1
    ret
.up:
    mov ecx, -1
    jmp .move
.down:
    mov ecx, 1
.move:
    cmp dword [fm_pane], 0
    jne .lmove
    mov eax, [fm_tsel]          ; the tree: the list follows
    add eax, ecx
    js .r
    cmp eax, [fm_tn]
    jae .r
    mov eax, [fm_tid+eax*4]
    mov [fm_cur], eax
    mov dword [fm_lsel], 0
    jmp fm_scan
.lmove:
    mov eax, [fm_lsel]
    add eax, ecx
    js .r
    cmp eax, [fm_ln]
    jae .r
    mov [fm_lsel], eax
    mov byte [fm_dirty], 1
.r:
    ret
.enter:
    cmp dword [fm_pane], 1
    jne .r
    call fm_chosen
    jc .r
    jmp fm_open
.back:
    mov eax, [fm_cur]
    test eax, eax
    jz .r
    dec eax
    shl eax, 5
    movzx eax, byte [FS_DIR+eax+DE_PARENT]
    mov [fm_cur], eax
    mov dword [fm_lsel], 0
    jmp fm_scan
.del:
    call fm_chosen
    jc .r
    mov al, FMO_DEL
    mov dword [fm_ask], fm_s_del
    jmp .start
.withfile:
    push eax
    call fm_chosen
    pop eax
    jc .r
.ask:
    mov dword [fm_ask], fm_s_copy
    cmp al, FMO_COPY
    je .start
    mov dword [fm_ask], fm_s_move
    cmp al, FMO_MOVE
    je .start
    mov dword [fm_ask], fm_s_ren
    cmp al, FMO_REN
    je .start
    mov dword [fm_ask], fm_s_mkdir
.start:
    mov [fm_op], al
    mov byte [fm_in], 0
    mov dword [fm_inn], 0
    mov dword [fm_stat], 0      ; the status line shows the question
    mov byte [fm_dirty], 1
    ret

; The File menu: Copy, Move, Rename, New directory, Delete, as a pop-up
; at the chosen list row (f), or at the pointer (the right button)
fm_menu:
    pushad
    mov eax, [fm_lx]
    add eax, 40
    mov ebx, [fm_lsel]
    sub ebx, [fm_ltop]
    inc ebx
    imul ebx, ebx, FM_ROW
    add ebx, [fm_py]
    call fm_popup
    popad
    ret

; eax, ebx = where: the File menu opens there
fm_popup:
    pushad
    mov esi, fm_mitems
    mov edx, FM_MITEMS
    mov ecx, [fm_win]
    call wm_popup
    mov byte [fm_dirty], 1
    popad
    ret

; eax = an entry: a directory opens in the list (a file does nothing)
fm_open:
    push esi
    mov esi, eax
    shl esi, 5
    cmp byte [FS_DIR+esi+DE_KIND], DK_DIR
    pop esi
    jne .r
    inc eax
    mov [fm_cur], eax
    mov dword [fm_lsel], 0
    jmp fm_scan
.r:
    ret

; al = a key while a question is on the status line
fm_pkey:
    cmp al, 27
    je .cancel
    cmp byte [fm_op], FMO_DEL
    je .yn
    cmp al, 10
    je .go
    cmp al, 8
    je .bs
    cmp al, ' '
    jbe .r
    cmp al, 0x7E
    ja .r
    mov ecx, [fm_inn]
    cmp ecx, FM_INMAX
    jae .r
    mov [fm_in+ecx], al
    mov byte [fm_in+ecx+1], 0
    inc dword [fm_inn]
    mov byte [fm_dirty], 1
.r:
    ret
.bs:
    mov ecx, [fm_inn]
    jecxz .r
    dec ecx
    mov [fm_inn], ecx
    mov byte [fm_in+ecx], 0
    mov byte [fm_dirty], 1
    ret
.yn:
    cmp al, 'y'
    jne .cancel
.go:
    call fm_do
    mov byte [fm_op], 0
    jmp fm_scan
.cancel:
    mov byte [fm_op], 0
    mov dword [fm_stat], fm_s_help
    mov byte [fm_dirty], 1
    ret

; Carries out [fm_op] on the chosen entry with what was typed; the status
; line says how it went.
fm_do:
    pushad
    cmp byte [fm_op], FMO_MKDIR
    je .mkdir
    call fm_chosen
    jc .fail
    mov edi, fm_p1              ; the chosen entry's path
    call fm_entpath
    mov esi, fm_in
    cmp byte [fm_op], FMO_DEL
    je .del
    cmp byte [esi], 0
    je .fail                    ; nothing typed
    mov edi, fm_p2
    cmp byte [fm_op], FMO_REN
    je .ren
    call fm_resolve
    mov esi, fm_p1
    mov edi, fm_p2
    cmp byte [fm_op], FMO_MOVE
    je .move
    call fm_copy
    jmp .result
.move:
    call fs_rename
    jmp .result
.ren:                           ; a new name in the same directory
    mov eax, [fm_lsel]
    mov eax, [fm_lent+eax*4]
    shl eax, 5
    movzx edx, byte [FS_DIR+eax+DE_PARENT]
    call fm_dirpath
    cmp byte [edi-1], '/'
    je .rn
    mov byte [edi], '/'
    inc edi
.rn:
    lodsb
    stosb
    test al, al
    jnz .rn
    mov esi, fm_p1
    mov edi, fm_p2
    call fs_rename
    jmp .result
.del:
    mov esi, fm_p1
    call fs_delete
    jmp .result
.mkdir:
    cmp byte [fm_in], 0
    je .fail
    mov esi, fm_in
    mov edi, fm_p2
    call fm_resolve
    mov esi, fm_p2
    call fs_mkdir
.result:
    cmp eax, -1
    je .fail
    mov dword [fm_stat], fm_s_done
    popad
    ret
.fail:
    movzx eax, byte [fs_errno]
    call fs_errstr
    mov [fm_stat], esi
    popad
    ret

; esi = source path, edi = target path (a directory: the same name in
; it) -> eax = 0, or -1 (fs_errno says why)
fm_copy:
    pushad
    push esi
    mov esi, edi
    call fs_find_dir            ; a directory: add the source's name
    pop esi
    jc .file
    push esi
    mov esi, edi
.end:
    lodsb
    test al, al
    jnz .end
    lea edi, [esi-1]
    pop esi
    cmp byte [edi-1], '/'
    je .tail
    mov byte [edi], '/'
    inc edi
.tail:
    push esi                    ; the source's last part
    mov edx, esi
.last:
    lodsb
    test al, al
    jz .lastd
    cmp al, '/'
    jne .last
    mov edx, esi
    jmp .last
.lastd:
    mov esi, edx
.cp:
    lodsb
    stosb
    test al, al
    jnz .cp
    pop esi
    mov edi, [esp+0]            ; (edi as pushed by pushad is the target)
.file:
    mov ecx, 0                  ; the source
    call fs_open
    cmp eax, -1
    je .fail
    mov [fm_fd1], eax
    mov esi, [esp+0]            ; the target, as completed
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .fail1
    mov [fm_fd2], eax
.chunk:
    mov ebx, [fm_fd1]
    mov edi, fm_cbuf
    mov ecx, 512
    call fs_read
    cmp eax, -1
    je .fail2
    test eax, eax
    jz .done
    mov ecx, eax
    mov ebx, [fm_fd2]
    mov esi, fm_cbuf
    call fs_write
    cmp eax, ecx
    jne .fail2
    jmp .chunk
.done:
    mov ebx, [fm_fd2]
    call fs_close
    mov ebx, [fm_fd1]
    call fs_close
    popad
    xor eax, eax
    ret
.fail2:
    mov ebx, [fm_fd2]
    call fs_close
.fail1:
    mov ebx, [fm_fd1]
    call fs_close
.fail:
    popad
    mov eax, -1
    ret

; eax = a list entry, edx = a tree row: the entry moves into that
; directory (copies with Ctrl held). A drop on its own directory, or of a
; directory into itself, changes nothing.
fm_drop:
    pushad
    cmp edx, [fm_tn]
    jae .r
    mov ecx, [fm_tid+edx*4]
    mov esi, eax
    shl esi, 5
    movzx ebx, byte [FS_DIR+esi+DE_PARENT]
    cmp ebx, ecx
    je .r
    mov edi, fm_p1
    call fm_entpath
    mov edx, ecx
    mov edi, fm_p2
    call fm_dirpath
    mov esi, fm_p1
    mov edi, fm_p2
    cmp byte [kbd_ctrl], 0
    jne .copy
    call fs_rename
    jmp .res
.copy:
    call fm_copy
.res:
    mov dword [fm_stat], fm_s_done
    cmp eax, -1
    jne .scan
    movzx eax, byte [fs_errno]
    call fs_errstr
    mov [fm_stat], esi
.scan:
    call fm_scan
.r:
    popad
    ret

; ---------- painting ----------

; The panes inside the client area eax, ebx, ecx (width), edx (height):
; fm_tx.. (tree), fm_lx.. (list), fm_sy (the status line's top)
fm_layout:
    pushad
    mov [fm_cx], eax
    mov [fm_cy], ebx
    lea esi, [edx-FM_ROW-8]     ; the panes' height
    mov [fm_ph], esi
    lea esi, [ebx+edx-FM_ROW-2]
    mov [fm_sy], esi
    mov esi, eax
    add esi, 4
    mov [fm_tx], esi
    mov eax, ecx
    xor edx, edx
    mov esi, 3
    div esi
    sub eax, 6
    mov [fm_tw], eax
    add eax, [fm_tx]
    add eax, 4
    mov [fm_lx], eax
    mov esi, [fm_cx]
    add esi, ecx
    sub esi, 4
    sub esi, eax
    mov [fm_lw], esi
    add ebx, 4
    mov [fm_py], ebx
    popad
    ret

; wm_draw's WIN_PAINT: edi = the record, eax..edx = the client area
fm_paint:
    pushad
    call fm_layout
    call pm_clipin              ; (2.3-groups: cut to the client area)
    mov byte [gfx_colour], TH_BTN_FACE
    mov eax, [fm_tx]            ; the panes: white, sunken
    mov ebx, [fm_py]
    mov ecx, [fm_tw]
    mov edx, [fm_ph]
    call gfx_fillrect
    mov esi, 1
    call gfx_bevel
    mov eax, [fm_lx]
    mov ecx, [fm_lw]
    call gfx_fillrect
    call gfx_bevel
    call fm_drawtree
    call fm_drawlist
    call fm_drawstat
    call pm_clipout
    popad
    ret

; -> ecx = rows that fit in a pane
fm_rows:
    push eax
    push edx
    mov eax, [fm_ph]
    sub eax, 2 * TH_BEVEL_W + 2
    xor edx, edx
    mov ecx, FM_ROW
    div ecx
    mov ecx, eax
    pop edx
    pop eax
    ret

; eax = the chosen row, esi = the first row's address -> [esi] adjusted so
; the chosen row shows (ecx = rows that fit)
fm_scroll:
    cmp eax, [esi]
    jae .below
    mov [esi], eax
    ret
.below:
    push eax
    sub eax, ecx
    inc eax
    js .ok
    cmp eax, [esi]
    jbe .ok
    mov [esi], eax
.ok:
    pop eax
    ret

fm_drawtree:
    pushad
    call fm_rows
    mov eax, [fm_tsel]
    mov esi, fm_ttop
    call fm_scroll
    xor ebp, ebp                ; row on the screen
.row:
    cmp ebp, ecx
    jae .r
    mov edx, [fm_ttop]
    add edx, ebp
    cmp edx, [fm_tn]
    jae .r
    push ecx
    mov eax, [fm_tdep+edx*4]
    imul eax, eax, FM_INDENT
    add eax, [fm_tx]
    add eax, TH_BEVEL_W + 2
    imul ebx, ebp, FM_ROW
    add ebx, [fm_py]
    add ebx, TH_BEVEL_W + 1
    mov esi, fm_s_root
    mov ecx, [fm_tid+edx*4]
    jecxz .name
    lea esi, [ecx-1]
    shl esi, 5
    add esi, FS_DIR
.name:
    mov ecx, [fm_tx]
    add ecx, [fm_tw]
    sub ecx, eax
    sub ecx, TH_BEVEL_W + 2     ; room
    cmp edx, [fm_tsel]
    sete dl
    xor dh, dh
    cmp dword [fm_pane], 0
    sete dh
    call fm_drawrow
    pop ecx
    inc ebp
    jmp .row
.r:
    popad
    ret

fm_drawlist:
    pushad
    call fm_rows
    mov eax, [fm_lsel]
    mov esi, fm_ltop
    call fm_scroll
    xor ebp, ebp
.row:
    cmp ebp, ecx
    jae .r
    mov edx, [fm_ltop]
    add edx, ebp
    cmp edx, [fm_ln]
    jae .r
    push ecx
    push edx
    mov eax, [fm_lx]
    add eax, TH_BEVEL_W + 2
    imul ebx, ebp, FM_ROW
    add ebx, [fm_py]
    add ebx, TH_BEVEL_W + 1
    mov esi, [fm_lent+edx*4]
    shl esi, 5
    add esi, FS_DIR
    mov ecx, [fm_lw]
    sub ecx, 2 * TH_BEVEL_W + 4
    cmp edx, [fm_lsel]
    sete dl
    xor dh, dh
    cmp dword [fm_pane], 1
    sete dh
    call fm_drawrow
    push esi                    ; the size, or <dir>, at the right
    mov edi, esi
    mov esi, fm_s_dir
    cmp byte [edi+DE_KIND], DK_DIR
    je .sz
    mov eax, [edi+DE_SIZE]
    push edi
    call itoa
    pop edi
    mov esi, num_buf
.sz:
    mov eax, [fm_lx]
    add eax, [fm_lw]
    sub eax, 48
    mov ecx, 40
    call wm_drawtitle
    pop esi
    pop edx
    pop ecx
    inc ebp
    jmp .row
.r:
    popad
    ret

; eax, ebx = where, ecx = room, esi = text, dl = 1 the chosen row, dh = 1
; its pane has the focus: the row's band and text
fm_drawrow:
    pushad
    mov byte [gfx_colour], TH_TEXT
    mov byte [gfx_bg], TH_BTN_FACE
    test dl, dl
    jz .text
    mov byte [fm_ink], TH_TEXT
    mov byte [gfx_bg], TH_FACE  ; chosen, pane without the focus: grey
    test dh, dh
    jz .band
    mov byte [fm_ink], TH_SELECT_TEXT
    mov byte [gfx_bg], TH_SELECT
.band:
    push eax
    push ebx
    push ecx
    dec eax
    dec ebx
    add ecx, 2
    mov dl, [gfx_bg]
    mov [gfx_colour], dl
    mov edx, FM_ROW
    call gfx_fillrect
    pop ecx
    pop ebx
    pop eax
    mov dl, [fm_ink]
    mov [gfx_colour], dl
.text:
    call wm_drawtitle
    popad
    ret

fm_drawstat:
    pushad
    mov eax, [fm_cx]
    add eax, 4
    mov ebx, [fm_sy]
    mov byte [gfx_colour], TH_TEXT
    mov byte [gfx_bg], TH_CLIENT
    mov esi, [fm_stat]
    test esi, esi
    jnz .say
    mov edi, fm_line            ; the question, what was typed and a cursor
    mov esi, [fm_ask]
    call fm_cat
    mov esi, fm_in
    call fm_cat
    mov byte [edi], '_'
    mov byte [edi+1], 0
    mov esi, fm_line
.say:
    mov ecx, [fm_lx]
    add ecx, [fm_lw]
    sub ecx, eax
    call wm_drawtitle
    popad
    ret

; esi = string -> copied to edi, edi at its end
fm_cat:
    lodsb
    test al, al
    jz .r
    stosb
    jmp fm_cat
.r:
    mov byte [edi], 0
    ret

; ---------- mouse ----------

; Like pm_wm: the mouse to the window manager; presses in the client
; choose a pane's row, a second press on the chosen list row soon after
; opens a directory, a press-and-release from a list row onto a tree row
; drops (fm_drop). CF set: quit (the close box).
fm_wm:
    cmp byte [dk_quit], 0
    je .live
    stc
    ret
.live:
    pushad
    pushfd
    cli
    mov eax, [mouse_x]
    mov ebx, [mouse_y]
    mov cl, [mouse_btns]
    popfd
    cmp eax, [dk_lmx]
    jne .go
    cmp ebx, [dk_lmy]
    jne .go
    cmp cl, [dk_lmb]
    je .no
.go:
    mov [dk_lmx], eax
    mov [dk_lmy], ebx
    mov [dk_lmb], cl
    test cl, 2                  ; the right button: the File menu there
    jz .noright
    test byte [fm_lbtn], 2
    jnz .noright
    mov [fm_lbtn], cl
    call fm_popup
    jmp .upd
.noright:
    mov [fm_lbtn], cl
    test cl, 1
    jnz .down
    cmp dword [fm_drag], -1     ; let go of a dragged list row
    je .down
    push eax
    push ebx
    push ecx
    call fm_hit                 ; over a tree row?
    jc .nodrop
    test ecx, ecx
    jnz .nodrop
    mov eax, [fm_drag]
    call fm_drop
.nodrop:
    mov dword [fm_drag], -1
    pop ecx
    pop ebx
    pop eax
.down:
    call wm_mouse
    cmp eax, WME_MENU           ; a File menu item clicked
    jne .notmenu
    inc ecx
    mov [dk_menu], ecx
    jmp .upd
.notmenu:
    cmp eax, WME_CLOSE
    jne .client
    cmp ebx, [fm_win]
    je .quit
    jmp .upd
.client:
    cmp eax, WME_CLIENT
    jne .upd
    mov eax, [dk_lmx]
    mov ebx, [dk_lmy]
    call fm_hit                 ; ecx = pane, edx = row
    jc .upd
    mov [fm_pane], ecx
    mov byte [fm_dirty], 1
    test ecx, ecx
    jnz .list
    mov eax, [fm_tid+edx*4]     ; a tree row: show it
    mov [fm_cur], eax
    mov dword [fm_lsel], 0
    call fm_scan
    jmp .upd
.list:
    mov eax, [ticks]
    cmp edx, [fm_last]
    jne .one
    sub eax, [fm_lastt]
    cmp eax, PM_DBL
    ja .one
    mov dword [fm_last], -1     ; double-click: a directory opens
    mov eax, [fm_lent+edx*4]
    call fm_open
    jmp .upd
.one:
    mov [fm_lsel], edx
    mov [fm_last], edx
    mov eax, [ticks]
    mov [fm_lastt], eax
    mov eax, [fm_lent+edx*4]
    mov [fm_drag], eax
.upd:
    cmp dword [wm_dn], 0
    jne .paint
    cmp byte [wm_dfull], 0
    je .no
.paint:
    call wm_update
.no:
    popad
    clc
    ret
.quit:
    popad
    stc
    ret

; eax, ebx = a place on the screen -> ecx = 0 tree / 1 list, edx = the
; row under it (scroll included), CF clear; CF set if no row is there
fm_hit:
    push eax
    push ebx
    mov edx, ebx
    sub edx, [fm_py]
    sub edx, TH_BEVEL_W + 1
    js .no
    push eax
    mov eax, edx
    xor edx, edx
    mov ecx, FM_ROW
    div ecx
    mov edx, eax                ; the row on the screen
    pop eax
    xor ecx, ecx
    mov ebx, eax
    sub ebx, [fm_tx]
    js .no
    cmp ebx, [fm_tw]
    jb .tree
    mov ebx, eax
    sub ebx, [fm_lx]
    js .no
    cmp ebx, [fm_lw]
    jae .no
    inc ecx
    add edx, [fm_ltop]
    cmp edx, [fm_ln]
    jae .no
    jmp .yes
.tree:
    add edx, [fm_ttop]
    cmp edx, [fm_tn]
    jae .no
.yes:
    pop ebx
    pop eax
    clc
    ret
.no:
    pop ebx
    pop eax
    stc
    ret

; ---------- fmtest ----------
; On the data disk: makes /fmt, /fmt/sub and /fmt/f ("abc"), shows /fmt
; and checks the panes (the tree has /fmt at depth 1 and sub at depth 2,
; the list sub then f), the paths, a drop of f onto sub (it moves), a copy
; back (fm_copy into a directory keeps the name; the copy reads "abc"),
; then removes it all. Prints `fm: PASS` or `fm: FAIL at N`.
cmd_fmtest_run:
    cmp byte [fs_mounted], 0
    jne .fs
    mov byte [fs_errno], FE_NOFS
    jmp fs_why
.fs:
    mov byte [fm_tok], 1
    mov byte [fm_tstep], 1
    mov esi, fmt_d
    call fs_mkdir
    cmp eax, -1
    je .bad
    mov byte [fm_tstep], 2
    mov esi, fmt_sub
    call fs_mkdir
    cmp eax, -1
    je .bad
    mov byte [fm_tstep], 3
    mov esi, fmt_f
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .bad
    mov ebx, eax
    mov esi, fmt_abc
    mov ecx, 3
    call fs_write
    call fs_close
    mov byte [fm_tstep], 4
    mov esi, fmt_d
    call fs_find_dir            ; dl = /fmt's id
    jc .bad
    movzx eax, dl
    mov [fm_cur], eax
    mov dword [fm_lsel], 0
    call fm_scan
    mov byte [fm_tstep], 5
    cmp dword [fm_ln], 2
    jne .bad
    mov eax, [fm_lent]          ; sub first (a directory)
    shl eax, 5
    cmp byte [FS_DIR+eax+DE_KIND], DK_DIR
    jne .bad
    mov byte [fm_tstep], 6
    mov ecx, [fm_tsel]          ; /fmt in the tree, at depth 1
    cmp dword [fm_tdep+ecx*4], 1
    jne .bad
    mov eax, [fm_tid+ecx*4]
    cmp eax, [fm_cur]
    jne .bad
    mov byte [fm_tstep], 7
    mov eax, [fm_lent]          ; its path
    mov edi, fm_p1
    call fm_entpath
    mov esi, fm_p1
    mov edi, fmt_sub
    call streq
    jne .bad
    mov byte [fm_tstep], 8
    mov ecx, [fm_tsel]          ; sub, under /fmt at depth 2
    inc ecx
    cmp dword [fm_tdep+ecx*4], 2
    jne .bad
    mov [fm_trow], ecx
    mov eax, [fm_lent+4]        ; drop f onto sub
    mov edx, ecx
    mov byte [kbd_ctrl], 0
    call fm_drop
    mov byte [fm_tstep], 9
    mov esi, fmt_subf
    call fs_lookup
    test edi, edi
    jz .bad
    cmp dword [fm_ln], 1        ; the list now has only sub
    jne .bad
    mov byte [fm_tstep], 10
    mov esi, fmt_subf           ; copy it back into /fmt
    mov edi, fm_p2
    push esi
    mov esi, fmt_d
.cp:
    lodsb
    stosb
    test al, al
    jnz .cp
    pop esi
    mov edi, fm_p2
    call fm_copy
    cmp eax, -1
    je .bad
    mov byte [fm_tstep], 11
    mov esi, fmt_f              ; it reads "abc"
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .bad
    mov ebx, eax
    mov edi, fm_cbuf
    mov ecx, 16
    call fs_read
    push eax
    call fs_close
    pop eax
    cmp eax, 3
    jne .bad
    cmp word [fm_cbuf], 'ab'
    jne .bad
    cmp byte [fm_cbuf+2], 'c'
    jne .bad
    jmp .clean
.bad:
    mov byte [fm_tok], 0
.clean:
    mov esi, fmt_subf
    call fs_delete
    mov esi, fmt_f
    call fs_delete
    mov esi, fmt_sub
    call fs_delete
    mov esi, fmt_d
    call fs_delete
    mov esi, fm_pass
    cmp byte [fm_tok], 1
    je .say
    mov esi, fm_fail
    call puts
    movzx eax, byte [fm_tstep]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, pm_nl
.say:
    jmp puts

align 4
fm_win dd -1
fm_cur dd 0                     ; the shown directory's id
fm_pane dd 1                    ; 0 tree, 1 list
fm_tn dd 0
fm_tsel dd 0
fm_ttop dd 0
fm_tid times FM_MAXT dd 0
fm_tdep times FM_MAXT dd 0
fm_ln dd 0
fm_lsel dd 0
fm_ltop dd 0
fm_lent times FM_MAXL dd 0      ; entry indices
fm_chain times 16 dd 0
fm_stat dd 0                    ; the status line, or 0: the question
fm_ask dd 0
fm_inn dd 0
fm_drag dd -1                   ; the entry being dragged, or -1
fm_last dd -1                   ; the last list row pressed, and when
fm_lastt dd 0
fm_fd1 dd 0
fm_fd2 dd 0
fm_cx dd 0
fm_cy dd 0
fm_tx dd 0
fm_tw dd 0
fm_lx dd 0
fm_lw dd 0
fm_py dd 0
fm_ph dd 0
fm_sy dd 0
fm_trow dd 0
fm_op db 0
fm_ink db 0
fm_lbtn db 0
fm_dirty db 0
fm_tok db 0
fm_tstep db 0
fm_in times FM_INMAX + 2 db 0
fm_p1 times FM_PATH db 0
fm_p2 times FM_PATH db 0
fm_line times 96 db 0
fm_cbuf times 512 db 0
fm_title db 'File Manager', 0
FM_MITEMS equ 5
align 4
fm_mitems dd fm_m_copy, fm_m_move, fm_m_ren, fm_m_mkdir, fm_m_del
fm_mkeys db FMO_COPY, FMO_MOVE, FMO_REN, FMO_MKDIR, WK_DEL
fm_m_copy db 'Copy...', 0
fm_m_move db 'Move...', 0
fm_m_ren db 'Rename...', 0
fm_m_mkdir db 'New directory...', 0
fm_m_del db 'Delete', 0
fm_s_help db 'f menu  c copy  m move  r rename  n new dir  Del delete  Esc quit', 0
fm_s_copy db 'Copy to: ', 0
fm_s_move db 'Move to: ', 0
fm_s_ren db 'Rename to: ', 0
fm_s_mkdir db 'New directory: ', 0
fm_s_del db 'Delete? y / n ', 0
fm_s_done db 'Done.', 0
fm_s_root db '/', 0
fm_s_dir db '<dir>', 0
fm_bye db 'File Manager closed.', 10, 0
fm_pass db 'fm: PASS', 10, 0
fm_fail db 'fm: FAIL at ', 0
fmt_d db '/fmt', 0
fmt_sub db '/fmt/sub', 0
fmt_f db '/fmt/f', 0
fmt_subf db '/fmt/sub/f', 0
fmt_abc db 'abc'
