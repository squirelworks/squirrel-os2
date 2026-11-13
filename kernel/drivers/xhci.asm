; Squirrel-OS/2 — xHCI USB host controller driver, H.5 (OS2-HW)
; Included from pm.asm (high image). Original code, written from the
; eXtensible Host Controller Interface 1.2 and USB 2.0/3.2 specifications.
;
; Finds the first xHCI controller (PCI class 0C/03/30), takes it from the
; firmware, resets it, and enumerates every device attached straight to a
; root-hub port (no external hubs yet). Two kinds of device get a driver:
;   - a boot-protocol keyboard (HID 3/1/1): usbkbd.asm turns its reports
;     into PC scan codes in the same queue the 8042 keyboard fills, so
;     `kbd`, the shell and every program see it as the keyboard;
;   - a bulk-only mass-storage device (8/6/50h): usbmsd.asm registers it
;     as the block device ud0.
; Everything is polled: the timer interrupt (hw_tick) drains the event
; ring, and the synchronous paths (commands, control and bulk transfers)
; poll it with interrupts off until their event arrives.
;
; DMA memory is whole pages from pg_alloc (identity-mapped, below 256 MB):
;   xhci_dcbaa   device context base address array; the event ring
;                segment table at +0x800
;   xhci_cmdring command ring, 255 TRBs and a link TRB
;   xhci_evring  event ring, 256 TRBs, one segment
; and for each device: output context, input context, data buffers,
; and one ring per endpoint (EP0 and up to two more).
; See documentation/kernel/hardware.md.

XHCI_CLASS      equ 0x0C0330
XHCI_MAP        equ 0x10000         ; capability, operational, runtime and doorbell registers
XHCI_MAXDEV     equ 4               ; devices we keep
XHCI_SLOTS      equ 8               ; slots we enable (CONFIG.MaxSlotsEn)
; capability registers
XC_CAPLEN       equ 0x00
XC_HCSP1        equ 0x04
XC_HCSP2        equ 0x08
XC_HCCP1        equ 0x10
XC_DBOFF        equ 0x14
XC_RTSOFF       equ 0x18
; operational registers (base + CAPLENGTH)
XO_USBCMD       equ 0x00
XO_USBSTS       equ 0x04
XO_CRCR         equ 0x18
XO_DCBAAP       equ 0x30
XO_CONFIG       equ 0x38
XO_PORTSC       equ 0x400           ; + 0x10 * (port - 1)
XCMD_RS         equ 1
XCMD_HCRST      equ 2
XSTS_HCH        equ 1
XSTS_CNR        equ 0x800
PSC_CCS         equ 1
PSC_PED         equ 2
PSC_PR          equ 0x10
PSC_PP          equ 0x200
PSC_RW1C        equ 0x00FE0002      ; PED and the change bits: written back as 0
PSC_PRC         equ 0x00200000
; interrupter 0 (runtime base + 0x20)
XI_IMAN         equ 0x20
XI_ERSTSZ       equ 0x28
XI_ERSTBA       equ 0x30
XI_ERDP         equ 0x38
; TRB types (control dword bits 15:10)
TRB_NORMAL      equ 1 << 10
TRB_SETUP       equ 2 << 10
TRB_DATA        equ 3 << 10
TRB_STATUS      equ 4 << 10
TRB_LINK        equ 6 << 10
TRB_ENSLOT      equ 9 << 10
TRB_ADDRDEV     equ 11 << 10
TRB_CONFEP      equ 12 << 10
TRB_EVALCTX     equ 13 << 10
TRB_RESETEP     equ 14 << 10
TRB_SETDEQ      equ 16 << 10
TRBT_XFER       equ 32
TRBT_CMD        equ 33
TRB_C           equ 1
TRB_TC          equ 2               ; link TRB: toggle cycle
TRB_ISP         equ 4
TRB_IOC         equ 0x20
TRB_IDT         equ 0x40
TRB_DIR_IN      equ 0x10000
CC_SUCCESS      equ 1
CC_SHORT        equ 13
; ring record
RG_BASE         equ 0
RG_ENQ          equ 4               ; index of the next TRB, 0..254
RG_CYC          equ 8
RG_SIZE         equ 12
RING_TRBS       equ 256             ; per page: 255 usable and a link TRB
; device record
XD_SLOT         equ 0
XD_PORT         equ 4
XD_SPEED        equ 8
XD_OUT          equ 12              ; output device context
XD_IN           equ 16              ; input context
XD_DATA         equ 20              ; data page
XD_MPS0         equ 24
XD_DONE         equ 28              ; set by xhci_event for a transfer event
XD_CODE         equ 32
XD_RESID        equ 36
XD_EVDCI        equ 40
XD_EP0          equ 44              ; ring record, DCI 1
XD_EPA          equ 56              ; ring record: interrupt IN or bulk IN
XD_EPB          equ 68              ; ring record: bulk OUT
XD_DCIA         equ 80
XD_DCIB         equ 84
XD_MPSA         equ 88
XD_MPSB         equ 92
XD_IFACE        equ 96
XD_CONFIG       equ 100
XD_SIZE         equ 104
; data page layout
XDP_CTRL        equ 0x000           ; control transfers, up to 1 KB
XDP_REPORT      equ 0x400           ; keyboard report (8 bytes)
XDP_CBW         equ 0x500           ; mass storage command block wrapper
XDP_CSW         equ 0x540           ; and status wrapper
XDP_SECTOR      equ 0x600           ; sector bounce buffer
XDP_SENSE       equ 0x800

