; Squirrel-OS/2 — Clock (A.1, OS2-APPS)
; Original code. run clock   |   run clock test
;
; An analogue clock face with hour, minute and second hands, and the time
; and date as text under it, from the CMOS clock (SYS_GUI GUI_TIME and
; GUI_DATE). It redraws when the second changes. Esc quits.
; "run clock test" draws one face, reads back pixels from the screen (the
; centre, the 12 o'clock mark and the face beside it), checks that the
; clock moves within two seconds, and prints "clock: PASS" or FAIL.
; See documentation/apps/gui-programs.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

WIN_W       equ 150
WIN_H       equ 160
WIN_X       equ (SCR_W - WIN_W) / 2
WIN_Y       equ (SCR_H - WIN_H) / 2
RADIUS      equ 52
FACE_X      equ WIN_X + WIN_W / 2           ; centre of the face
FACE_Y      equ WIN_Y + WIN_TITLE_H + 6 + RADIUS
TEXT_Y      equ FACE_Y + RADIUS + 6

main:
    mov eax, [esp+4]
    mov [arg], eax
    fninit
    call gui_open
    jc .nogfx
    mov eax, [arg]
    cmp byte [eax], 't'
    je selftest
.tick:
    call read_clock
    call draw
.wait:
    mov ecx, 20                 ; look at the clock five times a second
    call gui_event
    test eax, eax
    jz .poll
    cmp eax, EV_CLICK
    je .wait
    cmp ah, K_ESC
    je .quit
    jmp .wait
.poll:
    mov eax, SYS_GUI
    mov ebx, GUI_TIME
    int 0x80
    cmp eax, [now]
    je .wait
    jmp .tick
.quit:
    call gui_close
    xor eax, eax
    ret
.nogfx:
    mov esi, msg_nogfx
    call gui_puts
    mov eax, 1
    ret

selftest:
    call read_clock
    call draw
    mov byte [bad], 'c'         ; the centre: the hands' hub is black
    mov eax, FACE_X
    mov ebx, FACE_Y
    call gui_peek
    cmp cl, C_BLACK
    jne .fail
    mov byte [bad], 'm'         ; the 12 o'clock mark, on the rim
    mov eax, FACE_X
    mov ebx, FACE_Y - RADIUS + 2
    call gui_peek
    cmp cl, C_BLACK
    jne .fail
    mov byte [bad], 'f'         ; the face: white left of the hub, or
    mov eax, FACE_X - RADIUS / 2 ; right of it if a hand is there now
    mov ebx, FACE_Y + 3
    call gui_peek
    cmp cl, C_WHITE
    je .faceok
    mov eax, FACE_X + RADIUS / 2
    mov ebx, FACE_Y - 3
    call gui_peek
    cmp cl, C_WHITE
    jne .fail
.faceok:
    mov byte [bad], 't'         ; the clock moves within two seconds
    mov esi, [now]
    mov ecx, 220
.watch:
    push ecx
    mov ecx, 1
    call gui_waitkey
    pop ecx
    mov eax, SYS_GUI
    mov ebx, GUI_TIME
    int 0x80
    cmp eax, esi
    jne .moved
    loop .watch
    jmp .fail
.moved:
    mov byte [bad], 'r'         ; and reads as a time of day
    cmp al, 59
    ja .fail
    cmp ah, 59
    ja .fail
    shr eax, 16
    cmp eax, 23
    ja .fail
    call gui_close
    mov esi, pass
    call gui_puts
    xor eax, eax
    ret
.fail:
    call gui_close
    mov esi, fail
    call gui_puts
    mov esi, bad
    call gui_puts
    mov eax, 1
    ret

; now = hours << 16 | minutes << 8 | seconds, date = year << 16 | month << 8 | day
read_clock:
    mov eax, SYS_GUI
    mov ebx, GUI_TIME
    int 0x80
    mov [now], eax
    mov eax, SYS_GUI
    mov ebx, GUI_DATE
    int 0x80
    mov [date], eax
    ret

draw:
    pushad
    mov al, C_CYAN
    call gui_clear
    mov eax, WIN_X
    mov ebx, WIN_Y
    mov ecx, WIN_W
    mov edx, WIN_H
    mov esi, title
    call gui_window
    call face
    ; hands: hour (short, thick), minute, second (thin, red)
    movzx eax, byte [now+2]     ; hours
    xor edx, edx
    mov ecx, 12
    div ecx
    imul eax, edx, 60
    movzx ecx, byte [now+1]
    add eax, ecx                ; minutes since 12 o'clock, of 720
    mov ecx, 720
    mov edx, RADIUS * 5 / 10
    mov bl, C_BLACK
    call hand
    call hand_thick
    movzx eax, byte [now+1]
    imul eax, 60
    movzx ecx, byte [now]
    add eax, ecx                ; seconds since the hour, of 3600
    mov ecx, 3600
    mov edx, RADIUS * 8 / 10
    mov bl, C_BLACK
    call hand
    movzx eax, byte [now]
    mov ecx, 60
    mov edx, RADIUS * 9 / 10
    mov bl, C_LRED
    call hand
    mov byte [gui_ink], C_BLACK ; the hub
    mov eax, FACE_X - 1
    mov ebx, FACE_Y - 1
    mov ecx, 3
    mov edx, 3
    call gui_fill
    ; the time and the date as text
    mov edi, line
    movzx eax, byte [now+2]
    call two
    mov al, ':'
    stosb
    movzx eax, byte [now+1]
    call two
    mov al, ':'
    stosb
    movzx eax, byte [now]
    call two
    mov ax, '  '
    stosw
    mov eax, [date]
    shr eax, 16
    call gui_utoa
    mov al, '-'
    stosb
    movzx eax, byte [date+1]
    call two
    mov al, '-'
    stosb
    movzx eax, byte [date]
    call two
    mov byte [edi], 0
    mov esi, line
    call gui_textw
    mov ecx, WIN_W
    sub ecx, eax
    shr ecx, 1
    lea eax, [ecx+WIN_X]
    mov ebx, TEXT_Y
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    call gui_text
    call gui_flip
    popad
    ret

; eax = 0..99 -> two digits at edi
two:
    push edx
    push ecx
    xor edx, edx
    mov ecx, 10
    div ecx
    add al, '0'
    add dl, '0'
    stosb
    mov al, dl
    stosb
    pop ecx
    pop edx
    ret

; A white disc with a black rim and twelve marks.
face:
    pushad
    mov ebx, -RADIUS
.row:
    mov eax, -RADIUS
.col:
    mov ecx, eax
    imul ecx, ecx
    mov edx, ebx
    imul edx, edx
    add ecx, edx                ; x^2 + y^2
    cmp ecx, RADIUS * RADIUS
    jg .next
    mov dl, C_WHITE
    cmp ecx, (RADIUS - 1) * (RADIUS - 1)
    jle .put
    mov dl, C_BLACK
.put:
    push eax
    push ebx
    mov cl, dl
    add eax, FACE_X
    add ebx, FACE_Y
    call gui_pset
    pop ebx
    pop eax
.next:
    inc eax
    cmp eax, RADIUS
    jle .col
    inc ebx
    cmp ebx, RADIUS
    jle .row
    ; marks: from 0.85 R to R at each hour
    xor ebp, ebp
.mark:
    mov [frac], ebp
    mov dword [whole], 12
    fild dword [frac]
    fidiv dword [whole]
    call angle_xy               ; st0 = sin, st1 = -cos
    mov dword [len], RADIUS - 7
    call point
    mov [p0], eax
    mov [p0+4], ebx
    mov dword [len], RADIUS - 1
    call point
    fstp st0
    fstp st0
    mov ecx, [p0]
    mov edx, [p0+4]
    mov byte [gui_ink], C_BLACK
    call gui_line
    inc ebp
    cmp ebp, 12
    jb .mark
    popad
    ret

; st0 = fraction of a turn -> st0 = sin(2 pi f), st1 = -cos(2 pi f)
; (screen y grows downwards). The fraction is popped.
angle_xy:
    fldpi
    fadd st0, st0
    fmulp st1, st0
    fsincos                     ; st0 = cos, st1 = sin
    fchs
    fxch
    ret

; st0 = sin, st1 = -cos, [len] -> eax, ebx = the point at that distance
; from the centre (the FPU stack is kept).
point:
    fild dword [len]
    fmul st0, st1
    fistp dword [tmp]
    mov eax, [tmp]
    add eax, FACE_X
    fild dword [len]
    fmul st0, st2
    fistp dword [tmp]
    mov ebx, [tmp]
    add ebx, FACE_Y
    ret

; eax = position, ecx = positions in a turn, edx = length, bl = colour:
; a line from the centre. Leaves the tip in p0.
hand:
    pushad
    mov [frac], eax
    mov [whole], ecx
    mov [len], edx
    mov [gui_ink], bl
    fild dword [frac]
    fidiv dword [whole]
    call angle_xy
    call point
    fstp st0
    fstp st0
    mov [p0], eax
    mov [p0+4], ebx
    mov ecx, eax
    mov edx, ebx
    mov eax, FACE_X
    mov ebx, FACE_Y
    call gui_line
    popad
    ret

; The hand just drawn, again one pixel right and one down: thicker.
hand_thick:
    pushad
    mov eax, FACE_X + 1
    mov ebx, FACE_Y
    mov ecx, [p0]
    inc ecx
    mov edx, [p0+4]
    call gui_line
    mov eax, FACE_X
    mov ebx, FACE_Y + 1
    mov ecx, [p0]
    mov edx, [p0+4]
    inc edx
    call gui_line
    popad
    ret

title db 'Clock', 0
pass db 'clock: PASS', 10, 0
fail db 'clock: FAIL ', 0
bad db '?', 10, 0
msg_nogfx db 'clock: no graphics', 10, 0

SQX_BSS
GUI_BSS
arg resd 1
now resd 1
date resd 1
frac resd 1
whole resd 1
len resd 1
tmp resd 1
p0 resd 2
line resb 32
SQX_END
