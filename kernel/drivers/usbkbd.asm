; Squirrel-OS/2 — USB keyboard, H.5 (OS2-HW)
; Included from pm.asm (high image). Original code, written from the USB
; HID 1.11 specification (boot protocol, appendix B) and its usage tables.
;
; xhci.asm hands over a boot-protocol keyboard. We configure it, switch it
; to the boot report format (8 bytes: modifiers, reserved, six key usages)
; and keep one 8-byte interrupt IN transfer queued. Each report is
; compared with the one before and turned into PC set-1 make and break
; codes, which go into the same scan-code queue the 8042 interrupt fills
; (kbd_ring) and through key_event. So the shell, `kbd`, SYS_GETC and
; SYS_KEYEVENTS cannot tell the two keyboards apart.
; No typematic repeat yet: holding a key gives one make code.
; See documentation/kernel/hardware.md.

; ebx = device record (xhci.asm) -> CF if it could not be set up
usbkbd_attach:
    call xhci_configure
    jc .r
    mov eax, 0x00000B21             ; SET_PROTOCOL(boot), class, interface
    mov edx, [ebx+XD_IFACE]
    call xhci_control
    mov eax, 0x00000A21             ; SET_IDLE(0): report only on change
    mov edx, [ebx+XD_IFACE]
    call xhci_control               ; (optional for the device: errors ignored)
    mov [usbkbd_dev], ebx
    call usbkbd_queue
    clc
.r:
    ret

; Queues the next 8-byte report transfer (ebx = keyboard device)
usbkbd_queue:
    pushad
    lea ebp, [ebx+XD_EPA]
    mov eax, [ebx+XD_DATA]
    add eax, XDP_REPORT
    mov edx, 8
    mov ecx, TRB_NORMAL|TRB_IOC|TRB_ISP
    push ebx
    mov ebx, ebp
    call xhci_ring_put
    pop ebx
    mov esi, [xhci_db]
    mov eax, [ebx+XD_SLOT]
    mov ecx, [ebx+XD_DCIA]
    mov [esi+eax*4], ecx
    popad
    ret

; A transfer event for the keyboard's endpoint (from xhci_event, with
; interrupts off): esi = event TRB, ebx = device.
usbkbd_event:
    mov eax, [esi+8]
    shr eax, 24
    cmp eax, CC_SUCCESS
    je .ok
    cmp eax, CC_SHORT
    jne .r                          ; an error halts the endpoint: stop here
.ok:
    pushad
    mov esi, [ebx+XD_DATA]
    add esi, XDP_REPORT
    call usbkbd_report
    popad
    call usbkbd_queue
.r:
    ret

; esi = new 8-byte boot report: emits the changes against usbkbd_prev
usbkbd_report:
    ; a report with 01h in the key slots is "too many keys": ignore it
    cmp byte [esi+2], 1
    je .r
    ; modifiers
    movzx eax, byte [esi]
    movzx edx, byte [usbkbd_prev]
    xor eax, edx                    ; changed modifier bits
    xor ecx, ecx
.mod:
    bt eax, ecx
    jnc .modnext
    movzx edx, word [usbkbd_modcodes+ecx*2]
    xor ebp, ebp                    ; make
    bt [esi], ecx
    jc .modemit
    inc ebp                         ; break
.modemit:
    push eax
    call usbkbd_emit
    pop eax
.modnext:
    inc ecx
    cmp ecx, 8
    jb .mod
    ; released keys: in the old report, not in the new one
    mov edi, usbkbd_prev
    mov ebp, 1
    call .diff
    ; pressed keys: in the new report, not in the old one
    mov edi, esi
    push esi
    mov esi, usbkbd_prev
    xor ebp, ebp
    call .diff
    pop esi
    ; remember this report
    mov eax, [esi]
    mov [usbkbd_prev], eax
    mov eax, [esi+4]
    mov [usbkbd_prev+4], eax
.r:
    ret
