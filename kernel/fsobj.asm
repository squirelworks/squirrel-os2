; Squirrel-OS/2 — drive and shredder objects (2.7)
; Included from pm.asm, in the high image. Original code.
;
; Two classes under the desktop's DesktopObject (desktop.asm, objects.md):
;
;   Drive     field path ("d:/"). One per mounted drive: mount writes
;             /desktop/drive-d.obj (name "Drive D"), umount removes it, and
;             a boot removes any left from before. open lists the drive in a
;             window: arrows, Enter opens a directory or shows a file,
;             Backspace goes up, Esc closes. Folder views and the File
;             Manager list the path with fs_readdir_long (volume.asm).
;   Shredder  no fields; /desktop/shredder.obj. drop deletes what is dropped
;             on it: eax = the shredder, ebx = the dropped object (or 0),
;             ecx = the path of the file to delete (the object's file, or a
;             file or empty directory from a folder view) -> eax = 0 when it
;             was deleted (the desktop then forgets the object), -1 when
;             refused: drives and shredders are not shredded, and a path
;             that cannot be deleted stays.
;
; The classes are recorded when a drive is mounted and at boot when
; /desktop exists, before the desktop loads its object files.
; See documentation/kernel/fat.md ("Desktop objects").

; Records DesktopObject, Drive and Shredder (twice is harmless)
fsobj_register:
    push eax
    push esi
    mov esi, dk_c_dobj
    call obj_class
    mov esi, fo_c_drive
    call obj_class
    mov esi, fo_c_shred
    call obj_class
    pop esi
    pop eax
    ret

; At boot, after SQFS is mounted: if /desktop exists, drive objects from
; before the reboot go (no drive is mounted yet) and the shredder is made
; if it is missing.
fsobj_boot:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    mov esi, dk_dir
    call fs_find_dir
    jc .r
    call fsobj_register
    mov cl, 'a'
.l:
    mov [fo_file+FO_LETTER], cl
    mov esi, fo_file
    call fs_delete
    inc cl
    cmp cl, 'z'
    jbe .l
    call fsobj_shredder
.r:
    popad
    ret

; Writes /desktop/shredder.obj unless it is there
fsobj_shredder:
    pushad
    mov esi, fo_shred_file
    call fs_lookup
    test edi, edi
    jnz .r
    mov eax, fo_c_shred
    call obj_new
    test eax, eax
    jz .r
    xor ebx, ebx
    mov ecx, fo_cn_shred
    call obj_set                ; name
    inc ebx
    mov ecx, dk_empty
    call obj_set                ; in: the top level
    mov esi, fo_shred_file
    call obj_save
    call obj_free
.r:
    popad
    ret

; ebp = the volume just mounted: its Drive object goes to /desktop
fsobj_mounted:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    call fsobj_register
    mov esi, dk_dir
    call fs_mkdir               ; (already there: fine)
    mov al, [ebp+V_LETTER]
    mov [fo_name+FO_NLETTER], al
    mov [fo_path], al
    call fat_lower
    mov [fo_file+FO_LETTER], al
    mov eax, fo_c_drive
    call obj_new
    test eax, eax
    jz .r
    xor ebx, ebx
    mov ecx, fo_name
    call obj_set                ; name "Drive D"
    inc ebx
    mov ecx, dk_empty
    call obj_set                ; in: the top level
    inc ebx
    mov ecx, fo_path
    call obj_set                ; path "D:/"
    mov esi, fo_file
    call obj_save
    call obj_free
    call fsobj_shredder
.r:
    popad
    ret

; ebp = the volume being unmounted: its Drive object goes
fsobj_unmounted:
    pushad
    cmp byte [fs_mounted], 0
    je .r
    mov al, [ebp+V_LETTER]
    call fat_lower
    mov [fo_file+FO_LETTER], al
    mov esi, fo_file
    call fs_delete
.r:
    popad
    ret

; ---------- methods ----------

