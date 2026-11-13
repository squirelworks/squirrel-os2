; mixer — volume and mute for the sound device (3.0, OS2-NET-AUDIO)
; Original code.
;   run mixer                         the mixer in a window
;   run mixer show                    print the three controls
;   run mixer <control> <0-100>       set both sides of a control
;   run mixer <control> mute|unmute
; The controls are master, pcm and record. The values are what the codec
; reads back, so a level comes back rounded to the codec's steps.
; In the window: Left/Right pick a control, Up/Down (or PgUp/PgDn) move
; it by 5 (25), M mutes or unmutes it, Esc closes. A click on a slider
; sets it there. See documentation/apps/audio.md.
%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"
%include "audio.inc"

NCTL        equ 3
WIN_W       equ 180
WIN_H       equ 150
WIN_X       equ (SCR_W - WIN_W) / 2
WIN_Y       equ (SCR_H - WIN_H) / 2
COL_W       equ 56
COL_X0      equ WIN_X + 8
TRACK_Y     equ WIN_Y + WIN_TITLE_H + 28
TRACK_H     equ 76                  ; 100% at the top
TRACK_W     equ 10
STATUS_Y    equ WIN_Y + WIN_H - 12

main:
    mov esi, [esp+4]
    call skipsp
    cmp byte [esi], 0
    je window
    mov edi, w_show
    call word_is
    je show
    xor ebx, ebx                    ; <control> ...
.c:
    mov edi, [names + ebx * 4]
    call word_is
    je .ctl
    inc ebx
    cmp ebx, NCTL
    jb .c
    jmp usage
.ctl:
    mov [cur], ebx
    mov edi, w_mute
    call word_is
    je .mute
    mov edi, w_unmute
    call word_is
    je .unmute
    xor eax, eax                    ; a level
    xor ecx, ecx
.d:
    movzx edx, byte [esi]
    sub edx, '0'
    cmp edx, 9
    ja .dend
    imul eax, eax, 10
    add eax, edx
    inc esi
    inc ecx
    jmp .d
.dend:
    test ecx, ecx
    jz usage
    cmp byte [esi], 0
    jne usage
    cmp eax, 100
    ja usage
    push eax
    call getvol
    pop eax
    jc nodev
    and edx, 0x10000                ; keep the mute
    mov dl, al
    mov dh, al
    call setvol
    jc nodev
    jmp show
.mute:
    call getvol
    jc nodev
    or edx, 0x10000
    call setvol
    jmp show
.unmute:
    call getvol
    jc nodev
    and edx, ~0x10000
    call setvol
    jmp show

usage:
    mov ebx, m_usage
    jmp fail
nodev:
    mov ebx, m_nodev
fail:
    mov eax, SYS_PUTS
    int 0x80
    mov eax, 1
    ret

; [cur] = control -> edx = its value, CF if there is no device
getvol:
    mov eax, SYS_AUDIO
    mov ebx, AU_GETVOL
    mov ecx, [cur]
    int 0x80
    cmp eax, -1
    je .no
    mov edx, eax
    clc
    ret
.no:
    stc
    ret

; [cur] = control, edx = value -> CF if refused
setvol:
    mov eax, SYS_AUDIO
    mov ebx, AU_SETVOL
    mov ecx, [cur]
    int 0x80
    test eax, eax
    jz .ok
    stc
    ret
.ok:
    clc
    ret

; master  100%  100%  on
show:
    mov eax, SYS_AUDIO
    mov ebx, AU_INFO
    mov ecx, info
    int 0x80
    test eax, eax
    jnz nodev
    mov dword [cur], 0
.row:
    call getvol
    jc nodev
    mov edi, line
    mov ebx, [cur]
    mov esi, [names + ebx * 4]
    call cat
.pad:
    mov eax, edi
    sub eax, line
    cmp eax, 8
    jae .lv
    mov byte [edi], ' '
    inc edi
    jmp .pad