; edi = report whose keys are checked, esi = the other report,
; ebp = 1 for breaks or 0 for makes
.diff:
    mov ecx, 2
.k:
    movzx eax, byte [edi+ecx]
    cmp eax, 4
    jb .knext
    cmp eax, USBKBD_LAST
    ja .knext
    mov edx, 2
.find:
    cmp al, [esi+edx]
    je .knext                       ; in both: no change
    inc edx
    cmp edx, 8
    jb .find
    movzx edx, word [usbkbd_codes+(eax-4)*2]
    test edx, edx
    jz .knext
    call usbkbd_emit
.knext:
    inc ecx
    cmp ecx, 8
    jb .k
    ret

; edx = set-1 code (0xE0xx for the extended ones), ebp = 1 for a break
usbkbd_emit:
    pushad
    cmp dh, 0xE0
    jne .one
    mov al, 0xE0
    call usbkbd_push
.one:
    mov al, dl
    test ebp, ebp
    jz .p
    or al, 0x80
.p:
    call usbkbd_push
    popad
    ret

; al = scan code: into kbd_ring and to key_event, as kbd_isr does
usbkbd_push:
    pushad
    mov ebx, [kbd_head]
    lea ecx, [ebx+1]
    and ecx, KBD_RING_SIZE-1
    cmp ecx, [kbd_tail]
    je .full
    mov [kbd_ring+ebx], al
    mov [kbd_head], ecx
.full:
    call key_event
    popad
    ret

; modifier bits 0-7: left Ctrl, Shift, Alt, GUI, right Ctrl, Shift, Alt, GUI
usbkbd_modcodes dw 0x1D, 0x2A, 0x38, 0xE05B, 0xE01D, 0x36, 0xE038, 0xE05C
; HID keyboard usages 04h (a) to 65h (Application) -> set-1 codes; 0 = none
USBKBD_LAST equ 0x65
usbkbd_codes:
    dw 0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23    ; a-h
    dw 0x17, 0x24, 0x25, 0x26, 0x32, 0x31, 0x18, 0x19    ; i-p
    dw 0x10, 0x13, 0x1F, 0x14, 0x16, 0x2F, 0x11, 0x2D    ; q-x
    dw 0x15, 0x2C                                        ; y z
    dw 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09    ; 1-8
    dw 0x0A, 0x0B                                        ; 9 0
    dw 0x1C, 0x01, 0x0E, 0x0F, 0x39                      ; Enter Esc Backspace Tab Space
    dw 0x0C, 0x0D, 0x1A, 0x1B, 0x2B, 0x2B, 0x27, 0x28    ; - = [ ] \ #(non-US) ; '
    dw 0x29, 0x33, 0x34, 0x35, 0x3A                      ; ` , . / CapsLock
    dw 0x3B, 0x3C, 0x3D, 0x3E, 0x3F, 0x40, 0x41, 0x42    ; F1-F8
    dw 0x43, 0x44, 0x57, 0x58                            ; F9-F12
    dw 0xE037, 0x46, 0                                   ; PrintScreen ScrollLock Pause
    dw 0xE052, 0xE047, 0xE049, 0xE053, 0xE04F, 0xE051    ; Insert Home PgUp Delete End PgDn
    dw 0xE04D, 0xE04B, 0xE050, 0xE048                    ; Right Left Down Up
    dw 0x45, 0xE035, 0x37, 0x4A, 0x4E, 0xE01C            ; NumLock KP/ KP* KP- KP+ KPEnter
    dw 0x4F, 0x50, 0x51, 0x4B, 0x4C, 0x4D, 0x47, 0x48    ; KP1-KP8
    dw 0x49, 0x52, 0x53                                  ; KP9 KP0 KP.
    dw 0x56, 0xE05D                                      ; \|(non-US) Application
%if ($-usbkbd_codes)/2 != USBKBD_LAST-3
%error usbkbd_codes must cover usages 04h to USBKBD_LAST
%endif

align 4
usbkbd_dev dd 0
usbkbd_prev times 8 db 0