; Drive open: the drive's files in a window (eax = the Drive)
fo_drive_open:
    pushad
    mov [fo_obj], eax
    mov ebx, 2
    call obj_get                ; path
    mov esi, eax
    mov edi, fo_bpath
    call fat_copy_path
    mov eax, [fo_obj]
    xor ebx, ebx
    call obj_get                ; name, the window's title
    mov esi, eax
    mov ebx, fo_browse
    call dk_textwin
    popad
    xor eax, eax
    ret

; Shredder open: nothing to open
fo_shred_open:
    mov eax, -1
    ret

; Shredder drop: eax = shredder, ebx = dropped object or 0, ecx = path of
; what to delete -> eax = 0 deleted, -1 refused
fo_shred_drop:
    pushad
    test ebx, ebx
    jz .path
    mov eax, [ebx+OBJ_CLASS]
    cmp eax, fo_c_drive
    je .no
    cmp eax, fo_c_shred
    je .no
.path:
    test ecx, ecx
    jz .no
    mov esi, ecx
    call fs_delete
    test eax, eax
    jnz .no
    popad
    xor eax, eax
    ret
.no:
    popad
    mov eax, -1
    stc
    ret

; ---------- a drive's files, in text ----------

; Lists [fo_bpath] (a drive path like "d:/docs") and lets the user move
; through it. Runs in the desktop's text window or on the text screen.
fo_browse:
    mov dword [fo_sel], 0
    mov dword [fo_top], 0
.draw:
    call fo_draw
.key:
    call kbd_getscan
    call kbd_shift_track
    je .key
    cmp al, 0x80
    jae .key
    cmp al, 0x01                ; Esc
    je .quit
    cmp al, 0x48                ; Up
    je .up
    cmp al, 0x50                ; Down
    je .down
    cmp al, 0x1C                ; Enter
    je .open
    cmp al, 0x0E                ; Backspace
    je .back
    jmp .key
.up:
    cmp dword [fo_sel], 0
    je .key
    dec dword [fo_sel]
    jmp .draw
.down:
    mov eax, [fo_sel]
    inc eax
    cmp eax, [fo_count]
    jae .key
    mov [fo_sel], eax
    jmp .draw
.open:
    cmp dword [fo_count], 0
    je .key
    mov eax, [fo_sel]
    call fo_entry               ; fo_ent = the chosen entry
    jc .key
    call fo_join                ; fo_bfile = path/name
    jc .key
    test dword [fo_ent+RD_FLAGS], RDF_DIR
    jz .show
    mov esi, fo_bfile           ; into the directory
    mov edi, fo_bpath
    call fat_copy_path
    mov dword [fo_sel], 0
    mov dword [fo_top], 0
    jmp .draw
.show:
    call cls
    mov dword [cur], 0
    mov esi, fo_bfile
    call fs_cat
    mov esi, fo_m_key
    call puts
.wait:
    call kbd_getscan
    cmp al, 0x80
    jae .wait
    jmp .draw
.back:
    mov esi, fo_bpath           ; cut the last part, not "x:/"
    call strlen
    lea edi, [esi+eax]
.b:
    cmp edi, fo_bpath+3
    jbe .root
    dec edi
    cmp byte [edi], '/'
    jne .b
    mov byte [edi], 0
    jmp .moved
.root:
    mov byte [fo_bpath+3], 0
    mov byte [fo_bpath+2], '/'
.moved:
    mov dword [fo_sel], 0
    mov dword [fo_top], 0
    jmp .draw
.quit:
    ret

; Draws the path, the entries around the selection and the key help
fo_draw:
    pushad
    call cls
    mov dword [cur], 0
    mov esi, fo_bpath
    call puts
    mov al, 10
    call putc
    mov eax, [txt_rows]
    sub eax, 3
    mov [fo_rows], eax
    mov eax, [fo_sel]           ; keep the selection on screen
    cmp eax, [fo_top]
    jae .t1
    mov [fo_top], eax
.t1:
    mov edx, [fo_top]
    add edx, [fo_rows]
    cmp eax, edx
    jb .t2
    sub eax, [fo_rows]
    inc eax
    mov [fo_top], eax