xhci_init:
    pushad
    mov eax, XHCI_CLASS
    xor ecx, ecx
    call pci_find_class
    jc .out
    mov ebx, eax
    mov edx, PCI_REG_BAR0
    call pci_bar_mem
    jc .out
    mov [xhci_cap], eax
    mov ecx, XHCI_MAP
    call hw_map_mmio
    jc .out
    mov eax, ebx
    call pci_enable
    mov esi, [xhci_cap]
    movzx eax, byte [esi+XC_CAPLEN]
    add eax, esi
    mov [xhci_op], eax
    mov eax, [esi+XC_RTSOFF]
    and eax, ~0x1F
    add eax, esi
    mov [xhci_rt], eax
    mov eax, [esi+XC_DBOFF]
    and eax, ~3
    add eax, esi
    mov [xhci_db], eax
    mov eax, [esi+XC_HCCP1]
    mov ecx, 32
    test eax, 4                     ; CSZ: 64-byte contexts
    jz .csz
    mov ecx, 64
.csz:
    mov [xhci_ctx], ecx
    mov eax, [esi+XC_HCSP1]
    shr eax, 24
    mov [xhci_ports], eax
    call xhci_take_over
    call xhci_reset
    jc .out
    call xhci_rings
    jc .out
    mov byte [xhci_up], 1
    call xhci_scan_ports
.out:
    popad
    ret

; The firmware may own the controller (USB legacy support capability,
; ID 1, in the extended capability list): ask for it and turn its SMIs off.
xhci_take_over:
    mov esi, [xhci_cap]
    mov eax, [esi+XC_HCCP1]
    shr eax, 16                     ; xECP, in dwords
    jz .r
    lea edi, [esi+eax*4]
.cap:
    mov eax, [edi]
    cmp al, 1
    je .legacy
    movzx eax, ah                   ; next, in dwords
    test eax, eax
    jz .r
    lea edi, [edi+eax*4]
    jmp .cap
.legacy:
    or dword [edi], 1 << 24         ; HC OS Owned
    mov ecx, 1000000
.w:
    test dword [edi], 1 << 16       ; HC BIOS Owned
    jz .mine
    out 0x80, al
    loop .w
.mine:
    and dword [edi+4], 0x1F1EE      ; SMI enables off, keep reserved bits
    or dword [edi+4], 0xE0000000    ; and clear the SMI status bits
.r:
    ret

; Stop and reset the controller -> CF on time-out
xhci_reset:
    mov esi, [xhci_op]
    and dword [esi+XO_USBCMD], ~XCMD_RS
    mov ecx, 1000000
.halt:
    test dword [esi+XO_USBSTS], XSTS_HCH
    jnz .halted
    out 0x80, al
    loop .halt
    stc
    ret
.halted:
    or dword [esi+XO_USBCMD], XCMD_HCRST
    mov ecx, 1000000
.rst:
    test dword [esi+XO_USBCMD], XCMD_HCRST
    jnz .rw
    test dword [esi+XO_USBSTS], XSTS_CNR
    jz .ok
.rw:
    out 0x80, al
    loop .rst
    stc
    ret
.ok:
    clc
    ret

; DCBAA, scratchpad, command ring, event ring, then run -> CF on failure
xhci_rings:
    mov esi, [xhci_op]
    call pg_alloc
    test eax, eax
    jz .fail
    mov [xhci_dcbaa], eax
    ; scratchpad buffers the controller asks for (HCSPARAMS2)
    mov edi, [xhci_cap]
    mov ecx, [edi+XC_HCSP2]
    mov edx, ecx
    shr ecx, 27                     ; Max Scratchpad Bufs Lo
    shr edx, 21
    and edx, 0x1F                   ; Hi
    shl edx, 5
    or ecx, edx
    jz .nosp
    cmp ecx, 512
    ja .fail
    call pg_alloc                   ; the array
    test eax, eax
    jz .fail
    mov edi, [xhci_dcbaa]
    mov [edi], eax                  ; DCBAA[0] = scratchpad array
    mov edi, eax
