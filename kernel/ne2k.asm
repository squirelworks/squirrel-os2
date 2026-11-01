; Squirrel-OS/2 — NE2000 network card, polled (1.9.4)
; Included from pm.asm. Original code.
;
; The DP8390-based NE2000 on the ISA bus that QEMU emulates (ne2k_isa,
; I/O 0x300). Port I/O only: no bus mastering, no IRQ handler. The card
; keeps a ring of 256-byte pages for frames it receives (pages
; NE_RXSTART up to NE_RXSTOP) and a transmit buffer at NE_TXSTART. Frames
; are moved through the remote DMA data port, one word at a time.
; ne_poll moves whatever the card has received onto the interface's
; receive queue (net.asm). See documentation/kernel/network.md.

NE_BASE     equ 0x300
NE_CR       equ NE_BASE + 0x00      ; command
NE_PSTART   equ NE_BASE + 0x01      ; page 0
NE_PSTOP    equ NE_BASE + 0x02
NE_BNRY     equ NE_BASE + 0x03
NE_TPSR     equ NE_BASE + 0x04
NE_TBCR0    equ NE_BASE + 0x05
NE_TBCR1    equ NE_BASE + 0x06
NE_ISR      equ NE_BASE + 0x07
NE_RSAR0    equ NE_BASE + 0x08
NE_RSAR1    equ NE_BASE + 0x09
NE_RBCR0    equ NE_BASE + 0x0A
NE_RBCR1    equ NE_BASE + 0x0B
NE_RCR      equ NE_BASE + 0x0C
NE_TCR      equ NE_BASE + 0x0D
NE_DCR      equ NE_BASE + 0x0E
NE_IMR      equ NE_BASE + 0x0F
NE_PAR0     equ NE_BASE + 0x01      ; page 1
NE_CURR     equ NE_BASE + 0x07
NE_MAR0     equ NE_BASE + 0x08
NE_DATA     equ NE_BASE + 0x10
NE_RESET    equ NE_BASE + 0x1F

NE_TXSTART  equ 0x40                ; 6 pages: one full frame
NE_RXSTART  equ 0x46
NE_RXSTOP   equ 0x80

CR_STOP     equ 0x01
CR_START    equ 0x02
CR_TXP      equ 0x04
CR_RREAD    equ 0x08
CR_RWRITE   equ 0x10
CR_NODMA    equ 0x20
CR_PAGE1    equ 0x40

ISR_PRX     equ 0x01
ISR_PTX     equ 0x02
ISR_RDC     equ 0x40
ISR_RST     equ 0x80

; Finds and starts the card; reads its MAC address into ne_mac.
; -> CF if there is no card
ne_init:
    pushad
    mov byte [ne_up], 0
    mov dx, NE_RESET            ; reset: read the port, write it back
    in al, dx
    out dx, al
    mov ecx, 100000
    mov dx, NE_ISR
.rst:
    in al, dx
    test al, ISR_RST
    jnz .rdone
    loop .rst
    jmp .none
.rdone:
    mov al, 0xFF
    out dx, al                  ; clear every interrupt bit
    mov dx, NE_CR
    mov al, CR_NODMA | CR_STOP
    out dx, al
    in al, dx                   ; a missing card reads back 0xFF
    cmp al, CR_NODMA | CR_STOP
    jne .none
    mov dx, NE_DCR
    mov al, 0x49                ; word transfers, normal, FIFO 8 bytes
    out dx, al
    xor al, al
    mov dx, NE_RBCR0
    out dx, al
    mov dx, NE_RBCR1
    out dx, al
    mov dx, NE_RCR
    mov al, 0x20                ; monitor: take nothing yet
    out dx, al
    mov dx, NE_TCR
    mov al, 0x02                ; internal loopback while setting up
    out dx, al
    mov dx, NE_IMR
    xor al, al                  ; polled: no interrupts
    out dx, al
    ; the address PROM: 32 bytes, each byte doubled in word mode
    xor ebx, ebx
    mov ecx, 32
    call ne_dma_setup
    mov dx, NE_CR
    mov al, CR_RREAD | CR_START
    out dx, al
    mov dx, NE_DATA
    mov edi, ne_mac
    mov ecx, 6
.mac:
    in ax, dx
    stosb
    loop .mac
    mov ecx, 10
.rest:
    in ax, dx
    loop .rest
    call ne_dma_done
    cmp dword [ne_mac], 0xFFFFFFFF
    je .none
    ; the receive ring
    mov dx, NE_CR
    mov al, CR_NODMA | CR_STOP
    out dx, al
    mov dx, NE_TPSR
    mov al, NE_TXSTART
    out dx, al
    mov dx, NE_PSTART
    mov al, NE_RXSTART
    out dx, al
    mov dx, NE_BNRY
    out dx, al
    mov dx, NE_PSTOP
    mov al, NE_RXSTOP
    out dx, al
    mov dx, NE_CR               ; page 1: our address and CURR
    mov al, CR_PAGE1 | CR_NODMA | CR_STOP
    out dx, al
    mov esi, ne_mac
    mov dx, NE_PAR0
    mov ecx, 6
