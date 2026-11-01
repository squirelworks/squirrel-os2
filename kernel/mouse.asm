; Squirrel-OS/2 — polled PS/2 mouse (1.9.10)
; Included from pm.asm. Original code.
;
; Enables the auxiliary device and reads 3-byte packets by polling the
; keyboard controller (no IRQ12). Soft cursor coordinates are kept in
; mouse_x / mouse_y for the desktop. See documentation/kernel/mouse.md.

MOUSE_W     equ 320
MOUSE_H     equ 200

; Wait until the input buffer (bit 1 of 0x64) is clear.
mouse_wait_in:
    push ecx
    mov ecx, 100000
.w:
    in al, 0x64
    test al, 2
    jz .ok
    loop .w
.ok:
    pop ecx
    ret

; Wait until the output buffer (bit 0 of 0x64) has a byte.
mouse_wait_out:
    push ecx
    mov ecx, 100000
.w:
    in al, 0x64
    test al, 1
    jnz .ok
    loop .w
.ok:
    pop ecx
    ret

; al = command to the mouse (through 0xD4)
mouse_cmd:
    push eax
    call mouse_wait_in
    mov al, 0xD4
    out 0x64, al
    call mouse_wait_in
    pop eax
    out 0x60, al
    ret

; -> al = ACK byte (0xFA expected), CF if none
mouse_read_ack:
    call mouse_wait_out
    in al, 0x64
    test al, 1
    jz .no
    test al, 0x20                ; came from the aux device?
    jz .kbd
    in al, 0x60
    clc
    ret
.kbd:
    in al, 0x60                 ; drain a keyboard byte so we do not stick
.no:
    stc
    ret

mouse_init:
    mov byte [mouse_up], 0
    mov dword [mouse_x], MOUSE_W / 2
    mov dword [mouse_y], MOUSE_H / 2
    mov byte [mouse_btns], 0
    mov byte [mouse_pkt_n], 0
    mov dword [mouse_clicks], 0
    ; enable auxiliary device
    call mouse_wait_in
    mov al, 0xA8
    out 0x64, al
    ; Compaq status: enable IRQ12 and aux clock; we still poll
    call mouse_wait_in
    mov al, 0x20
    out 0x64, al
    call mouse_wait_out
    in al, 0x60
    or al, 2                     ; enable IRQ12 bit (harmless if masked)
    and al, 0xDF                 ; clear disable-aux
    mov bl, al
    call mouse_wait_in
    mov al, 0x60
    out 0x64, al
    call mouse_wait_in
    mov al, bl
    out 0x60, al
    ; defaults + enable streaming
    mov al, 0xF6
    call mouse_cmd
    call mouse_read_ack
    mov al, 0xF4
    call mouse_cmd
    call mouse_read_ack
    jc .r
    mov byte [mouse_up], 1
.r:
    ret

; Pull pending aux bytes into packets; update position and buttons.
mouse_poll:
    cmp byte [mouse_up], 0
    je .r
.more:
    in al, 0x64
    test al, 1
    jz .r
    test al, 0x20
    jz .r                       ; keyboard data: leave for kbd_isr
    in al, 0x60
    movzx ebx, byte [mouse_pkt_n]
    mov [mouse_pkt+ebx], al
    inc ebx
    mov [mouse_pkt_n], bl
    cmp bl, 1
    jne .chkfull
    test al, 0x08                ; first byte always has bit 3 set
    jnz .chkfull
    mov byte [mouse_pkt_n], 0   ; resync
    jmp .more
.chkfull:
    cmp bl, 3
    jb .more
    mov byte [mouse_pkt_n], 0
    ; dx / dy, with sign bits in byte 0
    movsx eax, byte [mouse_pkt+1]
    test byte [mouse_pkt], 0x10
    jz .xpos
    ; sign already in movsx from the byte; overflow bits ignored
.xpos:
    add [mouse_x], eax
    movsx eax, byte [mouse_pkt+2]
    test byte [mouse_pkt], 0x20
    jz .ypos
.ypos:
    neg eax                     ; PS/2 Y is opposite to screen Y
    add [mouse_y], eax
    ; clamp
    cmp dword [mouse_x], 0
    jge .xhi
    mov dword [mouse_x], 0
.xhi:
    cmp dword [mouse_x], MOUSE_W - 1
    jle .ylo
    mov dword [mouse_x], MOUSE_W - 1
.ylo:
    cmp dword [mouse_y], 0
    jge .yhi
    mov dword [mouse_y], 0
.yhi:
    cmp dword [mouse_y], MOUSE_H - 1
    jle .btns
    mov dword [mouse_y], MOUSE_H - 1
.btns:
    mov al, [mouse_pkt]
    and al, 7
    mov bl, [mouse_btns]
    mov [mouse_btns], al
    ; left button make edge
    test al, 1
    jz .more
    test bl, 1
    jnz .more
    inc dword [mouse_clicks]
    jmp .more
.r:
    ret

; Shell: mousetest — waits up to two seconds for motion or a click.
cmd_mousetest_run:
    cmp byte [mouse_up], 0
    je .no
    call mouse_poll
    mov eax, [mouse_x]
    mov [mt_x0], eax
    mov eax, [mouse_y]
    mov [mt_y0], eax
    mov eax, [mouse_clicks]
    mov [mt_c0], eax
    mov ebx, [ticks]
    add ebx, 200                ; two seconds
.wait:
    call mouse_poll
    mov eax, [mouse_x]
    cmp eax, [mt_x0]
    jne .pass
    mov eax, [mouse_y]
    cmp eax, [mt_y0]
    jne .pass
    mov eax, [mouse_clicks]
    cmp eax, [mt_c0]
    jne .pass
    call proc_idle
    cmp [ticks], ebx
    jb .wait
    mov esi, mt_fail
    jmp puts_nl_local
.pass:
    mov esi, mt_pass
    jmp puts_nl_local
.no:
    mov esi, mt_none
    jmp puts_nl_local

puts_nl_local:
    call puts
    mov al, 10
    jmp putc

mt_pass db 'mouse: PASS', 0
mt_fail db 'mouse: FAIL', 0
mt_none db 'mouse: none', 0

align 4
mouse_x     dd 0
mouse_y     dd 0
mouse_clicks dd 0
mt_x0       dd 0
mt_y0       dd 0
mt_c0       dd 0
mouse_up    db 0
mouse_btns  db 0
mouse_pkt_n db 0
mouse_pkt   times 3 db 0
