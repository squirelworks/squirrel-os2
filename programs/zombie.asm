; zombie — starts 12 short-lived threads in its own image and never
; waits for them, more than the 7 free process slots. Each spawn must
; still work (1.0.4: the oldest zombie gives way when the table is
; full); then one more is spawned and waited for. Original code.
; run zombie
%include "sqx.inc"
SQX_HEADER main

ROUNDS equ 12

main:
    mov dword [count], 0
.loop:
    mov eax, SYS_SPAWN
    mov ebx, child
    mov ecx, 0
    int 0x80
    test eax, eax
    js .full
    mov eax, SYS_YIELD          ; let it run and exit
    int 0x80
    inc dword [count]
    cmp dword [count], ROUNDS
    jb .loop
    ; one more, and this time wait for its exit code
    mov eax, SYS_SPAWN
    mov ebx, child
    mov ecx, 42
    int 0x80
    test eax, eax
    js .full
    mov ebx, eax
    mov eax, SYS_WAIT
    int 0x80
    cmp eax, 42
    jne .bad
    mov eax, SYS_PUTS
    mov ebx, m_ok
    int 0x80
    xor eax, eax
    ret
.full:
    mov eax, SYS_PUTS
    mov ebx, m_full
    int 0x80
    mov eax, 1
    ret
.bad:
    mov eax, SYS_PUTS
    mov ebx, m_bad
    int 0x80
    mov eax, 2
    ret

; child(arg): exits at once with arg as its code
child:
    mov eax, [esp+4]
    ret

m_ok db 'zombie: PASS', 10, 0
m_full db 'zombie: FAIL (process table full of zombies)', 10, 0
m_bad db 'zombie: FAIL (wrong exit code)', 10, 0

SQX_BSS
count resd 1
SQX_END