.par:
    lodsb
    out dx, al
    inc dx
    loop .par
    mov dx, NE_CURR
    mov al, NE_RXSTART + 1
    out dx, al
    mov dx, NE_MAR0             ; every multicast group
    mov ecx, 8
    mov al, 0xFF
.mar:
    out dx, al
    inc dx
    loop .mar
    mov dx, NE_CR
    mov al, CR_NODMA | CR_START
    out dx, al
    mov dx, NE_ISR
    mov al, 0xFF
    out dx, al
    mov dx, NE_RCR
    mov al, 0x04                ; our address and broadcasts
    out dx, al
    mov dx, NE_TCR
    xor al, al                  ; normal transmit
    out dx, al
    mov byte [ne_up], 1
    popad
    clc
    ret
.none:
    popad
    stc
    ret

; ebx = card address, ecx = bytes: set up a remote DMA
ne_dma_setup:
    push eax
    push edx
    mov dx, NE_ISR
    mov al, ISR_RDC
    out dx, al
    mov dx, NE_RBCR0
    mov al, cl
    out dx, al
    mov dx, NE_RBCR1
    mov al, ch
    out dx, al
    mov dx, NE_RSAR0
    mov al, bl
    out dx, al
    mov dx, NE_RSAR1
    mov al, bh
    out dx, al
    pop edx
    pop eax
    ret

; wait for the remote DMA to end, and clear its bit
ne_dma_done:
    push eax
    push ecx
    push edx
    mov dx, NE_ISR
    mov ecx, 100000
.w:
    in al, dx
    test al, ISR_RDC
    jnz .d
    loop .w
.d:
    mov al, ISR_RDC
    out dx, al
    pop edx
    pop ecx
    pop eax
    ret

; the interface's transmit: esi = frame, ecx = length (1..NET_MTU)
; -> CF if the card is not there or does not finish sending
ne_xmit:
    cmp byte [ne_up], 0
    je .no
    pushad
    cmp ecx, 60                 ; Ethernet's shortest frame
    jae .len
    push ecx                    ; pad with zeros in ne_txbuf
    push esi
    mov edi, ne_txbuf
    rep movsb
    pop esi
    pop ecx
    mov edi, ne_txbuf
    add edi, ecx
    push ecx
    neg ecx
    add ecx, 60
    xor al, al
    rep stosb
    pop ecx
    mov esi, ne_txbuf
    mov ecx, 60
.len:
    mov [ne_txlen], ecx
    inc ecx                     ; words: round up
    and ecx, ~1
    mov ebx, NE_TXSTART << 8
    call ne_dma_setup
    mov dx, NE_CR
    mov al, CR_RWRITE | CR_START
    out dx, al
    mov dx, NE_DATA
    shr ecx, 1
.w:
    lodsw
    out dx, ax
    loop .w
    call ne_dma_done
    mov ecx, [ne_txlen]
    mov dx, NE_TPSR
    mov al, NE_TXSTART
    out dx, al
    mov dx, NE_TBCR0
    mov al, cl
    out dx, al
    mov dx, NE_TBCR1
    mov al, ch
    out dx, al
    mov dx, NE_CR
    mov al, CR_NODMA | CR_TXP | CR_START
    out dx, al
    mov dx, NE_ISR
    mov ecx, 1000000
.tx:
    in al, dx
    test al, ISR_PTX | 0x08     ; sent, or given up (TXE)
    jnz .txd
    loop .tx
    popad
    stc
    ret
.txd:
    mov al, ISR_PTX | 0x08
    out dx, al
    popad
    clc
    ret
.no:
    stc
    ret

; Moves every frame the card has received onto the interface's queue.
; -> eax = frames moved
ne_poll:
    xor eax, eax
    cmp byte [ne_up], 0
    je .r
    pushad
    xor ebp, ebp
.next:
    mov dx, NE_CR               ; CURR is on page 1
    mov al, CR_PAGE1 | CR_NODMA | CR_START
    out dx, al
    mov dx, NE_CURR
    in al, dx
    mov bl, al
    mov dx, NE_CR
    mov al, CR_NODMA | CR_START
    out dx, al
    mov dx, NE_BNRY             ; the next page to read is BNRY + 1
    in al, dx
    inc al
    cmp al, NE_RXSTOP
    jb .nw
    mov al, NE_RXSTART