.lv:
    movzx eax, dl
    call pct
    movzx eax, dh
    call pct
    mov esi, m_on
    test edx, 0x10000
    jz .m
    mov esi, m_muted
.m:
    call cat
    mov word [edi], 10
    mov eax, SYS_PUTS
    mov ebx, line
    int 0x80
    inc dword [cur]
    cmp dword [cur], NCTL
    jb .row
    xor eax, eax
    ret

; eax = level -> "100%  " at edi
pct:
    call utoa
    mov byte [edi], '%'
    inc edi
    mov word [edi], '  '
    add edi, 2
    mov byte [edi], 0
    ret

; ---------- the window ----------

window:
    mov eax, SYS_AUDIO
    mov ebx, AU_INFO
    mov ecx, info
    int 0x80
    test eax, eax
    jnz nodev
    call gui_open
    jc .nogfx
    mov dword [cur], 0
.draw:
    call draw
.ev:
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .click
    cmp eax, EV_DRAG
    je .click
    mov edx, eax
    shr edx, 8
    and edx, 0xFF
    cmp dl, K_ESC
    je .quit
    cmp dl, K_LEFT
    je .left
    cmp dl, K_RIGHT
    je .right
    cmp dl, K_TAB
    je .right
    mov ebx, 5
    cmp dl, K_UP
    je .step
    mov ebx, 25
    cmp dl, K_PGUP
    je .step
    mov ebx, -5
    cmp dl, K_DOWN
    je .step
    mov ebx, -25
    cmp dl, K_PGDN
    je .step
    or al, 0x20
    cmp al, 'm'
    je .mute
    jmp .ev
.left:
    dec dword [cur]
    jns .draw
    mov dword [cur], NCTL - 1
    jmp .draw
.right:
    inc dword [cur]
    cmp dword [cur], NCTL
    jb .draw
    mov dword [cur], 0
    jmp .draw
.step:
    push ebx
    call getvol
    pop ebx
    jc .ev
    movzx eax, dl
    add eax, ebx
    call .set
    jmp .draw
.mute:
    call getvol
    jc .ev
    xor edx, 0x10000
    call setvol
    jmp .draw
.click:
    mov eax, [gui_mx]               ; which column, and how high
    sub eax, COL_X0
    js .ev
    xor edx, edx
    mov ecx, COL_W
    div ecx
    cmp eax, NCTL
    jae .ev
    mov [cur], eax
    mov eax, [gui_my]
    sub eax, TRACK_Y
    js .ev
    cmp eax, TRACK_H
    ja .ev
    neg eax
    add eax, TRACK_H
    imul eax, 100
    xor edx, edx
    mov ecx, TRACK_H
    div ecx
    push eax
    call getvol
    pop eax
    jc .ev
    call .set
    jmp .draw
; eax = new level (clamped to 0..100), edx = the old value: set both sides
.set:
    test eax, eax
    jns .s1
    xor eax, eax
.s1:
    cmp eax, 100
    jbe .s2
    mov eax, 100
.s2:
    and edx, 0x10000
    mov dl, al
    mov dh, al
    jmp setvol
.quit:
    call gui_close
    xor eax, eax
    ret
.nogfx:
    mov ebx, m_nogfx
    jmp fail

draw:
    pushad
    mov al, C_CYAN
    call gui_clear
    mov eax, WIN_X
    mov ebx, WIN_Y
    mov ecx, WIN_W
    mov edx, WIN_H
    mov esi, t_title
    call gui_window
    mov edi, line                   ; Device: ac97
    mov esi, m_dev
    call cat
    mov esi, info
    call cat
    mov eax, COL_X0
    mov ebx, WIN_Y + WIN_TITLE_H + 4
    mov esi, line
    call gui_text
    xor ebp, ebp
.col:
    mov [col], ebp
    mov eax, [cur]
    push eax
    mov [cur], ebp
    call getvol
    pop eax
    mov [cur], eax
    mov [val], edx
    mov eax, ebp
    imul eax, COL_W
    add eax, COL_X0
    mov [cx0], eax
    ; the name, highlighted when chosen
    mov ebx, TRACK_Y - 10
    mov esi, [labels + ebp * 4]
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    cmp ebp, [cur]
    jne .nm
    mov byte [gui_ink], C_WHITE
    mov byte [gui_bg], C_BLUE
