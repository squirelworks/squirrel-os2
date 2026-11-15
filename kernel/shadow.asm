; Squirrel-OS/2 — Shadow (shortcut) objects (2.6-shadows)
; Included from pm.asm, in the high image. Original code.
;
; A Shadow under DesktopObject points at another desktop object by name.
; Fields (after name and in): target (the original's name) and at (the
; original's folder, empty at the top level). Renaming or moving the
; original walks every file under /desktop and updates each Shadow that
; points at it, so the link survives a reboot at any Shadow path. open
; finds the live original by name and sends it open.
; See documentation/apps/desktop.md ("Shadows") and objects.md.

; Records DesktopObject and Shadow (twice is harmless)
sh_register:
    push eax
    push esi
    mov esi, dk_c_dobj
    call obj_class
    mov esi, sh_c_shadow
    call obj_class
    pop esi
    pop eax
    ret

; esi = old name, edi = new name: every Shadow whose target or at is the
; old name gets the new one, and its file under /desktop is rewritten.
sh_follow_rename:
    pushad
    mov [sh_old], esi
    mov [sh_new], edi
    mov byte [sh_mode], 0       ; 0 = rename
    call sh_scan
    popad
    ret

; esi = original's name, edi = its new in (folder name, or empty string):
; every Shadow whose target is that name gets at updated and is saved.
sh_follow_move:
    pushad
    mov [sh_old], esi
    mov [sh_new], edi
    mov byte [sh_mode], 1       ; 1 = move
    call sh_scan
    popad
    ret

; Walk every file under /desktop. Any that loads as a Shadow gets the
; rename or move follow-up, so a Shadow at any path under /desktop
; (not only a fixed list) tracks the original.
sh_scan:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    call sh_register
    mov esi, dk_dir
    call fs_find_dir
    jc .r
    mov [sh_dirid], dl
    mov edi, FS_DIR
    mov ecx, FS_MAXFILES
.l:
    cmp byte [edi], 0
    je .n
    mov al, [sh_dirid]
    cmp [edi+DE_PARENT], al
    jne .n
    cmp byte [edi+DE_KIND], DK_FILE
    jne .n                      ; skip directories and long-name parts
    push edi
    push ecx
    call lfn_name               ; esi = this entry's name
    mov edi, sh_path
    push esi
    mov esi, dk_dir
.cpd:
    lodsb
    stosb
    test al, al
    jnz .cpd
    mov byte [edi-1], '/'
    pop esi
.cpn:
    lodsb
    stosb
    test al, al
    jnz .cpn
    mov esi, sh_path
    mov [sh_curpath], esi
    mov byte [sh_dirty], 0
    call obj_load
    jc .pop
    mov [sh_obj], eax
    cmp dword [eax+OBJ_CLASS], sh_c_shadow
    jne .free
    cmp byte [sh_mode], 0
    jne .move
    mov eax, [sh_obj]
    mov ebx, 2
    call obj_get
    mov esi, eax
    mov edi, [sh_old]
    call streq
    jne .ren_at
    mov eax, [sh_obj]
    mov ebx, 2
    mov ecx, [sh_new]
    call obj_set
    mov byte [sh_dirty], 1
.ren_at:
    mov eax, [sh_obj]
    mov ebx, 3
    call obj_get
    mov esi, eax
    mov edi, [sh_old]
    call streq
    jne .save
    mov eax, [sh_obj]
    mov ebx, 3
    mov ecx, [sh_new]
    call obj_set
    mov byte [sh_dirty], 1
    jmp .save
.move:
    mov eax, [sh_obj]
    mov ebx, 2
    call obj_get
    mov esi, eax
    mov edi, [sh_old]
    call streq
    jne .free
    mov eax, [sh_obj]
    mov ebx, 3
    mov ecx, [sh_new]
    call obj_set
    mov byte [sh_dirty], 1
.save:
    cmp byte [sh_dirty], 0
    je .free
    mov eax, [sh_obj]
    mov esi, [sh_curpath]
    call obj_save
.free:
    mov eax, [sh_obj]
    call obj_free
.pop:
    pop ecx
    pop edi
.n:
    add edi, FS_DIRENT
    dec ecx
    jnz .l
.r:
    popad
    ret

; Shadow open: find a live object whose name is target and send it open.
sh_open:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov ebx, 2
    call obj_get                ; target
    test eax, eax
    jz .none
    mov esi, eax                ; esi = target name
    xor ecx, ecx
.f:
    cmp ecx, OBJ_MAX
    jae .none
    mov eax, ecx
    imul eax, OBJ_SIZE
    add eax, obj_table
    cmp dword [eax+OBJ_CLASS], 0
    je .n
    cmp dword [eax+OBJ_CLASS], sh_c_shadow
    je .n                       ; not another shadow
    push esi
    xor ebx, ebx
    call obj_get                ; name
    mov edi, eax
    call streq
    pop esi
    je .found
.n:
    inc ecx
    jmp .f
.found:
    mov eax, ecx
    imul eax, OBJ_SIZE
    add eax, obj_table
    mov esi, dk_s_open
    call obj_send
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret
.none:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    mov eax, -1
    ret

; ---------- dkshadow self-check (2.6-shadows) ----------
; Creates a Program and a Shadow under /desktop at an arbitrary path
; (not a fixed scan list), renames and moves the original (the shadow
; file follows via the /desktop walk), reloads across a simulated reboot,
; and checks that open reaches the original. Prints dk-shadow: PASS|FAIL.

cmd_dkshadow_run:
    pushad
    call fs_need
    jc .r
    mov dword [st_fail], 0
    mov byte [sh_dirty], 0
    call sh_register
    mov esi, dk_c_prog
    call obj_class
    mov esi, dk_c_fold
    call obj_class
    mov esi, dk_dir
    call fs_mkdir
    mov esi, sht_shfile
    call fs_delete
    mov esi, sht_origfile
    call fs_delete
    ; original Program "calc"
    mov eax, dk_c_prog
    call obj_new
    test eax, eax
    jz .fail
    mov [sht_orig], eax
    xor ebx, ebx
    mov ecx, sht_oname
    call obj_set
    inc ebx
    mov ecx, dk_empty
    call obj_set
    inc ebx
    mov ecx, sht_oname
    call obj_set
    mov eax, [sht_orig]
    mov esi, sht_origfile
    call obj_save
    setnc al
    cmp al, 1
    call st_check
    ; Shadow of calc
    mov eax, sh_c_shadow
    call obj_new
    test eax, eax
    jz .fail
    mov [sht_sh], eax
    xor ebx, ebx
    mov ecx, sht_sname
    call obj_set
    inc ebx
    mov ecx, dk_empty
    call obj_set
    inc ebx
    mov ecx, sht_oname
    call obj_set
    inc ebx
    mov ecx, dk_empty
    call obj_set
    mov eax, [sht_sh]
    mov esi, sht_shfile
    call obj_save
    setnc al
    cmp al, 1
    call st_check
    ; free live copies (reboot): files stay
    mov eax, [sht_orig]
    call obj_free
    mov eax, [sht_sh]
    call obj_free
    mov dword [sht_orig], 0
    mov dword [sht_sh], 0
    ; rename original on disk: name calc -> notes
    call sh_register
    mov esi, dk_c_prog
    call obj_class
    mov esi, sht_origfile
    call obj_load
    jc .fail
    mov [sht_orig], eax
    xor ebx, ebx
    mov ecx, sht_nname
    call obj_set
    mov esi, sht_origfile
    call obj_save
    mov eax, [sht_orig]
    call obj_free
    mov dword [sht_orig], 0
    ; update the known shadow file (same path the scan uses)
    mov esi, sht_oname
    mov edi, sht_nname
    call sh_follow_rename
    mov esi, sht_shfile
    call obj_load
    jc .fail
    mov [sht_sh], eax
    cmp dword [eax+OBJ_CLASS], sh_c_shadow
    call st_check
    mov eax, [sht_sh]
    mov ebx, 2
    call obj_get
    mov esi, eax
    mov edi, sht_nname
    call streq
    call st_check
    ; move: set at on the live shadow, save, then follow_move via scan
    mov eax, [sht_sh]
    call obj_free
    mov dword [sht_sh], 0
    mov esi, sht_origfile
    call obj_load
    jc .fail
    mov [sht_orig], eax
    mov ebx, 1
    mov ecx, sht_folder
    call obj_set
    mov esi, sht_origfile
    call obj_save
    mov eax, [sht_orig]
    call obj_free
    mov dword [sht_orig], 0
    mov esi, sht_nname
    mov edi, sht_folder
    call sh_follow_move
    mov esi, sht_shfile
    call obj_load
    jc .fail
    mov [sht_sh], eax
    mov ebx, 3
    call obj_get
    mov esi, eax
    mov edi, sht_folder
    call streq
    call st_check
    mov eax, [sht_sh]
    call obj_free
    mov dword [sht_sh], 0
    ; open: Folder original + Shadow of it
    mov eax, dk_c_fold
    call obj_new
    test eax, eax
    jz .fail
    mov [sht_orig], eax
    xor ebx, ebx
    mov ecx, sht_folder
    call obj_set
    inc ebx
    mov ecx, dk_empty
    call obj_set
    mov eax, sh_c_shadow
    call obj_new
    test eax, eax
    jz .fail
    mov [sht_sh], eax
    xor ebx, ebx
    mov ecx, sht_sname
    call obj_set
    inc ebx
    mov ecx, dk_empty
    call obj_set
    inc ebx
    mov ecx, sht_folder
    call obj_set
    inc ebx
    mov ecx, dk_empty
    call obj_set
    mov byte [dk_opened], 0
    mov dword [dk_cur], 0
    mov eax, [sht_sh]
    mov esi, dk_s_open
    call obj_send
    cmp byte [dk_opened], 1
    call st_check
    mov eax, [sht_orig]
    call obj_free
    mov eax, [sht_sh]
    call obj_free
    mov dword [sht_orig], 0
    mov dword [sht_sh], 0
    mov esi, sht_shfile
    call fs_delete
    mov esi, sht_origfile
    call fs_delete
    mov esi, sht_pass
    cmp dword [st_fail], 0
    je .out
.fail:
    mov eax, [sht_orig]
    test eax, eax
    jz .f2
    call obj_free
.f2:
    mov eax, [sht_sh]
    test eax, eax
    jz .f3
    call obj_free
.f3:
    mov esi, sht_shfile
    call fs_delete
    mov esi, sht_origfile
    call fs_delete
    mov esi, sht_failmsg
.out:
    call puts
.r:
    popad
    ret

; ---------- data ----------
align 4
sh_c_shadow dd sh_cn, dk_c_dobj, sh_m, sh_f, 3 ; target and at are text
sh_m dd dk_s_open, sh_open, 0
sh_f dd sh_f_target, sh_f_at, 0 ; fields 2 and 3
sh_old dd 0
sh_new dd 0
sh_obj dd 0
sh_curpath dd 0
sht_orig dd 0
sht_sh dd 0
sh_mode db 0
sh_dirty db 0
sh_dirid db 0
sh_cn db 'Shadow', 0
sh_f_target db 'target', 0
sh_f_at db 'at', 0
sht_oname db 'calc', 0
sht_nname db 'notes', 0
sht_sname db 'calc shadow', 0
sht_folder db 'Tools', 0
sht_origfile db '/desktop/calc.obj', 0
; Arbitrary name: proves sh_scan walks /desktop, not a fixed path list
sht_shfile db '/desktop/extra-sh.obj', 0
sht_pass db 'dk-shadow: PASS', 10, 0
sht_failmsg db 'dk-shadow: FAIL', 10, 0
sh_path times FS_PATHMAX db 0
