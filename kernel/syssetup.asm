; Squirrel-OS/2 — System Setup + Drive/Shredder desktop wiring (W.6-syssetup)
; Included from pm.asm, in the high image. Original code.
;
; System Setup is a top-level DesktopObject whose open runs the Control
; Panel (cmd_control_run). Drive and Shredder files under /desktop (from
; fsobj.asm) are loaded into dk_objs so they appear as desktop icons with
; the same context menu and Settings notebook path as any other object.
; See documentation/apps/desktop.md ("System Setup") and TODO.md W.6-syssetup.
;
; Commands: w6setup (self-check -> syssetup: PASS).

; Ensure System Setup exists and Drive/Shredder classes + files are in
; dk_objs. Called from dk_mkobjs after stu_attach.
ss_attach:
    pushad
    call fsobj_register
    mov esi, ss_c_setup
    call obj_class
    cmp byte [fs_mounted], 0
    je .mem
    mov esi, dk_dir
    call fs_mkdir
    call ss_ensure
    call fsobj_shredder         ; shredder.obj if missing
.mem:
    call ss_load_setup
    call ss_load_shredder
    call ss_load_drives
    popad
    ret

; Create /desktop/SystemSetup.obj when missing.
ss_ensure:
    pushad
    mov esi, ss_setup_file
    call fs_lookup
    test edi, edi
    jnz .r
    mov esi, ss_c_setup
    call obj_class
    mov eax, ss_c_setup
    call obj_new
    test eax, eax
    jz .r
    xor ebx, ebx
    mov ecx, ss_nm_setup
    call obj_set                ; name
    inc ebx
    mov ecx, dk_empty
    call obj_set                ; in: top level
    mov esi, ss_setup_file
    call obj_save
    call obj_free
.r:
    popad
    ret

; Load SystemSetup.obj into dk_objs when not already present.
ss_load_setup:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    mov esi, ss_fn_setup
    call stu_has_file
    jnc .r
    mov esi, ss_setup_file
    call fs_lookup
    test edi, edi
    jz .r
    mov esi, ss_c_setup
    call obj_class
    mov esi, ss_setup_file
    call obj_load
    jc .r
    mov esi, ss_fn_setup
    call dk_addobj
    jnc .r
    call obj_free
.r:
    popad
    ret

; Load shredder.obj into dk_objs when the file exists and is not loaded.
ss_load_shredder:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    mov esi, ss_fn_shred
    call stu_has_file
    jnc .r
    mov esi, fo_shred_file
    call fs_lookup
    test edi, edi
    jz .r
    call fsobj_register
    mov esi, fo_shred_file
    call obj_load
    jc .r
    mov esi, ss_fn_shred
    call dk_addobj
    jnc .r
    call obj_free
.r:
    popad
    ret

; Load any /desktop/drive-?.obj into dk_objs (a–z).
ss_load_drives:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    call fsobj_register
    mov cl, 'a'
.l:
    mov [fo_file+FO_LETTER], cl
    mov [ss_drive_fn+6], cl     ; "drive-X"
    mov esi, ss_drive_fn
    call stu_has_file
    jnc .n
    mov esi, fo_file
    call fs_lookup
    test edi, edi
    jz .n
    mov esi, fo_file
    call obj_load
    jc .n
    movzx ebx, cl
    sub ebx, 'a'
    lea esi, [ss_drive_names+ebx*8]
    mov byte [esi], 'd'
    mov byte [esi+1], 'r'
    mov byte [esi+2], 'i'
    mov byte [esi+3], 'v'
    mov byte [esi+4], 'e'
    mov byte [esi+5], '-'
    mov [esi+6], cl
    mov byte [esi+7], 0
    call dk_addobj
    jnc .n
    call obj_free
.n:
    inc cl
    cmp cl, 'z'
    jbe .l
.r:
    popad
    ret

