; Squirrel-OS/2 — Startup folder (W.6-startup)
; Included from pm.asm, in the high image. Original code.
;
; A Folder named "Startup" at the top level of /desktop holds Programs
; (or Shadows) that are opened when the desktop / Program Manager starts.
; Removing an object from that folder (or deleting it) stops that. Folders
; inside Startup are not auto-opened. See documentation/apps/desktop.md
; ("Startup") and TODO.md W.6-startup.
;
; Commands: w6startup (self-check -> startup: PASS).

; Ensure Startup.obj exists and is loaded into dk_objs. Called from
; dk_mkobjs after wps_attach.
stu_attach:
    pushad
    cmp byte [fs_mounted], 0
    je .mem
    mov esi, dk_dir
    call fs_mkdir
    call stu_ensure
.mem:
    call stu_load
    popad
    ret

; Create /desktop/Startup.obj (Folder, in empty) when missing.
stu_ensure:
    pushad
    mov esi, stu_fold_file
    call fs_lookup
    test edi, edi
    jnz .r
    mov eax, dk_c_fold
    call obj_new
    test eax, eax
    jz .r
    xor ebx, ebx
    mov ecx, stu_nm_startup
    call obj_set                ; name
    inc ebx
    mov ecx, dk_empty
    call obj_set                ; in: top level
    mov esi, stu_fold_file
    call obj_save
    call obj_free
.r:
    popad
    ret

; Load Startup.obj into dk_objs when not already present.
stu_load:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    mov esi, stu_fn_startup
    call stu_has_file
    jnc .r
    mov esi, stu_fold_file
    call fs_lookup
    test edi, edi
    jz .r
    mov esi, stu_fold_file
    call obj_load
    jc .r
    mov edx, [dk_n]
    cmp edx, DK_MAX
    jae .full
    mov [dk_objs+edx*4], eax
    mov dword [dk_files+edx*4], stu_fn_startup
    inc dword [dk_n]
    jmp .r
.full:
    call obj_free
.r:
    popad
    ret

; esi = file basename -> CF clear if some dk_files slot matches
stu_has_file:
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

; After objects are loaded: open every Program/Shadow whose `in` is
; "Startup". Skips Folders. With stu_test=1, records names in stu_hit /
; stu_n and uses dki_test so Program open does not enter a text window.
stu_run:
    pushad
    mov dword [stu_n], 0
    mov byte [stu_hit], 0
    xor edx, edx                ; loop index
.l:
    cmp edx, [dk_n]
    jae .done
    mov eax, [dk_objs+edx*4]
    test eax, eax
    jz .n
    cmp dword [eax+OBJ_CLASS], dk_c_fold
    je .n                       ; Folders inside Startup are not auto-opened
    mov ebx, 1
    call obj_get                ; in
    test eax, eax
    jz .n
    mov esi, eax
    mov edi, stu_nm_startup
    call streq
    jne .n
    mov eax, [dk_objs+edx*4]
    cmp byte [stu_test], 0
    je .send
    xor ebx, ebx
    call obj_get                ; name
    test eax, eax
    jz .send2
    mov esi, eax
    call stu_record
.send2:
    mov eax, [dk_objs+edx*4]
.send:
    mov esi, dk_s_open
    call obj_send
.n:
    inc edx
    jmp .l
.done:
    popad
    ret

; esi = name string: copy into stu_hit[stu_n] if room
stu_record:
    pushad
    mov edx, [stu_n]
    cmp edx, 16
    jae .r
    mov edi, stu_hit
    mov eax, edx
    imul eax, 16
    add edi, eax
    mov ecx, 15
.c:
    lodsb
    stosb
    test al, al
    jz .z
    loop .c
    mov byte [edi], 0
.z:
    inc dword [stu_n]
.r:
    popad
    ret

; ---------- w6startup self-check ----------
; Startup folder + Program in it opens at stu_run; nested Folder skipped;
; after moving the Program out, stu_run opens nothing. -> startup: PASS