.t2:
    xor ebp, ebp                ; index
    mov ebx, 0x80000000
.l:
    mov ecx, fo_ent
    mov edx, fo_bpath
    call fs_readdir_long
    cmp eax, -1
    je .bad
    test eax, eax
    jz .done
    mov ebx, eax
    cmp ebp, [fo_top]
    jb .n
    mov edx, [fo_top]
    add edx, [fo_rows]
    cmp ebp, edx
    jae .n
    mov esi, fo_m_sel
    cmp ebp, [fo_sel]
    je .mark
    mov esi, fo_m_nosel
.mark:
    call puts
    mov esi, fo_ent
    call puts
    test dword [fo_ent+RD_FLAGS], RDF_DIR
    jz .size
    mov al, '/'
    call putc
    jmp .eol
.size:
    mov al, ' '
    call putc
    mov eax, [fo_ent+RD_SIZE]
    call itoa
    mov esi, num_buf
    call puts
.eol:
    mov al, 10
    call putc
.n:
    inc ebp
    jmp .l
.bad:
    call fs_why
.done:
    mov [fo_count], ebp
    test ebp, ebp
    jnz .help
    mov esi, fo_m_empty
    call puts
.help:
    mov esi, fo_m_help
    call puts
    popad
    ret

; eax = index -> fo_ent = that entry of [fo_bpath]. CF if none.
fo_entry:
    pushad
    mov ebp, eax
    mov ebx, 0x80000000
.l:
    mov ecx, fo_ent
    mov edx, fo_bpath
    call fs_readdir_long
    cmp eax, -1
    je .no
    test eax, eax
    jz .no
    mov ebx, eax
    dec ebp
    jns .l
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; fo_bfile = fo_bpath + '/' (unless it ends in one) + fo_ent's name. CF
; if it does not fit.
fo_join:
    pushad
    mov esi, fo_bpath
    mov edi, fo_bfile
    call fat_copy_path
    mov edi, fo_bfile
    call strlen_edi
    add edi, eax
    cmp byte [edi-1], '/'
    je .n
    mov byte [edi], '/'
    inc edi
.n:
    mov esi, fo_ent
    mov ecx, fo_bfile+FS_PATHMAX-1
.c:
    cmp edi, ecx
    jae .long
    lodsb
    stosb
    test al, al
    jnz .c
    popad
    clc
    ret
.long:
    popad
    stc
    ret

; edi = string -> eax = its length
strlen_edi:
    push esi
    mov esi, edi
    call strlen
    pop esi
    ret

; ---------- fsobjtest ----------

; fsobjtest: the classes, a Drive's fields through a file, the shredder
; deleting a dropped file and refusing a drive and a missing path.
cmd_fsobjtest_run:
    pushad
    call fs_need
    jc .r
    mov dword [st_fail], 0
    call fsobj_register
    mov eax, fo_c_drive
    call obj_new
    test eax, eax
    jz .fail
    mov [fot_drive], eax
    xor ebx, ebx
    mov ecx, fot_dname
    call obj_set
    inc ebx
    mov ecx, dk_empty
    call obj_set
    inc ebx
    mov ecx, fot_dpath
    call obj_set
    mov esi, dk_s_name          ; inherited from DesktopObject
    call obj_send
    mov esi, eax
    mov edi, fot_dname
    call streq
    call st_check
    mov eax, [fot_drive]        ; through a file and back
    mov esi, fot_file
    call obj_save
    setnc al
    cmp al, 1
    call st_check
    mov esi, fot_file
    call obj_load
    jc .fail
    mov [fot_back], eax
    cmp dword [eax+OBJ_CLASS], fo_c_drive
    call st_check
    mov eax, [fot_back]
    mov ebx, 2
    call obj_get
    mov esi, eax
    mov edi, fot_dpath
    call streq
    call st_check
    ; the shredder
    mov eax, fo_c_shred
    call obj_new
    test eax, eax
    jz .fail
    mov [fot_shred], eax
    mov esi, fot_victim
    call fs_create
    mov eax, [fot_shred]
    xor ebx, ebx
    mov ecx, fot_victim
    mov esi, fo_s_drop
    call obj_send
    test eax, eax
    call st_check
    mov esi, fot_victim
    call fs_lookup
    test edi, edi
    call st_check
    mov eax, [fot_shred]        ; the object's own file
    mov ebx, [fot_back]
    mov ecx, fot_file
    mov esi, fo_s_drop
    call obj_send
    cmp eax, -1                 ; a Drive: refused, its file stays
    call st_check
    mov esi, fot_file
    call fs_lookup
    test edi, edi
    jz .fail1
    mov eax, [fot_shred]
    xor ebx, ebx
    mov ecx, fot_victim         ; gone already
    mov esi, fo_s_drop
    call obj_send
    cmp eax, -1
    call st_check
    mov eax, [fot_shred]        ; open does nothing
    mov esi, dk_s_open
    call obj_send
    cmp eax, -1
    call st_check
    mov eax, [fot_drive]
    call obj_free
    mov eax, [fot_back]
    call obj_free
    mov eax, [fot_shred]
    call obj_free
    mov esi, fot_file
    call fs_delete
    mov esi, fot_pass
    cmp dword [st_fail], 0
    je .out
    jmp .fail
.fail1:
    inc dword [st_fail]
.fail:
    mov esi, fot_failmsg
.out:
    call puts
.r:
    popad
    ret

; drive x: : the drive's files on the text screen (fo_browse)
cmd_drive_run:
    pushad
    call next_word
    call vol_path
    jc .usage
    call vol_find
    jc .why
    mov edi, fo_bpath
    mov al, [esi]
    stosb
    mov ax, ':/'
    stosw
    mov byte [edi], 0
    call fo_browse
    call cls
    mov dword [cur], 0
    popad
    ret
.why:
    call fs_why
    popad
    ret
.usage:
    mov esi, fo_m_usage
    call puts
    popad
    ret

; ---------- data ----------
FO_LETTER equ 15                ; in fo_file
FO_NLETTER equ 6                ; in fo_name
align 4
fo_c_drive dd fo_cn_drive, dk_c_dobj, fo_drive_m, fo_drive_f, 1 ; path is text
fo_c_shred dd fo_cn_shred, dk_c_dobj, fo_shred_m, 0, 0
fo_drive_m dd dk_s_open, fo_drive_open, 0
fo_shred_m dd dk_s_open, fo_shred_open, fo_s_drop, fo_shred_drop, 0
fo_drive_f dd fo_f_path, 0      ; field 2, after name and in
fo_obj dd 0
fo_sel dd 0
fo_top dd 0
fo_rows dd 0
fo_count dd 0
fot_drive dd 0
fot_back dd 0
fot_shred dd 0
fo_cn_drive db 'Drive', 0
fo_cn_shred db 'Shredder', 0
fo_f_path db 'path', 0
fo_s_drop db 'drop', 0
fo_file db '/desktop/drive-d.obj', 0
fo_shred_file db '/desktop/shredder.obj', 0
fo_name db 'Drive D', 0
fo_path db 'D:/', 0
fo_m_sel db '> ', 0
fo_m_nosel db '  ', 0
fo_m_empty db '  (empty)', 10, 0
fo_m_help db 'Enter: open  Bksp: up  Esc: close', 0
fo_m_key db 10, '(press a key)', 0
fo_m_usage db 'Usage: drive <x:>', 10, 0
fot_dname db 'Drive T', 0
fot_dpath db 'T:/', 0
fot_file db '/fsobjtest.obj', 0
fot_victim db 'shred me, a file with a long name', 0
fot_pass db 'fsobjtest: PASS', 10, 0
fot_failmsg db 'fsobjtest: FAIL', 10, 0
fo_ent times RD_LEN db 0
fo_bpath times FS_PATHMAX db 0
fo_bfile times FS_PATHMAX db 0
