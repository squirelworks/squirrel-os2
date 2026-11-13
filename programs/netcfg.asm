; netcfg — network settings (3.0, OS2-NET-AUDIO)
; Original code.
;   run netcfg              the settings in a window
;   run netcfg show         print them
;   run netcfg dhcp         ask a DHCP server, then print them
;   run netcfg set <ip> <mask> <gw> <dns>   set them by hand
;   run netcfg save         write network.cfg ("dhcp", or "static ip mask gw dns")
;   run netcfg load         apply network.cfg (put it in autoexec.bat)
; In the window: Up/Down or Tab pick a field, digits and dots edit it,
; Backspace deletes, Enter applies, F2 asks DHCP, F3 saves network.cfg,
; Esc closes. The buttons can be clicked too.
; See documentation/apps/network.md.
%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"
%include "net.inc"

NFIELDS     equ 4                   ; address, mask, gateway, DNS
K_F3        equ 0x3D
FLEN        equ 15                  ; "255.255.255.255"
WIN_W       equ 232
WIN_H       equ 150
WIN_X       equ (SCR_W - WIN_W) / 2
WIN_Y       equ (SCR_H - WIN_H) / 2
LAB_X       equ WIN_X + 8
VAL_X       equ WIN_X + 80
ROW0_Y      equ WIN_Y + WIN_TITLE_H + 8
ROW_H       equ 13
FIELD_Y     equ ROW0_Y + 2 * ROW_H      ; the first edit field's row
FIELD_W     equ FLEN * CELL_W + 4
BTN_Y       equ WIN_Y + WIN_H - 34
BTN_W       equ 64
BTN_H       equ 14
STATUS_Y    equ WIN_Y + WIN_H - 14

main:
    mov esi, [esp+4]
.sp:
    cmp byte [esi], ' '
    jne .w
    inc esi
    jmp .sp
.w:
    mov [arg], esi
    cmp byte [esi], 0
    je window
    mov edi, w_show
    call word_is
    je cmd_show
    mov edi, w_dhcp
    call word_is
    je cmd_dhcp
    mov edi, w_set
    call word_is
    je cmd_set
    mov edi, w_save
    call word_is
    je cmd_save
    mov edi, w_load
    call word_is
    je cmd_load
    mov ebx, m_usage
    jmp fail

; esi = text, edi = word -> ZF if the text starts with the word and a
; space or the end follows; esi then points past them
word_is:
    push esi
.l:
    mov al, [edi]
    test al, al
    jz .end
    cmp al, [esi]
    jne .no
    inc esi
    inc edi
    jmp .l
.end:
    mov al, [esi]
    test al, al
    jz .yes
    cmp al, ' '
    jne .no
.s:
    cmp byte [esi], ' '
    jne .yes
    inc esi
    jmp .s
.yes:
    add esp, 4                      ; keep the moved esi
    xor eax, eax                    ; ZF
    ret
.no:
    pop esi
    or eax, 1                       ; NZ
    ret

fail:
    mov eax, SYS_PUTS
    int 0x80
    mov eax, 1
    ret

info:
    mov eax, SYS_NET
    mov ebx, NET_INFO
    mov ecx, ni
    int 0x80
    ret

; ---------- text commands ----------

cmd_dhcp:
    mov eax, SYS_NET
    mov ebx, NET_DHCP
    int 0x80
    test eax, eax
    jz cmd_show
    mov ebx, m_nodhcp
    jmp fail

cmd_show:
    call info
    mov edi, line
    mov esi, m_card
    call cat
    test byte [ni + NI_FLAGS], 1
    jnz .mac
    mov esi, m_none
    call cat
    jmp .meth
.mac:
    mov esi, ni + NI_MAC
    call put_mac
.meth:
    mov esi, m_nl_method
    call cat
    mov esi, m_manual
    test byte [ni + NI_FLAGS], 2
    jz .m
    mov esi, m_dhcp
.m:
    call cat
    mov esi, m_nl_addr
    call cat
    mov eax, [ni + NI_IP]
    call net_ntoa
    mov esi, m_nl_mask
    call cat
    mov eax, [ni + NI_MASK]
    call net_ntoa
    mov esi, m_nl_gw
    call cat
    mov eax, [ni + NI_GW]
    call net_ntoa
    mov esi, m_nl_dns
    call cat
    mov eax, [ni + NI_DNS]
    call net_ntoa
    movzx eax, word [ni + NI_DNSPORT]
    cmp eax, 53
    je .nl
    mov byte [edi], ':'
    inc edi
    call net_utoa
.nl:
    mov word [edi], 10
    mov eax, SYS_PUTS
    mov ebx, line
    int 0x80
    xor eax, eax
    ret

; esi = six bytes -> aa:bb:cc:dd:ee:ff at edi
put_mac:
    mov ecx, 6
