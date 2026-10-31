; Squirrel-OS/2 — shell line editing and command history (0.5.1)
; Included from pm.asm. Original code.
;
; Keys: Left/Right/Home/End move, Backspace/Delete erase, typing inserts
; at the cursor, Up/Down walk the history, Esc clears the line.
; The last 16 commands are kept in memory and appended to shell.hist on
; the data disk, which is read back at boot.
; See documentation/kernel/shell.md.

HIST_MAX    equ 16
HIST_BUF    equ KSCRATCH+0x2800     ; HIST_MAX * SH_LINE bytes
HIST_FILE_MAX equ 0x8000            ; read at most this much at boot
HIST_REWRITE equ 64                 ; compact the file after this many lines

; Shows the prompt and starts an empty line.
sh_prompt:
    push esi
    cmp byte [fs_mounted], 0    ; outside the root, show where we are
    je .plain
    cmp byte [fs_cwd], 0
    je .plain
    push edx
    mov dl, [fs_cwd]
    call fs_print_path
    pop edx
.plain:
    mov esi, [lstr+LS_PROMPT*4]
    call puts
    pop esi
    mov eax, [cur]
    mov [sh_start], eax
    mov byte [cmdline], 0
    mov dword [cmdpos], 0
    mov dword [sh_len], 0
    mov dword [sh_oldlen], 0
    mov dword [hist_sel], 0
    ret

; al = scancode (make code, not a modifier) for the command line
sh_key:
    cmp al, 0x1C
    je .enter
    cmp al, 0x0E
    je .bs
    cmp al, 0x53
    je .del
    cmp al, 0x4B
    je .left
    cmp al, 0x4D
    je .right
    cmp al, 0x47
    je .home
    cmp al, 0x4F
    je .end
    cmp al, 0x48
    je hist_up
    cmp al, 0x50
    je hist_down
    cmp al, 0x01
    je .clear
    call kbd_ascii
    test al, al
    jz .r
    cmp al, 10
    je .r
    ; insert at the cursor
    mov ecx, [sh_len]
    cmp ecx, SH_LINE-8
    jae .r
    mov ebx, [cmdpos]
.shift:
    cmp ecx, ebx
    jbe .put
    mov dl, [cmdline+ecx-1]
    mov [cmdline+ecx], dl
    dec ecx
    jmp .shift
.put:
    mov [cmdline+ebx], al
    inc dword [sh_len]
    inc dword [cmdpos]
    jmp sh_redraw
.bs:
    mov ebx, [cmdpos]
    test ebx, ebx
    jz .r
    dec dword [cmdpos]
    dec ebx
    jmp .remove
.del:
    mov ebx, [cmdpos]
    cmp ebx, [sh_len]
    jae .r
.remove:                        ; drop the character at ebx
    mov ecx, [sh_len]
.rm:
    mov dl, [cmdline+ebx+1]
    mov [cmdline+ebx], dl
    inc ebx
    cmp ebx, ecx
    jb .rm
    dec dword [sh_len]
    jmp sh_redraw
.left:
    cmp dword [cmdpos], 0
    je .r
    dec dword [cmdpos]
    jmp sh_redraw
.right:
    mov eax, [cmdpos]
    cmp eax, [sh_len]
    jae .r
    inc dword [cmdpos]
    jmp sh_redraw
.home:
    mov dword [cmdpos], 0
    jmp sh_redraw
.end:
    mov eax, [sh_len]
    mov [cmdpos], eax
    jmp sh_redraw
.clear:
    mov dword [sh_len], 0
    mov dword [cmdpos], 0
    jmp sh_redraw
.enter:
    mov eax, [sh_len]
    mov byte [cmdline+eax], 0
    mov [cmdpos], eax
    call sh_redraw              ; leaves the cursor at the end of the line
    mov al, 10
    call putc
    call hist_add
    jmp do_command
.r:
    ret

; Rewrites the line from sh_start and places the cursor.
sh_redraw:
    mov eax, [sh_len]
    mov byte [cmdline+eax], 0
    mov eax, [scroll_count]
    push eax
    mov eax, [sh_start]
    mov [cur], eax
    mov esi, cmdline
    call puts
    ; blank what is left of a longer previous line
    mov ecx, [sh_oldlen]
    sub ecx, [sh_len]
    jbe .blanked
.blank:
    mov al, ' '
    call putc
    loop .blank
.blanked:
    mov eax, [sh_len]
    mov [sh_oldlen], eax
    ; rows that scrolled away moved the start of the line up
    pop eax
    sub eax, [scroll_count]
    imul eax, 80
    add [sh_start], eax
    mov eax, [sh_start]
    add eax, [cmdpos]
    mov [cur], eax
    jmp cursor_sync

; ---------- history ----------

