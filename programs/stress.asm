; stress — hammers processes, threads, messages, preemption, the FPU and
; the heap, and checks every result. Original code.
;   run stress          every part below, in order
;   run stress <part>   one part: threads ring flood fpu heap churn exec
; Each part prints "stress <part>: PASS" or "stress <part>: FAIL ..." and
; the whole run ends with "stress: PASS" or "stress: FAIL".
%include "sqx.inc"
SQX_HEADER main

NTHREADS    equ 6               ; slots 2-7 (shell is 0, this program 1)
SPIN_STEPS  equ 20000           ; per thread per round, no system calls
ROUNDS      equ 30
RING_LAPS   equ 300             ; token passes = RING_LAPS * NTHREADS
FLOOD_MSGS  equ 1500            ; per sender
FPU_ITERS   equ 20000
HEAP_ROUNDS equ 20
HEAP_BYTES  equ 0x400000        ; the whole 4 MB heap
CHURN       equ 400
EXEC_ROUNDS equ 20

main:
    mov esi, [esp+4]            ; argument string (may be empty)
    mov [arg], esi
    mov eax, SYS_GETPID
    int 0x80
    mov [self], eax
    mov esi, [arg]
    cmp byte [esi], 'k'         ; "kid": the exec part's child
    je kid_main
    mov dword [failed], 0
    mov ebx, parts
.next:
    mov esi, [ebx]
    test esi, esi
    jz .done
    mov edi, [arg]
    cmp byte [edi], 0
    je .run                     ; no argument: every part
    call streq
    jne .skip
.run:
    push ebx
    mov [cur_name], esi
    call [ebx+4]                ; -> CF on failure, esi = reason
    jc .bad
    call say_name
    mov ebx, m_pass
    call puts
    jmp .after
.bad:
    push esi
    call say_name
    mov ebx, m_fail
    call puts
    pop ebx
    call puts
    mov ebx, m_nl
    call puts
    mov dword [failed], 1
.after:
    pop ebx
.skip:
    add ebx, 8
    jmp .next
.done:
    mov ebx, m_all_pass
    cmp dword [failed], 0
    je .print
    mov ebx, m_all_fail
.print:
    call puts
    mov eax, [failed]
    ret

say_name:
    mov ebx, m_stress
    call puts
    mov ebx, [cur_name]
    call puts
    ret

; esi, edi = strings: ZF if equal (edi may end at a space)
streq:
    push esi
    push edi
.c:
    mov al, [esi]
    mov ah, [edi]
    cmp ah, ' '
    jne .x
    xor ah, ah
.x:
    cmp al, ah
    jne .r
    test al, al
    jz .r
    inc esi
    inc edi
    jmp .c
.r:
    pop edi
    pop esi
    ret

puts:                           ; ebx = string
    push eax
    mov eax, SYS_PUTS
    int 0x80
    pop eax
    ret

putn:                           ; eax = unsigned number
    pushad
    mov edi, numbuf+11
    mov byte [edi], 0
    mov ecx, 10
.d:
    xor edx, edx
    div ecx
    add dl, '0'
    dec edi
    mov [edi], dl
    test eax, eax
    jnz .d
    mov ebx, edi
    call puts
    popad
    ret

yield:
    push eax
    mov eax, SYS_YIELD
    int 0x80
    pop eax
    ret

; ebx = entry, ecx = arg -> eax = pid (CF if spawn failed)
spawn:
    mov eax, SYS_SPAWN
    int 0x80
    test eax, eax
    js .f
    clc
    ret
.f:
    stc
    ret

; waits for the NTHREADS pids in kids -> eax = sum of their exit codes,
; CF if a wait returned -1
wait_kids:
    push ebx
    push ecx
    push edx
    xor edx, edx
    xor ecx, ecx
.w:
    mov eax, SYS_WAIT
    mov ebx, [kids+ecx*4]
    int 0x80
    cmp eax, -1
    je .bad
    add edx, eax
    inc ecx
    cmp ecx, NTHREADS
    jb .w
    mov eax, edx
    clc
    jmp .r
.bad:
    stc
.r:
    pop edx
    pop ecx
    pop ebx
    ret

; ---------- threads: a full table of spinning threads, many rounds ------
part_threads:
    mov dword [round], 0
.round:
    mov dword [counter], 0
    mov dword [go], 0
    xor ecx, ecx