.nm:
    call gui_text
    ; the track, sunken
    mov eax, [cx0]
    add eax, 8
    mov ebx, TRACK_Y
    mov ecx, TRACK_W
    mov edx, TRACK_H + 1
    mov byte [gui_ink], C_DGREY
    call gui_fill
    mov byte [gui_bevel_up], 0
    call gui_bevel
    ; the filled part
    movzx eax, byte [val]           ; left
    imul eax, TRACK_H
    xor edx, edx
    mov ecx, 100
    div ecx
    mov edx, eax                    ; height
    mov eax, [cx0]
    add eax, 9
    mov ebx, TRACK_Y + TRACK_H
    sub ebx, edx
    mov ecx, TRACK_W - 2
    mov byte [gui_ink], C_LGREEN
    test dword [val], 0x10000
    jz .fill
    mov byte [gui_ink], C_RED
.fill:
    call gui_fill
    ; the level and on / mute under it
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    mov edi, line
    movzx eax, byte [val]
    call utoa
    mov byte [edi], '%'
    mov byte [edi + 1], 0
    mov eax, [cx0]
    mov ebx, TRACK_Y + TRACK_H + 4
    mov esi, line
    call gui_text
    mov esi, m_on
    test dword [val], 0x10000
    jz .st
    mov esi, m_muted
.st:
    add ebx, CELL_H + 1
    call gui_text
    inc ebp
    cmp ebp, NCTL
    jb .col
    mov eax, COL_X0
    mov ebx, STATUS_Y
    mov esi, m_keys
    call gui_text
    call gui_flip
    popad
    ret

; esi = text, edi = word -> ZF if the text starts with it and a space or
; the end follows; esi then points past them
word_is:
    push esi
.l:
    mov al, [edi]
    test al, al
    jz .end
    cmp al, [esi]
    jne .no
    inc esi
    inc edi
    jmp .l
.end:
    mov al, [esi]
    test al, al
    jz .yes
    cmp al, ' '
    jne .no
    call skipsp
.yes:
    add esp, 4
    xor eax, eax
    ret
.no:
    pop esi
    or eax, 1
    ret

skipsp:
    cmp byte [esi], ' '
    jne .r
    inc esi
    jmp skipsp
.r:
    ret

cat:
    lodsb
    test al, al
    jz .r
    stosb
    jmp cat
.r:
    mov byte [edi], 0
    ret

utoa:
    push eax
    push ebx
    push ecx
    push edx
    mov ebx, 10
    xor ecx, ecx
.d:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    test eax, eax
    jnz .d
.o:
    pop eax
    add al, '0'
    stosb
    loop .o
    mov byte [edi], 0
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

t_title     db 'Mixer', 0
w_show      db 'show', 0
w_mute      db 'mute', 0
w_unmute    db 'unmute', 0
n_master    db 'master', 0
n_pcm       db 'pcm', 0
n_record    db 'record', 0
l_master    db 'Master', 0
l_pcm       db 'PCM', 0
l_record    db 'Record', 0
align 4
names       dd n_master, n_pcm, n_record
labels      dd l_master, l_pcm, l_record
m_dev       db 'Device: ', 0
m_on        db 'on', 0
m_muted     db 'muted', 0
m_keys      db 'Arrows, M mute, Esc', 0
m_usage     db 'Usage: run mixer [show | master|pcm|record <0-100>|mute|unmute]', 10, 0
m_nodev     db 'mixer: no sound device', 10, 0
m_nogfx     db 'mixer: no graphics', 10, 0

SQX_BSS
cur         resd 1
col         resd 1
val         resd 1
cx0         resd 1
info        resb 16
line        resb 96
WAV_BSS
GUI_BSS
SQX_END