; esi = HIST entry index (0 = oldest kept) -> esi = its text
hist_entry:
    push eax
    push edx
    mov eax, [hist_next]
    sub eax, [hist_count]
    add eax, esi
    and eax, HIST_MAX-1
    imul eax, SH_LINE
    lea esi, [HIST_BUF+eax]
    pop edx
    pop eax
    ret

hist_up:
    mov eax, [hist_sel]
    cmp eax, [hist_count]
    jae .r
    test eax, eax
    jnz .go
    ; leaving the new line: keep it as a draft
    mov esi, cmdline
    mov edi, sh_draft
    mov ecx, SH_LINE/4
    rep movsd
    mov eax, [sh_len]
    mov [sh_draftlen], eax
.go:
    inc dword [hist_sel]
    jmp hist_show
.r:
    ret

hist_down:
    cmp dword [hist_sel], 0
    je .r
    dec dword [hist_sel]
    jnz hist_show
    mov esi, sh_draft
    mov edi, cmdline
    mov ecx, SH_LINE/4
    rep movsd
    mov eax, [sh_draftlen]
    jmp hist_set
.r:
    ret

; copies history entry (count - sel) into the line
hist_show:
    mov esi, [hist_count]
    sub esi, [hist_sel]
    call hist_entry
    mov edi, cmdline
    mov ecx, SH_LINE/4
    rep movsd
    mov esi, cmdline
    call strlen
hist_set:
    mov [sh_len], eax
    mov [cmdpos], eax
    jmp sh_redraw

; Remembers cmdline (if not blank and not a repeat) and appends it to
; the history file.
hist_add:
    mov esi, cmdline
    call sh_trim
    cmp byte [esi], 0
    je .r
    cmp dword [hist_count], 0
    je .new
    push esi
    mov esi, [hist_count]
    dec esi
    call hist_entry
    mov edi, esi
    mov esi, cmdline
    call streq
    pop esi
    je .r
.new:
    mov esi, cmdline
    call hist_push
    cmp byte [fs_mounted], 0
    je .r
    inc dword [hist_appends]
    cmp dword [hist_appends], HIST_REWRITE
    jae hist_rewrite
    mov esi, hist_name
    mov ecx, O_CREATE|O_APPEND
    call fs_open
    cmp eax, -1
    je .r
    mov ebx, eax
    mov esi, cmdline
    call strlen
    push eax
    mov ecx, eax
    mov byte [esi+ecx], 10      ; the line buffer has room past the text
    inc ecx
    call fs_write
    pop eax
    mov byte [cmdline+eax], 0
    call fs_close
.r:
    ret

; esi = text: stores it as the newest entry
hist_push:
    push edi
    push ecx
    mov edi, [hist_next]
    imul edi, SH_LINE
    add edi, HIST_BUF
    mov ecx, SH_LINE-1
.c:
    lodsb
    test al, al
    jz .z
    cmp al, 10
    je .z
    stosb
    loop .c
.z:
    mov byte [edi], 0
    inc dword [hist_next]
    and dword [hist_next], HIST_MAX-1
    cmp dword [hist_count], HIST_MAX
    jae .full
    inc dword [hist_count]
.full:
    pop ecx
    pop edi
    ret

; Replaces the history file with the entries in memory.
hist_rewrite:
    mov dword [hist_appends], 0
    mov esi, hist_name
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .r
    mov ebx, eax
    xor edx, edx
.l:
    cmp edx, [hist_count]
    jae .done
    mov esi, edx
    call hist_entry
    push esi
    call strlen
    mov ecx, eax
    call fs_write
    mov esi, hist_nl
    mov ecx, 1
    call fs_write
    pop esi
    inc edx
    jmp .l
.done:
    call fs_close
.r:
    ret

; At boot: loads the newest HIST_MAX lines of the history file.
hist_load:
    cmp byte [fs_mounted], 0
    je .r
    mov esi, hist_name
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .r
    mov ebx, eax
    mov edi, SH_BUF0
    mov ecx, HIST_FILE_MAX-1
    call fs_read
    mov edx, eax
    call fs_close
    cmp edx, -1
    je .r
    mov byte [SH_BUF0+edx], 0
    mov esi, SH_BUF0
    xor ecx, ecx                ; lines read
.line:
    cmp byte [esi], 0
    je .end
    cmp byte [esi], 10
    je .skip
    push esi
    call hist_push
    pop esi
    inc ecx
.skip:                          ; to the start of the next line
    lodsb
    test al, al
    jz .end
    cmp al, 10
    jne .skip
    jmp .line
.end:
    cmp ecx, HIST_REWRITE
    jb .r
    call hist_rewrite           ; keep the file small
.r:
    ret

hist_name db '/shell.hist', 0      ; in the root, wherever the shell is
hist_nl db 10

align 4
sh_start dd 0
sh_len dd 0
sh_oldlen dd 0
sh_draftlen dd 0
hist_next dd 0
hist_count dd 0
hist_sel dd 0
hist_appends dd 0
sh_draft times SH_LINE db 0
