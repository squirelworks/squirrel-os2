; Squirrel-OS/2 — desktop shell (1.6)
; Included from pm.asm. Original code.
;
; The desktop command: graphics mode, a window listing the programs, keys
; to the window's widgets. Enter opens the chosen program in a window
; (calc since 1.6.1, draw since 1.6.3); Esc returns to the text shell.
; Since 1.7.6 the entries are Program objects and Enter sends them open.
; See documentation/apps/desktop.md.

DK_X equ 40                     ; the desktop's window
DK_Y equ 24
DK_W equ 240
DK_H equ 150

cmd_desktop_run:
    call gfx_mode13
    jnc .ok
    mov esi, dk_nomem
    jmp puts
.ok:
    call dk_mkobjs              ; the entries are objects (1.7.6)
    mov dword [dk_cur], 0       ; the top level (1.9.0)
    mov eax, DK_X
    mov ebx, DK_Y
    mov ecx, DK_W
    mov edx, DK_H
    mov esi, dk_title
    call wm_create
    mov [dk_win], eax
    mov ebx, 4
    mov ecx, 4
    mov esi, dk_heading
    call wg_label
    mov eax, [dk_win]
    mov ebx, 4
    mov ecx, 16
    mov esi, dk_names
    xor edx, edx
    call wg_list
    mov [dk_list], eax
    mov eax, [dk_win]
    mov ebx, 4
    mov ecx, DK_H - WM_TITLE_H - 2 - GFX_CELL_H - 4
    mov esi, dk_help
    call wg_label
    mov [dk_hlp], eax
    mov dword [dk_held], 0
    call dk_relist
.draw:
    call wm_redraw
.key:
    call wg_getkey
    cmp al, 27
    je .esc
    cmp al, 8
    je .up
    cmp al, 'm'
    je .pick
    cmp al, 'p'
    je .drop
    cmp al, 'r'
    je .rename
    cmp al, WK_DEL
    je .delete
    call wg_key
    jnc .draw
    cmp al, 10
    jne .key
    cmp dword [dk_nvis], 0
    je .key
    mov eax, [dk_list]          ; Enter: send open to the chosen object
    call wg_selected
    mov eax, [dk_vis+eax*4]
    mov eax, [dk_objs+eax*4]
    mov byte [dk_opened], 0
    mov esi, dk_s_open
    call obj_send
    cmp byte [dk_opened], 0      ; a folder was opened
    je .draw
    call dk_relist
    jmp .draw
.esc:                           ; Esc: put a held object back, or quit
    cmp dword [dk_held], 0
    je .quit
    call dk_unhold
    jmp .draw
.pick:                          ; m: pick up the chosen object (1.9.1)
    cmp dword [dk_held], 0
    jne .key
    cmp dword [dk_nvis], 0
    je .key
    mov eax, [dk_list]
    call wg_selected
    mov eax, [dk_vis+eax*4]
    mov [dk_heldk], eax
    mov eax, [dk_objs+eax*4]
    mov [dk_held], eax
    call dk_holdhelp
    jmp .draw
.drop:                          ; p: drop it into the folder shown
    cmp dword [dk_held], 0
    je .key
    call dk_drop
    jmp .draw
.rename:                        ; r: rename the chosen object (1.9.2)
    call dk_chosen
    jc .key
    call dk_rename
    jmp .draw
.delete:                        ; Delete: remove it after a confirm step
    call dk_chosen
    jc .key
    call dk_delete
    jmp .draw
.up:                            ; Backspace: from a folder to the top
    cmp dword [dk_cur], 0
    je .key
    mov dword [dk_cur], 0
    call dk_relist
    jmp .draw
.quit:
    mov eax, [dk_win]
    call wm_close
    call dk_freeobjs
    call gfx_text
    mov esi, dk_bye
    jmp puts

; List the objects whose `in` is the folder shown ([dk_cur], 0 for the
; top level), and name the window after that folder (1.9.0).
dk_relist:
    pushad
    xor ebx, ebx                ; objects
    xor edx, edx                ; listed
