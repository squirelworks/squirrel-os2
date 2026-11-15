; Squirrel-OS/2 — desktop icons and drag/drop (2.6-icons / 2.6-drag).
; Original code.
;
; When live, top-level desktop objects are drawn as 32×32 icons with
; captions on the desktop surface (below the WarpCenter strip when that
; is up, and under windows). Dragging an icon onto a Folder updates its
; `in` and saves the object file; dropping a File onto a Program opens
; that program with the file's path (dk_arg / run_arg).
;
; Commands: dkicons / dkdrag (self-checks -> dk-icons / dk-drag: PASS).
; See documentation/apps/desktop.md.

DI_CW       equ 64              ; icon cell (same as Program Manager)
DI_CH       equ 48
DI_CAP_Y    equ 34
DI_MARGIN   equ 16
DI_OX       equ 24              ; left column of desktop icons

; ---------- enable / disable ----------

dki_on:
    mov byte [dki_live], 1
    mov dword [dki_sel], -1
    call dki_layout
    ret

dki_off:
    mov byte [dki_live], 0
    mov dword [dki_sel], -1
    ret

; ---------- layout / paint (wm_paint) ----------

; Top-level objects (empty `in`) in a column below wc_top.
dki_layout:
    pushad
    xor esi, esi                ; icon slot
    xor ebx, ebx                ; dk_objs index
.o:
    cmp ebx, [dk_n]
    jae .done
    mov eax, [dk_objs+ebx*4]
    test eax, eax
    jz .next
    push ebx
    mov ebx, 1
    call obj_get                ; in
    pop ebx
    test eax, eax
    jz .top
    cmp byte [eax], 0
    jne .next
.top:
    cmp esi, DK_MAX
    jae .done
    mov [dki_obj+esi*4], ebx
    mov dword [dki_x+esi*4], DI_OX
    mov eax, [wc_top]
    add eax, DI_MARGIN
    imul edx, esi, DI_CH
    add eax, edx
    mov [dki_y+esi*4], eax
    inc esi
.next:
    inc ebx
    jmp .o
.done:
    mov [dki_n], esi
    popad
    ret

; Drawn from wm_paint after the desktop fill, before windows.
dki_paint:
    cmp byte [dki_live], 0
    je .r
    pushad
    xor esi, esi
.i:
    cmp esi, [dki_n]
    jae .out
    mov eax, [dki_x+esi*4]
    mov ebx, [dki_y+esi*4]
    push esi
    push eax
    push ebx
    mov edx, [dki_obj+esi*4]
    mov eax, [dk_objs+edx*4]
    call pm_icon                ; esi = icon data
    pop ebx
    pop eax
    push eax
    add eax, (DI_CW - 32) / 2
    call gfx_drawicon
    pop eax
    pop esi
    push esi
    mov edx, [dki_obj+esi*4]
    mov edx, [dk_objs+edx*4]
    xchg eax, edx
    push ebx
    xor ebx, ebx
    call obj_get                ; name
    pop ebx
    xchg eax, edx
    mov esi, edx
    add ebx, DI_CAP_Y
    mov cl, TH_TEXT
    mov ch, [th_desk]
    mov edx, [esp]              ; icon slot
    cmp edx, [dki_sel]
    jne .cap
    mov cl, TH_SELECT_TEXT
    mov ch, TH_SELECT
.cap:
    call pm_caption
    pop esi
    inc esi
    jmp .i
.out:
    popad
.r:
    ret

; ---------- hit testing ----------

; eax, ebx = screen point -> edx = icon slot, CF clear; CF set if none
dki_hit:
    push eax
    push ebx
    push ecx
    xor edx, edx
.h:
    cmp edx, [dki_n]
    jae .no
    mov ecx, [dki_x+edx*4]
    cmp eax, ecx
    jb .n
    add ecx, DI_CW
    cmp eax, ecx
    jae .n
    mov ecx, [dki_y+edx*4]
    cmp ebx, ecx
    jb .n
    add ecx, DI_CH
    cmp ebx, ecx
    jae .n
    pop ecx
    pop ebx
    pop eax
    clc
    ret
.n:
    inc edx
    jmp .h
.no:
    pop ecx
    pop ebx
    pop eax
    stc
    ret

; Find the icon whose object name is esi -> edx = slot, CF clear.
dki_find:
    push eax
    push ebx
    push edi
    xor edx, edx
.f:
    cmp edx, [dki_n]
    jae .no
    mov eax, [dki_obj+edx*4]
    mov eax, [dk_objs+eax*4]
    xor ebx, ebx
    call obj_get
    mov edi, eax
    call streq
    je .yes
    inc edx
    jmp .f
.yes:
    pop edi
    pop ebx
    pop eax
    clc
    ret
.no:
    pop edi
    pop ebx
    pop eax
    stc
    ret

; ---------- drop ----------

