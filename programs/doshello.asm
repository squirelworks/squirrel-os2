; doshello — a DOS .COM program (P.8). Original code.
; Prints through INT 21h AH=09h, AH=02h and AH=40h and the BIOS teletype
; (INT 10h AH=0Eh), echoes its command tail from the PSP, exits with
; INT 21h AH=4Ch. run doshello.com [words]
; Build: nasm -f bin doshello.asm -o doshello.com
BITS 16
org 0x100

start:
    mov ah, 0x09
    mov dx, hello
    int 0x21
    mov ah, 0x02                ; one character
    mov dl, '#'
    int 0x21
    mov ah, 0x0E                ; the BIOS teletype
    mov al, '!'
    int 0x10
    mov ah, 0x40                ; write to handle 1
    mov bx, 1
    mov cx, tail_len
    mov dx, tail
    int 0x21
    jc fail
    cmp ax, tail_len
    jne fail
    ; the command tail at PSP:80h: length, text, CR
    mov cl, [0x80]
    xor ch, ch
    mov si, 0x81
    mov bx, 1
    mov dx, si
    mov ah, 0x40
    int 0x21
    mov ah, 0x09
    mov dx, crlf
    int 0x21
    mov ah, 0x30                ; DOS version: 5
    int 0x21
    cmp al, 5
    jne fail
    mov ah, 0x09
    mov dx, pass
    int 0x21
    mov ax, 0x4C00
    int 0x21
fail:
    mov ah, 0x09
    mov dx, failmsg
    int 0x21
    mov ax, 0x4C01
    int 0x21

hello db 'Hello from DOS land!', 13, 10, '$'
tail db ' tail:'
tail_len equ $ - tail
crlf db 13, 10, '$'
pass db 'doshello: PASS', 13, 10, '$'
failmsg db 'doshello: FAIL', 13, 10, '$'
