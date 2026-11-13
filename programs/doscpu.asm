; doscpu — checks the 8086/80186 instructions dosrun interprets (P.8).
; Original code. Each step compares a result with the value an 8086
; gives; prints "doscpu: PASS" or "doscpu: FAIL x" (x = the step).
; Build: nasm -f bin doscpu.asm -o doscpu.com
BITS 16
CPU 186
org 0x100

%macro STEP 1
    mov byte [step], %1
%endmacro
%macro EXPECT 2                 ; register/memory, value
    cmp %1, %2
    jne fail
%endmacro

start:
    STEP 'a'                        ; add/adc/sub/sbb and their flags
    mov ax, 0xFFFF
    add ax, 1
    jnc fail
    jnz fail
    mov ax, 0x7FFF
    add ax, 1
    jno fail
    js .a1
    jmp fail
.a1:
    stc
    mov ax, 5
    adc ax, 5
    EXPECT ax, 11
    stc
    sbb ax, 1
    EXPECT ax, 9
    mov al, 0x80
    sub al, 1
    jno fail
    STEP 'b'                        ; mul, imul, div, idiv
    mov ax, 300
    mov bx, 400
    mul bx
    jnc fail                        ; the high half is not zero
    EXPECT ax, 0xD4C0               ; 120000 = 0x1D4C0
    EXPECT dx, 1
    mov ax, -7
    mov cx, 3
    imul cx
    EXPECT ax, -21
    EXPECT dx, 0xFFFF
    mov dx, 1
    mov ax, 0xD4C1
    mov bx, 400
    div bx
    EXPECT ax, 300
    EXPECT dx, 1
    mov ax, -100
    cwd
    mov bx, 7
    idiv bx
    EXPECT ax, -14
    EXPECT dx, -2
    mov ax, 200
    mov bl, 7
    div bl
    EXPECT al, 28
    EXPECT ah, 4
    STEP 'c'                        ; shifts and rotates
    mov ax, 0x8001
    shl ax, 1
    jnc fail
    EXPECT ax, 2
    mov cl, 4
    mov ax, 0x1234
    rol ax, cl
    EXPECT ax, 0x2341
    mov al, 0x81
    sar al, 1
    EXPECT al, 0xC0
    stc
    mov al, 0
    rcl al, 1
    EXPECT al, 1
    mov bx, 0x00F0
    shr bx, 4
    EXPECT bx, 0x000F
    STEP 'd'                        ; strings: rep movsb, stosw, cmpsb, scasb, lods
    push ds
    pop es
    cld
    mov si, src
    mov di, dst
    mov cx, 6
    rep movsb
    mov si, src
    mov di, dst
    mov cx, 6
    repe cmpsb
    jne fail
    EXPECT cx, 0
    mov di, dst
    mov al, 'r'
    mov cx, 6
    repne scasb
    jne fail
    EXPECT di, dst+4                ; just past the match
    mov di, words
    mov ax, 0xBEEF
    mov cx, 3
    rep stosw
    EXPECT word [words+4], 0xBEEF
    mov si, words+2
    lodsw
    EXPECT ax, 0xBEEF
    EXPECT si, words+4
    std
    mov si, src+5
    lodsb
    cld
    EXPECT al, 's'
    EXPECT si, src+4
    STEP 'e'                        ; xlat, xchg, cbw, lea, les/lds, overrides
    mov bx, hexdig
    mov al, 11
    xlatb
    EXPECT al, 'B'
    mov ax, 1
    mov dx, 2
    xchg ax, dx
    EXPECT ax, 2
    mov al, 0x90
    cbw
    EXPECT ax, 0xFF90
    mov bx, 0x100
    mov si, 0x23
    lea di, [bx+si+0x11]
    EXPECT di, 0x134
    les di, [farptr]
    mov ax, es
    EXPECT ax, 0x1234
    EXPECT di, 0x5678
    push ds
    pop es
    mov word [es:words], 0x4321
    EXPECT word [words], 0x4321
    STEP 'f'                        ; BCD
    mov al, 0x19
    add al, 0x28
    daa
    EXPECT al, 0x47
    mov al, 0x47
    sub al, 0x19
    das
    EXPECT al, 0x28
    mov ax, 0x0009
    add al, 5
    aaa
    EXPECT ax, 0x0104
    mov al, 79
    aam
    EXPECT ax, 0x0709
    aad
    EXPECT ax, 79
    STEP 'g'                        ; loops, calls, the stack, flags
    xor ax, ax
    mov cx, 10
