; winprog — a program with windows (2.2-progwin). Original code.
; run winprog: opens One, draws in it, opens Two over part of it, draws in
; One under Two (which must not show through), reads pixels back, then
; waits for a key (reported) and Alt+F4 on Two (WE_CLOSE: it closes Two),
; then closes One. Back in text mode it prints what it saw and
; `progwin: PASS` or `progwin: FAIL`.
%include "sqx.inc"
SQX_HEADER main

%macro DRAW 7                   ; window var, op, x, y, a, b, colour (ptr in cmd+24)
    mov dword [cmd], %2
    mov dword [cmd+4], %3
    mov dword [cmd+8], %4
    mov dword [cmd+12], %5
    mov dword [cmd+16], %6
    mov dword [cmd+20], %7
    mov eax, SYS_WINDRAW
    mov ebx, [%1]
    mov ecx, cmd
    int 0x80
%endmacro

main:
    mov byte [ok], 1
    mov eax, SYS_WINOPEN        ; One: client at (101, 111), 238 x 149
    mov ebx, open1
    int 0x80
    cmp eax, -1
    je .fail
    mov [w1], eax
    mov eax, SYS_WINFLUSH
    mov ebx, [w1]
    int 0x80
    DRAW w1, WD_FILL, 10, 10, 40, 30, 0x2A
    mov dword [cmd+24], hello
    DRAW w1, WD_TEXT, 10, 50, -1, 0, 0x00
    mov eax, SYS_WINFLUSH
    mov ebx, [w1]
    int 0x80
    DRAW w1, WD_PIXEL, 20, 20, 0, 0, 0
    cmp eax, 0x2A               ; the fill is on the screen
    jne .fail
    mov eax, SYS_WINOPEN        ; Two over One's middle: screen x 130.., y 110..
    mov ebx, open2
    int 0x80
    cmp eax, -1
    je .fail
    mov [w2], eax
    mov eax, SYS_WINFLUSH
    mov ebx, [w2]
    int 0x80
    DRAW w1, WD_FILL, 10, 20, 60, 40, 0x0C  ; screen x 111..170: under Two from 130
    mov eax, SYS_WINFLUSH
    mov ebx, [w1]
    int 0x80
    DRAW w1, WD_PIXEL, 15, 25, 0, 0, 0
    cmp eax, 0x0C               ; left of Two: drawn
    jne .fail
    DRAW w2, WD_PIXEL, 10, 30, 0, 0, 0
    cmp eax, 0x0C               ; Two's client over One's fill: not drawn there
    je .fail
    mov eax, SYS_WININFO
    mov ebx, [w1]
    mov ecx, info
    int 0x80
    cmp dword [info], 101
    jne .fail
    cmp dword [info+8], 238
    jne .fail
.events:                        ; a key, then WE_CLOSE for Two
    mov eax, SYS_WINEVENT
    mov ebx, ev
    xor ecx, ecx
    int 0x80
    mov eax, [ev]
    cmp eax, WE_PAINT
    je .paint
    cmp eax, WE_KEY
    je .key
    cmp eax, WE_CLOSE
    jne .events
    mov eax, [ev+4]
    cmp eax, [w2]
    jne .events
    mov eax, SYS_WINCLOSE
    mov ebx, [w2]
    int 0x80
    mov eax, SYS_WINCLOSE
    mov ebx, [w1]
    int 0x80
    jmp .report
.paint:
    inc dword [paints]
    jmp .events
.key:
    mov eax, [ev+8]
    mov [keych], al
    jmp .events
.fail:
    mov byte [ok], 0
    mov eax, SYS_WINCLOSE
    mov ebx, [w2]
    int 0x80
    mov eax, SYS_WINCLOSE
    mov ebx, [w1]
    int 0x80
.report:
    mov eax, SYS_PUTS
    mov ebx, keymsg
    int 0x80
    mov eax, SYS_PUTS
    mov ebx, pass
    cmp byte [ok], 1
    je .say
    mov ebx, failmsg
.say:
    int 0x80
    xor eax, eax
    ret

open1 dd 100, 100, 240, 160, title1, 0
open2 dd 130, 110, 200, 120, title2, 0
title1 db 'One', 0
title2 db 'Two', 0
hello db 'Hello', 0
keymsg db 'progwin key: '
keych db '?', 10, 0
pass db 'progwin: PASS', 10, 0
failmsg db 'progwin: FAIL', 10, 0
align 4
w1 dd -1
w2 dd -1

SQX_BSS
cmd resd 7
ev resd 4
info resd 4
paints resd 1
ok resb 1
SQX_END