.sp:
    call pg_alloc
    test eax, eax
    jz .fail
    stosd
    xor eax, eax
    stosd
    loop .sp
.nosp:
    mov eax, XHCI_SLOTS
    mov edi, [xhci_cap]
    movzx edx, byte [edi+XC_HCSP1]
    cmp eax, edx
    jbe .slots
    mov eax, edx
.slots:
    mov [esi+XO_CONFIG], eax
    mov eax, [xhci_dcbaa]
    mov [esi+XO_DCBAAP], eax
    mov dword [esi+XO_DCBAAP+4], 0
    ; command ring
    mov ebx, xhci_cmdring
    call xhci_ring_new
    jc .fail
    mov eax, [xhci_cmdring+RG_BASE]
    or eax, 1                       ; RCS
    mov [esi+XO_CRCR], eax
    mov dword [esi+XO_CRCR+4], 0
    ; event ring: one segment of 256 TRBs, its table in the DCBAA page
    call pg_alloc
    test eax, eax
    jz .fail
    mov [xhci_evring], eax
    mov dword [xhci_evidx], 0
    mov dword [xhci_evcyc], 1
    mov edi, [xhci_dcbaa]
    add edi, 0x800
    mov [edi], eax
    mov dword [edi+4], 0
    mov dword [edi+8], RING_TRBS
    mov dword [edi+12], 0
    mov edx, [xhci_rt]
    mov dword [edx+XI_ERSTSZ], 1
    mov [edx+XI_ERDP], eax
    mov dword [edx+XI_ERDP+4], 0
    mov [edx+XI_ERSTBA], edi
    mov dword [edx+XI_ERSTBA+4], 0
    mov dword [edx+XI_IMAN], 1      ; clear IP; IE stays off: we poll
    or dword [esi+XO_USBCMD], XCMD_RS
    mov ecx, 1000000
.run:
    test dword [esi+XO_USBSTS], XSTS_HCH
    jz .ok
    out 0x80, al
    loop .run
.fail:
    stc
    ret
.ok:
    clc
    ret

; ebx = ring record: a fresh page with a link TRB at the end -> CF
xhci_ring_new:
    call pg_alloc
    test eax, eax
    jz .fail
    mov [ebx+RG_BASE], eax
    mov dword [ebx+RG_ENQ], 0
    mov dword [ebx+RG_CYC], 1
    mov [eax+(RING_TRBS-1)*16], eax     ; link back to the start
    mov dword [eax+(RING_TRBS-1)*16+4], 0
    mov dword [eax+(RING_TRBS-1)*16+8], 0
    mov dword [eax+(RING_TRBS-1)*16+12], TRB_LINK|TRB_TC   ; cycle 0: not yet valid
    clc
    ret
.fail:
    stc
    ret

; Puts a TRB on ring ebx: eax = parameter low, edx = status, ecx = control
; (without the cycle bit); parameter high is [xhci_trb_hi], which is
; reset to 0. -> eax = its address.
; The control dword (with the cycle bit) is written last.
xhci_ring_put:
    push esi
    push edi
    mov edi, [ebx+RG_ENQ]
    shl edi, 4
    add edi, [ebx+RG_BASE]
    mov [edi], eax
    mov eax, [xhci_trb_hi]
    mov [edi+4], eax
    mov dword [xhci_trb_hi], 0
    mov [edi+8], edx
    mov eax, [ebx+RG_CYC]
    or eax, ecx
    mov [edi+12], eax
    mov esi, edi                    ; this TRB
    mov eax, [ebx+RG_ENQ]
    inc eax
    cmp eax, RING_TRBS-1
    jb .same
    ; hand the link TRB over with the current cycle, then flip it
    mov edi, [ebx+RG_BASE]
    mov eax, [ebx+RG_CYC]
    or eax, TRB_LINK|TRB_TC
    mov [edi+(RING_TRBS-1)*16+12], eax
    xor dword [ebx+RG_CYC], 1
    xor eax, eax
.same:
    mov [ebx+RG_ENQ], eax
    mov eax, esi
    pop edi
    pop esi
    ret

; Drains the event ring. Call with interrupts off (hw_tick, or the
; waits below between pushfd/cli and popfd).
xhci_poll:
    cmp byte [xhci_up], 0
    je .r
    pushad
    xor ebp, ebp                    ; events handled
.next:
    mov esi, [xhci_evidx]
    shl esi, 4
    add esi, [xhci_evring]
    mov eax, [esi+12]
    and eax, 1
    cmp eax, [xhci_evcyc]
    jne .done
    call xhci_event
    inc ebp
    mov eax, [xhci_evidx]
    inc eax
    cmp eax, RING_TRBS
    jb .idx
    xor eax, eax
    xor dword [xhci_evcyc], 1
