; Squirrel-OS/2 0.1.0
; Cooperative multitasking: two tasks yield to each other.
BITS 16
ORG 0x8000
stage2:
    cli
    lgdt [gdt_desc]
    mov eax, cr0
    or eax, 1
    mov cr0, eax
    jmp 0x08:pm

BITS 32
pm:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov esp, 0x9F000

    mov edi, idt
    mov ecx, 256
.fill:
    mov eax, default_isr
    call set_gate
    add edi, 8
    loop .fill
    mov edi, idt+0x20*8
    mov eax, timer_isr
    call set_gate
    lidt [idt_desc]

    mov al, 0x11
    out 0x20, al
    out 0xA0, al
    mov al, 0x20
    out 0x21, al
    mov al, 0x28
    out 0xA1, al
    mov al, 4
    out 0x21, al
    mov al, 2
    out 0xA1, al
    mov al, 1
    out 0x21, al
    out 0xA1, al
    mov al, 0xFE
    out 0x21, al
    mov al, 0xFF
    out 0xA1, al
    mov al, 0x36
    out 0x43, al
    mov ax, 11932
    out 0x40, al
    mov al, ah
    out 0x40, al

    call cls
    mov esi, banner
    call puts
    sti

    mov dword [task0_esp], task0_stack_top
    mov dword [task1_esp], task1_stack_top
    mov dword [current], 0

    mov esp, [task0_esp]
    jmp task0

task0:
    mov esi, t0msg
    call puts
    call yield
    jmp task0

task1:
    mov esi, t1msg
    call puts
    call yield
    jmp task1

yield:
    pusha
    mov eax, [current]
    cmp eax, 0
    je .save0
    mov [task1_esp], esp
    mov dword [current], 0
    mov esp, [task0_esp]
    jmp .restore
.save0:
    mov [task0_esp], esp
    mov dword [current], 1
    mov esp, [task1_esp]
.restore:
    popa
    ret

set_gate:
    mov [edi], ax
    mov word [edi+2], 0x08
    mov byte [edi+4], 0
    mov byte [edi+5], 0x8E
    shr eax, 16
    mov [edi+6], ax
    ret

cls:
    mov edi, 0xB8000
    mov ecx, 80*25
    mov ax, 0x0720
    rep stosw
    mov dword [cur], 0
    ret

puts:
    lodsb
    or al, al
    jz .d
    call putc
    jmp puts
.d:
    ret

putc:
    mov edi, 0xB8000
    mov ebx, [cur]
    shl ebx, 1
    add edi, ebx
    mov ah, 0x07
    mov [edi], ax
    inc dword [cur]
    ret

timer_isr:
    push eax
    inc dword [ticks]
    mov al, 0x20
    out 0x20, al
    pop eax
    iretd

default_isr:
    iretd

banner db 'Squirrel-OS/2 0.1.0 — cooperative tasks', 10, 0
t0msg  db 'Task0 ', 0
t1msg  db 'Task1 ', 0
cur dd 0
ticks dd 0
current dd 0
task0_esp dd 0
task1_esp dd 0

align 16
task0_stack: times 1024 db 0
task0_stack_top:
align 16
task1_stack: times 1024 db 0
task1_stack_top:

align 8
gdt:
    dq 0
    dw 0xFFFF,0,0x9A00,0x00CF
    dw 0xFFFF,0,0x9200,0x00CF
gdt_desc:
    dw $-gdt-1
    dd gdt
align 8
idt: times 256 dq 0
idt_desc:
    dw 256*8-1
    dd idt
times 8192-($-$$) db 0
