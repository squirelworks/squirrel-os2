; ring3 — checks that programs run in ring 3 and the kernel is protected
; (2.4). Original code.
; run ring3
; 1. The code segment's privilege level is 3.
; 2. System calls refuse pointers into kernel memory with -1, and
;    SYS_PALLOC is kernel-only; strings and buffers on ring-3 stack pages
;    the kernel must not touch (another thread's untouched page, a guard
;    page) are refused too, without ending this program.
; 3. Threads that read or write kernel memory, or use cli, hlt, in or a
;    kernel interrupt vector, are ended by the kernel (wait returns -1)
;    while this program carries on.
; 4. A thread may use far more than the old 8 KB of stack: its ring-3
;    stack grows page by page.
; Prints "ring3: PASS", or "ring3: FAIL n" with the failed step.
%include "sqx.inc"
SQX_HEADER main

KTESTS equ 6                    ; the privileged things a thread tries
USTACK_BASE equ 0x7FC00000      ; ring-3 stack windows, 512 KB per slot
OTHER_STACK equ USTACK_BASE+7*0x80000+0x40000 ; slot 7's, never touched here
GUARD_PAGE  equ USTACK_BASE+0x10 ; slot 0's guard page

main:
    mov byte [step], '1'
    mov eax, cs
    and eax, 3
    cmp eax, 3
    jne .fail
    mov byte [step], '2'
    mov eax, SYS_PUTS
    mov ebx, 0x8000             ; the kernel's first bytes
    int 0x80
    cmp eax, -1
    jne .fail
    mov eax, SYS_FSERROR
    mov ebx, 0x100000           ; the high kernel image
    mov ecx, 16
    int 0x80
    cmp eax, -1
    jne .fail
    mov eax, SYS_READDIR
    xor ebx, ebx
    mov ecx, PROG_BASE+0x10000-8 ; runs past the program area
    int 0x80
    cmp eax, -1
    jne .fail
    mov eax, SYS_PALLOC
    int 0x80
    cmp eax, -1
    jne .fail
    ; pointers into ring-3 stack pages the kernel must not touch: another
    ; slot's untouched stack page, and a guard page. Refused, not a crash.
    mov eax, SYS_PUTS
    mov ebx, OTHER_STACK
    int 0x80
    cmp eax, -1
    jne .fail
    mov eax, SYS_PUTS
    mov ebx, GUARD_PAGE
    int 0x80
    cmp eax, -1
    jne .fail
    mov eax, SYS_FSERROR
    mov ebx, OTHER_STACK
    mov ecx, 16
    int 0x80
    cmp eax, -1
    jne .fail
    mov byte [step], '3'
    xor esi, esi
.k:
    mov ecx, esi
    call run_thread
    cmp eax, -1
    jne .fail
    inc esi
    cmp esi, KTESTS
    jb .k
    mov byte [step], '4'
    mov ecx, KTESTS             ; the deep-stack thread
    call run_thread
    cmp eax, 7
    jne .fail
    mov ebx, m_pass
    jmp .print
.fail:
    mov ebx, m_fail
.print:
    mov eax, SYS_PUTS
    int 0x80
    xor eax, eax
    ret

; ecx = test number -> eax = the thread's exit code
run_thread:
    mov eax, SYS_SPAWN
    mov ebx, worker
    int 0x80
    test eax, eax
    js .r
    mov ebx, eax
    mov eax, SYS_WAIT
    int 0x80
.r:
    ret

; worker(n): each n < KTESTS must be stopped by the kernel
worker:
    mov eax, [esp+4]
    cmp eax, 0
    je .read
    cmp eax, 1
    je .write
    cmp eax, 2
    je .cli
    cmp eax, 3
    je .hlt
    cmp eax, 4
    je .in
    cmp eax, 5
    je .int
    ; deep stack: 64 KB of frames, each touching its page
    mov ecx, 16
    call deep
    mov eax, 7
    ret
.read:
    mov eax, [0x8000]
    jmp .survived
.write:
    mov dword [0x100000], 0
    jmp .survived
.cli:
    cli
    jmp .survived
.hlt:
    hlt
    jmp .survived
.in:
    in al, 0x60
    jmp .survived
.int:
    int 0x21                    ; the keyboard IRQ's gate is ring 0 only
.survived:
    xor eax, eax                ; exit code 0: not stopped
    ret

; ecx = depth: recurses with 4 KB frames
deep:
    sub esp, 4096
    mov [esp], ecx
    dec ecx
    jz .out
    call deep
.out:
    add esp, 4096
    ret

m_pass db 'ring3: PASS', 10, 0
m_fail db 'ring3: FAIL '
step db '0', 10, 0

SQX_BSS
SQX_END
