; Squirrel-OS/2 — desktop shell (1.6)
; Included from pm.asm. Original code.
;
; The desktop command: graphics mode, a window listing the programs, keys
; to the window's widgets. Esc returns to the text shell. Opening a
; program in a window comes in the later 1.6 tasks.
; See documentation/apps/desktop.md.

DK_X equ 40                     ; the desktop's window
DK_Y equ 24
DK_W equ 240
DK_H equ 150

cmd_desktop_run:
    call gfx_mode13
    jnc .ok
    mov esi, dk_nomem
    jmp puts
.ok:
    mov eax, DK_X
    mov ebx, DK_Y
    mov ecx, DK_W
    mov edx, DK_H
    mov esi, dk_title
    call wm_create
    mov [dk_win], eax
    mov ebx, 4
    mov ecx, 4
    mov esi, dk_heading
    call wg_label
    mov eax, [dk_win]
    mov ebx, 4
    mov ecx, 16
    mov esi, dk_apps
    mov edx, DK_NAPPS
    call wg_list
    mov eax, [dk_win]
    mov ebx, 4
    mov ecx, DK_H - WM_TITLE_H - 2 - GFX_CELL_H - 4
    mov esi, dk_help
    call wg_label
.draw:
    call wm_redraw
.key:
    call wg_getkey
    cmp al, 27
    je .quit
    call wg_key
    jnc .draw
    jmp .key                    ; Enter opens a program in a later 1.6 task
.quit:
    mov eax, [dk_win]
    call wm_close
    call gfx_text
    mov esi, dk_bye
    jmp puts

; Waits for a key -> al = what wg_key takes: ASCII, 8 for Backspace,
; 27 for Esc, WK_UP and WK_DOWN for the arrows.
wg_getkey:
    call kbd_getscan
    call kbd_shift_track
    je wg_getkey
    cmp al, 0x80
    jae wg_getkey               ; releases, and the 0xE0 before an arrow
    mov ah, 27
    cmp al, 0x01
    je .r
    mov ah, 8
    cmp al, 0x0E
    je .r
    mov ah, WK_UP
    cmp al, 0x48
    je .r
    mov ah, WK_DOWN
    cmp al, 0x50
    je .r
    call kbd_ascii
    mov ah, al
    test al, al
    jz wg_getkey
.r:
    mov al, ah
    ret

DK_NAPPS equ 5
dk_title db 'Squirrel-OS/2 Desktop', 0
dk_heading db 'Programs:', 0
dk_help db 'Up/Down: choose   Esc: shell', 0
dk_a0 db 'files', 0
dk_a1 db 'calc', 0
dk_a2 db 'edit', 0
dk_a3 db 'vedit', 0
dk_a4 db 'draw', 0
dk_bye db 'Desktop closed.', 10, 0
dk_nomem db 'desktop: no memory for graphics', 10, 0
align 4
dk_apps dd dk_a0, dk_a1, dk_a2, dk_a3, dk_a4
dk_win dd 0
