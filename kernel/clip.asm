; Squirrel-OS/2 — the clipboard (2.3-clipboard). Original code.
;
; One text clipboard in the kernel, CLIP_MAX bytes. Field widgets and the
; editors copy to it and paste from it (Ctrl+Ins / Ctrl+C copy, Shift+Ins
; / Ctrl+V paste, Shift+Del / Ctrl+X cut); programs use SYS_CLIPPUT and
; SYS_CLIPGET; `run clipbrd` shows it in a window. It lasts until the next
; copy (or a reboot). See documentation/kernel/clipboard.md.

CLIP_MAX    equ 1024

WK_COPY     equ 0x03            ; widget keys (wg_key): Ctrl+C,
WK_PASTE    equ 0x16            ; Ctrl+V,
WK_CUT      equ 0x18            ; Ctrl+X

; esi = text, ecx = its length: the clipboard holds it (cut to CLIP_MAX)
; -> eax = the length kept
clip_put:
    push ecx
    push esi
    push edi
    cmp ecx, CLIP_MAX
    jbe .ok
    mov ecx, CLIP_MAX
.ok:
    mov [clip_len], ecx
    mov eax, ecx
    mov edi, clip_buf
    rep movsb
    pop edi
    pop esi
    pop ecx
    ret

; edi = buffer, ecx = its size -> as much of the clipboard as fits there
; (no zero added), eax = the clipboard's length
clip_get:
    push ecx
    push esi
    push edi
    cmp ecx, [clip_len]
    jbe .ok
    mov ecx, [clip_len]
.ok:
    mov esi, clip_buf
    rep movsb
    mov eax, [clip_len]
    pop edi
    pop esi
    pop ecx
    ret

; SYS_CLIPPUT: ebx = text, ecx = length -> the length kept
sys_clipput:
    mov esi, ebx
    jmp clip_put

; SYS_CLIPGET: ebx = buffer, ecx = its size -> the clipboard's length
; (what fits is copied)
sys_clipget:
    mov edi, ebx
    jmp clip_get

; al = a scancode just read (kbd_shift_track has seen the modifiers) ->
; al = WK_COPY, WK_PASTE or WK_CUT and CF clear for the clipboard keys;
; CF set and al kept otherwise
clip_key:
    cmp byte [kbd_ctrl], 0
    je .shift
    cmp al, 0x52                ; Ctrl+Ins
    je .copy
    cmp al, 0x2E                ; Ctrl+C
    je .copy
    cmp al, 0x2F                ; Ctrl+V
    je .paste
    cmp al, 0x2D                ; Ctrl+X
    je .cut
    stc
    ret
.shift:
    cmp byte [kbd_shift], 0
    je .no
    cmp al, 0x52                ; Shift+Ins
    je .paste
    cmp al, 0x53                ; Shift+Del
    je .cut
.no:
    stc
    ret
.copy:
    mov al, WK_COPY
    clc
    ret
.paste:
    mov al, WK_PASTE
    clc
    ret
.cut:
    mov al, WK_CUT
    clc
    ret

; edi = a field widget, dl = WK_COPY / WK_PASTE / WK_CUT: the whole text
; is copied (and cleared, for a cut); a paste adds the clipboard to the
; end, up to the first newline and as much as the field takes
clip_field:
    pushad
    mov esi, [edi+WG_TEXT]
    cmp dl, WK_PASTE
    je .paste
    call strlen
    mov ecx, eax
    call clip_put
    cmp dl, WK_CUT
    jne .r
    mov byte [esi], 0
    jmp .r
.paste:
    call strlen                 ; eax = characters now
    mov ebx, esi
    add ebx, eax                ; where the paste goes
    mov ecx, [edi+WG_CODE]
    sub ecx, eax                ; room
    xor edx, edx
.c:
    cmp edx, [clip_len]
    jae .end
    cmp edx, ecx
    jae .end
    mov al, [clip_buf+edx]
    cmp al, 10
    je .end
    cmp al, ' '
    jb .skip
    cmp al, 0x7E
    ja .skip
    mov [ebx], al
    inc ebx
.skip:
    inc edx
    jmp .c
.end:
    mov byte [ebx], 0
.r:
    popad
    ret

; cbtest: a window with a field holding "clip me"; Ctrl+Ins (WK_COPY)
; copies it. That window closes; in a second one with an empty field
; Shift+Ins (WK_PASTE) pastes it, Shift+Del (WK_CUT) empties the field and
; leaves the clipboard as it was, and SYS_CLIPGET from the kernel side
; reads it back. The clipboard keeps "clip me" (for `run clipbrd`).
; Prints `clip: PASS` or `clip: FAIL` (the name cliptest is 2.1's clip rectangle).
cmd_cbtest_run:
    call gfx_mode13
    jnc .ok
    mov esi, dk_nomem
    jmp puts
.ok:
    mov byte [ct_ok], 1
    mov esi, ct_text
    mov edi, ct_b1
    mov ecx, ct_tlen + 1
    rep movsb
    mov byte [ct_b2], 0
    mov eax, 40
    mov ebx, 40
    mov ecx, 200
    mov edx, 60
    mov esi, ct_t1
    call wm_create
    mov [ct_win], eax
    mov ebx, 4
    mov ecx, 4
    mov esi, ct_b1
    mov edx, 20
    call wg_field
    mov al, WK_COPY
    call wg_key
    jc .bad
    cmp dword [clip_len], ct_tlen
    jne .bad
    mov esi, clip_buf
    mov edi, ct_text
    mov ecx, ct_tlen
    repe cmpsb
    jne .bad
    mov eax, [ct_win]
    call wm_close
    mov eax, 60
    mov ebx, 60
    mov ecx, 200
    mov edx, 60
    mov esi, ct_t2
    call wm_create
    mov [ct_win], eax
    mov ebx, 4
    mov ecx, 4
    mov esi, ct_b2
    mov edx, 20
    call wg_field
    mov al, WK_PASTE
    call wg_key
    jc .bad
    mov esi, ct_b2
    mov edi, ct_text
    call streq
    jne .bad
    mov al, WK_CUT
    call wg_key
    cmp byte [ct_b2], 0
    jne .bad
    mov ebx, ct_back            ; what a program's SYS_CLIPGET gets
    mov ecx, 32
    call sys_clipget
    cmp eax, ct_tlen
    jne .bad
    mov byte [ct_back+ct_tlen], 0
    mov esi, ct_back
    mov edi, ct_text
    call streq
    je .end
.bad:
    mov byte [ct_ok], 0
.end:
    mov eax, [ct_win]
    call wm_close
    call gfx_text
    mov esi, ct_pass
    cmp byte [ct_ok], 1
    je .say
    mov esi, ct_fail
.say:
    jmp puts

ct_text db 'clip me', 0
ct_tlen equ 7
ct_t1 db 'Copy', 0
ct_t2 db 'Paste', 0
ct_pass db 'clip: PASS', 10, 0
ct_fail db 'clip: FAIL', 10, 0
ct_ok db 0
align 4
ct_win dd -1
ct_b1 times 24 db 0
ct_b2 times 24 db 0
ct_back times 33 db 0

align 4
clip_len dd 0
clip_buf times CLIP_MAX db 0