.l:
    add ax, cx
    loop .l
    EXPECT ax, 55
    call near_fn
    EXPECT ax, 0x1111
    push cs
    call far_fn                     ; far call within the segment
    EXPECT ax, 0x2222
    stc
    pushf
    clc
    popf
    jnc fail
    mov ah, 0xC1                    ; SF ZF CF
    sahf
    jnz fail
    lahf
    and ah, 0xC1
    EXPECT ah, 0xC1
    STEP 'h'                        ; 80186: pusha/popa, push imm, imul imm, enter/leave, shl imm
    mov ax, 1
    mov bx, 2
    pusha
    xor ax, ax
    xor bx, bx
    popa
    EXPECT ax, 1
    EXPECT bx, 2
    push 0x55AA
    pop dx
    EXPECT dx, 0x55AA
    mov cx, 12
    imul dx, cx, 7
    EXPECT dx, 84
    mov bp, 0x1234
    enter 4, 0
    mov word [bp-2], 9
    leave
    EXPECT bp, 0x1234
    mov ax, 3
    shl ax, 5
    EXPECT ax, 96
    STEP 'i'                        ; neg, not, inc/dec keep CF
    mov ax, 5
    neg ax
    jnc fail
    EXPECT ax, -5
    not ax
    EXPECT ax, 4
    stc
    inc ax
    jnc fail
    STEP 'j'                        ; a hooked interrupt and INT 21h 35h/25h
    mov ax, 0x2560
    mov dx, int60
    int 0x21
    mov ax, 0x3560
    int 0x21
    EXPECT bx, int60
    mov ax, 7
    int 0x60
    EXPECT ax, 8
    STEP 'k'                        ; divide error goes to the INT 0 handler
    mov ax, 0x2500
    mov dx, int00
    int 0x21
    xor bl, bl
    mov ax, 10
    div bl
    EXPECT byte [div_hit], 1
    mov ah, 0x09
    mov dx, pass
    int 0x21
    mov ax, 0x4C00
    int 0x21

fail:                               ; FAIL x, then AX and DX in hex
    push dx
    push ax
    mov ah, 0x09
    mov dx, failmsg
    int 0x21
    pop ax
    call hex
    pop ax
    call hex
    mov ax, 0x4C01
    int 0x21
hex:                                ; AX as four digits and a space
    mov cx, 4
.d:
    rol ax, 4
    push ax
    and al, 15
    add al, '0'
    cmp al, '9'
    jbe .p
    add al, 7
.p:
    mov dl, al
    mov ah, 0x02
    int 0x21
    pop ax
    loop .d
    mov dl, ' '
    mov ah, 0x02
    int 0x21
    ret

near_fn:
    mov ax, 0x1111
    ret
far_fn:
    mov ax, 0x2222
    retf
int60:
    inc ax
    iret
int00:                              ; skip the 2-byte div bl
    mov byte [cs:div_hit], 1
    push bp
    mov bp, sp
    add word [bp+2], 2
    pop bp
    iret

src db 'acorns'
dst times 6 db 0
words times 3 dw 0
hexdig db '0123456789ABCDEF'
farptr dw 0x5678, 0x1234
div_hit db 0
pass db 'doscpu: PASS', 13, 10, '$'
failmsg db 'doscpu: FAIL '
step db '?', ' $'
