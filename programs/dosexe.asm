; dosexe — a DOS .EXE program, MZ written by hand (P.8). Original code.
; Three segments (code, data, stack) and two relocations: the program
; loads DS from a segment word the loader fixed up, far-calls a routine in
; a second code segment, and checks SS:SP came from the header.
;   run dosrun dosexe.exe   ->  Hello from an MZ .EXE! ... dosexe: PASS
; Build: nasm -f bin dosexe.asm -o dosexe.exe
BITS 16
CPU 8086

; paragraph of a label inside the image (the image starts after the header)
%define PARA(x) (((x) - image) >> 4)

hdr:
    dw 'MZ'
    dw (file_end - hdr) % 512       ; bytes in the last page
    dw (file_end - hdr + 511) / 512 ; pages
    dw 2                            ; relocations
    dw (image - hdr) / 16           ; header paragraphs
    dw 0x10, 0xFFFF                 ; min and max extra paragraphs
    dw PARA(stk)                    ; SS
    dw stk_top - stk                ; SP
    dw 0                            ; checksum
    dw main - code1                 ; IP
    dw PARA(code1)                  ; CS
    dw reltab - hdr                 ; relocation table
    dw 0                            ; overlay
reltab:
    dw fix_ds + 1 - code1, PARA(code1)      ; "mov ax, seg data"
    dw fix_far + 3 - code1, PARA(code1)     ; "call far code2:far_add"
    align 16, db 0
image:

code1:
main:
fix_ds:
    mov ax, PARA(data)
    mov ds, ax
    mov dx, hello - data
    mov ah, 0x09
    int 0x21
    ; SS from the header, relocated: one paragraph after CS's data
    mov ax, ss
    mov bx, ds
    sub ax, bx
    cmp ax, PARA(stk) - PARA(data)
    jne fail1
    cmp sp, stk_top - stk
    jne fail1
    ; a far call into the second code segment and back
    mov ax, 40
    mov bx, 2
fix_far:
    call PARA(code2):(far_add - code2)
    cmp ax, 42
    jne fail1
    ; ES = DS = PSP at entry: INT 20h at PSP:0
    mov ah, 0x62
    int 0x21
    mov es, bx
    cmp word [es:0], 0x20CD
    jne fail1
    mov dx, pass - data
    mov ah, 0x09
    int 0x21
    mov ax, 0x4C00
    int 0x21
fail1:
    mov dx, failmsg - data
    mov ah, 0x09
    int 0x21
    mov ax, 0x4C01
    int 0x21
    align 16, db 0

code2:
far_add:
    add ax, bx
    retf
    align 16, db 0

data:
hello   db 'Hello from an MZ .EXE!', 13, 10, '$'
pass    db 'dosexe: PASS', 13, 10, '$'
failmsg db 'dosexe: FAIL', 13, 10, '$'
    align 16, db 0

stk:
    times 256 db 0
stk_top:
file_end:
