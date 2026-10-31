; Squirrel-OS/2 — file browser (0.2.3)
; Included from pm.asm. Original code.
;
; run files: list the files, move with the arrows, Enter launches an app
; (a file whose name is a built-in app) or views any other file.
; See documentation/apps/files.md.

FB_ROWS       equ 18            ; list rows on screen
FB_MAX        equ 64

fb_main:
    mov dword [fb_sel], 0
    mov dword [fb_top], 0
.reload:
    call fb_scan
.draw:
    call fb_draw
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
    cmp al, 0x49                ; PgUp
    je .pgup
    cmp al, 0x51                ; PgDn
    je .pgdn
    cmp al, 0x47                ; Home
    je .home
    cmp al, 0x4F                ; End
    je .end
    cmp al, 0x1C                ; Enter
    je .open
    cmp al, 0x2F                ; v
    je .view
    cmp al, 0x20                ; d
    je .delete
    cmp al, 0x12                ; e
    je .edit
    jmp .key
.up:
    cmp dword [fb_sel], 0
    je .key
    dec dword [fb_sel]
    jmp .draw
.down:
    mov eax, [fb_sel]
    inc eax
    cmp eax, [fb_count]
    jae .key
    mov [fb_sel], eax
    jmp .draw
.pgup:
    mov eax, [fb_sel]
    sub eax, FB_ROWS
    jns .set
    xor eax, eax
    jmp .set
.pgdn:
    mov eax, [fb_sel]
    add eax, FB_ROWS
    jmp .clamp
.home:
    xor eax, eax
    jmp .set
.end:
    mov eax, [fb_count]
.clamp:
    cmp eax, [fb_count]
    jb .set
    mov eax, [fb_count]
    dec eax
    jns .set
    xor eax, eax
.set:
    mov [fb_sel], eax
    jmp .draw
.open:
    call fb_current
    jc .key
    call fb_app_for             ; ebx = start routine or 0
    test ebx, ebx
    jz .prog
.launch:
    mov ecx, ebx                ; launch as a child process and wait
    mov ebx, app_host
    mov eax, SYS_SPAWN
    int SYSCALL_VEC
    cmp eax, -1
    je .draw
    mov ebx, eax
    mov eax, SYS_WAIT
    int SYSCALL_VEC
    jmp .reload                 ; the app may have changed files
.edit:
    call fb_current
    jc .key
    mov edi, esi
    call set_run_arg
    mov ebx, run_edit
    jmp .launch
.prog:
    ; a program file (SQX/ELF) runs through the loader; anything else is viewed
    push esi
    call cls
    pop esi
    mov ebx, esi
    xor ecx, ecx
    mov eax, SYS_EXEC
    int SYSCALL_VEC
    cmp eax, LD_EFORMAT
    je .view
    test eax, eax
    js .progerr
    mov ebx, eax
    mov eax, SYS_WAIT
    int SYSCALL_VEC
    jmp .progdone
.progerr:
    call ld_perror
.progdone:
    mov esi, fb_anykey
    call puts
    call fb_waitkey
    jmp .reload
.view:
    call fb_current
    jc .key
    call cls
    call fs_cat
    mov esi, fb_anykey
    call puts
    call fb_waitkey
    jmp .draw
.delete:
    call fb_current
    jc .key
    cmp byte [fs_mounted], 0
    je .key                     ; ROM files cannot be deleted
    push esi
    mov esi, fb_confirm
    call fb_status
    call fb_waitkey
    pop esi
    cmp al, 0x15                ; y
    jne .draw
    call fs_delete
    jmp .reload
.quit:
    call app_home
    xor eax, eax
    ret

; Collects name pointers (and sizes) from the mounted FS or the ROM table.
fb_scan:
    pushad
    mov dword [fb_count], 0
    mov edi, fb_names
    cmp byte [fs_mounted], 0
    je .rom
    mov esi, FS_DIR
    mov ecx, FS_MAXFILES
    mov dl, [fs_cwd]            ; the files of the current directory
