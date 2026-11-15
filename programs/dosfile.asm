; dosfile — DOS file, memory and input services through dosrun (P.8).
; Original code. Create/write/close, open/seek/read, attributes, rename,
; delete, a missing file (CF, AX = 2), memory blocks (48h/4Ah), then a
; line typed at the keyboard (0Ah) is echoed back.
;   run dosfile.com   (type a word and Enter)  ->  got: <word> / dosfile: PASS
; Build: nasm -f bin dosfile.asm -o dosfile.com
BITS 16
org 0x100

%macro STEP 1
    mov byte [step], %1
%endmacro

start:
    STEP 'a'                        ; create and write
    mov ah, 0x3C
    xor cx, cx
    mov dx, fname
    int 0x21
    jc fail
    mov bx, ax
    mov ah, 0x40
    mov cx, text_len
    mov dx, text
    int 0x21
    jc fail
    cmp ax, text_len
    jne fail
    mov ah, 0x3E
    int 0x21
    jc fail
    STEP 'b'                        ; open, seek to 4, read the rest
    mov ax, 0x3D00
    mov dx, fname
    int 0x21
    jc fail
    mov bx, ax
    mov ax, 0x4200
    xor cx, cx
    mov dx, 4
    int 0x21
    jc fail
    cmp ax, 4
    jne fail
    mov ah, 0x3F
    mov cx, 64
    mov dx, buf
    int 0x21
    jc fail
    cmp ax, text_len - 4
    jne fail
    mov si, buf
    mov di, text + 4
    mov cx, text_len - 4
    push ds
    pop es
    repe cmpsb
    jne fail
    mov ah, 0x3E
    int 0x21
    STEP 'c'                        ; attributes, rename, delete, missing
    mov ax, 0x4300
    mov dx, fname
    int 0x21
    jc fail
    mov ah, 0x56
    mov dx, fname
    mov di, fname2
    int 0x21
    jc fail
    mov ax, 0x3D00
    mov dx, fname
    int 0x21
    jnc fail                        ; the old name is gone
    cmp ax, 2
    jne fail
    mov ah, 0x41
    mov dx, fname2
    int 0x21
    jc fail
    STEP 'd'                        ; memory: shrink ourselves, take a block
    mov ah, 0x4A
    mov bx, 0x1000                  ; 64 KB for the .COM
    int 0x21
    jc fail
    mov ah, 0x48
    mov bx, 0x100                   ; 4 KB
    int 0x21
    jc fail
    mov es, ax
    mov word [es:0], 0xACE
    cmp word [es:0], 0xACE
    jne fail
    mov ah, 0x48
    mov bx, 0xFFFF                  ; too much: CF, AX = 8, BX = what is free
    int 0x21
    jnc fail
    cmp ax, 8
    jne fail
    STEP 'e'                        ; device information for the console
    mov ax, 0x4400
    mov bx, 1
    int 0x21
    test dl, 0x80
    jz fail
    STEP 'f'                        ; a typed line through 0Ah
    mov ah, 0x09
    mov dx, prompt
    int 0x21
    mov ah, 0x0A
    mov dx, line
    int 0x21
    mov bl, [line+1]
    xor bh, bh
    mov byte [line+2+bx], '$'
    mov ah, 0x09
    mov dx, got
    int 0x21
    mov ah, 0x09
    mov dx, line+2
    int 0x21
    mov ah, 0x09
    mov dx, crlf
    int 0x21
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

fname db 'DOSFILE.TXT', 0           ; DOS names are upper case; dosrun lowers them
fname2 db 'DOSFILE.REN', 0
text db 'DOS wrote this', 13, 10
text_len equ $ - text
prompt db 'type a word: $'
got db 'got: $'
crlf db 13, 10, '$'
pass db 'dosfile: PASS', 13, 10, '$'
failmsg db 'dosfile: FAIL '
step db '?', 13, 10, '$'
line db 20, 0
    times 21 db 0
buf times 64 db 0