.idx:
    mov [xhci_evidx], eax
    jmp .next
.done:
    test ebp, ebp
    jz .out
    mov eax, [xhci_evidx]           ; tell the controller how far we got
    shl eax, 4
    add eax, [xhci_evring]
    or eax, 8                       ; EHB: write 1 to clear
    mov edx, [xhci_rt]
    mov [edx+XI_ERDP], eax
    mov dword [edx+XI_ERDP+4], 0
.out:
    popad
.r:
    ret

; esi = an event TRB
xhci_event:
    mov eax, [esi+12]
    shr eax, 10
    and eax, 0x3F
    cmp eax, TRBT_CMD
    je .cmd
    cmp eax, TRBT_XFER
    je .xfer
    ret                             ; port status changes etc.: not used
.cmd:
    mov eax, [esi+8]
    shr eax, 24
    mov [xhci_cmd_code], eax
    mov eax, [esi+12]
    shr eax, 24
    mov [xhci_cmd_slot], eax
    mov byte [xhci_cmd_done], 1
    ret
.xfer:
    mov eax, [esi+12]
    shr eax, 24                     ; slot
    call xhci_dev_by_slot
    jc .r
    mov eax, [esi+12]
    shr eax, 16
    and eax, 0x1F                   ; endpoint (DCI)
    cmp ebx, [usbkbd_dev]
    jne .sync
    cmp eax, [ebx+XD_DCIA]
    jne .sync
    jmp usbkbd_event                ; the keyboard's interrupt endpoint
.sync:
    mov [ebx+XD_EVDCI], eax
    mov eax, [esi+8]
    mov edx, eax
    and edx, 0x00FFFFFF
    mov [ebx+XD_RESID], edx
    shr eax, 24
    mov [ebx+XD_CODE], eax
    mov byte [ebx+XD_DONE], 1
.r:
    ret

; eax = slot -> ebx = device record, CF if none
xhci_dev_by_slot:
    push ecx
    test eax, eax
    jz .no
    mov ebx, xhci_devs
    mov ecx, XHCI_MAXDEV            ; the one being enumerated too
.l:
    cmp [ebx+XD_SLOT], eax
    je .ok
    add ebx, XD_SIZE
    loop .l
.no:
    pop ecx
    stc
    ret
.ok:
    pop ecx
    clc
    ret

; Command: eax = parameter low, ecx = control (type, slot << 24)
; -> eax = completion code, edx = slot ID from the event; CF unless success
xhci_command:
    push ebx
    push ecx
    mov byte [xhci_cmd_done], 0
    xor edx, edx
    mov ebx, xhci_cmdring
    call xhci_ring_put
    mov eax, [xhci_db]
    mov dword [eax], 0              ; doorbell 0: the command ring
    mov ecx, 2000000
.w:
    pushfd
    cli
    call xhci_poll
    popfd
    cmp byte [xhci_cmd_done], 0
    jne .got
    out 0x80, al
    loop .w
    mov eax, -1
    jmp .bad
.got:
    mov eax, [xhci_cmd_code]
    mov edx, [xhci_cmd_slot]
    cmp eax, CC_SUCCESS
    jne .bad
    pop ecx
    pop ebx
    clc
    ret
.bad:
    pop ecx
    pop ebx
    stc
    ret

; ebx = device, ecx = DCI: rings its doorbell and waits for the transfer
; event -> eax = completion code, edx = residual bytes; CF unless success
; or short packet
xhci_xfer_wait:
    push ecx
    push esi
    mov esi, [xhci_db]
    mov eax, [ebx+XD_SLOT]
    mov [esi+eax*4], ecx
    mov ecx, 5000000
.w:
    pushfd
    cli
    call xhci_poll
    popfd
    cmp byte [ebx+XD_DONE], 0
    jne .got
    out 0x80, al
    loop .w
    mov eax, -1
    xor edx, edx
    jmp .bad
.got:
    mov eax, [ebx+XD_CODE]
    mov edx, [ebx+XD_RESID]
    cmp eax, CC_SUCCESS
    je .ok
    cmp eax, CC_SHORT
    je .ok
.bad:
    pop esi
    pop ecx
    stc
    ret
.ok:
    pop esi
    pop ecx
    clc
    ret

; Control transfer on EP0 with the data stage in the device's data page
; at XDP_CTRL. ebx = device, eax = bmRequestType | bRequest << 8 |
; wValue << 16, edx = wIndex | wLength << 16 -> CF on failure.
xhci_control:
    pushad
    mov byte [ebx+XD_DONE], 0
    mov esi, eax                    ; setup packet, low half
    mov edi, edx                    ; high half
    lea ebp, [ebx+XD_EP0]
    ; transfer type: no data, IN or OUT data stage
    xor ecx, ecx
    shr edx, 16
    jz .setup
    mov ecx, 2 << 16                ; OUT
    test al, 0x80
    jz .setup
    mov ecx, 3 << 16                ; IN