.b:
    lodsb
    mov ah, al
    shr al, 4
    call hexd
    mov al, ah
    and al, 15
    call hexd
    dec ecx
    jz .r
    mov byte [edi], ':'
    inc edi
    jmp .b
.r:
    mov byte [edi], 0
    ret
hexd:
    add al, '0'
    cmp al, '9'
    jbe .s
    add al, 'a' - '0' - 10
.s:
    mov [edi], al
    inc edi
    ret

; set <ip> <mask> <gw> <dns>
cmd_set:
    mov edi, nset
    mov ecx, 4
.f:
    call net_aton
    jc .bad
    stosd
.s:
    cmp byte [esi], ' '
    jne .n
    inc esi
    jmp .s
.n:
    loop .f
    cmp byte [esi], 0
    jne .bad
    mov word [nset + 16], 0
    call apply_set
    jc .refused
    jmp cmd_show
.bad:
    mov ebx, m_bad
    jmp fail
.refused:
    mov ebx, m_offnet
    jmp fail

; nset -> the kernel. CF if refused.
apply_set:
    mov eax, SYS_NET
    mov ebx, NET_SET
    mov ecx, nset
    int 0x80
    test eax, eax
    jz .ok
    stc
    ret
.ok:
    clc
    ret

cmd_save:
    call info
    call save_cfg
    jc .no
    mov ebx, m_saved
    mov eax, SYS_PUTS
    int 0x80
    xor eax, eax
    ret
.no:
    mov ebx, m_nosave
    jmp fail

; the current settings -> network.cfg. CF if it cannot be written.
save_cfg:
    mov edi, line
    test byte [ni + NI_FLAGS], 2
    jz .static
    mov esi, w_dhcp
    call cat
    jmp .write
.static:
    mov esi, w_static
    call cat
    mov byte [edi], ' '
    inc edi
    mov eax, [ni + NI_IP]
    call net_ntoa
    mov byte [edi], ' '
    inc edi
    mov eax, [ni + NI_MASK]
    call net_ntoa
    mov byte [edi], ' '
    inc edi
    mov eax, [ni + NI_GW]
    call net_ntoa
    mov byte [edi], ' '
    inc edi
    mov eax, [ni + NI_DNS]
    call net_ntoa
.write:
    mov byte [edi], 10
    inc edi
    sub edi, line
    mov [len], edi
    mov eax, SYS_OPEN
    mov ebx, cfg_name
    mov ecx, O_CREATE | O_TRUNC
    int 0x80
    cmp eax, -1
    je .no
    mov [fd], eax
    mov eax, SYS_WRITE
    mov ebx, [fd]
    mov ecx, line
    mov edx, [len]
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    mov ebx, [fd]
    int 0x80
    pop eax
    cmp eax, [len]
    jne .no
    clc
    ret
.no:
    stc
    ret

cmd_load:
    mov eax, SYS_OPEN
    mov ebx, cfg_name
    xor ecx, ecx
    int 0x80
    cmp eax, -1
    je .none
    mov [fd], eax
    mov eax, SYS_READ
    mov ebx, [fd]
    mov ecx, line
    mov edx, 100
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    mov ebx, [fd]
    int 0x80
    pop eax
    test eax, eax
    jle .bad
    mov byte [line + eax], 0
    mov esi, line
    mov edi, w_dhcp
    call word_is_line
    je cmd_dhcp
    mov edi, w_static
    call word_is
    jne .bad
    mov edi, nset
    mov ecx, 4
.f:
    call net_aton
    jc .bad
    stosd
.s:
    cmp byte [esi], ' '
    jne .n
    inc esi
    jmp .s
.n:
    loop .f
    mov word [nset + 16], 0
    call apply_set
    jc .bad
    jmp cmd_show
.none:
    mov ebx, m_nocfg
    jmp fail
.bad:
    mov ebx, m_badcfg
    jmp fail

; as word_is, but the word may also end at a line break
word_is_line:
    push esi
.l:
    mov al, [edi]
    test al, al
    jz .end
    cmp al, [esi]
    jne .no
    inc esi
    inc edi
    jmp .l
.end:
    mov al, [esi]
    cmp al, ' '
    ja .no
    add esp, 4
    xor eax, eax
    ret
.no:
    pop esi
    or eax, 1
    ret

; esi = ASCIIZ -> copied to edi, edi at the copy's end (no zero written)
cat:
    lodsb
    test al, al
    jz .r
    stosb
    jmp cat
.r:
    mov byte [edi], 0
    ret

; ---------- the window ----------

window:
    call gui_open
    jc .nogfx
    call load_fields
    mov dword [status], m_s_ready
.draw:
    call draw
