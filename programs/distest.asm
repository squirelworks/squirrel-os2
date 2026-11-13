; distest — checks the debugger's disassembler (programs/disasm.inc, A.4)
; on a block of instructions against the text it must print. The block
; is never run. The expected lines were checked against ndisasm.
; Original code. run distest
%include "sqx.inc"
SQX_HEADER main
%include "disasm.inc"

BASE equ 0x30000                ; the block is shown as if it started here

main:
    mov esi, dt_code
    mov edi, dt_want
    xor ebp, ebp                ; failures
.l: cmp esi, dt_end
    jae .done
    mov ebx, esi
    sub ebx, dt_code-BASE
    push edi
    call dis_one
    pop edi
    add esi, eax
    push esi
    mov esi, dis_text
    mov edx, edi
.c: mov al, [esi]
    cmp al, [edi]
    jne .bad
    inc esi
    inc edi
    test al, al
    jnz .c
    pop esi
    jmp .l
.bad:
    inc ebp
    mov eax, SYS_PUTS           ; "want: ... / got: ..."
    mov ebx, m_want
    int 0x80
    mov ebx, edx
    int 0x80
    mov ebx, m_got
    int 0x80
    mov ebx, dis_text
    int 0x80
    mov ebx, m_nl
    int 0x80
.skip:
    cmp byte [edi], 0
    je .sk
    inc edi
    jmp .skip
.sk:
    inc edi
    pop esi
    jmp .l
.done:
    mov eax, SYS_PUTS
    mov ebx, m_pass
    test ebp, ebp
    jz .p
    mov ebx, m_fail
.p: int 0x80
    mov eax, ebp
    ret

m_want db 'want: ', 0
m_got db ' / got: ', 0
m_nl db 10, 0
m_pass db 'distest: PASS', 10, 0
m_fail db 'distest: FAIL', 10, 0

dt_code:
    add [ebx+ecx*4+0x10],ecx
    add cl,[esi-0x8]
    sub esp,0x20
    and esi,byte -16
    xor dword [ebp-4],byte 3
    cmp byte [eax],7
    push dword 0x12345678
    push byte -1
    imul ecx,edx,-3
    imul eax,[ebx],0x1000
    mov ax,ds
    lea eax,[eax+eax*2]
    mov eax,[fs:0x18]
    mov [es:edi],al
    mov al,[0x30010]
    xchg eax,edi
    cdq
    rep movsd
    repe cmpsb
    repne scasb
    movsw
    mov si,0x1234
    shl eax,4
    sar dword [ecx],5
    rcl ebx,cl
    shr dword [eax],1
    ret 8
    enter 16,0
    leave
    int 0x80
    in al,dx
    out 0x20,al
    lock xadd [ebx],eax
    test byte [eax],0x10
    test dword [eax],0x1000
    neg ecx
    idiv byte [ebx]
    inc dword [eax]
    call [eax+4]
    jmp far [ebx]
    push dword [esi]
    pop dword [eax]
    mov byte [eax],0x41
    mov word [eax],0x1234
    movzx eax,byte [ebx]
    movsx ecx,word [eax+2]
    cmovl esi,edi
    setnz byte [eax]
    bt eax,5
    bts [eax],ecx
    bsr ecx,[edx]
    shld eax,ebx,4
    shrd edx,eax,cl
    cmpxchg [eax],ecx
    bswap edi
    cpuid
    rdtsc
    fld qword [eax]
    fstp tword [ebx]
    fild word [eax]
    fistp qword [eax]
    fnstsw ax
    fldcw [eax]
    fxch st2
    fsqrt
    faddp st1,st0
    fdivr st5,st0
    pause
dt_here: jz dt_here
    call dt_here
    loop dt_here
    jmp near dt_here
dt_end:

dt_want:
    db 'add [ebx+ecx*4+0x10],ecx', 0
    db 'add cl,[esi-0x8]', 0
    db 'sub esp,0x20', 0
    db 'and esi,-0x10', 0
    db 'xor dword [ebp-0x4],0x3', 0
    db 'cmp byte [eax],0x7', 0
    db 'push 0x12345678', 0
    db 'push -0x1', 0
    db 'imul ecx,edx,-0x3', 0
    db 'imul eax,[ebx],0x1000', 0
    db 'mov ax,ds', 0
    db 'lea eax,[eax+eax*2]', 0
    db 'mov eax,[fs:0x18]', 0
    db 'mov [es:edi],al', 0
    db 'mov al,[0x30010]', 0
    db 'xchg eax,edi', 0
    db 'cdq', 0
    db 'rep movsd', 0
    db 'repe cmpsb', 0
    db 'repne scasb', 0
    db 'movsw', 0
    db 'mov si,0x1234', 0
    db 'shl eax,0x4', 0
    db 'sar dword [ecx],0x5', 0
    db 'rcl ebx,cl', 0
    db 'shr dword [eax],1', 0
    db 'ret 0x8', 0
    db 'enter 0x10,0x0', 0
    db 'leave', 0
    db 'int 0x80', 0
    db 'in al,dx', 0
    db 'out 0x20,al', 0
    db 'lock xadd [ebx],eax', 0
    db 'test byte [eax],0x10', 0
    db 'test dword [eax],0x1000', 0
    db 'neg ecx', 0
    db 'idiv byte [ebx]', 0
    db 'inc dword [eax]', 0
    db 'call [eax+0x4]', 0
    db 'jmp far [ebx]', 0
    db 'push dword [esi]', 0
    db 'pop dword [eax]', 0
    db 'mov byte [eax],0x41', 0
    db 'mov word [eax],0x1234', 0
    db 'movzx eax,byte [ebx]', 0
    db 'movsx ecx,word [eax+0x2]', 0
    db 'cmovl esi,edi', 0
    db 'setnz byte [eax]', 0
    db 'bt eax,0x5', 0
    db 'bts [eax],ecx', 0
    db 'bsr ecx,[edx]', 0
    db 'shld eax,ebx,0x4', 0
    db 'shrd edx,eax,cl', 0
    db 'cmpxchg [eax],ecx', 0
    db 'bswap edi', 0
    db 'cpuid', 0
    db 'rdtsc', 0
    db 'fld qword [eax]', 0
    db 'fstp tword [ebx]', 0
    db 'fild word [eax]', 0
    db 'fistp qword [eax]', 0
    db 'fnstsw ax', 0
    db 'fldcw word [eax]', 0
    db 'fxch st2', 0
    db 'fsqrt', 0
    db 'faddp st1,st0', 0
    db 'fdivr st5,st0', 0
    db 'pause', 0
    db 'jz 0x300be', 0
    db 'call 0x300be', 0
    db 'loop 0x300be', 0
    db 'jmp 0x300be', 0

SQX_BSS
SQX_END
