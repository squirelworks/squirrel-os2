; clipbrd — the Clipboard viewer (2.3-clipboard). Original code.
; run clipbrd: a window that shows the clipboard's text, a line per row,
; in the window face; "(empty)" when there is nothing. Painted again when
; the window manager asks (WE_PAINT); q or Alt+F4 closes it. On the way
; out it prints `clipbrd: N bytes`.
%include "sqx.inc"
SQX_HEADER main

CB_MAX equ 1024
CB_ROW equ 11

main:
    mov eax, SYS_CLIPGET
    mov ebx, text
    mov ecx, CB_MAX - 1
    int 0x80
    mov [len], eax
    cmp eax, CB_MAX - 1
    jbe .z
    mov eax, CB_MAX - 1
.z:
    mov byte [text+eax], 0
    mov eax, SYS_WINOPEN
    mov ebx, openb
    int 0x80
    cmp eax, -1
    je .out
    mov [win], eax
    call paint
.events:
    mov eax, SYS_WINEVENT
    mov ebx, ev
    xor ecx, ecx
    int 0x80
    mov eax, [ev]
    cmp eax, WE_PAINT
    je .paint
    cmp eax, WE_CLOSE
    je .close
    cmp eax, WE_KEY
    jne .events
    cmp byte [ev+8], 'q'
    jne .events
.close:
    mov eax, SYS_WINCLOSE
    mov ebx, [win]
    int 0x80
.out:
    mov eax, [len]              ; "clipbrd: N bytes"
    mov edi, num + 10
    mov byte [edi], 0
    mov ebx, 10
.d:
    xor edx, edx
    div ebx
    add dl, '0'
    dec edi
    mov [edi], dl
    test eax, eax
    jnz .d
    mov eax, SYS_PUTS
    mov ebx, said
    int 0x80
    mov eax, SYS_PUTS
    mov ebx, edi
    int 0x80
    mov eax, SYS_PUTS
    mov ebx, bytes
    int 0x80
    xor eax, eax
    ret
.paint:
    call paint
    jmp .events

; The client white, then the text a line per row
paint:
    pushad
    mov dword [cmd], WD_FILL
    mov dword [cmd+4], 0
    mov dword [cmd+8], 0
    mov dword [cmd+12], 640
    mov dword [cmd+16], 480
    mov dword [cmd+20], 0x3F
    call draw
    mov esi, text
    mov dword [y], 4
    cmp byte [esi], 0
    jne .line
    mov esi, empty
.line:
    cmp byte [esi], 0
    je .flush
    mov edi, row                ; one line, without its newline
    mov ecx, 120
.c:
    lodsb
    test al, al
    jz .end
    cmp al, 10
    je .nl
    jecxz .c
    stosb
    dec ecx
    jmp .c
.end:
    dec esi                     ; stay on the zero
.nl:
    mov byte [edi], 0
    mov dword [cmd], WD_PTEXT
    mov dword [cmd+4], 6
    mov eax, [y]
    mov [cmd+8], eax
    mov dword [cmd+12], -1      ; no background
    mov dword [cmd+16], 0       ; the window face
    mov dword [cmd+20], 0x00
    mov dword [cmd+24], row
    call draw
    add dword [y], CB_ROW
    cmp dword [y], 170
    jb .line
.flush:
    mov eax, SYS_WINFLUSH
    mov ebx, [win]
    int 0x80
    popad
    ret

draw:
    mov eax, SYS_WINDRAW
    mov ebx, [win]
    mov ecx, cmd
    int 0x80
    ret

openb dd 120, 120, 400, 200, title, 0
title db 'Clipboard', 0
empty db '(empty)', 0
said db 'clipbrd: ', 0
bytes db ' bytes', 10, 0
align 4
win dd -1

SQX_BSS
len resd 1
y resd 1
cmd resd 7
ev resd 4
num resb 12
row resb 128
text resb CB_MAX
SQX_END
