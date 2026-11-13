; Squirrel-OS/2 — text clipboard (2.3-clipboard)
; Included from pm.asm. Original code.
;
; One kernel text clipboard shared by field widgets, the editors, the
; Clipboard viewer, and SYS_CLIPPUT / SYS_CLIPGET. See
; documentation/kernel/clipboard.md.

CLIP_MAX        equ 1024        ; bytes of text, including the zero

; esi = text, eax = length (not including a zero). Caps at CLIP_MAX-1,
; stores a zero after the text. -> eax = length stored, or -1 if esi is 0.
clip_put:
    push ebx
    push ecx
    push edi
    test esi, esi
    jz .bad
    cmp eax, CLIP_MAX - 1
    jbe .len
    mov eax, CLIP_MAX - 1
.len:
    mov [clip_len], eax
    mov ecx, eax
    mov edi, clip_buf
    rep movsb
    mov byte [edi], 0
    jmp .out
.bad:
    mov eax, -1
.out:
    pop edi
    pop ecx
    pop ebx
    ret

; edi = destination, ecx = most bytes of text (room for ecx + a zero).
; Copies the clipboard text, zero-terminated. -> eax = length copied.
clip_get:
    push ebx
    push ecx
    push esi
    push edi
    mov eax, [clip_len]
    cmp eax, ecx
    jbe .n
    mov eax, ecx
.n:
    mov ecx, eax
    mov esi, clip_buf
    rep movsb
    mov byte [edi], 0
    pop edi
    pop esi
    pop ecx
    pop ebx
    ret

; ebx = ASCIIZ text -> eax = length stored, or -1
sys_clipput:
    mov esi, ebx
    call strlen
    jmp clip_put

; ebx = buffer, ecx = most characters (room for ecx + a zero)
; -> eax = length copied
sys_clipget:
    mov edi, ebx
    jmp clip_get

; Shell: clipboard — show the clipboard in a window (Esc closes), or
; "(empty)" when there is nothing.
cmd_clipboard_run:
    call gfx_mode13
    jnc .ok
    mov esi, cbv_nomem
    jmp puts
.ok:
    mov eax, 40
    mov ebx, 40
    mov ecx, 240
    mov edx, 80
    mov esi, [lstr+LS_CLIP_TITLE*4]
    call wm_create
    mov [cbv_win], eax
    mov ebx, 8
    mov ecx, 8
    mov esi, [lstr+LS_CLIP_EMPTY*4]
    cmp dword [clip_len], 0
    je .lab
    mov esi, clip_buf
.lab:
    call wg_label
.draw:
    call wm_redraw
.key:
    call kbd_getscan
    call kbd_shift_track
    je .key
    cmp al, 0x80
    jae .key
    cmp al, 0x01                ; Esc
    jne .key
    mov eax, [cbv_win]
    call wm_close
    call gfx_text
    ret

align 4
clip_len dd 0
clip_buf times CLIP_MAX db 0
cbv_win dd 0
cbv_nomem db 'clipboard: no memory for graphics', 10, 0
