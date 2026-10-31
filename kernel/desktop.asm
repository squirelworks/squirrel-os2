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
    mov edx, DK_NAPPS
    call wg_list
    mov [dk_list], eax
    mov eax, [dk_win]
    mov ebx, 4
    mov ecx, DK_H - WM_TITLE_H - 2 - GFX_CELL_H - 4
    mov esi, dk_help
    call wg_label
.draw:
    call wm_redraw
.key:
    call wg_getkey
    cmp al, 27
    je .quit
    call wg_key
    jnc .draw
    cmp al, 10
    jne .key
    mov eax, [dk_list]          ; Enter: send open to the chosen object
    call wg_selected
    mov eax, [dk_objs+eax*4]
    mov esi, dk_s_open
    call obj_send
    jmp .draw
.quit:
    mov eax, [dk_win]
    call wm_close
    call dk_freeobjs
    call gfx_text
    mov esi, dk_bye
    jmp puts

; ---------- desktop objects (1.7.6) ----------
; DesktopObject: field name, methods name and open (nothing to open).
; Program under it: field entry, and open runs the entry in a window.

dk_mkobjs:
    pushad
    mov esi, dk_c_dobj
    call obj_class
    mov esi, dk_c_prog
    call obj_class
    xor edi, edi
.n:
    mov eax, dk_c_prog
    call obj_new
    mov [dk_objs+edi*4], eax
    test eax, eax
    jz .name                    ; no slot: the entry opens nothing
    xor ebx, ebx
    mov ecx, [dk_apps+edi*4]
    call obj_set                ; name
    mov ebx, 1
    mov ecx, [dk_run+edi*4]
    call obj_set                ; entry
.name:
    mov ecx, [dk_apps+edi*4]    ; the list shows what name answers
    mov esi, dk_s_name
    call obj_send
    jc .keep
    mov ecx, eax
.keep:
    mov [dk_names+edi*4], ecx
    inc edi
    cmp edi, DK_NAPPS
    jb .n
    popad
    ret

dk_freeobjs:
    pushad
    xor edi, edi
.f:
    mov eax, [dk_objs+edi*4]
    call obj_free               ; refuses 0
    inc edi
    cmp edi, DK_NAPPS
    jb .f
    popad
    ret

dk_dobj_name:
    xor ebx, ebx
    jmp obj_get
dk_dobj_open:
    mov eax, -1
    ret
dk_prog_open:                   ; dk_textwin(entry, name)
    push eax
    mov ebx, 1
    call obj_get
    mov edx, eax
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
    call kbd_ascii
    mov ah, al
    test al, al
    jz wg_getkey
.r:
    mov al, ah
    ret

DK_NAPPS equ 5
dk_title db 'Squirrel-OS/2 Desktop', 0
dk_heading db 'Programs:', 0
dk_help db 'Up/Down, Enter: open   Esc: shell', 0
dk_a0 db 'files', 0
dk_a1 db 'calc', 0
dk_a2 db 'edit', 0
dk_a3 db 'vedit', 0
dk_a4 db 'draw', 0
dk_bye db 'Desktop closed.', 10, 0
dk_cn_dobj db 'DesktopObject', 0
dk_cn_prog db 'Program', 0
dk_s_name db 'name', 0
dk_s_open db 'open', 0
dk_f_entry db 'entry', 0
dk_nomem db 'desktop: no memory for graphics', 10, 0
align 4
dk_apps dd dk_a0, dk_a1, dk_a2, dk_a3, dk_a4
dk_run dd fb_main, run_calc, run_edit, run_vedit, run_draw ; each Program's entry
dk_objs times DK_NAPPS dd 0
dk_names times DK_NAPPS dd 0
dk_c_dobj dd dk_cn_dobj, 0, dk_dobj_m, dk_dobj_f, 1 ; name is text
dk_c_prog dd dk_cn_prog, dk_c_dobj, dk_prog_m, dk_prog_f, 0
dk_dobj_m dd dk_s_name, dk_dobj_name, dk_s_open, dk_dobj_open, 0
dk_prog_m dd dk_s_open, dk_prog_open, 0
dk_dobj_f dd dk_s_name, 0       ; field 0
dk_prog_f dd dk_f_entry, 0      ; field 1
dk_win dd 0
dk_list dd 0
dk_twin dd 0
dk_prog dd 0
dk_name dd 0
dk_page dd 0
dk_oldbase dd 0
dk_oldcur dd 0