.o:
    cmp ebx, [dk_n]
    jae .done
    mov eax, [dk_objs+ebx*4]
    test eax, eax
    jz .no
    push ebx
    mov ebx, 1
    call obj_get                ; in
    pop ebx
    mov esi, eax
    test esi, esi
    jnz .cmp
    mov esi, dk_empty
.cmp:
    mov edi, [dk_cur]
    test edi, edi
    jnz .eq
    mov edi, dk_empty
.eq:
    call streq
    jne .no
    mov [dk_vis+edx*4], ebx
    mov eax, [dk_objs+ebx*4]
    push ebx
    push edx
    mov esi, dk_s_name
    call obj_send
    pop edx
    pop ebx
    mov [dk_names+edx*4], eax
    inc edx
.no:
    inc ebx
    jmp .o
.done:
    mov [dk_nvis], edx
    mov eax, [dk_list]
    imul eax, WG_SIZE
    mov [wg_table+eax+WG_CODE], edx
    mov dword [wg_table+eax+WG_SEL], 0
    mov esi, [dk_cur]
    test esi, esi
    jnz .t
    mov esi, dk_title
.t:
    mov eax, [dk_win]
    imul eax, WIN_SIZE
    mov [wm_table+eax+WIN_TITLE], esi
    popad
    ret

; ---------- pick up and drop (1.9.1) ----------

; The help row names the held object: "Held: <name>  p: drop  Esc: back"
dk_holdhelp:
    pushad
    mov eax, [dk_held]
    mov esi, dk_s_name
    call obj_send
    mov esi, eax
    mov edi, dk_hbuf
    push esi
    mov esi, dk_h1
    mov ecx, 15
    call dk_cpy
    pop esi
    mov ecx, 15                 ; the name: at most 15 characters
    call dk_cpy
    mov esi, dk_h2
    mov ecx, 31
    call dk_cpy
    mov esi, dk_hbuf
    jmp dk_sethelp

dk_unhold:
    pushad
    mov dword [dk_held], 0
    mov esi, dk_help
dk_sethelp:                     ; (inside pushad) esi = the help row's text
    mov eax, [dk_hlp]
    imul eax, WG_SIZE
    mov [wg_table+eax+WG_TEXT], esi
    popad
    ret

; esi = text, ecx = most characters -> copied to edi, edi at its 0
dk_cpy:
    push ecx
.c:
    lodsb
    test al, al
    jz .e
    stosb
    loop .c
.e:
    mov byte [edi], 0
    pop ecx
    ret

; Drop the held object into the folder shown: set its in and save its file.
; A folder can only be dropped at the top level (folders do not nest).
dk_drop:
    pushad
    mov eax, [dk_held]
    mov ecx, [dk_cur]
    test ecx, ecx
    jnz .infolder
    mov ecx, dk_empty
    jmp .set
.infolder:
    cmp dword [eax+OBJ_CLASS], dk_c_fold
    je .r                       ; refused: still held
.set:
    mov ebx, 1
    call obj_set                ; in
    mov edx, [dk_heldk]
    mov esi, [dk_files+edx*4]
    test esi, esi
    jz .nofile
    call dk_path
    call obj_save               ; (no data disk: kept until the desktop closes)
.nofile:
    call dk_unhold
    call dk_relist
.r:
    popad
    ret

; ---------- rename and delete (1.9.2) ----------

; -> eax = the chosen object's index in dk_objs, CF clear; CF set while
; an object is held or the list is empty
dk_chosen:
    cmp dword [dk_held], 0
    jne .no
    cmp dword [dk_nvis], 0
    je .no
    mov eax, [dk_list]
    call wg_selected
    mov eax, [dk_vis+eax*4]
    clc
    ret
.no:
    stc
    ret

