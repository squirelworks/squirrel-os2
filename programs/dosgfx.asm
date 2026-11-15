; dosgfx — a DOS .COM program in VGA mode 13h (P.8). Original code.
; Sets mode 13h, draws through A000 and INT 10h pixels, changes a DAC
; entry through ports 3C8h/3C9h and reads it back through INT 10h, waits
; for the retrace on 3DAh, writes "dosgfx: drawn" with the BIOS
; teletype in graphics, waits for a key, goes back to text mode and
; prints "dosgfx: PASS" (or "dosgfx: FAIL x").
; Build: nasm -f bin dosgfx.asm -o dosgfx.com
BITS 16
CPU 186
org 0x100

%macro STEP 1
    mov byte [step], %1
%endmacro
%macro CHECK 1                  ; jump to fail unless condition %1
    j%-1 fail
%endmacro

start:
    STEP 'a'                        ; mode 13h
    mov ax, 0x0013
    int 0x10
    mov ah, 0x0F
    int 0x10
    cmp al, 0x13
    CHECK e
    STEP 'b'                        ; no key waits yet
    mov ah, 0x01
    int 0x16
    CHECK z
    STEP 'c'                        ; a red block straight into A000
    push 0xA000
    pop es
    mov di, 120*320 + 100
    mov dx, 40
.rows:
    mov cx, 120
    mov al, 4
    rep stosb
    add di, 320 - 120
    dec dx
    jnz .rows
    cmp byte [es:130*320 + 150], 4
    CHECK e
    STEP 'd'                        ; INT 10h pixels, written and read
    mov ax, 0x0C0E                  ; yellow
    xor bx, bx
    mov cx, 10
    mov dx, 190
    int 0x10
    mov ax, 0x0D00
    int 0x10
    cmp al, 0x0E
    CHECK e
    cmp byte [es:190*320 + 10], 0x0E
    CHECK e
    STEP 'e'                        ; DAC 200 through the ports
    mov dx, 0x3C8
    mov al, 200
    out dx, al
    inc dx
    mov al, 63
    out dx, al
    mov al, 32
    out dx, al
    mov al, 1
    out dx, al
    mov ax, 0x1015
    mov bx, 200
    int 0x10
    cmp dh, 63
    CHECK e
    cmp ch, 32
    CHECK e
    cmp cl, 1
    CHECK e
    STEP 'f'                        ; one retrace, both edges
    mov dx, 0x3DA
.v1:
    in al, dx
    test al, 8
    jnz .v1
.v2:
    in al, dx
    test al, 8
    jz .v2
    STEP 'g'                        ; text in graphics
    mov ah, 0x02
    xor bh, bh
    mov dx, 0x0201                  ; row 2, column 1
    int 0x10
    mov si, drawn
.t:
    lodsb
    test al, al
    jz .td
    mov ah, 0x0E
    mov bl, 14
    int 0x10
    jmp .t
.td:
    mov ah, 0x03
    int 0x10
    cmp dx, 0x0201 + drawn_len
    CHECK e
    xor ah, ah                      ; wait for a key
    int 0x16
    mov ax, 0x0003
    int 0x10
    mov ah, 0x0F
    int 0x10
    cmp al, 3
    CHECK e
    mov ah, 0x09
    mov dx, pass
    int 0x21
    mov ax, 0x4C00
    int 0x21
fail:
    mov ax, 0x0003
    int 0x10
    mov ah, 0x09
    mov dx, failmsg
    int 0x21
    mov ax, 0x4C01
    int 0x21

drawn db 'dosgfx: drawn', 0
drawn_len equ $ - drawn - 1
pass db 'dosgfx: PASS', 13, 10, '$'
failmsg db 'dosgfx: FAIL '
step db '?', 13, 10, '$'
