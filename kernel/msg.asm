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

; ebx = pid, ecx = message -> eax = 0, MSG_ENOPID or MSG_EFULL
sys_send:
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
    mov edi, [proc_cur]
    call msg_slot
    cmp byte [msg_count+eax], 0
    jne .take
    call proc_idle              ; let the senders run
    jmp sys_recv
.take:
    dec byte [msg_count+eax]
    movzx edx, byte [msg_head+eax]
    inc byte [msg_head+eax]
    and byte [msg_head+eax], MSG_QMAX-1
    lea edx, [eax*MSG_QMAX+edx]
    mov eax, [msg_data+edx*4]
    ret

; edx = slot index: an empty queue for a new process (from proc_spawn)
msg_reset:
    mov byte [msg_count+edx], 0
    mov byte [msg_head+edx], 0
    ret

msg_count times PROC_MAX db 0
msg_head times PROC_MAX db 0
align 4
msg_data times PROC_MAX*MSG_QMAX dd 0