.sp:
    mov ebx, spinner
    push ecx
    inc ecx
    call spawn                  ; arg = 1..NTHREADS
    pop ecx
    jc .nospawn
    mov [kids+ecx*4], eax
    inc ecx
    cmp ecx, NTHREADS
    jb .sp
    mov ebx, spinner            ; the table is full now
    xor ecx, ecx
    call spawn
    jnc .extra
    mov dword [go], 1
    call wait_kids
    jc .lost
    cmp eax, NTHREADS*(NTHREADS+1)/2
    jne .codes
    cmp dword [counter], NTHREADS*SPIN_STEPS
    jne .count
    inc dword [round]
    cmp dword [round], ROUNDS
    jb .round
    clc
    ret
.nospawn:
    mov esi, r_nospawn
    stc
    ret
.extra:
    mov esi, r_extra
    stc
    ret
.lost:
    mov esi, r_lost
    stc
    ret
.codes:
    mov esi, r_codes
    stc
    ret
.count:
    mov esi, r_count
    stc
    ret

; spinner(n): SPIN_STEPS locked increments with no system call, so only
; the timer can switch away; returns n
spinner:
.hold:
    cmp dword [go], 0           ; until the table has been checked
    je .hold
    mov ecx, SPIN_STEPS
.s:
    lock inc dword [counter]
    mov eax, 50                 ; a little work between increments
.d:
    dec eax
    jnz .d
    dec ecx
    jnz .s
    mov eax, [esp+4]
    ret

; ---------- ring: a token passed around NTHREADS threads ----------------
part_ring:
    mov dword [ring_seen], 0
    xor ecx, ecx
.sp:
    mov ebx, ring_node
    call spawn                  ; arg = its index
    jc .nospawn
    mov [kids+ecx*4], eax
    inc ecx
    cmp ecx, NTHREADS
    jb .sp
    ; every node now knows the pids through kids; start the token
    mov ebx, [kids]
    xor ecx, ecx
    call send_retry
    call wait_kids
    jc .lost
    cmp dword [ring_seen], RING_LAPS*NTHREADS
    jne .count
    clc
    ret
.nospawn:
    mov esi, r_nospawn
    stc
    ret
.lost:
    mov esi, r_lost
    stc
    ret
.count:
    mov esi, r_ring
    stc
    ret

; ebx = pid, ecx = message: sends, yielding while the queue is full
send_retry:
    push eax
.s:
    mov eax, SYS_SEND
    int 0x80
    cmp eax, -2
    jne .r
    call yield
    jmp .s
.r:
    pop eax
    ret

; ring_node(i): forwards token+1 to node i+1 until the token reaches the
; end, then passes the end on so every node stops
ring_node:
    mov esi, [esp+4]
    lea edi, [esi+1]
    cmp edi, NTHREADS
    jb .n
    xor edi, edi
.n:
.loop:
    mov eax, SYS_RECV
    int 0x80
    cmp eax, -1                 ; the stop token
    je .stop
    cmp eax, RING_LAPS*NTHREADS
    jae .last
    lock inc dword [ring_seen]
    inc eax
    mov ecx, eax
    mov ebx, [kids+edi*4]
    call send_retry
    jmp .loop
.last:
    mov ecx, -1
    mov ebx, [kids+edi*4]
    call send_retry
    jmp .loop
.stop:
    mov ecx, -1                 ; pass it on; the last send may fail (-1)
    mov ebx, [kids+edi*4]
    mov eax, SYS_SEND
    int 0x80
    xor eax, eax
    ret

; ---------- flood: many senders, one receiver ---------------------------
part_flood:
    xor ecx, ecx
.clr:
    mov dword [flood_next+ecx*4], 0
    inc ecx
    cmp ecx, NTHREADS
    jb .clr
    xor ecx, ecx
.sp:
    mov ebx, flooder
    call spawn                  ; arg = sender index
    jc .nospawn
    mov [kids+ecx*4], eax
    inc ecx
    cmp ecx, NTHREADS
    jb .sp
    mov edi, FLOOD_MSGS*NTHREADS
.r:
    mov eax, SYS_RECV
    int 0x80
    mov ecx, eax
    shr ecx, 16                 ; sender
    cmp ecx, NTHREADS
    jae .junk
    and eax, 0xFFFF             ; its sequence number
    cmp eax, [flood_next+ecx*4]
    jne .order
    inc dword [flood_next+ecx*4]
    dec edi
    jnz .r
    call wait_kids
    jc .lost
    clc
    ret
.nospawn:
    mov esi, r_nospawn
    stc
    ret
.junk:
    mov esi, r_junk
    stc
    ret
.order:
    mov esi, r_order
    stc
    ret