; cl = lowercase drive letter: drop drive-X from live dk_objs (W.6 #235).
; Frees the object and closes the slot; refreshes deskicons when live.
ss_drive_drop:
    pushad
    mov [ss_drive_fn+6], cl
    xor edx, edx
.f:
    cmp edx, [dk_n]
    jae .r
    mov esi, [dk_files+edx*4]
    test esi, esi
    jz .n
    mov edi, ss_drive_fn
    call streq
    je .drop
.n:
    inc edx
    jmp .f
.drop:
    mov eax, [dk_objs+edx*4]
    test eax, eax
    jz .sh
    call obj_free
.sh:
    lea eax, [edx+1]
    cmp eax, [dk_n]
    jae .last
    mov eax, [dk_objs+edx*4+4]
    mov [dk_objs+edx*4], eax
    mov eax, [dk_files+edx*4+4]
    mov [dk_files+edx*4], eax
    inc edx
    jmp .sh
.last:
    mov dword [dk_objs+edx*4], 0
    mov dword [dk_files+edx*4], 0
    dec dword [dk_n]
    cmp byte [dki_live], 0
    je .r
    call dki_layout
.r:
    popad
    ret

; After fsobj_mounted writes a Drive file: keep the live object in dk_objs
; when the desktop table is in use. eax = Drive object still live after
; obj_save; cl = drive letter (lowercase). Frees eax when not kept.
ss_drive_live:
    pushad
    mov [ss_tmp], eax
    mov [ss_let], cl
    cmp dword [dk_n], 0
    je .free
    mov [ss_drive_fn+6], cl
    mov esi, ss_drive_fn
    call stu_has_file
    jnc .free                   ; already listed; free the duplicate
    movzx ebx, byte [ss_let]
    sub ebx, 'a'
    lea esi, [ss_drive_names+ebx*8]
    mov byte [esi], 'd'
    mov byte [esi+1], 'r'
    mov byte [esi+2], 'i'
    mov byte [esi+3], 'v'
    mov byte [esi+4], 'e'
    mov byte [esi+5], '-'
    mov cl, [ss_let]
    mov [esi+6], cl
    mov byte [esi+7], 0
    mov eax, [ss_tmp]
    call dk_addobj
    jnc .r
.free:
    mov eax, [ss_tmp]
    call obj_free
.r:
    popad
    ret

; System Setup open: Control Panel, or record a hit in ss_test mode.
ss_setup_open:
    cmp byte [ss_test], 0
    je .live
    mov byte [ss_opened], 1
    xor eax, eax
    ret
.live:
    call cmd_control_run
    xor eax, eax
    ret

; ---------- w6setup self-check ----------
; System Setup + Shredder (+ a Drive) are desktop objects; open reaches
; Control Panel (test mode); Settings notebook opens. -> syssetup: PASS

cmd_w6setup_run:
    pushad
    call fs_need
    jc .nof
    call wm_screen              ; Settings notebook needs a graphics screen
    jc .nof
    mov dword [st_fail], 0
    mov byte [ss_ok], 0
    mov byte [ss_test], 1
    mov byte [ss_opened], 0
    call dk_mkobjs              ; includes ss_attach
    cmp dword [dk_n], 0
    je .fail
    ; System Setup present
    mov esi, ss_nm_setup
    call stu_find
    setnc al
    cmp al, 1
    call st_check
    cmp dword [st_fail], 0
    jne .fail
    mov eax, [dk_objs+edx*4]
    cmp dword [eax+OBJ_CLASS], ss_c_setup
    call st_check
    ; open -> Control Panel entry (test mode)
    mov eax, [dk_objs+edx*4]
    mov esi, dk_s_open
    call obj_send
    cmp byte [ss_opened], 1
    call st_check
    ; Settings notebook on System Setup
    call wps_settings
    cmp dword [pm_set_win], -1
    setne al
    cmp al, 1
    call st_check
    cmp dword [pm_set_nb], -1
    setne al
    cmp al, 1
    call st_check
    cmp dword [pm_set_win], -1
    je .nset
    mov eax, [pm_set_win]
    call wm_close
    mov dword [pm_set_win], -1
.nset:
    cmp dword [st_fail], 0
    jne .fail
    ; Shredder in dk_objs
    mov esi, ss_nm_shred
    call stu_find
    setnc al
    cmp al, 1
    call st_check
    cmp dword [st_fail], 0
    jne .fail
    mov eax, [dk_objs+edx*4]
    cmp dword [eax+OBJ_CLASS], fo_c_shred
    call st_check
    call wps_settings
    cmp dword [pm_set_win], -1
    setne al
    cmp al, 1
    call st_check
    cmp dword [pm_set_win], -1
    je .nset2
    mov eax, [pm_set_win]
    call wm_close
    mov dword [pm_set_win], -1
.nset2:
    cmp dword [st_fail], 0
    jne .fail
    ; Drive object: create, save, load via ss_load_drives
    mov esi, ss_drive_tfile
    call fs_delete
    call fsobj_register
    mov eax, fo_c_drive
    call obj_new
    test eax, eax
    jz .fail
    mov [ss_tmp], eax
    xor ebx, ebx
    mov ecx, ss_nm_tdrive
    call obj_set
    inc ebx
    mov ecx, dk_empty
    call obj_set
    inc ebx
    mov ecx, ss_tdrive_path
    call obj_set
    mov eax, [ss_tmp]
    mov esi, ss_drive_tfile
    call obj_save
    setnc al
    cmp al, 1
    call st_check
    call obj_free
    mov byte [fo_file+FO_LETTER], 't'
    call ss_load_drives
    mov esi, ss_nm_tdrive
    call stu_find
    setnc al
    cmp al, 1
    call st_check
    cmp dword [st_fail], 0
    jne .fail
    mov eax, [dk_objs+edx*4]
    cmp dword [eax+OBJ_CLASS], fo_c_drive
    call st_check
    call wps_settings
    cmp dword [pm_set_win], -1
    setne al
    cmp al, 1
    call st_check
    cmp dword [pm_set_win], -1
    je .nset3
    mov eax, [pm_set_win]
    call wm_close
    mov dword [pm_set_win], -1
.nset3:
    ; #235: dropping the live Drive removes it from dk_objs
    mov cl, 't'
    call ss_drive_drop
    mov esi, ss_nm_tdrive
    call stu_find
    setc al
    cmp al, 1
    call st_check
    mov esi, ss_drive_tfile
    call fs_delete
    cmp dword [st_fail], 0
    jne .fail
    mov byte [ss_ok], 1
    jmp .end
.fail:
    mov byte [ss_ok], 0
.end:
    cmp dword [pm_set_win], -1
    je .noset
    mov eax, [pm_set_win]
    call wm_close
    mov dword [pm_set_win], -1
.noset:
    call dk_freeobjs
    call gfx_text
    mov byte [ss_test], 0
    mov byte [ss_opened], 0
    mov esi, ss_pass
    cmp byte [ss_ok], 1
    je .say
    mov esi, ss_failmsg
.say:
    call puts
    popad
    ret
.nof:
    mov esi, ss_failmsg
    call puts
    popad
    ret

; ---------- data ----------

ss_pass db 'syssetup: PASS', 10, 0
ss_failmsg db 'syssetup: FAIL', 10, 0
ss_setup_file db '/desktop/SystemSetup.obj', 0
ss_drive_tfile db '/desktop/drive-t.obj', 0
ss_fn_setup db 'SystemSetup', 0
ss_fn_shred db 'shredder', 0
ss_nm_setup db 'System Setup', 0
ss_nm_shred db 'Shredder', 0
ss_nm_tdrive db 'Drive T', 0
ss_tdrive_path db 'T:/', 0
ss_drive_fn db 'drive-a', 0     ; letter patched at +6
ss_cn_setup db 'SystemSetup', 0

align 4
ss_c_setup dd ss_cn_setup, dk_c_dobj, ss_setup_m, 0, 0
ss_setup_m dd dk_s_open, ss_setup_open, 0
ss_tmp dd 0
ss_drive_names times 26 * 8 db 0
ss_test db 0
ss_opened db 0
ss_ok db 0
ss_let db 0
