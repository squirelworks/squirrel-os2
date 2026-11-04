; Squirrel-OS/2 — PS/2 mouse (1.9.10 polled, 2.0.1 on IRQ 12)
; Included from pm.asm. Original code.
;
; Enables the auxiliary device and builds 3-byte packets from its bytes.
; Since 2.0.1 the bytes arrive on IRQ 12 (mouse_isr), and an auxiliary
; byte that turns up on IRQ 1 is handed here too, so mouse data never
; sits in the controller and blocks the keyboard. Soft cursor coordinates
; are kept in mouse_x / mouse_y for the desktop.
; See documentation/kernel/mouse.md.

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
    ; Compaq status: enable IRQ12 and the aux clock
    call mouse_wait_in
    mov al, 0x20
    out 0x64, al
    call mouse_wait_out
    in al, 0x60
    or al, 2                     ; aux bytes raise IRQ 12 (2.0.1)
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

; Pull pending aux bytes into packets (fallback for when IRQ 12 has not
; run yet; with the interrupt on there is normally nothing left here).
mouse_poll:
    cmp byte [mouse_up], 0
    je .r
    pushfd
    cli                         ; the ISRs share the packet state
.more:
    in al, 0x64
    test al, 1
    jz .done
    test al, 0x20
    jz .done                    ; keyboard data: leave for kbd_isr
    in al, 0x60
    call mouse_byte
    jmp .more
.done:
    popfd
.r:
    ret

; IRQ 12 (vector 0x2C): one auxiliary byte from the controller.
mouse_isr:
    pushad
    in al, 0x64
    test al, 1
    jz .eoi                     ; nothing there (already read by a poll)
    in al, 0x60
    test byte [mouse_up], 1
    jz .eoi
    call mouse_byte
.eoi:
    inc dword [mouse_irqs]
    mov al, 0x20
    out 0xA0, al                ; slave PIC
    out 0x20, al                ; master PIC (cascade)
    popad
    iretd

; al = one byte from the auxiliary device. Builds packets and updates
; position and buttons. Call with interrupts disabled. Keeps all registers.
mouse_byte:
    pushad
    movzx ebx, byte [mouse_pkt_n]
    mov [mouse_pkt+ebx], al
    inc ebx
    mov [mouse_pkt_n], bl
    cmp bl, 1
    jne .chkfull
    test al, 0x08                ; first byte always has bit 3 set
    jnz .r
    mov byte [mouse_pkt_n], 0   ; resync
    jmp .r
.chkfull:
    cmp bl, 3
    jb .r
    mov byte [mouse_pkt_n], 0
    mov esi, mouse_pkt
    call mouse_decode           ; eax = dx, ebx = screen dy (2.0.1)
    jc .btns                    ; overflowed: buttons only
    add [mouse_x], eax
    add [mouse_y], ebx
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
    jz .r
    test bl, 1
    jnz .r
    inc dword [mouse_clicks]
.r:
    popad
    ret

; esi -> 3-byte packet. -> eax = dx, ebx = dy in screen terms (down is
; positive), CF set if either overflow bit is set (the motion is then
; meaningless and is dropped). PS/2 sends 9-bit motion: the 9th (sign)
; bits are bit 4 (X) and bit 5 (Y) of byte 0, so a byte of 0x90 with no
; Y sign is +144, not -112 (2.0.1).
mouse_decode:
    movzx eax, byte [esi+1]
    test byte [esi], 0x10
    jz .xok
    sub eax, 0x100              ; X is negative
.xok:
    movzx ebx, byte [esi+2]
    test byte [esi], 0x20
    jz .yok
    sub ebx, 0x100              ; Y is negative
.yok:
    neg ebx                     ; PS/2 Y is opposite to screen Y
    test byte [esi], 0xC0       ; X or Y overflow
    jnz .ovf
    clc
    ret
.ovf:
    stc
    ret

; Runs mouse_decode on fixed packets and prints decode: PASS or FAIL.
mouse_dectest:
    pushad
    mov byte [mdt_ok], 1
    mov esi, mdt_cases
.l:
    cmp byte [esi], 0
    je .done
    push esi
    call mouse_decode
    pop esi
    setc dl
    cmp dl, [esi+11]
    jne .bad
    test dl, dl
    jnz .next                   ; overflow: the motion is not looked at
    cmp eax, [esi+3]
    jne .bad
    cmp ebx, [esi+7]
    je .next
.bad:
    mov byte [mdt_ok], 0
.next:
    add esi, MDT_SIZE
    jmp .l
.done:
    mov esi, mt_dec_pass
    cmp byte [mdt_ok], 1
    je .say
    mov esi, mt_dec_fail
.say:
    call puts_nl_local
    popad
    ret

; byte0, byte1, byte2, dd dx, dd screen dy, db overflow
MDT_SIZE equ 12
mdt_cases:
    db 0x08, 5, 3
    dd 5, -3
    db 0
    db 0x18, 0xFB, 0            ; left 5
    dd -5, 0
    db 0
    db 0x18, 0x10, 0            ; left 240: needs the 9th bit
    dd -240, 0
    db 0
    db 0x28, 0, 0xF0            ; PS/2 down 16: screen +16
    dd 0, 16
    db 0
    db 0x08, 0, 0x90            ; PS/2 up 144: screen -144 (not +112)
    dd 0, -144
    db 0
    db 0x38, 0x80, 0x80         ; both negative, -128 each
    dd -128, 128
    db 0
    db 0x48, 0x20, 0            ; X overflow: dropped
    dd 0, 0
    db 1
    db 0x88, 0, 0x20            ; Y overflow: dropped
    dd 0, 0
    db 1
    db 0                        ; end (bit 3 is always set in a real byte 0)
mdt_ok db 0
mt_dec_pass db 'decode: PASS', 0
mt_dec_fail db 'decode: FAIL', 0

; Shell: mousetest — first checks packet decoding (2.0.1), then waits up
; to two seconds for motion or a click.
; It does not poll (2.0.1): only IRQ 12 can move the cursor here, so a
; PASS means the interrupt path works.
cmd_mousetest_run:
    call mouse_dectest
    cmp byte [mouse_up], 0
    je .no
    mov eax, [mouse_x]
    mov [mt_x0], eax
    mov eax, [mouse_y]
    mov [mt_y0], eax
    mov eax, [mouse_clicks]
    mov [mt_c0], eax
    mov ebx, [ticks]
    add ebx, 200                ; two seconds
.wait:
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
mouse_irqs  dd 0              ; IRQ 12 count (2.0.1)
mt_x0       dd 0
mt_y0       dd 0
mt_c0       dd 0
mouse_up    db 0
mouse_btns  db 0
mouse_pkt_n db 0
mouse_pkt   times 3 db 0
