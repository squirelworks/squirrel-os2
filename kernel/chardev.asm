; Squirrel-OS/2 — console and keyboard as devices (0.7.1)
; Included from pm.asm. Original code.
;
; The VGA text console and the keyboard keep their code in pm.asm (putc,
; the IRQ 1 ring buffer, the scancode maps); this file puts them behind
; the device interface of dev.asm as "con" (write only) and "kbd" (read
; only). SYS_PUTS and SYS_GETC go through these devices.
; See documentation/kernel/drivers.md.

align 4
dev_con:
    db 'con', 0, 0, 0, 0, 0
    dd DEV_CHAR, dev_probe_yes, dev_fail, con_write, 0, 0, 0, 0
dev_kbd:
    db 'kbd', 0, 0, 0, 0, 0
    dd DEV_CHAR, dev_probe_yes, kbd_read, dev_fail, 0, 0, 0, 0

; esi = text, ecx = count -> eax = count. Goes through putc, so output
; redirection and pipes see it as well.
con_write:
    push ecx
    push esi
    mov eax, ecx
    jecxz .r
.c:
    push eax
    lodsb
    call putc
    pop eax
    loop .c
.r:
    pop esi
    pop ecx
    ret

; edi = buffer, ecx = count -> eax = count. Waits for each key; stores
; ASCII (Enter 10, Backspace 8, Esc 27) and skips keys without one.
kbd_read:
    push ecx
    push edi
    mov eax, ecx
    jecxz .r
.c:
    push eax
    call kbd_getchar
    stosb
    pop eax
    loop .c
.r:
    pop edi
    pop ecx
    ret

; Waits for a key press -> eax = its ASCII code (see kbd_read)
kbd_getchar:
    call kbd_getscan
    call kbd_shift_track
    je kbd_getchar
    cmp al, 0x80
    jae kbd_getchar             ; releases
    cmp al, 0x01
    je .esc
    cmp al, 0x0E
    je .bs
    call kbd_ascii
    movzx eax, al
    test eax, eax
    jz kbd_getchar
    ret
.esc:
    mov eax, 27
    ret
.bs:
    mov eax, 8
    ret
