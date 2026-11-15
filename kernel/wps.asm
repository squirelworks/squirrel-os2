; Squirrel-OS/2 — Workplace Shell templates (W.2-templates)
; Included from pm.asm, in the high image. Original code.
;
; A Template under DesktopObject describes a class to instantiate. Fields
; (after name and in): of (class name text: "Folder" or "Program") and
; seed (for Program: the entry name; empty for Folder). Template files
; live under /desktop with in "Templates". Dragging (or dropping) a
; Template creates a new object of that class in the destination folder
; and leaves the template where it was. open on a Template opens a
; settings notebook (2.6-notebook), as for other desktop objects.
; See documentation/apps/desktop.md ("Templates").

; Records DesktopObject, Folder, Program and Template (twice is harmless)
wps_register:
    push eax
    push esi
    mov esi, dk_c_dobj
    call obj_class
    mov esi, dk_c_fold
    call obj_class
    mov esi, dk_c_prog
    call obj_class
    mov esi, wps_c_tmpl
    call obj_class
    pop esi
    pop eax
    ret

; Writes Templates.obj and the seed templates when missing, then loads
; any that are not already in dk_objs. Called from dk_mkobjs.
wps_attach:
    pushad
    call wps_register
    cmp byte [fs_mounted], 0
    je .mem
    mov esi, dk_dir
    call fs_mkdir
    call wps_ensure
.mem:
    call wps_load_all
    popad
    ret

; Create Templates folder + Folder/Program templates on disk if absent.
wps_ensure:
    pushad
    mov esi, wps_fold_file
    call fs_lookup
    test edi, edi
    jnz .tmpls
    mov eax, dk_c_fold
    call obj_new
    test eax, eax
    jz .tmpls
    xor ebx, ebx
    mov ecx, wps_nm_templates
    call obj_set
    inc ebx
    mov ecx, dk_empty
    call obj_set
    mov esi, wps_fold_file
    call obj_save
    call obj_free
.tmpls:
    mov esi, wps_tf_file
    call fs_lookup
    test edi, edi
    jnz .tprog
    mov eax, wps_c_tmpl
    call obj_new
    test eax, eax
    jz .tprog
    xor ebx, ebx
    mov ecx, wps_nm_folder
    call obj_set                ; name
    inc ebx
    mov ecx, wps_nm_templates
    call obj_set                ; in: Templates
    inc ebx
    mov ecx, wps_nm_folder
    call obj_set                ; of: Folder
    inc ebx
    mov ecx, dk_empty
    call obj_set                ; seed
    mov esi, wps_tf_file
    call obj_save
    call obj_free
.tprog:
    mov esi, wps_tp_file
    call fs_lookup
    test edi, edi
    jnz .r
    mov eax, wps_c_tmpl
    call obj_new
    test eax, eax
    jz .r
    xor ebx, ebx
    mov ecx, wps_nm_program
    call obj_set
    inc ebx
    mov ecx, wps_nm_templates
    call obj_set
    inc ebx
    mov ecx, wps_nm_program
    call obj_set                ; of: Program
    inc ebx
    mov ecx, wps_seed_edit
    call obj_set                ; seed: edit
    mov esi, wps_tp_file
    call obj_save
    call obj_free
.r:
    popad
    ret

; Load Templates + templates into dk_objs when not already present.
wps_load_all:
    pushad
    mov esi, wps_fold_file
    mov edx, wps_nm_templates
    call wps_load_one
    mov esi, wps_tf_file
    mov edx, wps_fn_folder
    call wps_load_one
    mov esi, wps_tp_file
    mov edx, wps_fn_program
    call wps_load_one
    popad
    ret

; esi = path, edx = file basename for dk_files.
wps_load_one:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    mov [wps_tmp], esi
    mov [wps_tmpn], edx
    call fs_lookup
    test edi, edi
    jz .r
    mov esi, [wps_tmpn]
    call wps_has_file
    jnc .r
    mov esi, [wps_tmp]
    call obj_load
    jc .r
    mov edx, [dk_n]
    cmp edx, DK_MAX
    jae .full
    mov [dk_objs+edx*4], eax
    mov ebx, [wps_tmpn]
    mov [dk_files+edx*4], ebx
    inc dword [dk_n]
    jmp .r
.full:
    call obj_free
.r:
    popad
    ret

; esi = file basename -> CF clear if some dk_files slot matches
wps_has_file:
    push eax
    push ebx
    push edi
    xor ebx, ebx
.h:
    cmp ebx, [dk_n]
    jae .no
    mov edi, [dk_files+ebx*4]
    test edi, edi
    jz .n
    call streq
    je .yes
.n:
    inc ebx
    jmp .h
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

; eax = object, edx = file basename: append to dk_objs. CF set if full
; (object is freed).
wps_dk_add:
    push ebx
    mov ebx, [dk_n]
    cmp ebx, DK_MAX
    jae .full
    mov [dk_objs+ebx*4], eax
    mov [dk_files+ebx*4], edx
    inc dword [dk_n]
    pop ebx
    clc
    ret
.full:
    call obj_free
    pop ebx
    stc
    ret

; Template open: settings notebook (W.2 / 2.6-notebook).
wps_tmpl_open:
    call wps_settings
    xor eax, eax
    ret

; Opens a General / View settings notebook (shared pm_set_* window).
wps_settings:
    pushad
    cmp dword [pm_set_win], -1
    je .mk
    mov eax, [pm_set_win]
    call wm_close
    mov dword [pm_set_win], -1
.mk:
    mov eax, 80
    mov ebx, 60
    mov ecx, 280
    mov edx, 160
    mov esi, pm_set_title
    call wm_create
    cmp eax, -1
    je .r
    mov [pm_set_win], eax
    mov ebx, 8
    mov ecx, 8
    mov esi, pm_set_tabs
    mov edx, 2
    mov edi, 260
    mov ebp, 120
    call wg_notebook
    mov [pm_set_nb], eax
    call wm_redraw
.r:
    popad
    ret

; eax = Template, esi = destination folder name (empty = top level) ->
; eax = new object, CF clear; or eax = -1, CF set. Template is not moved.
wps_create_from:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov [wps_src], eax
    mov [wps_dest], esi
    test eax, eax
    jz .fail
    cmp dword [eax+OBJ_CLASS], wps_c_tmpl
    jne .fail
    mov ebx, 2
    call obj_get                ; of
    test eax, eax
    jz .fail
    mov [wps_of], eax
    mov eax, [wps_src]
    mov ebx, 3
    call obj_get                ; seed
    test eax, eax
    jnz .seedok
    mov eax, dk_empty
.seedok:
    mov [wps_seed], eax
    mov esi, [wps_of]
    mov edi, wps_nm_folder
    call streq
    je .as_fold
    mov esi, [wps_of]
    mov edi, wps_nm_program
    call streq
    jne .fail
    mov dword [wps_newcls], dk_c_prog
    jmp .new
.as_fold:
    mov dword [wps_newcls], dk_c_fold
.new:
    mov eax, [wps_newcls]
    call obj_new
    test eax, eax
    jz .fail
    mov [wps_new], eax
    call wps_uniq_name          ; -> esi = unique name, CF clear
    jc .nofree
    mov [wps_newname], esi
    mov eax, [wps_new]
    xor ebx, ebx
    mov ecx, esi
    call obj_set                ; name
    inc ebx
    mov ecx, [wps_dest]
    test ecx, ecx
    jnz .inok
    mov ecx, dk_empty
.inok:
    cmp byte [ecx], 0
    jne .inset
    mov ecx, dk_empty
.inset:
    call obj_set                ; in
    mov eax, [wps_new]
    cmp dword [eax+OBJ_CLASS], dk_c_prog
    jne .save
    mov ebx, 2
    mov ecx, [wps_seed]
    call obj_set                ; entry
.save:
    mov esi, [wps_newname]
    call dk_path
    mov eax, [wps_new]
    cmp byte [fs_mounted], 0
    je .nosave
    call obj_save
.nosave:
    mov eax, [wps_new]
    mov edx, [wps_newname]
    call wps_dk_add
    jc .fail                    ; object already freed
    mov eax, [wps_new]
    clc
    jmp .out
.nofree:
    mov eax, [wps_new]
    call obj_free
.fail:
    mov eax, -1
    stc
.out:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; Unique name from seed (if set) or of. -> esi = interned name, CF clear.
wps_uniq_name:
    push eax
    push ebx
    push ecx
    push edx
    push edi
    mov esi, [wps_seed]
    cmp byte [esi], 0
    jne .base
    mov esi, [wps_of]
