; smpspin — ring-3 threads run on several CPUs at once (2.8-smp-sched).
; Original code.
; run smpspin [n]
; Starts THREADS threads that spin in ring 3. Each one keeps reading its
; CPU's local APIC id (CPUID leaf 1, EBX bits 31-24, allowed in ring 3)
; into a shared bit mask. A thread stops once n CPUs (1 to 9, default 1)
; are in the mask, or after LIMIT rounds. Each thread also makes system calls while
; it spins (SYS_GETPID), so kernel entries from the application
; processors are exercised too. Prints "smpspin: N CPU(s)" and
; "smpspin: threads ok" when every thread exited with its code.
%include "sqx.inc"
SQX_HEADER main

THREADS equ 4
LIMIT   equ 20000000            ; only reached when n CPUs never show up

main:
    mov eax, [esp+4]            ; the argument: how many CPUs to wait for
    movzx eax, byte [eax]
    sub eax, '1'
    cmp eax, 8
    ja .one
    inc eax
    mov [want], eax
.one:
    xor esi, esi
.spawn:
    mov eax, SYS_SPAWN
    mov ebx, worker
    mov ecx, esi
    int 0x80
    test eax, eax
    js .fail
    mov [pids+esi*4], eax
    inc esi
    cmp esi, THREADS
    jb .spawn
    xor esi, esi
.wait:
    mov eax, SYS_WAIT
    mov ebx, [pids+esi*4]
    int 0x80
    cmp eax, 7
    jne .fail
    inc esi
    cmp esi, THREADS
    jb .wait
    ; report
    mov eax, [mask]
    xor ecx, ecx
.pop:
    test eax, eax
    jz .popped
    mov edx, eax
    dec edx
    and eax, edx                ; clear the lowest set bit
    inc ecx
    jmp .pop
.popped:
    mov eax, ecx
    mov edi, m_cpus
    call digit
    mov eax, SYS_PUTS
    mov ebx, m_line
    int 0x80
    mov eax, SYS_PUTS
    mov ebx, m_ok
    int 0x80
    xor eax, eax
    ret
.fail:
    mov eax, SYS_PUTS
    mov ebx, m_fail
    int 0x80
    mov eax, 1
    ret

; eax = 0..9 -> the digit at [edi]
digit:
    cmp eax, 9
    jbe .d
    mov eax, 9
.d:
    add al, '0'
    mov [edi], al
    ret

worker:
    mov esi, LIMIT
.spin:
    mov eax, 1
    cpuid
    shr ebx, 24                 ; this CPU's local APIC id
    and ebx, 31
    lock bts dword [mask], ebx
    test esi, 0x3FFF            ; now and then: a system call from here
    jnz .nosys
    mov eax, SYS_GETPID
    int 0x80
.nosys:
    mov eax, [mask]             ; THREADS CPUs seen?
    xor ecx, ecx
.c:
    test eax, eax
    jz .counted
    mov edx, eax
    dec edx
    and eax, edx
    inc ecx
    jmp .c
.counted:
    cmp ecx, [want]
    jae .done
.more:
    dec esi
    jnz .spin
.done:
    mov eax, 7
    ret

m_line db 'smpspin: '
m_cpus db '0 CPU(s)', 10, 0
m_ok   db 'smpspin: threads ok', 10, 0
m_fail db 'smpspin: FAIL', 10, 0
align 4
mask    dd 0
want    dd 1
pids    times THREADS dd 0

SQX_BSS
SQX_END
