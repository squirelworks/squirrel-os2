; wget — fetch a URL over HTTP/1.1 and save it (3.0, OS2-NET-AUDIO)
; Original code.
;   run wget <url>          save to the last part of the path (index.htm for "/")
;   run wget <url> <file>   save to <file>
;   run wget <url> -        print the body on the screen
; It prints one line at the end:
;   wget: 200, 34 bytes, sum 2961 -> hello.txt
; "sum" is the bytes added together (mod 65536), to compare with the
; server's copy. A status that is not 2xx is reported and nothing is kept.
; See documentation/apps/network.md.
%include "sqx.inc"
SQX_HEADER main
%include "net.inc"
%include "http.inc"

NAMEMAX     equ 15                  ; SQFS names

main:
    mov esi, [esp+4]
.sp:
    cmp byte [esi], ' '
    jne .url
    inc esi
    jmp .sp
.url:
    cmp byte [esi], 0
    je usage
    mov [url], esi
.u:                                 ; cut the URL off at a space
    mov al, [esi]
    test al, al
    jz .noname
    cmp al, ' '
    je .cut
    inc esi
    jmp .u
.cut:
    mov byte [esi], 0
    inc esi
.sp2:
    cmp byte [esi], ' '
    jne .named
    inc esi
    jmp .sp2
.named:
    cmp byte [esi], 0
    je .noname
    cmp word [esi], '-'             ; "-" alone: to the screen
    jne .file
    mov byte [toscreen], 1
    jmp .go
.file:
    mov edi, fname
    mov ecx, NAMEMAX
.fc:
    lodsb
    cmp al, ' '
    jbe .fe
    stosb
    loop .fc
.fe:
    mov byte [edi], 0
    jmp .go
.noname:
    call name_from_url
.go:
    cmp byte [toscreen], 0
    jne .get
    mov eax, SYS_OPEN
    mov ebx, fname
    mov ecx, O_CREATE | O_TRUNC
    int 0x80
    cmp eax, -1
    je .nofile
    mov [fd], eax
.get:
    mov esi, [url]
    mov edi, sink
    call http_get
    mov [status], eax
    cmp byte [toscreen], 0
    jne .report
    mov eax, SYS_CLOSE
    mov ebx, [fd]
    int 0x80
    mov eax, [status]               ; keep the file only for a 2xx answer
    cmp eax, 200
    jl .drop
    cmp eax, 300
    jl .report
.drop:
    mov eax, SYS_DELETE
    mov ebx, fname
    int 0x80
.report:
    mov eax, [status]
    test eax, eax
    js error
    mov edi, line
    mov esi, m_wget
    call cat
    mov eax, [status]
    call net_utoa
    mov esi, m_comma
    call cat
    mov eax, [http_got]
    call net_utoa
    mov esi, m_bytes
    call cat
    mov eax, [sum]
    call net_utoa
    cmp byte [toscreen], 0
    jne .nl
    cmp dword [status], 200
    jl .nl
    cmp dword [status], 300
    jge .nl
    mov esi, m_arrow
    call cat
    mov esi, fname
    call cat
.nl:
    mov word [edi], 10
    mov eax, SYS_PUTS
    mov ebx, line
    int 0x80
    mov eax, [status]               ; exit 0 for 2xx, 1 otherwise
    cmp eax, 200
    jl .one
    cmp eax, 300
    jge .one
    xor eax, eax
    ret
.one:
    mov eax, 1
    ret
.nofile:
    mov ebx, m_nofile
    jmp say_fail

usage:
    mov ebx, m_usage
say_fail:
    mov eax, SYS_PUTS
    int 0x80
    mov eax, 1
    ret

; eax = HTTP_E* -> its message
error:
    neg eax
    dec eax
    mov ebx, [errs + eax * 4]
    jmp say_fail

; The callback: esi = bytes, ecx = count. Adds them to the sum, then
; writes them to the file or the screen.
sink:
    push ecx
    push esi
    xor eax, eax
    mov edx, [sum]
.s:
    lodsb
    add edx, eax
    loop .s
    and edx, 0xFFFF
    mov [sum], edx
    pop esi
    pop ecx
    cmp byte [toscreen], 0
    jne .screen
    mov eax, SYS_WRITE
    mov ebx, [fd]
    mov edx, ecx
    mov ecx, esi
    int 0x80
    cmp eax, edx
    jne .full
    clc
    ret
.full:
    mov byte [diskfull], 1
    stc
    ret
.screen:
    lodsb
    cmp al, 13
    je .n
    movzx ebx, al
    mov eax, SYS_PUTC
    push ecx
    push esi
    int 0x80
    pop esi
    pop ecx
.n:
    loop .screen
    clc
    ret

; fname = the URL's last path part, cut to NAMEMAX; index.htm when empty
name_from_url:
    mov esi, [url]
    mov edi, http_scheme            ; skip "http://" and the host
    call http_prefixi
    jne .h
    add esi, 7
.h:
    cmp byte [esi], 0
    je .index
    cmp byte [esi], '/'
    je .path
    inc esi
    jmp .h
.path:
    mov ebx, esi                    ; after the last '/', before any '?'
.p:
    mov al, [esi]
    test al, al
    jz .last
    cmp al, '?'
    je .last
    cmp al, '/'
    jne .pn
    lea ebx, [esi + 1]
.pn:
    inc esi
    jmp .p
.last:
    mov esi, ebx
    mov edi, fname
    mov ecx, NAMEMAX
.c:
    lodsb
    test al, al
    jz .end
    cmp al, '?'
    je .end
    stosb
    loop .c
.end:
    mov byte [edi], 0
    cmp edi, fname
    jne .r
.index:
    mov esi, m_index
    mov edi, fname
    call cat
    mov byte [edi], 0
.r:
    ret

; esi = ASCIIZ -> copied to edi, edi at the copy's end (no zero written)
cat:
    lodsb
    test al, al
    jz .r
    stosb
    jmp cat
.r:
    ret

m_usage     db 'Usage: run wget <url> [file|-]', 10, 0
m_nofile    db 'wget: cannot create the file', 10, 0
m_wget      db 'wget: ', 0
m_comma     db ', ', 0
m_bytes     db ' bytes, sum ', 0
m_arrow     db ' -> ', 0
m_index     db 'index.htm', 0
e_url       db 'wget: not an http:// URL', 10, 0
e_host      db 'wget: host not found', 10, 0
e_conn      db 'wget: no connection', 10, 0
e_proto     db 'wget: the reply broke off', 10, 0
e_loop      db 'wget: too many redirects', 10, 0
e_stop      db 'wget: disk full', 10, 0
align 4
errs        dd e_url, e_host, e_conn, e_proto, e_loop, e_stop

SQX_BSS
url         resd 1
fd          resd 1
status      resd 1
sum         resd 1
toscreen    resb 1
diskfull    resb 1
fname       resb NAMEMAX + 1
line        resb 128
HTTP_BSS
SQX_END