; eax = index: a small window with the name in a field; Enter keeps the
; new name (saved; a folder's contents follow it), Esc leaves it as it was
dk_rename:
    pushad
    mov [dk_k], eax
    mov eax, [dk_objs+eax*4]
    xor ebx, ebx
    call obj_get
    mov esi, eax
    mov edi, dk_rbuf
    mov ecx, DK_NAMEMAX
    call dk_cpy
    mov eax, DK_X + 20
    mov ebx, DK_Y + 50
    mov ecx, DK_W - 40
    mov edx, 34
    mov esi, dk_rtitle
    call wm_create
    cmp eax, -1
    je .r
    mov [dk_rwin], eax
    mov ebx, 4
    mov ecx, 4
    mov esi, dk_rbuf
    mov edx, DK_NAMEMAX
    call wg_field
.k:
    call wm_redraw
    call wg_getkey
    cmp al, 27
    je .close
    cmp al, 10
    je .ok
    call wg_key
    jmp .k
.ok:
    mov esi, dk_rbuf
    call strlen
    test eax, eax
    jz .close                   ; an empty name: nothing changes
    mov ecx, eax
    call obj_intern             ; a copy that lasts
    jc .close
    mov ecx, eax                ; ecx = the new name
    mov edx, [dk_k]
    mov eax, [dk_objs+edx*4]
    xor ebx, ebx
    push eax
    call obj_get
    mov ebp, eax                ; ebp = the old name
    pop eax
    call obj_set
    call dk_save
    cmp dword [eax+OBJ_CLASS], dk_c_fold
    jne .close
    xor edx, edx                ; a folder: what was in it moves with it
.f:
    cmp edx, [dk_n]
    jae .close
    mov eax, [dk_objs+edx*4]
    push ecx
    mov ebx, 1
    call obj_get
    mov esi, eax
    mov edi, ebp
    call streq
    pop ecx
    jne .fn
    mov eax, [dk_objs+edx*4]
    mov ebx, 1
    call obj_set
    call dk_save
.fn:
    inc edx
    jmp .f
.close:
    mov eax, [dk_rwin]
    call wm_close
    call dk_relist
.r:
    popad
    ret

; eax = object, edx = its index: save it to its file, if it has one
dk_save:
    pushad
    mov esi, [dk_files+edx*4]
    test esi, esi
    jz .r
    call dk_path
    call obj_save
.r:
    popad
    ret

; eax = index: ask on the help row; y deletes the object and its file. A
; folder with something in it is refused.
dk_delete:
    pushad
    mov [dk_k], eax
    mov eax, [dk_objs+eax*4]
    cmp dword [eax+OBJ_CLASS], dk_c_fold
    jne .ask
    xor ebx, ebx
    call obj_get
    mov ebp, eax                ; the folder's name
    xor edx, edx
.f:
    cmp edx, [dk_n]
    jae .ask
    mov eax, [dk_objs+edx*4]
    mov ebx, 1
    call obj_get
    mov esi, eax
    mov edi, ebp
    call streq
    je .full
    inc edx
    jmp .f
.full:
    mov esi, dk_dfull
    jmp .tell
.ask:
    mov eax, [dk_k]
    mov eax, [dk_objs+eax*4]
    mov esi, dk_s_name
    call obj_send
    mov esi, eax
    mov edi, dk_hbuf
    push esi
    mov esi, dk_d1
    mov ecx, 15
    call dk_cpy
    pop esi
    mov ecx, DK_NAMEMAX
    call dk_cpy
    mov esi, dk_d2
    mov ecx, 31
    call dk_cpy
    mov esi, dk_hbuf
    call dk_help_to
    call wm_redraw
    call wg_getkey
    cmp al, 'y'
    jne .back
    mov edx, [dk_k]             ; the file goes
    mov esi, [dk_files+edx*4]
    test esi, esi
    jz .gone
    call dk_path
    call fs_delete
.gone:
    mov eax, [dk_objs+edx*4]    ; the object goes, and the lists close up
    call obj_free
.sh:
    mov eax, [dk_objs+edx*4+4]
    mov [dk_objs+edx*4], eax
    mov eax, [dk_files+edx*4+4]
    mov [dk_files+edx*4], eax
    inc edx
    cmp edx, DK_NDEF - 1
    jb .sh
    mov dword [dk_objs+edx*4], 0
    mov dword [dk_files+edx*4], 0
    dec dword [dk_n]
    jmp .back
.tell:
    call dk_help_to
    call wm_redraw
    call wg_getkey              ; any key
.back:
    mov esi, dk_help
    call dk_help_to
    call dk_relist
    popad
    ret

; esi = the help row's text
dk_help_to:
    push eax
    mov eax, [dk_hlp]
    imul eax, WG_SIZE
    mov [wg_table+eax+WG_TEXT], esi
    pop eax
    ret

; ---------- desktop objects (1.7.6) ----------
; DesktopObject: fields name and in (the folder holding it, 1.9.0);
; methods name and open (nothing to open).
; Program under it: field entry (a program's name), and open runs that
; program in a window. Folder under it (1.9.0): open shows its contents.

dk_mkobjs:
    pushad
    xor eax, eax
    mov [dk_n], eax
    mov edi, dk_objs
    mov ecx, DK_NDEF
    rep stosd
    mov edi, dk_files
    mov ecx, DK_NDEF
    rep stosd
    mov esi, dk_c_dobj
    call obj_class
    mov esi, dk_c_prog
    call obj_class
    mov esi, dk_c_fold
    call obj_class
    cmp byte [fs_mounted], 0
    je .builtin
    mov esi, dk_dir             ; the first time: write the defaults (1.8.3)
    call fs_mkdir
    test eax, eax
    jz .write
.load:                          ; an entry for each file still there
    xor edi, edi
.l:
    mov esi, [dk_defs+edi*4]
    call dk_path
    call obj_load
    jc .ln
    call dk_add
.ln:
    inc edi
    cmp edi, DK_NDEF
    jb .l
    cmp dword [dk_n], 0
    jne .out
    cmp byte [dk_wrote], 0      ; none loaded (files from 1.8 have one
    jne .builtin                ; field fewer): write the defaults again
.write:
    mov byte [dk_wrote], 1
    xor edi, edi
.w:
    call dk_newobj
    test eax, eax
    jz .load
    mov esi, [dk_defs+edi*4]
    call dk_path
    call obj_save
    call obj_free
    inc edi
    cmp edi, DK_NDEF
    jb .w
    jmp .load
.builtin:                       ; no data disk, or nothing loaded
    xor edi, edi
.b:
    call dk_newobj              ; 0 when no slot: the entry is left out
    call dk_add
    inc edi
    cmp edi, DK_NDEF
    jb .b
.out:
    mov byte [dk_wrote], 0
    popad
    ret

; edi = default entry -> eax = a new Program (or, for the last, a Folder)
; for it, or 0
dk_newobj:
    push ebx
    push ecx
    mov eax, dk_c_prog
    cmp edi, DK_NAPPS
    jb .new
    mov eax, dk_c_fold
.new:
    call obj_new
    test eax, eax
    jz .r
    xor ebx, ebx
    mov ecx, [dk_defs+edi*4]
    call obj_set                ; name
    inc ebx
    mov ecx, dk_empty
    call obj_set                ; in: the top level
    cmp edi, DK_NAPPS
    jae .r
    inc ebx
    mov ecx, [dk_defs+edi*4]
    call obj_set                ; entry: the program's name, as text
.r:
    pop ecx
    pop ebx
    ret

; eax = object (or 0), edi = default entry: keep it, with its file's name
dk_add:
    test eax, eax
    jz .r
    push edx
    mov edx, [dk_n]
    cmp edx, DK_NDEF
    jae .full
    mov [dk_objs+edx*4], eax
    push eax
    mov eax, [dk_defs+edi*4]
    mov [dk_files+edx*4], eax
    pop eax
    inc dword [dk_n]
.full:
    pop edx
.r:
    ret

; esi = an entry's name -> esi = "/desktop/<name>.obj" in dk_pbuf
dk_path:
    push eax
    push edi
    mov edi, dk_pbuf
    push esi
    mov esi, dk_dir
.d:
    lodsb
    stosb
    test al, al
    jnz .d
    mov byte [edi-1], '/'
    pop esi
.n:
    lodsb
    stosb
    test al, al
    jnz .n
    dec edi
    mov esi, dk_ext
.e:
    lodsb
    stosb
    test al, al
    jnz .e
    mov esi, dk_pbuf
    pop edi
    pop eax
    ret

dk_freeobjs:
    pushad
    xor edi, edi
.f:
    mov eax, [dk_objs+edi*4]
    call obj_free               ; refuses 0
    inc edi
    cmp edi, DK_NDEF
    jb .f
    popad
    ret

dk_dobj_name:
    xor ebx, ebx
    jmp obj_get
dk_dobj_open:
    mov eax, -1
    ret
dk_fold_open:                   ; show the folder's contents (1.9.0)
    xor ebx, ebx
    call obj_get
    mov [dk_cur], eax
    mov byte [dk_opened], 1
    xor eax, eax
    ret
dk_prog_open:                   ; dk_textwin(entry, name)
    push eax
    mov ebx, 2
    call obj_get                ; the entry is a program's name (1.8.3)
    xor ecx, ecx
.f:
    mov esi, eax
    mov edi, [dk_apps+ecx*4]
    push eax
    call streq
    pop eax
    je .found
    inc ecx
    cmp ecx, DK_NAPPS
    jb .f
    pop eax                     ; no such program: nothing opens
    mov eax, -1
    ret
.found:
    mov edx, [dk_run+ecx*4]
    pop eax
    xor ebx, ebx
    call obj_get
    mov esi, eax
    mov ebx, edx
    call dk_textwin
    xor eax, eax
    ret

; ebx = a text program's entry (as file_table runs it), esi = its name.
; Runs it in a window over the desktop: putc, cls and scroll_up write to a
; page that stands in for the text screen (txt_base), and a console widget
; shows it. The window is redrawn whenever kbd_getscan waits for a key and
; something was written. When the program returns, the window closes and
; the text screen and cursor are as they were.
DKT_COLS equ 52                 ; columns shown (52 x 6 = 312 pixels)
DKT_ROWS equ 20                 ; rows shown
DKT_W equ DKT_COLS * GFX_CELL_W + 2 + 4
DKT_H equ DKT_ROWS * GFX_CELL_H + WM_TITLE_H + 2 + 4
DKT_X equ (GFX_W - DKT_W) / 2
DKT_Y equ (GFX_H - DKT_H) / 2

dk_textwin:
    pushad
    mov [dk_prog], ebx
    mov [dk_name], esi
    call pg_alloc
    test eax, eax
    jz .out                     ; no memory: the program does not open
    mov [dk_page], eax
    mov edi, eax                ; a blank text screen
    mov ecx, 80*25
    mov ax, 0x0720
    rep stosw
    mov eax, [txt_base]
    mov [dk_oldbase], eax
    mov eax, [cur]
    mov [dk_oldcur], eax
    mov eax, [dk_page]
    mov [txt_base], eax
    mov dword [cur], 0
    mov dword [txt_cols], DKT_COLS ; what the program may use (1.6.4)
    mov dword [txt_rows], DKT_ROWS
    mov byte [run_arg], 0       ; no file name: edit asks when it saves
    mov eax, DKT_X
    mov ebx, DKT_Y
    mov ecx, DKT_W
    mov edx, DKT_H
    mov esi, [dk_name]
    call wm_create
    mov [dk_twin], eax
    mov ebx, 2
    mov ecx, 2
    mov esi, [dk_page]
    mov edx, DKT_ROWS
    call wg_console
    call wm_redraw
    mov byte [txt_dirty], 0
    mov dword [kbd_wait_hook], dk_refresh
    xor ecx, ecx                ; no arguments
    call [dk_prog]
    mov dword [kbd_wait_hook], 0
    mov eax, [dk_twin]
    call wm_close
    mov eax, [dk_oldbase]
    mov [txt_base], eax
    mov dword [txt_cols], 80
    mov dword [txt_rows], 25
    mov eax, [dk_oldcur]
    mov [cur], eax
    mov eax, [dk_page]
    call pg_free
.out:
    popad
    ret

; kbd_wait_hook while a program runs in a window: redraws if it wrote.
dk_refresh:
    cmp byte [txt_dirty], 0
    je .r
    mov byte [txt_dirty], 0
    pushad
    call wm_redraw
    popad
.r:
    ret

; Waits for a key -> al = what wg_key takes: ASCII, 8 for Backspace,
; 27 for Esc, WK_UP and WK_DOWN for the arrows.
wg_getkey:
    call kbd_getscan
    call kbd_shift_track
    je wg_getkey
    cmp al, 0x80
    jae wg_getkey               ; releases, and the 0xE0 before an arrow
    mov ah, 27
    cmp al, 0x01
    je .r
    mov ah, 8
    cmp al, 0x0E
    je .r
    mov ah, WK_UP
    cmp al, 0x48
    je .r
    mov ah, WK_DOWN
    cmp al, 0x50
    je .r
    mov ah, WK_DEL              ; Delete (1.9.2)
    cmp al, 0x53
    je .r
    call kbd_ascii
    mov ah, al
    test al, al
    jz wg_getkey
.r:
    mov al, ah
    ret

DK_NAPPS equ 5                  ; programs
DK_NDEF equ DK_NAPPS + 1        ; and the Tools folder (1.9.0)
dk_title db 'Squirrel-OS/2 Desktop', 0
dk_heading db 'Programs:', 0
dk_help db 'Enter: open  Bksp: up  Esc: shell', 0
dk_a0 db 'files', 0
dk_a1 db 'calc', 0
dk_a2 db 'edit', 0
dk_a3 db 'vedit', 0
dk_a4 db 'draw', 0
dk_a5 db 'Tools', 0
dk_empty db 0
dk_bye db 'Desktop closed.', 10, 0
dk_cn_dobj db 'DesktopObject', 0
dk_cn_prog db 'Program', 0
dk_cn_fold db 'Folder', 0
dk_f_in db 'in', 0
dk_s_name db 'name', 0
dk_s_open db 'open', 0
dk_dir db '/desktop', 0
dk_ext db '.obj', 0
dk_pbuf times 32 db 0
dk_f_entry db 'entry', 0
dk_nomem db 'desktop: no memory for graphics', 10, 0
align 4
dk_apps dd dk_a0, dk_a1, dk_a2, dk_a3, dk_a4
dk_defs dd dk_a0, dk_a1, dk_a2, dk_a3, dk_a4, dk_a5 ; the files in /desktop
dk_run dd fb_main, run_calc, run_edit, run_vedit, run_draw ; each Program's entry
dk_objs times DK_NDEF dd 0
dk_n dd 0                       ; objects loaded (1.8.3)
dk_files times DK_NDEF dd 0     ; each object's file name, or 0 (1.9.1)
dk_vis times DK_NDEF dd 0       ; the objects listed, by their index (1.9.0)
dk_nvis dd 0
dk_names times DK_NDEF dd 0
dk_cur dd 0                     ; the folder shown: its name, or 0 for the top
dk_c_dobj dd dk_cn_dobj, 0, dk_dobj_m, dk_dobj_f, 3 ; name and in are text
dk_c_prog dd dk_cn_prog, dk_c_dobj, dk_prog_m, dk_prog_f, 1 ; entry is text
dk_c_fold dd dk_cn_fold, dk_c_dobj, dk_fold_m, 0, 0
dk_dobj_m dd dk_s_name, dk_dobj_name, dk_s_open, dk_dobj_open, 0
dk_prog_m dd dk_s_open, dk_prog_open, 0
dk_fold_m dd dk_s_open, dk_fold_open, 0
dk_dobj_f dd dk_s_name, dk_f_in, 0 ; fields 0 and 1
dk_prog_f dd dk_f_entry, 0      ; field 2
dk_opened db 0                  ; a folder's open ran
dk_held dd 0                    ; the object picked up, or 0 (1.9.1)
dk_heldk dd 0                   ; its index in dk_objs
dk_hlp dd 0                     ; the help row's widget
dk_h1 db 'Held: ', 0
dk_h2 db '  p: drop  Esc: back', 0
dk_hbuf times 48 db 0
DK_NAMEMAX equ 15
dk_k dd 0                       ; the object being renamed or deleted (1.9.2)
dk_rwin dd 0
dk_rbuf times DK_NAMEMAX + 1 db 0
dk_rtitle db 'Rename', 0
dk_d1 db 'Delete ', 0
dk_d2 db '? y: yes', 0
dk_dfull db 'Not empty: move its contents out', 0
dk_wrote db 0
dk_win dd 0
dk_list dd 0
dk_twin dd 0
dk_prog dd 0
dk_name dd 0
dk_page dd 0
dk_oldbase dd 0
dk_oldcur dd 0