.setup:
    push ebx
    mov ebx, ebp
    or ecx, TRB_SETUP|TRB_IDT
    mov [xhci_trb_hi], edi          ; parameter high: wIndex | wLength << 16
    mov eax, esi
    mov edx, 8
    call xhci_ring_put
    pop ebx
    ; data stage
    mov edx, edi
    shr edx, 16                     ; wLength
    jz .status
    push ebx
    mov eax, [ebx+XD_DATA]
    add eax, XDP_CTRL
    mov ecx, TRB_DATA
    test esi, 0x80
    jz .dout
    or ecx, TRB_DIR_IN
.dout:
    mov ebx, ebp
    call xhci_ring_put
    pop ebx
.status:
    ; status stage: IN unless the data stage was IN
    mov ecx, TRB_STATUS|TRB_IOC|TRB_DIR_IN
    mov edx, edi
    shr edx, 16
    jz .st
    test esi, 0x80
    jz .st
    mov ecx, TRB_STATUS|TRB_IOC
.st:
    push ebx
    mov ebx, ebp
    xor eax, eax
    xor edx, edx
    call xhci_ring_put
    pop ebx
    mov ecx, 1                      ; DCI 1: EP0
    call xhci_xfer_wait
    jc .fail
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; One Normal TRB: ebx = device, ebp = ring record, ecx = DCI,
; eax = buffer, edx = length -> CF on failure, edx = residual bytes
xhci_bulk:
    push eax
    push ecx
    push ebx
    mov byte [ebx+XD_DONE], 0
    push ecx
    mov ebx, ebp
    mov ecx, TRB_NORMAL|TRB_IOC|TRB_ISP
    call xhci_ring_put
    pop ecx
    pop ebx
    call xhci_xfer_wait
    pop ecx
    pop eax
    ret

; ---------- enumeration ----------

xhci_scan_ports:
    mov ecx, 1
.port:
    cmp ecx, [xhci_ports]
    ja .r
    cmp dword [xhci_ndev], XHCI_MAXDEV
    jae .r
    push ecx
    call xhci_port
    pop ecx
    inc ecx
    jmp .port
.r:
    ret

; ecx = root-hub port number (1-based): reset it if a device is there,
; then address and configure the device
xhci_port:
    mov esi, [xhci_op]
    lea edi, [esi+XO_PORTSC+ecx*8]
    lea edi, [edi+ecx*8-0x10]       ; XO_PORTSC + 0x10 * (port - 1)
    mov eax, [edi]
    test eax, PSC_CCS
    jz .r
    test eax, PSC_PED
    jnz .enabled                    ; USB 3 ports enable themselves
    and eax, ~PSC_RW1C
    or eax, PSC_PR|PSC_PP
    mov [edi], eax
    mov edx, 2000000
.reset:
    mov eax, [edi]
    test eax, PSC_PRC
    jz .rw
    test eax, PSC_PED
    jnz .enabled
.rw:
    out 0x80, al
    dec edx
    jnz .reset
    ret
.enabled:
    mov eax, [edi]                  ; clear the change bits
    and eax, ~PSC_PED
    or eax, PSC_PP
    mov [edi], eax
    mov eax, [edi]
    shr eax, 10
    and eax, 0x0F                   ; port speed ID
    jz .r
    mov edx, ecx
    call xhci_new_device
.r:
    ret

; eax = speed, edx = port: Enable Slot, Address Device, read the
; descriptors and hand the device to its driver. Drops it on failure.
xhci_new_device:
    pushad
    mov ebx, [xhci_ndev]
    imul ebx, XD_SIZE
    add ebx, xhci_devs
    mov edi, ebx
    push eax
    mov ecx, XD_SIZE/4
    xor eax, eax
    rep stosd
    pop eax
    mov [ebx+XD_SPEED], eax
    mov [ebx+XD_PORT], edx
    ; EP0 max packet: 8 until the device descriptor says (full/low
    ; speed), 64 high speed, 512 SuperSpeed
    mov ecx, 8
    cmp eax, 3
    jb .mps
    mov ecx, 64
    je .mps
    mov ecx, 512