.ev:
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .click
    cmp eax, EV_DRAG
    je .ev
    mov edx, eax
    shr edx, 8
    and edx, 0xFF                   ; scancode
    cmp dl, K_ESC
    je .quit
    cmp dl, K_UP
    je .up
    cmp dl, K_DOWN
    je .down
    cmp dl, K_TAB
    je .down
    cmp dl, K_ENTER
    je .apply
    cmp dl, K_F2
    je .dhcp
    cmp dl, K_F3
    je .save
    cmp dl, K_BKSP
    je .bksp
    cmp al, '.'
    je .type
    cmp al, '0'
    jb .ev
    cmp al, '9'
    ja .ev
.type:
    call field_ptr                  ; edi = the field, ecx = its length
    cmp ecx, FLEN
    jae .ev
    mov [edi + ecx], al
    mov byte [edi + ecx + 1], 0
    jmp .draw
.bksp:
    call field_ptr
    test ecx, ecx
    jz .ev
    mov byte [edi + ecx - 1], 0
    jmp .draw
.up:
    dec dword [cur]
    jns .draw
    mov dword [cur], NFIELDS - 1
    jmp .draw
.down:
    inc dword [cur]
    cmp dword [cur], NFIELDS
    jb .draw
    mov dword [cur], 0
    jmp .draw
.apply:
    call apply_fields
    jmp .draw
.dhcp:
    mov dword [status], m_s_asking
    call draw
    mov eax, SYS_NET
    mov ebx, NET_DHCP
    int 0x80
    mov dword [status], m_s_bound
    test eax, eax
    jz .reload
    mov dword [status], m_s_nodhcp
.reload:
    call load_fields
    jmp .draw
.save:
    call info
    call save_cfg
    mov dword [status], m_s_saved
    jnc .draw
    mov dword [status], m_s_nosave
    jmp .draw
.click:
    mov eax, [gui_mx]
    mov ebx, [gui_my]
    cmp ebx, BTN_Y
    jb .fieldclick
    cmp ebx, BTN_Y + BTN_H
    jae .ev
    mov ecx, eax
    sub ecx, WIN_X + 8
    js .ev
    xor edx, edx
    mov eax, ecx
    mov ecx, BTN_W + 8
    div ecx
    cmp edx, BTN_W
    jae .ev
    cmp eax, 0
    je .dhcp
    cmp eax, 1
    je .apply
    cmp eax, 2
    je .save
    jmp .ev
.fieldclick:
    sub ebx, FIELD_Y
    js .ev
    mov eax, ebx
    xor edx, edx
    mov ecx, ROW_H
    div ecx
    cmp eax, NFIELDS
    jae .ev
    mov [cur], eax
    jmp .draw
.quit:
    call gui_close
    xor eax, eax
    ret
.nogfx:
    mov ebx, m_nogfx
    jmp fail

; -> edi = the current field's text, ecx = its length
field_ptr:
    mov edi, [cur]
    imul edi, FLEN + 1
    add edi, fields
    xor ecx, ecx
.l:
    cmp byte [edi + ecx], 0
    je .r
    inc ecx
    jmp .l
.r:
    ret

; the kernel's settings -> the four fields
load_fields:
    pushad
    call info
    mov esi, ni
    mov ebx, fields
    mov ecx, NFIELDS
.f:
    lodsd
    mov edi, ebx
    call net_ntoa
    add ebx, FLEN + 1
    loop .f
    popad
    ret

; the four fields -> the kernel, with a word in the status line
apply_fields:
    mov esi, fields
    mov edi, nset
    mov ecx, NFIELDS
.f:
    push esi
    call net_aton
    jc .bad
    cmp byte [esi], 0
    jne .bad
    pop esi
    stosd
    add esi, FLEN + 1
    loop .f
    mov word [nset + 16], 0
    call apply_set
    mov dword [status], m_s_offnet
    jc .r
    mov dword [status], m_s_applied
    call load_fields
.r:
    ret
.bad:
    pop esi
    mov dword [status], m_s_bad
    ret

draw:
    pushad
    call info
    mov al, C_CYAN
    call gui_clear
    mov eax, WIN_X
    mov ebx, WIN_Y
    mov ecx, WIN_W
    mov edx, WIN_H
    mov esi, t_title
    call gui_window
    ; Card
    mov eax, LAB_X
    mov ebx, ROW0_Y
    mov esi, l_card
    call gui_text
    mov edi, line
    test byte [ni + NI_FLAGS], 1
    jnz .mac
    mov esi, m_none
    call cat
    jmp .card
.mac:
    mov esi, ni + NI_MAC
    call put_mac
