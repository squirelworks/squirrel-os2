; Squirrel-OS/2 — network layer: packet buffers and loopback (1.9.3)
; Included from pm.asm. Original code.
;
; An interface is a record with a name, a transmit routine and a receive
; queue of NET_QLEN frames. Each queued frame lives in its own page from
; pg_alloc (its length in the first dword, the bytes after it), taken
; when the frame is queued and given back when it is read, so an idle
; interface holds no memory. The loopback interface's transmit puts the
; frame on its own receive queue. See documentation/kernel/network.md.

NET_MTU     equ 1514                ; an Ethernet frame without its CRC
NET_QLEN    equ 8                   ; frames waiting on one interface

IF_NAME     equ 0                   ; ASCIIZ name
IF_XMIT     equ 4                   ; esi = frame, ecx = length -> CF
IF_HEAD     equ 8                   ; next slot to read
IF_TAIL     equ 12                  ; next slot to fill
IF_COUNT    equ 16                  ; frames waiting
IF_SLOTS    equ 20                  ; NET_QLEN page addresses
IF_SIZE     equ IF_SLOTS + NET_QLEN * 4

; ebx = interface, esi = frame, ecx = length -> CF set if the frame is
; empty or longer than NET_MTU, or the interface could not take it
net_send:
    test ecx, ecx
    jz .bad
    cmp ecx, NET_MTU
    ja .bad
    jmp [ebx+IF_XMIT]
.bad:
    stc
    ret

; ebx = interface, esi = frame, ecx = length (1..NET_MTU) -> CF set if
; the queue is full or there is no page: puts a copy on the receive queue
net_rxq:
    pushad
    cmp dword [ebx+IF_COUNT], NET_QLEN
    jae .no
    call pg_alloc
    test eax, eax
    jz .no
    mov edi, eax
    mov [edi], ecx
    add edi, 4
    rep movsb
    mov edx, [ebx+IF_TAIL]
    mov [ebx+IF_SLOTS+edx*4], eax
    inc edx
    cmp edx, NET_QLEN
    jb .t
    xor edx, edx
.t:
    mov [ebx+IF_TAIL], edx
    inc dword [ebx+IF_COUNT]
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; ebx = interface, edi = buffer, ecx = its size -> eax = the frame's
; length, CF clear (a longer frame is cut to the buffer); or eax = -1,
; CF set, when nothing is waiting
net_recv:
    cmp dword [ebx+IF_COUNT], 0
    je .none
    push ecx
    push edx
    push esi
    push edi
    mov edx, [ebx+IF_HEAD]
    mov esi, [ebx+IF_SLOTS+edx*4]
    mov eax, [esi]
    push eax                    ; the length to return
    cmp ecx, eax
    jbe .n
    mov ecx, eax
.n:
    push esi
    add esi, 4
    rep movsb
    pop eax
    call pg_free
    inc edx
    cmp edx, NET_QLEN
    jb .h
    xor edx, edx
.h:
    mov [ebx+IF_HEAD], edx
    dec dword [ebx+IF_COUNT]
    pop eax
    pop edi
    pop esi
    pop edx
    pop ecx
    clc
    ret
.none:
    mov eax, -1
    stc
    ret

; loopback: what is sent comes back on the same interface
net_lo_xmit:
    jmp net_rxq

; ---------- nettest ----------
; Sends three frames of different lengths on loopback, reads them back in
; order and compares them; an empty queue and an oversized frame must be
; refused. Prints net: PASS or net: FAIL.

NT_BUF      equ NET_MTU + 2         ; room to see a frame that is too long

cmd_nettest_run:
    mov byte [nt_ok], 1
    mov ebx, net_lo
    xor ebp, ebp                ; frame number
.s:
    mov ecx, [nt_lens+ebp*4]
    call nt_fill                ; nt_out = the pattern for frame ebp
    mov esi, nt_out
    call net_send
    jnc .sn
    mov byte [nt_ok], 0
.sn:
    inc ebp
    cmp ebp, 3
    jb .s
    xor ebp, ebp
.r:
    mov edi, nt_in
    mov ecx, NT_BUF
    call net_recv
    jc .bad
    cmp eax, [nt_lens+ebp*4]
    jne .bad
    mov ecx, eax
    call nt_fill
    mov esi, nt_out
    mov edi, nt_in
    repe cmpsb
    jne .bad
    inc ebp
    cmp ebp, 3
    jb .r
    mov edi, nt_in              ; nothing more is waiting
    mov ecx, NT_BUF
    call net_recv
    jnc .bad
    mov esi, nt_out             ; too long for a frame
    mov ecx, NET_MTU + 1
    call net_send
    jnc .bad
    mov ecx, 0                  ; and empty
    call net_send
    jc .say
.bad:
    mov byte [nt_ok], 0
.drain:                         ; leave the queue empty
    mov edi, nt_in
    mov ecx, NT_BUF
    call net_recv
    jnc .drain
.say:
    mov esi, nt_pass
    cmp byte [nt_ok], 1
    je .p
    mov esi, nt_fail
.p:
    call puts
    cmp byte [ne_up], 0         ; 1.9.4: and the card, when there is one
    je .nonic
    jmp ne_selftest
.nonic:
    ret

; ebp = frame number, ecx = length: nt_out[i] = i * 7 + frame number * 31
nt_fill:
    pushad
    mov edi, nt_out
    xor edx, edx
    imul ebx, ebp, 31
.f:
    mov eax, edx
    imul eax, 7
    add eax, ebx
    stosb
    inc edx
    loop .f
    popad
    ret

nt_pass db 'net: PASS', 10, 0
nt_fail db 'net: FAIL', 10, 0
net_n_lo db 'lo', 0
align 4
nt_lens dd 60, NET_MTU, 1
net_lo:
    dd net_n_lo, net_lo_xmit, 0, 0, 0
    times NET_QLEN dd 0
nt_ok db 0
align 4
nt_out times NT_BUF db 0
nt_in times NT_BUF db 0