.base:
    mov edi, wps_nbuf
    mov ecx, DK_NAMEMAX - 1
.c:
    lodsb
    test al, al
    jz .e
    stosb
    loop .c
.e:
    mov byte [edi], 0
    mov byte [wps_nsuf], 0
.try:
    mov esi, wps_nbuf
    call wps_name_taken         ; CF clear = taken, CF set = free
    jc .use
    movzx edx, byte [wps_nsuf]
    inc edx
    cmp edx, 9
    ja .fail
    mov [wps_nsuf], dl
    mov esi, wps_nbuf
    call strlen
    cmp byte [wps_nsuf], 1
    je .addfirst
    lea ebx, [eax-1]
    jmp .put
.addfirst:
    cmp eax, DK_NAMEMAX - 1
    jae .fail
    mov ebx, eax
.put:
    mov dl, [wps_nsuf]
    add dl, '0'
    mov [wps_nbuf+ebx], dl
    mov byte [wps_nbuf+ebx+1], 0
    jmp .try
.use:
    mov esi, wps_nbuf
    call strlen
    mov ecx, eax
    mov esi, wps_nbuf
    call obj_intern
    jc .fail
    mov esi, eax
    clc
    jmp .out
.fail:
    stc
.out:
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; esi = file basename -> CF clear if taken (dk_files or /desktop file),
; CF set if free. Display names may repeat; object files may not.
wps_name_taken:
    push eax
    push ebx
    push edi
    push esi
    call wps_has_file           ; CF clear = already in dk_files
    jnc .yes
    cmp byte [fs_mounted], 0
    je .no
    mov esi, [esp]
    call dk_path
    call fs_lookup
    test edi, edi
    jnz .yes
.no:
    pop esi
    pop edi
    pop ebx
    pop eax
    stc
    ret
.yes:
    pop esi
    pop edi
    pop ebx
    pop eax
    clc
    ret

; ---------- wps-tmpl self-check (W.2-templates) ----------
; Ensures Templates + templates, creates a Folder on the desktop and a
; Program in Tools from them, opens a settings notebook and probes a tab
; face. Prints `wps: PASS` or `wps: FAIL`.

cmd_wpstmpl_run:
    pushad
    call fs_need
    jc .r
    mov dword [st_fail], 0
    mov byte [wps_step], '0'
    mov dword [pm_set_win], -1
    mov dword [pm_set_nb], -1
    call wm_screen
    setnc al
    cmp al, 1
    call st_check
    cmp dword [st_fail], 0
    jne .bail
    mov byte [wps_step], '1'
    call dk_mkobjs
    mov esi, wps_nm_folder
    mov edi, wps_nm_templates
    call wps_find_tmpl
    mov [wps_src], eax
    setnc bl
    cmp bl, 1
    call st_check
    cmp dword [st_fail], 0
    jne .bail
    mov byte [wps_step], '2'
    mov eax, [wps_src]
    mov esi, dk_empty
    call wps_create_from
    mov [wps_new], eax
    setnc bl
    cmp bl, 1
    call st_check
    cmp dword [st_fail], 0
    jne .bail
    mov byte [wps_step], '3'
    mov eax, [wps_new]
    cmp dword [eax+OBJ_CLASS], dk_c_fold
    call st_check
    cmp dword [st_fail], 0
    jne .bail
    mov ebx, 1
    call obj_get
    mov esi, eax
    mov edi, dk_empty
    call streq
    call st_check
    cmp dword [st_fail], 0
    jne .bail
    mov byte [wps_step], '4'
    mov esi, wps_nm_program
    mov edi, wps_nm_templates
    call wps_find_tmpl
    mov [wps_src], eax
    setnc bl
    cmp bl, 1
    call st_check
    cmp dword [st_fail], 0
    jne .bail
    mov byte [wps_step], '5'
    mov eax, [wps_src]
    mov esi, wps_nm_tools
    call wps_create_from
    mov [wps_new], eax
    setnc bl
    cmp bl, 1
    call st_check
    cmp dword [st_fail], 0
    jne .bail
    mov byte [wps_step], '6'
    mov eax, [wps_new]
    cmp dword [eax+OBJ_CLASS], dk_c_prog
    call st_check
    cmp dword [st_fail], 0
    jne .bail
    mov ebx, 1
    call obj_get
    mov esi, eax
    mov edi, wps_nm_tools
    call streq
    call st_check
    cmp dword [st_fail], 0
    jne .bail
    mov byte [wps_step], '7'
    mov eax, [wps_new]
    mov ebx, 2
    call obj_get
    mov esi, eax
    mov edi, wps_seed_edit
    call streq
    call st_check
    cmp dword [st_fail], 0
    jne .bail
    mov byte [wps_step], '8'
    call wps_settings
    cmp dword [pm_set_win], -1
    setne al
    cmp al, 1
    call st_check
    cmp dword [pm_set_nb], -1
    setne al
    cmp al, 1
    call st_check
    cmp dword [st_fail], 0
    jne .bail
    mov byte [wps_step], '9'
    mov eax, [pm_set_win]
    call wm_record
    setnc al
    cmp al, 1
    call st_check
    cmp dword [st_fail], 0
    jne .bail
    mov eax, [edi+WIN_X]
    mov ebx, [edi+WIN_Y]
    add eax, 1 + 8 + TH_BEVEL_W + 2
    add ebx, 1 + WM_TITLE_H + 8 + TH_BEVEL_W + 1
    call gfx_getpixel
    cmp cl, TH_FACE
    call st_check
    cmp dword [st_fail], 0
    jne .bail
    mov byte [wps_step], 'A'
    jmp .cleanup