.d:
    cmp byte [esi], 0
    je .dn
    cmp [esi+DE_PARENT], dl
    jne .dn
    cmp byte [esi+DE_KIND], DK_DIR
    je .dn
    mov [edi], esi
    mov eax, [esi+DE_SIZE]
    mov [edi+FB_MAX*4], eax
    add edi, 4
    inc dword [fb_count]
.dn:
    add esi, FS_DIRENT
    loop .d
    jmp .fix
.rom:
    mov esi, file_table
    mov ecx, [file_count]
.r:
    mov [edi], esi
    push esi
    mov esi, [esi+8]
    call strlen
    pop esi
    mov [edi+FB_MAX*4], eax
    add edi, 4
    inc dword [fb_count]
    add esi, 16
    loop .r
.fix:
    mov eax, [fb_count]         ; keep the selection inside the list
    cmp [fb_sel], eax
    jb .ok
    dec eax
    jns .s
    xor eax, eax
.s:
    mov [fb_sel], eax
.ok:
    popad
    ret

fb_draw:
    pushad
    ; scroll the window so the selection is visible
    mov eax, [fb_sel]
    cmp eax, [fb_top]
    jae .below
    mov [fb_top], eax
.below:
    mov ebx, [fb_top]
    add ebx, FB_ROWS
    cmp eax, ebx
    jb .drawn
    sub eax, FB_ROWS-1
    mov [fb_top], eax
.drawn:
    call cls
    mov esi, fb_title
    call puts
    mov esi, fb_src_disk
    cmp byte [fs_mounted], 0
    jne .src
    mov esi, fb_src_rom
.src:
    call puts
    mov ecx, [fb_top]
    mov edx, FB_ROWS
.row:
    cmp ecx, [fb_count]
    jae .blank
    mov al, ' '
    cmp ecx, [fb_sel]
    jne .mark
    mov al, '>'
.mark:
    call putc
    mov al, ' '
    call putc
    mov esi, [fb_names+ecx*4]
    call puts
    mov al, 20
    call puts_pad
    mov eax, [fb_sizes+ecx*4]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 30
    call puts_pad
    mov esi, [fb_names+ecx*4]
    push ebx
    call fb_app_for
    test ebx, ebx
    pop ebx
    jz .noapp
    mov esi, fb_tag_app
    call puts
.noapp:
    inc ecx
.blank:
    mov al, 10
    call putc
    dec edx
    jnz .row
    mov esi, fb_help
    call puts
    mov eax, [fb_count]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, fb_nfiles
    call puts
    popad
    ret

; esi = message: print on its own line (used for confirmations)
fb_status:
    call puts
    ret

; -> esi = selected name, CF if the list is empty
fb_current:
    mov eax, [fb_sel]
    cmp eax, [fb_count]
    jae .none
    mov esi, [fb_names+eax*4]
    clc
    ret
.none:
    stc
    ret

; esi = name -> ebx = app start routine from run_table, or 0
fb_app_for:
    push edi
    mov ebx, run_table
.l:
    mov edi, [ebx]
    test edi, edi
    jz .none
    call streq
    je .hit
    add ebx, 8
    jmp .l
.hit:
    mov ebx, [ebx+4]
    pop edi
    ret
.none:
    xor ebx, ebx
    pop edi
    ret

; waits for a key press (not a release or Shift) -> al = scancode
fb_waitkey:
    call kbd_getscan
    call kbd_shift_track
    je fb_waitkey
    cmp al, 0x80
    jae fb_waitkey
    ret

fb_sel dd 0
fb_top dd 0
fb_count dd 0
fb_names times FB_MAX dd 0
fb_sizes times FB_MAX dd 0      ; must follow fb_names (indexed as +FB_MAX*4)
fb_title db 'Files', 0
fb_src_disk db ' (data disk)', 10, 10, 0
fb_src_rom db ' (built-in, no data disk)', 10, 10, 0
fb_tag_app db '[app]', 0
fb_help db 10, 'Arrows PgUp/PgDn Home/End  Enter: open  v: view  e: edit  d: delete  Esc', 10, 0
fb_nfiles db ' files', 0
fb_anykey db 10, '-- press any key --', 0
fb_confirm db 10, 'Delete this file? (y/n)', 0
