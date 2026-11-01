; keyev — checks key events in the message queue (1.2.1). Original code.
; run keyev, then press a key
; Asks for key events, then reads one key twice: as a message from its
; queue (MSG_KEY | ASCII) and with SYS_GETC. Both must be the same
; character.
%include "sqx.inc"
SQX_HEADER main

main:
    mov eax, SYS_KEYEVENTS
    mov ebx, 1
    int 0x80
    mov eax, SYS_PUTS
    mov ebx, m_ask
    int 0x80
    mov eax, SYS_RECV           ; the key, as an event
    int 0x80
    mov [event], eax
    mov eax, SYS_GETC           ; the same key, as before
    int 0x80
    mov [line_getc], al
    mov eax, SYS_KEYEVENTS
    xor ebx, ebx
    int 0x80
    mov eax, [event]
    mov [line_queue], al
    mov eax, SYS_PUTS
    mov ebx, m_line
    int 0x80
    mov eax, [event]
    mov ecx, eax
    and ecx, 0xFFFFFF00
    cmp ecx, MSG_KEY
    jne .fail
    cmp al, [line_getc]
    jne .fail
    mov ebx, m_pass
    jmp .print
.fail:
    mov ebx, m_fail
.print:
    mov eax, SYS_PUTS
    int 0x80
    xor eax, eax
    ret

m_ask db 'keyev: press a key', 10, 0
m_line db 'keyev: queue '
line_queue db '?', ' getc '
line_getc db '?', 10, 0
m_pass db 'keyev: PASS', 10, 0
m_fail db 'keyev: FAIL', 10, 0

SQX_BSS
event resd 1
SQX_END