.mps:
    mov [ebx+XD_MPS0], ecx
    xor eax, eax
    mov ecx, TRB_ENSLOT
    call xhci_command
    jc .out
    mov [ebx+XD_SLOT], edx
    ; pages: output context, input context, data, EP0 ring
    call pg_alloc
    test eax, eax
    jz .out
    mov [ebx+XD_OUT], eax
    call pg_alloc
    test eax, eax
    jz .out
    mov [ebx+XD_IN], eax
    call pg_alloc
    test eax, eax
    jz .out
    mov [ebx+XD_DATA], eax
    push ebx
    lea ebx, [ebx+XD_EP0]
    call xhci_ring_new
    pop ebx
    jc .out
    mov eax, [ebx+XD_SLOT]
    mov ecx, [xhci_dcbaa]
    mov edx, [ebx+XD_OUT]
    mov [ecx+eax*8], edx
    mov dword [ecx+eax*8+4], 0
    ; input context: add the slot and EP0
    call xhci_in_clear
    mov edi, [ebx+XD_IN]
    mov dword [edi+4], 3            ; A0 | A1
    mov ecx, 1                      ; context entries
    call xhci_slot_ctx
    call xhci_ep0_ctx
    mov eax, [ebx+XD_IN]
    mov ecx, [ebx+XD_SLOT]
    shl ecx, 24
    or ecx, TRB_ADDRDEV
    call xhci_command
    jc .out
    ; the first 8 bytes of the device descriptor give EP0's packet size
    mov eax, 0x01000680             ; GET_DESCRIPTOR(device)
    mov edx, 8 << 16
    call xhci_control
    jc .out
    mov edi, [ebx+XD_DATA]
    movzx eax, byte [edi+XDP_CTRL+7]
    cmp dword [ebx+XD_SPEED], 3
    jae .desc                       ; fixed for high and SuperSpeed
    cmp eax, [ebx+XD_MPS0]
    je .desc
    cmp eax, 8
    jb .desc
    mov [ebx+XD_MPS0], eax
    call xhci_in_clear
    mov edi, [ebx+XD_IN]
    mov dword [edi+4], 2            ; A1: EP0 only
    call xhci_ep0_ctx
    mov eax, [ebx+XD_IN]
    mov ecx, [ebx+XD_SLOT]
    shl ecx, 24
    or ecx, TRB_EVALCTX
    call xhci_command
    jc .out
.desc:
    ; configuration descriptor: 9 bytes for its length, then all of it
    mov eax, 0x02000680
    mov edx, 9 << 16
    call xhci_control
    jc .out
    mov edi, [ebx+XD_DATA]
    movzx edx, word [edi+XDP_CTRL+2]    ; wTotalLength
    cmp edx, 0x400
    jbe .len
    mov edx, 0x400
.len:
    shl edx, 16
    mov eax, 0x02000680
    call xhci_control
    jc .out
    call xhci_parse_config
    jc .out
    inc dword [xhci_ndev]           ; the event handler can see it from here
    cmp dword [xhci_kind], 1
    je .kbd
    cmp dword [xhci_kind], 2
    jne .keep
    call usbmsd_attach
    jmp .keep
.kbd:
    call usbkbd_attach
.keep:
.out:
    popad
    ret

; zeroes the input context (ebx = device)
xhci_in_clear:
    push eax
    push ecx
    push edi
    mov edi, [ebx+XD_IN]
    mov ecx, 1024
    xor eax, eax
    rep stosd
    pop edi
    pop ecx
    pop eax
    ret

; ebx = device, ecx = context entries: fills the input slot context
xhci_slot_ctx:
    push eax
    push edi
    mov edi, [ebx+XD_IN]
    add edi, [xhci_ctx]
    mov eax, [ebx+XD_SPEED]
    shl eax, 20
    shl ecx, 27
    or eax, ecx
    shr ecx, 27
    mov [edi], eax
    mov eax, [ebx+XD_PORT]
    shl eax, 16
    mov [edi+4], eax
    pop edi
    pop eax
    ret

; ebx = device: fills the input EP0 context (DCI 1)
xhci_ep0_ctx:
    push eax
    push edi
    mov edi, [ebx+XD_IN]
    mov eax, [xhci_ctx]
    add edi, eax
    add edi, eax                    ; input control, slot, then EP0
    mov dword [edi], 0
    mov eax, [ebx+XD_MPS0]
    shl eax, 16
    or eax, (4 << 3) | (3 << 1)     ; control endpoint, CErr 3
    mov [edi+4], eax
    mov eax, [ebx+XD_EP0+RG_BASE]
    mov ecx, [ebx+XD_EP0+RG_ENQ]
    shl ecx, 4
    add eax, ecx
    or eax, [ebx+XD_EP0+RG_CYC]     ; DCS
    mov [edi+8], eax
    mov dword [edi+12], 0
    mov dword [edi+16], 8           ; average TRB length
    pop edi
    pop eax
    ret