.nw:
    cmp al, bl
    je .done                    ; nothing new
    mov [ne_page], al
    movzx ebx, al               ; the 4-byte header: status, next, length
    shl ebx, 8
    mov ecx, 4
    call ne_dma_setup
    mov dx, NE_CR
    mov al, CR_RREAD | CR_START
    out dx, al
    mov dx, NE_DATA
    in ax, dx
    mov [ne_hdr], ax
    in ax, dx
    mov [ne_hdr+2], ax
    call ne_dma_done
    movzx ecx, word [ne_hdr+2]  ; the count includes the 4-byte header, not a CRC
    sub ecx, 4
    jbe .skip
    cmp ecx, NET_MTU
    ja .skip
    ; the frame may wrap from the ring's end to its start
    movzx ebx, byte [ne_page]
    shl ebx, 8
    add ebx, 4
    mov edi, ne_rxbuf
    mov [ne_rxlen], ecx
    mov eax, NE_RXSTOP << 8
    sub eax, ebx                ; bytes before the end of the ring
    cmp ecx, eax
    jbe .one
    push ecx
    mov ecx, eax
    call ne_read
    pop ecx
    sub ecx, eax
    mov ebx, NE_RXSTART << 8
.one:
    call ne_read
    push ebx
    mov ebx, ne_if
    mov esi, ne_rxbuf
    mov ecx, [ne_rxlen]
    call net_rxq                ; a full queue drops the frame
    pop ebx
    inc ebp
.skip:
    mov al, [ne_hdr+1]          ; the next frame's page
    dec al                      ; BNRY trails it by one
    cmp al, NE_RXSTART
    jae .bn
    mov al, NE_RXSTOP - 1
.bn:
    mov dx, NE_BNRY
    out dx, al
    jmp .next
.done:
    mov dx, NE_ISR
    mov al, ISR_PRX | 0x10      ; received, and overwrite warning
    out dx, al
    mov [esp+28], ebp
    popad
.r:
    ret

; ebx = card address, ecx = bytes, edi = where -> edi after them
ne_read:
    push eax
    push ecx
    push edx
    push ecx
    inc ecx
    and ecx, ~1
    call ne_dma_setup
    mov dx, NE_CR
    mov al, CR_RREAD | CR_START
    out dx, al
    mov dx, NE_DATA
    shr ecx, 1
.r:
    in ax, dx
    stosw
    loop .r
    call ne_dma_done
    pop ecx
    test ecx, 1                 ; an odd count read one byte too many
    jz .e
    dec edi
.e:
    pop edx
    pop ecx
    pop eax
    ret

; nettest's part for the card: sends an ARP request for 10.0.2.2 (QEMU's
; gateway) and waits up to two seconds for any ARP reply to come back
ne_selftest:
    mov esi, ne_mac             ; our address, as sender, in the request
    mov edi, ne_arpq + 6
    movsd
    movsw
    mov esi, ne_mac
    mov edi, ne_arpq + 22
    movsd
    movsw
    mov ebx, ne_if
    mov esi, ne_arpq
    mov ecx, NE_ARPQ_LEN
    call net_send
    jc .fail
    mov edx, [ticks]
    add edx, 200
.wait:
    call ne_poll
.take:
    mov ebx, ne_if
    mov edi, nt_in
    mov ecx, NT_BUF
    call net_recv
    jc .more
    cmp eax, 42
    jb .take
    cmp word [nt_in+12], 0x0608 ; ARP (bytes 08 06)
    jne .take
    cmp word [nt_in+20], 0x0200 ; a reply (bytes 00 02)
    jne .take
    mov esi, ne_m_pass
    jmp puts
.more:
    cmp [ticks], edx
    jb .wait
.fail:
    mov esi, ne_m_fail
    jmp puts

ne_m_pass db 'nic: PASS', 10, 0
ne_m_fail db 'nic: FAIL', 10, 0
ne_arpq:
    db 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF   ; to everyone
    times 6 db 0                            ; from us
    db 0x08, 0x06                           ; ARP
    db 0, 1, 0x08, 0, 6, 4, 0, 1            ; Ethernet, IPv4, request
    times 6 db 0                            ; our address
    db 10, 0, 2, 15                         ; our IP
    times 6 db 0
    db 10, 0, 2, 2                          ; who has 10.0.2.2?
NE_ARPQ_LEN equ $ - ne_arpq

; the device table's entry (devices lists the card and its address)
ne_dev_probe:
    call ne_init
    ret

ne_n_if db 'ne0', 0
align 4
ne_if:
    dd ne_n_if, ne_xmit, 0, 0, 0
    times NET_QLEN dd 0
dev_ne0:
    db 'ne0', 0, 0, 0, 0, 0
    dd DEV_NET, ne_dev_probe, dev_fail, dev_fail, ne_mac, 0, 0, 0
ne_up db 0
ne_page db 0
ne_mac times 8 db 0
ne_hdr times 4 db 0
align 4
ne_txlen dd 0
ne_rxlen dd 0
ne_txbuf times 64 db 0
ne_rxbuf times NET_MTU + 2 db 0