; eax = source icon slot, ebx = target icon slot.
; File on Program -> send `drop` (opens with path).
; Any object on Folder -> set `in`, save .obj. CF set on refuse.
dki_drop:
    pushad
    cmp eax, ebx
    je .no
    mov esi, [dki_obj+eax*4]     ; source dk_objs index
    mov edi, [dki_obj+ebx*4]     ; target dk_objs index
    mov eax, [dk_objs+esi*4]
    mov ebx, [dk_objs+edi*4]
    test eax, eax
    jz .no
    test ebx, ebx
    jz .no
    cmp dword [ebx+OBJ_CLASS], dk_c_fold
    je .folder
    cmp dword [ebx+OBJ_CLASS], dk_c_prog
    jne .no
    cmp dword [eax+OBJ_CLASS], dk_c_file
    jne .no
    ; eax = File, ebx = Program -> drop wants Program, File
    xchg eax, ebx
    mov esi, dk_s_drop
    call obj_send
    cmp eax, -1
    je .no
    jmp .ok
.folder:
    ; eax = source, ebx = folder: source.in = folder.name
    push eax
    push esi                    ; source index for save
    mov eax, ebx
    xor ebx, ebx
    call obj_get                ; folder name
    mov ecx, eax
    pop esi
    pop eax
    push esi
    mov ebx, 1
    call obj_set
    pop esi
    ; save /desktop/<name>.obj when we have a file stem
    mov edi, [dk_files+esi*4]
    test edi, edi
    jz .ok
    push eax
    mov esi, edi
    call dk_path                ; esi = /desktop/<name>.obj
    pop eax
    call obj_save
    jmp .ok
.no:
    popad
    stc
    ret
.ok:
    popad
    call dki_layout              ; refresh which icons are top-level
    clc
    ret

; ---------- create a File object on the desktop ----------

; esi = short name, edi = path -> eax = object, edx = dk_objs index;
; CF set on failure. Registers the object and lays icons out again.
dki_mkfile:
    push ebx
    push ecx
    push esi
    push edi
    mov eax, dk_c_file
    call obj_new
    test eax, eax
    jz .fail
    xor ebx, ebx
    mov ecx, [esp+4]            ; name (esi saved)
    call obj_set
    inc ebx
    mov ecx, dk_empty
    call obj_set                ; in: top level
    inc ebx
    mov ecx, [esp]              ; path (edi saved)
    call obj_set
    mov esi, [esp+4]            ; name for /desktop/<name>.obj
    call dk_addobj
    jc .freefail
    mov edx, [dk_n]
    dec edx
    cmp byte [fs_mounted], 0
    je .nosave
    push eax
    push edx
    call dk_path
    pop edx
    pop eax
    push edx
    call obj_save
    pop edx
.nosave:
    call dki_layout
    pop edi
    pop esi
    pop ecx
    pop ebx
    clc
    ret
.freefail:
    call obj_free
.fail:
    pop edi
    pop esi
    pop ecx
    pop ebx
    xor eax, eax
    stc
    ret

; ---------- self-check: dk-icons ----------

; Lay out icons under a live WarpCenter offset, draw, probe the calc
; glyph pixels (same colours as icontest) -> dk-icons: PASS
cmd_dkicons_run:
    call wm_screen
    mov esi, dki_icons_fail
    jc .say
    mov byte [dki_ok], 1
    mov byte [dki_stage], '0'
    call wc_on                  ; reserves the top strip; icons sit below
    call dk_mkobjs
    mov byte [dki_stage], '1'
    cmp dword [dk_n], 0
    je .bad
    call dki_on
    call wm_redraw
    mov byte [dki_stage], '2'
    mov esi, dk_a1              ; "calc"
    call dki_find
    jc .bad
    mov [dki_slot], edx
    ; icon glyph is centred in the cell: x + (DI_CW-32)/2
    mov eax, [dki_x+edx*4]
    add eax, (DI_CW - 32) / 2
    mov ebx, [dki_y+edx*4]
    mov [dki_ix], eax
    mov [dki_iy], ebx
    ; transparent corner shows the desktop colour
    mov byte [dki_stage], '3'
    mov dl, [th_desk]
    call .probe
    jc .bad
    ; calc display (light green) at (+10, +5) inside the glyph
    mov byte [dki_stage], '4'
    mov eax, [dki_ix]
    add eax, 10
    mov ebx, [dki_iy]
    add ebx, 5
    mov dl, 0x3A
    call .probe
    jc .bad
    ; calc last key (light red) at (+20, +26)
    mov byte [dki_stage], '5'
    mov eax, [dki_ix]
    add eax, 20
    mov ebx, [dki_iy]
    add ebx, 26
    mov dl, 0x3C
    call .probe
    jc .bad
    ; bottom-right corner transparent again
    mov byte [dki_stage], '6'
    mov eax, [dki_ix]
    add eax, 31
    mov ebx, [dki_iy]
    add ebx, 31
    mov dl, [th_desk]
    call .probe
    jc .bad
    jmp .end
.bad:
    mov byte [dki_ok], 0
.end:
    call dki_off
    call dk_freeobjs
    call wc_off
    call gfx_text
    mov esi, dki_icons_pass
    cmp byte [dki_ok], 1
    je .say
    mov esi, dki_icons_fail
.say:
    call puts
    cmp byte [dki_ok], 1
    je .r
    mov al, [dki_stage]          ; which probe failed
    call putc
    mov al, 10
    call putc
.r:
    ret
.probe:                         ; eax, ebx = pixel; dl = expected
    push edx
    call gfx_getpixel
    pop edx
    cmp cl, dl
    je .same
    stc
    ret
.same:
    clc
    ret

; ---------- self-check: dk-drag ----------

; Make a File, drop it on edit (path lands in dk_arg), move it into
; Tools (in saved on disk) -> dk-drag: PASS
cmd_dkdrag_run:
    call wm_screen
    mov esi, dki_drag_fail
    jc .say
    mov byte [dki_ok], 0
    mov byte [dki_test], 1       ; Program open must not enter dk_textwin
    mov byte [dki_stage], '0'
    call wc_on
    call dk_mkobjs
    mov byte [dki_stage], '1'
    cmp dword [dk_n], 0
    je .fail
    call dki_on
    ; create /hello.txt when a data disk is mounted (for a real path)
    cmp byte [fs_mounted], 0
    je .nofs
    mov esi, dki_hellopath
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .nofs
    mov ebx, eax
    mov esi, dki_hellotxt
    mov ecx, 6                  ; "hello\n"
    call fs_write
    call fs_close
.nofs:
    mov byte [dki_stage], '2'
    mov esi, dki_notename
    mov edi, dki_hellopath
    call dki_mkfile
    jc .fail
    mov [dki_fobj], eax
    mov [dki_fidx], edx
    mov byte [dki_stage], '3'
    mov esi, dk_a2              ; "edit"
    call dki_find
    jc .fail
    mov [dki_pslot], edx
    mov esi, dki_notename
    call dki_find
    jc .fail
    mov [dki_fslot], edx
    ; drop File onto edit
    mov byte [dki_stage], '4'
    mov byte [dk_arg], 0
    mov eax, [dki_fslot]
    mov ebx, [dki_pslot]
    call dki_drop
    jc .fail
    mov byte [dki_stage], '5'
    mov esi, dk_arg
    mov edi, dki_hellopath
    call streq
    jne .fail
    ; move the File into Tools
    mov byte [dki_stage], '6'
    mov esi, dk_a5              ; "Tools"
    call dki_find
    jc .fail
    mov ebx, edx
    mov eax, [dki_fslot]
    call dki_drop
    jc .fail
    mov byte [dki_stage], '7'
    mov eax, [dki_fobj]
    mov ebx, 1
    call obj_get                ; in
    test eax, eax
    jz .fail
    mov esi, eax
    mov edi, dk_a5
    call streq
    jne .fail
    ; after a folder move it is no longer top-level
    mov byte [dki_stage], '8'
    mov esi, dki_notename
    call dki_find
    jnc .fail                   ; must be gone from the surface
    ; object file on disk records in: Tools
    cmp byte [fs_mounted], 0
    je .skipdisk
    mov byte [dki_stage], '9'
    mov esi, dki_notename
    call dk_path
    call obj_load
    jc .fail
    push eax
    mov ebx, 1
    call obj_get
    mov esi, eax
    mov edi, dk_a5
    call streq
    pop eax
    pushf
    call obj_free
    popf
    jne .fail
.skipdisk:
    mov byte [dki_ok], 1
    jmp .end
.fail:
    mov byte [dki_ok], 0
.end:
    call dki_off
    call dk_freeobjs
    call wc_off
    mov byte [dki_test], 0
    mov byte [dk_arg], 0
    call gfx_text
    mov esi, dki_drag_pass
    cmp byte [dki_ok], 1
    je .say
    mov esi, dki_drag_fail
.say:
    call puts
    cmp byte [dki_ok], 1
    je .r
    mov al, [dki_stage]
    call putc
    mov al, 10
    call putc
.r:
    ret

; ---------- data ----------

dki_icons_pass db 'dk-icons: PASS', 10, 0
dki_icons_fail db 'dk-icons: FAIL', 10, 0
dki_drag_pass  db 'dk-drag: PASS', 10, 0
dki_drag_fail  db 'dk-drag: FAIL', 10, 0
dki_notename   db 'notes', 0
dki_hellopath  db '/hello.txt', 0
dki_hellotxt   db 'hello', 10, 0

align 4
dki_n dd 0
dki_obj times DK_MAX dd 0        ; dk_objs index per icon
dki_x times DK_MAX dd 0
dki_y times DK_MAX dd 0
dki_sel dd -1
dki_slot dd 0
dki_ix dd 0
dki_iy dd 0
dki_fobj dd 0
dki_fidx dd 0
dki_fslot dd 0
dki_pslot dd 0
dki_live db 0
dki_ok db 0
dki_test db 0                    ; 1: Program open leaves dk_arg, no window
dki_stage db '0'