; Walks the configuration descriptor in the data page. Takes the first
; interface that is a boot keyboard (xhci_kind 1) or a bulk-only SCSI
; mass-storage device (2) and its endpoints. CF if neither is there.
xhci_parse_config:
    pushad
    mov dword [xhci_kind], 0
    mov esi, [ebx+XD_DATA]
    add esi, XDP_CTRL
    movzx eax, byte [esi+5]
    mov [ebx+XD_CONFIG], eax        ; bConfigurationValue
    movzx ecx, word [esi+2]
    cmp ecx, 0x400
    jbe .n
    mov ecx, 0x400
.n:
    lea ebp, [esi+ecx]              ; end
    xor edi, edi                    ; kind of the current interface (0 = ignore)
.desc:
    lea eax, [esi+2]
    cmp eax, ebp
    jae .end
    movzx ecx, byte [esi]
    cmp ecx, 2
    jb .end
    mov al, [esi+1]
    cmp al, 4
    je .iface
    cmp al, 5
    je .ep
.skip:
    add esi, ecx
    jmp .desc
.iface:
    xor edi, edi
    cmp dword [xhci_kind], 0
    jne .skip                       ; one interface per device
    mov eax, [esi+5]                ; class, subclass, protocol (+ iInterface)
    and eax, 0x00FFFFFF
    cmp eax, 0x010103               ; HID, boot, keyboard
    jne .msd
    mov edi, 1
    jmp .take
.msd:
    cmp eax, 0x500608               ; mass storage, SCSI, bulk-only
    jne .skip
    mov edi, 2
.take:
    movzx eax, byte [esi+2]
    mov [ebx+XD_IFACE], eax
    jmp .skip
.ep:
    test edi, edi
    jz .skip
    movzx eax, byte [esi+2]         ; bEndpointAddress
    movzx edx, byte [esi+3]
    and edx, 3                      ; transfer type
    push ecx
    mov ecx, eax
    and ecx, 0x0F
    shl ecx, 1                      ; DCI = 2 * number (+ 1 for IN)
    test al, 0x80
    jz .out_ep
    inc ecx
    cmp edi, 1
    jne .in_bulk
    cmp edx, 3                      ; keyboard: interrupt IN
    jne .ep_done
    jmp .set_a
.in_bulk:
    cmp edx, 2
    jne .ep_done
.set_a:
    cmp dword [ebx+XD_DCIA], 0
    jne .ep_done
    mov [ebx+XD_DCIA], ecx
    movzx eax, word [esi+4]
    and eax, 0x7FF
    mov [ebx+XD_MPSA], eax
    movzx eax, byte [esi+6]
    mov [xhci_interval], eax
    jmp .ep_done
.out_ep:
    cmp edi, 2
    jne .ep_done
    cmp edx, 2
    jne .ep_done
    cmp dword [ebx+XD_DCIB], 0
    jne .ep_done
    mov [ebx+XD_DCIB], ecx
    movzx eax, word [esi+4]
    and eax, 0x7FF
    mov [ebx+XD_MPSB], eax
.ep_done:
    pop ecx
    ; the interface is complete when its endpoints are in
    cmp edi, 1
    jne .chk2
    cmp dword [ebx+XD_DCIA], 0
    je .skip
    mov dword [xhci_kind], 1
    jmp .skip
.chk2:
    cmp dword [ebx+XD_DCIA], 0
    je .skip
    cmp dword [ebx+XD_DCIB], 0
    je .skip
    mov dword [xhci_kind], 2
    jmp .skip
.end:
    cmp dword [xhci_kind], 0
    je .none
    popad
    clc
    ret
.none:
    popad
    stc
    ret

; SET_CONFIGURATION and Configure Endpoint for the endpoints found by
; xhci_parse_config: A (interrupt or bulk IN), and B (bulk OUT) if any.
; ebx = device -> CF on failure
xhci_configure:
    pushad
    mov eax, [ebx+XD_CONFIG]
    shl eax, 16
    or eax, 0x0900                  ; SET_CONFIGURATION, host to device
    xor edx, edx
    call xhci_control
    jc .fail
    call xhci_in_clear
    lea ebp, [ebx+XD_EPA]
    push ebx
    mov ebx, ebp
    call xhci_ring_new
    pop ebx
    jc .fail
    mov ecx, [ebx+XD_DCIA]
    mov edx, 1
    shl edx, cl
    or edx, 1                       ; A0: the slot context
    cmp dword [ebx+XD_DCIB], 0
    je .one
    lea ebp, [ebx+XD_EPB]
    push ebx
    mov ebx, ebp
    call xhci_ring_new
    pop ebx
    jc .fail
    mov ecx, [ebx+XD_DCIB]
    mov eax, 1
    shl eax, cl
    or edx, eax