cmd_w6startup_run:
    pushad
    call fs_need
    jc .nof
    mov dword [st_fail], 0
    mov byte [stu_ok], 0
    mov byte [dki_test], 1
    mov byte [stu_test], 1
    call dk_mkobjs              ; includes stu_attach
    cmp dword [dk_n], 0
    je .fail
    mov esi, stu_boot_file
    call fs_delete
    mov esi, stu_nest_file
    call fs_delete
    ; Program "stu_boot" / entry calc / in Startup
    mov eax, dk_c_prog
    call obj_new
    test eax, eax
    jz .fail
    mov [stu_boot], eax
    xor ebx, ebx
    mov ecx, stu_nm_boot
    call obj_set                ; name
    inc ebx
    mov ecx, stu_nm_startup
    call obj_set                ; in: Startup
    inc ebx
    mov ecx, dk_a1              ; entry: calc
    call obj_set
    mov eax, [stu_boot]
    mov esi, stu_boot_file
    call obj_save
    setnc al
    cmp al, 1
    call st_check
    mov eax, [stu_boot]
    mov esi, stu_nm_boot
    call dk_addobj
    jc .fail
    ; Folder "stu_nest" in Startup (must NOT auto-open)
    mov eax, dk_c_fold
    call obj_new
    test eax, eax
    jz .fail
    mov [stu_nest], eax
    xor ebx, ebx
    mov ecx, stu_nm_nest
    call obj_set
    inc ebx
    mov ecx, stu_nm_startup
    call obj_set
    mov eax, [stu_nest]
    mov esi, stu_nest_file
    call obj_save
    setnc al
    cmp al, 1
    call st_check
    mov eax, [stu_nest]
    mov esi, stu_nm_nest
    call dk_addobj
    jc .fail
    call stu_run
    cmp dword [stu_n], 1
    call st_check
    mov esi, stu_hit
    mov edi, stu_nm_boot
    call streq
    call st_check
    ; move Program out of Startup
    mov esi, stu_nm_boot
    call stu_find
    jc .fail
    mov eax, [dk_objs+edx*4]
    mov ebx, 1
    mov ecx, dk_empty
    call obj_set
    mov esi, stu_boot_file
    call obj_save
    call stu_run
    cmp dword [stu_n], 0
    call st_check
    cmp dword [st_fail], 0
    jne .fail
    mov byte [stu_ok], 1
    jmp .end
.fail:
    mov byte [stu_ok], 0
.end:
    call dk_freeobjs
    mov byte [dki_test], 0
    mov byte [stu_test], 0
    mov byte [dk_arg], 0
    mov esi, stu_pass
    cmp byte [stu_ok], 1
    je .say
    mov esi, stu_failmsg
.say:
    call puts
    popad
    ret
.nof:
    mov esi, stu_failmsg
    call puts
    popad
    ret

; esi = name -> CF clear, edx = dk_objs index
stu_find:
    push eax
    push ebx
    push edi
    xor edx, edx
.f:
    cmp edx, [dk_n]
    jae .no
    mov eax, [dk_objs+edx*4]
    test eax, eax
    jz .n
    xor ebx, ebx
    call obj_get
    test eax, eax
    jz .n
    mov edi, eax
    push esi
    call streq
    pop esi
    je .yes
.n:
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

; ---------- data ----------

stu_pass db 'startup: PASS', 10, 0
stu_failmsg db 'startup: FAIL', 10, 0
stu_fold_file db '/desktop/Startup.obj', 0
stu_boot_file db '/desktop/stu_boot.obj', 0
stu_nest_file db '/desktop/stu_nest.obj', 0
stu_fn_startup db 'Startup', 0
stu_nm_startup db 'Startup', 0
stu_nm_boot db 'stu_boot', 0
stu_nm_nest db 'stu_nest', 0

align 4
stu_n dd 0
stu_boot dd 0
stu_nest dd 0
stu_hit times 16 * 16 db 0
stu_test db 0
stu_ok db 0
