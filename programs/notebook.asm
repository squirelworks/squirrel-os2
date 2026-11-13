; Squirrel-OS/2 — Notebook (C.8, OS2-APPS). Original code.
; (work in progress: the Nut interpreter's self-test)

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

main:
    call nut_init
    jc .nomem
    mov esi, [esp+4]
    jmp selftest
.nomem:
    mov eax, 1
    ret

selftest:
    mov esi, ntests
    mov byte [bad], 'a'
.t:
    cmp byte [esi], 0
    je .done
    push esi
    call nut_reset
    call nut_run
    pop esi
    jnc .ran
    mov eax, [nut_errmsg]       ; an error: "!message"
    mov edi, [nut_out]
    add edi, [nut_olen]
    mov byte [edi], '!'
    inc edi
    push esi
    mov esi, eax
.cp:
    lodsb
    stosb
    test al, al
    jnz .cp
    pop esi
.ran:
.skip:
    lodsb
    test al, al
    jnz .skip
    mov edi, [nut_out]
    push esi
.c:
    mov al, [esi]
    cmp al, [edi]
    jne .fail
    inc esi
    inc edi
    test al, al
    jnz .c
    pop esi
.n:
    lodsb
    test al, al
    jnz .n
    inc byte [bad]
    jmp .t
.fail:
    pop esi
    push esi
    mov esi, failm
    call gui_puts
    mov esi, bad
    call gui_puts
    mov esi, [nut_out]
    call gui_puts
    mov esi, nl
    call gui_puts
    pop esi
    jmp .n
.done:
    mov esi, donem
    call gui_puts
    xor eax, eax
    ret

%include "nut.inc"

ntests:
    db 'print 1 + 2 * 3', 0, '7', 10, 0
    db 'x = 2', 10, 'print x ^ 3, "and", x % 3', 0, '8 and 2', 10, 0
    db 'if 3 > 2 then print "yes" else print "no" end', 0, 'yes', 10, 0
    db 'i = 0', 10, 's = 0', 10, 'while i < 5 do', 10, ' i = i + 1', 10, ' s = s + i', 10, 'end', 10, 'print s', 0, '15', 10, 0
    db 'for i = 1 to 3 do print i end', 0, '1', 10, '2', 10, '3', 10, 0
    db 'fn f(n)', 10, ' if n < 2 then return 1 end', 10, ' return n * f(n - 1)', 10, 'end', 10, 'print f(5)', 0, '120', 10, 0
    db 'print "a" + 1 + 2', 0, 'a12', 10, 0
    db 'print sqrt(16), abs(-3), floor(2.7), max(1, 5, 3)', 0, '4 3 2 5', 10, 0
    db 'for i = 10 to 1 step -3 do print i end', 0, '10', 10, '7', 10, '4', 10, '1', 10, 0
    db 'n = 0', 10, 'while true do', 10, ' n = n + 1', 10, ' if n == 4 then break end', 10, 'end', 10, 'print n', 0, '4', 10, 0
    db 'print 1 / 0', 0, '!division by zero', 0
    db 'print y', 0, '!unknown variable', 0
    db 'x = 1', 10, 'if x == 1 then', 10, 'print "one"', 10, 'elif x == 2 then', 10, 'print "two"', 10, 'else', 10, 'print "many"', 10, 'end', 0, 'one', 10, 0
    db 'x = 2', 10, 'if x == 1 then print "one" elif x == 2 then print "two" else print "many" end', 0, 'two', 10, 0
    db 'print "b" < "c", 2 >= 3, not 0, 1 and 0 or 1', 0, '1 0 1 1', 10, 0
    db 'g = 5', 10, 'fn add(a) return a + g end', 10, 'print add(1)', 0, '6', 10, 0
    db 'fn fib(n) if n < 2 then return n end return fib(n-1) + fib(n-2) end', 10, 'print fib(15)', 0, '610', 10, 0
    db 'print len("acorn"), str(3) + "!"', 0, '5 3!', 10, 0
    db 'while 1 do end', 0, '!too many steps (a loop that never ends?)', 0
    db 'if 1 then print 2', 0, '2', 10, '!end is missing', 0
    db 0
failm db 'nut FAIL: ', 0
donem db 'nut tests done', 10, 0
nl db 10, 0
bad db '?', 0

SQX_BSS
GUI_BSS
NUT_BSS
SQX_END