.one:
    mov edi, [ebx+XD_IN]
    mov [edi+4], edx                ; add flags
    ; context entries = the highest DCI
    mov ecx, [ebx+XD_DCIA]
    cmp ecx, [ebx+XD_DCIB]
    jae .ce
    mov ecx, [ebx+XD_DCIB]
.ce:
    call xhci_slot_ctx
    ; endpoint A
    mov ecx, [ebx+XD_DCIA]
    lea ebp, [ebx+XD_EPA]
    mov eax, [ebx+XD_MPSA]
    mov edx, 6                      ; bulk IN
    cmp dword [xhci_kind], 1
    jne .a
    mov edx, 7                      ; interrupt IN
.a:
    call xhci_ep_ctx
    cmp dword [ebx+XD_DCIB], 0
    je .cmd
    mov ecx, [ebx+XD_DCIB]
    lea ebp, [ebx+XD_EPB]
    mov eax, [ebx+XD_MPSB]
    mov edx, 2                      ; bulk OUT
    call xhci_ep_ctx
.cmd:
    mov eax, [ebx+XD_IN]
    mov ecx, [ebx+XD_SLOT]
    shl ecx, 24
    or ecx, TRB_CONFEP
    call xhci_command
    jc .fail
    popad
    clc
    ret
.fail:
    popad
    stc
    ret

; ebx = device, ecx = DCI, ebp = ring, eax = max packet, edx = EP type:
; fills that endpoint's input context
xhci_ep_ctx:
    pushad
    mov edi, [ebx+XD_IN]
    inc ecx                         ; input control context comes first
    imul ecx, [xhci_ctx]
    add edi, ecx
    mov esi, eax                    ; max packet
    shl eax, 16
    shl edx, 3
    or eax, edx
    or eax, 3 << 1                  ; CErr 3
    mov [edi+4], eax
    xor eax, eax
    cmp edx, 7 << 3
    jne .noint
    ; interrupt: interval as 2^n * 125 us. Full/low speed give bInterval
    ; in ms (n = log2(bInterval * 8)); high and SuperSpeed give n + 1.
    mov ecx, [xhci_interval]
    test ecx, ecx
    jnz .iv
    inc ecx
.iv:
    cmp dword [ebx+XD_SPEED], 3
    jae .hs
    shl ecx, 3
    bsr ecx, ecx
    jmp .ivset
.hs:
    dec ecx
.ivset:
    cmp ecx, 15
    jbe .ivok
    mov ecx, 15
.ivok:
    shl ecx, 16
    mov eax, ecx
.noint:
    mov [edi], eax
    mov eax, [ebp+RG_BASE]
    or eax, [ebp+RG_CYC]
    mov [edi+8], eax
    mov dword [edi+12], 0
    mov eax, esi
    shl eax, 16                     ; max ESIT payload (low)
    or eax, esi                     ; average TRB length
    mov [edi+16], eax
    popad
    ret

; After a STALL or error on a bulk endpoint: Reset Endpoint, point its
; dequeue at our enqueue, CLEAR_FEATURE(ENDPOINT_HALT).
; ebx = device, ecx = DCI, ebp = its ring.
xhci_ep_recover:
    pushad
    mov esi, ecx
    mov eax, 0
    mov ecx, [ebx+XD_SLOT]
    shl ecx, 24
    mov edx, esi
    shl edx, 16
    or ecx, edx
    or ecx, TRB_RESETEP
    call xhci_command
    mov eax, [ebp+RG_ENQ]
    shl eax, 4
    add eax, [ebp+RG_BASE]
    or eax, [ebp+RG_CYC]
    mov ecx, [ebx+XD_SLOT]
    shl ecx, 24
    mov edx, esi
    shl edx, 16
    or ecx, edx
    or ecx, TRB_SETDEQ
    call xhci_command
    ; endpoint address from the DCI: number = DCI / 2, IN if odd
    mov edx, esi
    shr edx, 1
    test esi, 1
    jz .o
    or edx, 0x80
.o:
    mov eax, 0x00000102             ; CLEAR_FEATURE, endpoint recipient, ENDPOINT_HALT
    call xhci_control
    popad
    ret

align 4
xhci_up db 0
xhci_cmd_done db 0
align 4
xhci_cap dd 0
xhci_op dd 0
xhci_rt dd 0
xhci_db dd 0
xhci_ctx dd 32
xhci_ports dd 0
xhci_dcbaa dd 0
xhci_evring dd 0
xhci_evidx dd 0
xhci_evcyc dd 1
xhci_cmdring times RG_SIZE db 0
xhci_cmd_code dd 0
xhci_cmd_slot dd 0
xhci_kind dd 0
xhci_trb_hi dd 0
xhci_interval dd 0
xhci_ndev dd 0
xhci_devs times XHCI_MAXDEV*XD_SIZE db 0
