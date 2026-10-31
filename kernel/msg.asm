; Squirrel-OS/2 — message queues between processes (1.2)
; Included from pm.asm. Original code.
;
; Every process slot has a queue of MSG_QMAX messages. A message is one
; dword (four bytes). SYS_SEND appends to another process's queue and never
; blocks; SYS_RECV takes the oldest message from the caller's own queue
; and waits while it is empty. spawn empties the queue of the slot it
; takes. See documentation/kernel/messages.md.

MSG_QMAX        equ 8           ; messages per queue
MSG_ENOPID      equ -1          ; SYS_SEND: no live process has that pid
MSG_EFULL       equ -2          ; SYS_SEND: the receiver's queue is full

%if PCB_SIZE != 64
%error "msg_slot assumes 64-byte PCBs"
%endif

; edi = PCB -> eax = its slot index
msg_slot:
    mov eax, edi
    sub eax, proc_table
    shr eax, 6
    ret

; ebx = pid, ecx = message -> eax = 0, MSG_ENOPID or MSG_EFULL.
; Interrupts are off while the queue changes: the keyboard IRQ posts too.
sys_send:
    pushfd
    cli
    call msg_put
    popfd
    ret

msg_put:
    call proc_find              ; edi = PCB or 0
    test edi, edi
    jz .nopid
    cmp dword [edi+PCB_STATE], P_ZOMBIE
    je .nopid
    call msg_slot
    movzx edx, byte [msg_count+eax]
    cmp edx, MSG_QMAX
    jae .full
    inc byte [msg_count+eax]
    add dl, [msg_head+eax]      ; the free entry after the last message
    and edx, MSG_QMAX-1
    lea edx, [eax*MSG_QMAX+edx]
    mov [msg_data+edx*4], ecx
    xor eax, eax
    ret
.nopid:
    mov eax, MSG_ENOPID
    ret
.full:
    mov eax, MSG_EFULL
    ret

; -> eax = the oldest message in the caller's queue; waits for one
sys_recv:
    pushfd
    cli
    mov edi, [proc_cur]
    call msg_slot
    cmp byte [msg_count+eax], 0
    jne .take
    popfd
    call proc_idle              ; let the senders run
    jmp sys_recv
.take:
    dec byte [msg_count+eax]
    movzx edx, byte [msg_head+eax]
    inc byte [msg_head+eax]
    and byte [msg_head+eax], MSG_QMAX-1
    lea edx, [eax*MSG_QMAX+edx]
    mov eax, [msg_data+edx*4]
    popfd
    ret

; ---------- key events (1.2.1) ----------
; The keyboard IRQ decodes each scancode a second time, the way kbd_getchar
; does for SYS_GETC (its own Shift state, releases skipped, Esc 27,
; Backspace 8), and posts MSG_KEY | ASCII to the one process that asked
; with SYS_KEYEVENTS. The raw scancode still goes to the ring, so SYS_GETC
; and the shell see the key as before.

MSG_KEY         equ 0x4B000000  ; 'K' in the top byte, ASCII in the low byte

; ebx = 1 to receive key events, 0 to stop -> eax = 0
sys_keyevents:
    mov eax, [proc_cur]
    mov eax, [eax+PCB_PID]
    test ebx, ebx
    jz .off
    mov [key_ev_pid], eax       ; the newest caller takes over
    jmp .r
.off:
    cmp [key_ev_pid], eax
    jne .r
    mov dword [key_ev_pid], -1
.r:
    xor eax, eax
    ret

; al = scancode, from kbd_isr with interrupts off. Clobbers everything.
key_event:
    cmp al, 0x2A
    je .shdown
    cmp al, 0x36
    je .shdown
    cmp al, 0xAA
    je .shup
    cmp al, 0xB6
    je .shup
    cmp al, 0x80
    jae .r                      ; releases and prefixes
    mov ecx, 27
    cmp al, 0x01
    je .post
    mov ecx, 8
    cmp al, 0x0E
    je .post
    movzx ebx, al
    movzx ecx, byte [scancode_map+ebx]
    cmp byte [key_ev_shift], 0
    je .mapped
    movzx ecx, byte [scancode_map_shift+ebx]
.mapped:
    test ecx, ecx
    jz .r                       ; no ASCII: SYS_GETC skips it too
.post:
    mov ebx, [key_ev_pid]
    cmp ebx, -1
    je .r
    or ecx, MSG_KEY
    jmp msg_put                 ; a full queue drops the event
.shdown:
    mov byte [key_ev_shift], 1
    ret
.shup:
    mov byte [key_ev_shift], 0
.r:
    ret

key_ev_pid dd -1                ; who gets key events; -1 nobody
key_ev_shift db 0

; edx = slot index: an empty queue for a new process (from proc_spawn)
msg_reset:
    mov byte [msg_count+edx], 0
    mov byte [msg_head+edx], 0
    ret

msg_count times PROC_MAX db 0
msg_head times PROC_MAX db 0
align 4
msg_data times PROC_MAX*MSG_QMAX dd 0