.bail:
.cleanup:
    cmp dword [pm_set_win], -1
    je .noset
    mov eax, [pm_set_win]
    call wm_close
    mov dword [pm_set_win], -1
.noset:
    call dk_freeobjs
    call gfx_text
    mov esi, wps_pass
    cmp dword [st_fail], 0
    je .say
    mov esi, wps_fail
    call puts
    movzx eax, byte [wps_step]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, wps_nl
.say:
    call puts
.r:
    popad
    ret

; esi = template name, edi = its in -> eax = object, CF clear; else CF set.
wps_find_tmpl:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov [wps_wantn], esi
    mov [wps_wantin], edi
    xor ecx, ecx
.f:
    cmp ecx, [dk_n]
    jae .no
    mov eax, [dk_objs+ecx*4]
    test eax, eax
    jz .n
    cmp dword [eax+OBJ_CLASS], wps_c_tmpl
    jne .n
    push eax
    xor ebx, ebx
    call obj_get
    mov esi, eax
    mov edi, [wps_wantn]
    call streq
    pop eax
    jne .n
    push eax
    mov ebx, 1
    call obj_get
    mov esi, eax
    mov edi, [wps_wantin]
    call streq
    pop eax
    jne .n
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    clc
    ret
.n:
    inc ecx
    jmp .f
.no:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    mov eax, -1
    stc
    ret

; ---------- data ----------
align 4
wps_c_tmpl dd wps_cn_tmpl, dk_c_dobj, wps_tmpl_m, wps_tmpl_f, 3
wps_tmpl_m dd dk_s_open, wps_tmpl_open, 0
wps_tmpl_f dd wps_f_of, wps_f_seed, 0
wps_src dd 0
wps_dest dd 0
wps_of dd 0
wps_seed dd 0
wps_new dd 0
wps_newname dd 0
wps_newcls dd 0
wps_tmp dd 0
wps_tmpn dd 0
wps_wantn dd 0
wps_wantin dd 0
wps_cn_tmpl db 'Template', 0
wps_f_of db 'of', 0
wps_f_seed db 'seed', 0
wps_nm_templates db 'Templates', 0
wps_nm_folder db 'Folder', 0
wps_nm_program db 'Program', 0
wps_nm_tools db 'Tools', 0
wps_seed_edit db 'edit', 0
wps_fn_folder db 'tmpl-Folder', 0
wps_fn_program db 'tmpl-Program', 0
wps_fold_file db '/desktop/Templates.obj', 0
wps_tf_file db '/desktop/tmpl-Folder.obj', 0
wps_tp_file db '/desktop/tmpl-Program.obj', 0
wps_nbuf times 16 db 0
wps_nsuf db 0
wps_step db 0
wps_nl db 10, 0
wps_pass db 'wps: PASS', 10, 0
wps_fail db 'wps: FAIL at ', 0
