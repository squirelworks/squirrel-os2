; Squirrel-OS/2 0.0.6
; PM + IDT + keyboard console + bump allocator
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

    ; IDT setup
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
    mov edi, idt+0x21*8
    mov eax, kbd_isr
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
    mov al, 0xFC
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

    mov eax, 64
    call kmalloc
    mov esi, alloc_msg
    call puts

    sti
.loop:
    hlt
    jmp .loop

kmalloc:
    mov ebx, [heap_ptr]
    add eax, ebx
    mov [heap_ptr], eax
    mov eax, ebx
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
    cmp al, 10
    je .nl
    mov edi, 0xB8000
    mov ebx, [cur]
    shl ebx, 1
    add edi, ebx
    mov ah, 0x07
    mov [edi], ax
    inc dword [cur]
    ret
.nl:
    mov eax, [cur]
    xor edx, edx
    mov ebx, 80
    div ebx
    inc eax
    mul ebx
    mov [cur], eax
    ret

timer_isr:
    push eax
    inc dword [ticks]
    mov al, 0x20
    out 0x20, al
    pop eax
    iretd

kbd_isr:
    push eax
    push ebx
    in al, 0x60
    cmp al, 0x80
    jae .e
    movzx ebx, al
    mov al, [scancode_map+ebx]
    or al, al
    jz .e
    call putc
.e:
    mov al, 0x20
    out 0x20, al
    pop ebx
    pop eax
    iretd

default_isr:
    iretd

banner db 'Squirrel-OS/2 0.0.6 — allocator online', 10, 0
alloc_msg db 'kmalloc(64) succeeded', 10, 0
cur dd 0
ticks dd 0
heap_ptr dd 0x100000

scancode_map:
    db 0,0,'1','2','3','4','5','6','7','8','9','0','-','=',0,0
    db 'q','w','e','r','t','y','u','i','o','p','[',']',10,0
    db 'a','s','d','f','g','h','j','k','l',';',39,'`',0,'\'
    db 'z','x','c','v','b','n','m',',','.','/',0,0,0,' '
    times 128 db 0

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