.lost:
    mov esi, r_lost
    stc
    ret

; flooder(i): sends FLOOD_MSGS messages (i << 16 | n) to the main thread
flooder:
    mov esi, [esp+4]
    shl esi, 16
    xor edi, edi
.s:
    mov ecx, esi
    or ecx, edi
    mov ebx, [self]
    call send_retry
    inc edi
    cmp edi, FLOOD_MSGS
    jb .s
    xor eax, eax
    ret

; ---------- fpu: preempted floating point must not mix -------------------
part_fpu:
    push dword 1                ; reference values, computed alone
    call fpu_work
    add esp, 4
    mov [fpu_ref], eax
    push dword 2
    call fpu_work
    add esp, 4
    mov [fpu_ref+4], eax
    xor ecx, ecx
.sp:
    mov ebx, fpu_thread
    push ecx
    and ecx, 1
    inc ecx                     ; seeds alternate 1, 2
    call spawn
    pop ecx
    jc .nospawn
    mov [kids+ecx*4], eax
    inc ecx
    cmp ecx, NTHREADS
    jb .sp
    call wait_kids
    jc .lost
    cmp eax, NTHREADS           ; each returns 1 if its result matched
    jne .mix
    clc
    ret
.nospawn:
    mov esi, r_nospawn
    stc
    ret
.lost:
    mov esi, r_lost
    stc
    ret
.mix:
    mov esi, r_fpu
    stc
    ret

fpu_thread:
    mov eax, [esp+4]
    push eax
    call fpu_work
    add esp, 4
    mov ecx, [esp+4]
    xor edx, edx
    cmp eax, [fpu_ref+ecx*4-4]
    sete dl
    mov eax, edx
    ret

; fpu_work(seed) -> eax = low dword of a long chain of x87 operations
; with the whole register stack in use, and no system calls
fpu_work:
    sub esp, 8
    fninit
    fild dword [esp+12]         ; st0 = seed
    fld1
    fld1
    fld1
    fld1
    fld1
    fld1                        ; 7 registers used
    mov ecx, FPU_ITERS
.l:
    fadd st0, st6               ; st0 += seed
    fsqrt
    fmul st0, st1
    fadd st0, st6
    fxch st3
    fadd st0, st0
    fsqrt
    fxch st3
    dec ecx
    jnz .l
    faddp st1, st0
    faddp st1, st0
    faddp st1, st0
    faddp st1, st0
    faddp st1, st0
    faddp st1, st0
    fstp qword [esp]
    mov eax, [esp]
    xor eax, [esp+4]
    add esp, 8
    ret

; ---------- heap: the whole 4 MB, grown, written, checked, freed --------
part_heap:
    mov dword [round], 0
.round:
    mov eax, SYS_SBRK
    xor ebx, ebx
    int 0x80
    cmp eax, 0x40000000
    jne .base
    mov eax, SYS_SBRK
    mov ebx, HEAP_BYTES
    int 0x80
    cmp eax, 0x40000000
    jne .grow
    mov eax, SYS_SBRK           ; one byte more is refused
    mov ebx, 1
    int 0x80
    cmp eax, -1
    jne .over
    mov edi, 0x40000000         ; a pattern in every page
    mov edx, [round]
.w:
    mov eax, edi
    xor eax, edx
    cmp dword [edi+4], 0        ; fresh heap reads as zero
    jne .dirty
    mov [edi], eax
    mov [edi+4092], eax
    add edi, 4096
    cmp edi, 0x40000000+HEAP_BYTES
    jb .w
    call yield
    mov edi, 0x40000000
.c:
    mov eax, edi
    xor eax, edx
    cmp [edi], eax
    jne .lostdata
    cmp [edi+4092], eax
    jne .lostdata
    add edi, 4096
    cmp edi, 0x40000000+HEAP_BYTES
    jb .c
    mov eax, SYS_SBRK
    mov ebx, -HEAP_BYTES
    int 0x80
    cmp eax, 0x40000000+HEAP_BYTES
    jne .shrink
    inc dword [round]
    cmp dword [round], HEAP_ROUNDS
    jb .round
    clc
    ret
.base:
    mov esi, r_hbase
    stc
    ret
.grow:
    mov esi, r_hgrow
    stc
    ret
.over:
    mov esi, r_hover
    stc
    ret
.dirty:
    mov esi, r_hdirty
    stc
    ret
.lostdata:
    mov esi, r_hlost
    stc
    ret
.shrink:
    mov esi, r_hshrink
    stc
    ret