.card:
    mov eax, VAL_X
    mov esi, line
    call gui_text
    ; Method (and the lease)
    mov eax, LAB_X
    add ebx, ROW_H
    mov esi, l_method
    call gui_text
    mov edi, line
    mov esi, m_manual
    test byte [ni + NI_FLAGS], 2
    jz .meth
    mov esi, m_dhcp
    call cat
    mov esi, m_lease
    call cat
    mov eax, [ni + NI_FLAGS]
    shr eax, 16
    call net_utoa
    mov esi, m_min
.meth:
    call cat
    mov eax, VAL_X
    mov esi, line
    call gui_text
    ; the fields
    xor ebp, ebp
    mov ebx, FIELD_Y
.row:
    mov eax, LAB_X
    mov esi, [labels + ebp * 4]
    call gui_text
    mov eax, VAL_X - 2
    push ebx
    sub ebx, 2
    mov ecx, FIELD_W
    mov edx, CELL_H + 3
    mov byte [gui_ink], C_WHITE
    cmp ebp, [cur]
    jne .bg
    mov byte [gui_ink], C_YELLOW
.bg:
    mov cl, [gui_ink]
    mov [gui_bg], cl
    mov ecx, FIELD_W
    call gui_fill
    mov byte [gui_bevel_up], 0
    call gui_bevel
    pop ebx
    mov byte [gui_ink], C_BLACK
    mov eax, VAL_X
    mov esi, ebp
    imul esi, FLEN + 1
    add esi, fields
    call gui_text
    mov byte [gui_bg], C_LGREY
    add ebx, ROW_H
    inc ebp
    cmp ebp, NFIELDS
    jb .row
    ; the buttons
    mov byte [gui_bevel_up], 1
    mov eax, WIN_X + 8
    mov ebx, BTN_Y
    mov ecx, BTN_W
    mov edx, BTN_H
    mov esi, b_dhcp
    call gui_button
    add eax, BTN_W + 8
    mov esi, b_apply
    call gui_button
    add eax, BTN_W + 8
    mov esi, b_save
    call gui_button
    ; the status line
    mov byte [gui_ink], C_BLACK
    mov eax, LAB_X
    mov ebx, STATUS_Y
    mov esi, [status]
    call gui_text
    call gui_flip
    popad
    ret

t_title     db 'Network Settings', 0
l_card      db 'Card', 0
l_method    db 'Method', 0
l_addr      db 'Address', 0
l_mask      db 'Mask', 0
l_gw        db 'Gateway', 0
l_dns       db 'DNS server', 0
align 4
labels      dd l_addr, l_mask, l_gw, l_dns
b_dhcp      db 'DHCP F2', 0
b_apply     db 'Apply', 0
b_save      db 'Save F3', 0
m_s_ready   db 'Enter applies, Esc closes', 0
m_s_asking  db 'Asking for an address...', 0
m_s_bound   db 'DHCP: bound', 0
m_s_nodhcp  db 'No DHCP server answered', 0
m_s_applied db 'Applied', 0
m_s_bad     db 'Bad address', 0
m_s_offnet  db 'Gateway is not on that subnet', 0
m_s_saved   db 'Saved network.cfg', 0
m_s_nosave  db 'Cannot write network.cfg', 0
m_lease     db ', lease ', 0
m_min       db ' min', 0
w_show      db 'show', 0
w_dhcp      db 'dhcp', 0
w_set       db 'set', 0
w_save      db 'save', 0
w_load      db 'load', 0
w_static    db 'static', 0
cfg_name    db 'network.cfg', 0
m_card      db 'card    ', 0
m_none      db 'none', 0
m_nl_method db 10, 'method  ', 0
m_manual    db 'manual', 0
m_dhcp      db 'dhcp', 0
m_nl_addr   db 10, 'address ', 0
m_nl_mask   db 10, 'mask    ', 0
m_nl_gw     db 10, 'gateway ', 0
m_nl_dns    db 10, 'dns     ', 0
m_usage     db 'Usage: run netcfg [show|dhcp|save|load|set <ip> <mask> <gw> <dns>]', 10, 0
m_nodhcp    db 'netcfg: no DHCP server answered', 10, 0
m_bad       db 'netcfg: bad address', 10, 0
m_offnet    db 'netcfg: the gateway is not on that subnet', 10, 0
m_saved     db 'netcfg: saved network.cfg', 10, 0
m_nosave    db 'netcfg: cannot write network.cfg', 10, 0
m_nocfg     db 'netcfg: no network.cfg', 10, 0
m_badcfg    db 'netcfg: network.cfg is not understood', 10, 0
m_nogfx     db 'netcfg: no graphics', 10, 0

SQX_BSS
arg         resd 1
fd          resd 1
len         resd 1
cur         resd 1
status      resd 1
ni          resb NI_SIZE
nset        resb 20
fields      resb NFIELDS * (FLEN + 1)
line        resb 128
GUI_BSS
SQX_END