; ---------- churn: threads that start and end, waited for or not --------
part_churn:
    mov esi, CHURN              ; never waited for: zombies are reclaimed
.a:
    mov ebx, quick
    mov ecx, 7
    call spawn
    jc .nospawn
    call yield
    dec esi
    jnz .a
    mov esi, CHURN              ; waited for, with a known exit code
.b:
    mov ebx, quick
    mov ecx, esi
    call spawn
    jc .nospawn
    mov ebx, eax
    mov eax, SYS_WAIT
    int 0x80
    cmp eax, esi
    jne .code
    dec esi
    jnz .b
    clc
    ret
.nospawn:
    mov esi, r_nospawn
    stc
    ret
.code:
    mov esi, r_codes
    stc
    ret

quick:
    mov eax, [esp+4]
    ret

; ---------- exec: separately loaded copies, several at once -------------
part_exec:
    mov dword [round], 0
.round:
    xor ecx, ecx
.sp:
    mov eax, SYS_EXEC           ; "stress kid": loads a fresh copy
    mov ebx, m_self
    mov edx, ecx
    mov ecx, m_kidarg
    int 0x80
    mov ecx, edx
    test eax, eax
    js .noexec
    mov [kids+ecx*4], eax
    inc ecx
    cmp ecx, 3                  ; three programs alive besides this one
    jb .sp
    xor ecx, ecx
    xor edx, edx
.w:
    mov eax, SYS_WAIT
    mov ebx, [kids+ecx*4]
    int 0x80
    add edx, eax
    inc ecx
    cmp ecx, 3
    jb .w
    cmp edx, 3*KID_CODE
    jne .code
    cmp dword [PROG_BASE], 'SQX1'   ; our own image is still ours
    jne .clobbered
    inc dword [round]
    cmp dword [round], EXEC_ROUNDS
    jb .round
    clc
    ret
.noexec:
    mov esi, r_noexec
    stc
    ret
.code:
    mov esi, r_codes
    stc
    ret
.clobbered:
    mov esi, r_clobbered
    stc
    ret

KID_CODE equ 77
; the child: spins a little, uses its heap, then exits with KID_CODE
kid_main:
    mov eax, SYS_SBRK
    mov ebx, 0x10000
    int 0x80
    cmp eax, 0x40000000
    jne .bad
    mov dword [0x40000000+0xFFFC], KID_CODE
    mov ecx, 200000
.s:
    dec ecx
    jnz .s
    mov eax, [0x40000000+0xFFFC]
    ret
.bad:
    mov eax, 1
    ret

parts:
    dd p_threads, part_threads
    dd p_ring, part_ring
    dd p_flood, part_flood
    dd p_fpu, part_fpu
    dd p_heap, part_heap
    dd p_churn, part_churn
    dd p_exec, part_exec
    dd 0, 0

p_threads db 'threads', 0
p_ring db 'ring', 0
p_flood db 'flood', 0
p_fpu db 'fpu', 0
p_heap db 'heap', 0
p_churn db 'churn', 0
p_exec db 'exec', 0
m_self db 'stress', 0
m_kidarg db 'kid', 0
m_stress db 'stress ', 0
m_pass db ': PASS', 10, 0
m_fail db ': FAIL ', 0
m_nl db 10, 0
m_all_pass db 'stress: PASS', 10, 0
m_all_fail db 'stress: FAIL', 10, 0
r_nospawn db '(spawn failed)', 0
r_extra db '(spawn worked with a full table)', 0
r_lost db '(a wait returned -1)', 0
r_codes db '(wrong exit codes)', 0
r_count db '(lost increments)', 0
r_ring db '(token count wrong)', 0
r_junk db '(message from nobody)', 0
r_order db '(messages out of order)', 0
r_fpu db '(FPU results differ)', 0
r_hbase db '(break not at heap base)', 0
r_hgrow db '(could not grow to 4 MB)', 0
r_hover db '(grew past 4 MB)', 0
r_hdirty db '(fresh heap not zero)', 0
r_hlost db '(heap data changed)', 0
r_hshrink db '(shrink returned the wrong break)', 0
r_noexec db '(exec failed)', 0
r_clobbered db '(own image overwritten)', 0

SQX_BSS
arg resd 1
self resd 1
failed resd 1
cur_name resd 1
round resd 1
counter resd 1
go resd 1
ring_seen resd 1
kids resd NTHREADS
flood_next resd NTHREADS
fpu_ref resd 2
numbuf resb 12
SQX_END
