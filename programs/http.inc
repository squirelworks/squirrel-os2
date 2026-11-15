; Squirrel-OS/2 — HTTP/1.1 client library for programs (3.0)
; Original code, from RFC 9110 / RFC 9112. Include after net.inc:
;
;     %include "sqx.inc"
;     SQX_HEADER main
;     %include "net.inc"
;     %include "http.inc"
;     ...
;     SQX_BSS
;     HTTP_BSS
;     SQX_END
;
; http_get fetches a URL over the kernel's TCP connection (SYS_NET):
;   http://host[:port][/path]   (the scheme may be left out; no https)
; It sends a GET with Host, User-Agent and "Connection: close", reads the
; status line and headers, follows up to HTTP_HOPS redirects (301, 302,
; 303, 307, 308 with a Location), and hands the body to a callback as it
; arrives: Content-Length bodies, chunked bodies (chunk extensions and
; trailers are read past), or everything until the server closes.
; See documentation/apps/network.md.

HTTP_HOPS   equ 4
HTTP_LINE   equ 512             ; the longest header line kept (longer ones are cut)
HTTP_RBUF   equ 2048
HTTP_HOSTMAX equ 63
HTTP_PATHMAX equ 255

HTTP_EURL   equ -1              ; not a URL we can fetch
HTTP_EHOST  equ -2              ; the name was not found
HTTP_ECONN  equ -3              ; no connection, or the request was not taken
HTTP_EPROTO equ -4              ; the reply was not HTTP, or it broke off
HTTP_ELOOP  equ -5              ; too many redirects
HTTP_ESTOP  equ -6              ; the callback asked to stop

; esi = URL, edi = callback: called with esi = bytes, ecx = how many
; (never 0); it may change any register but must return CF clear, or
; CF set to stop. -> eax = the final status code (100..599), or HTTP_E*.
; http_status, http_clen (Content-Length or -1), http_got (body bytes
; handed over) describe the last response.
http_get:
    mov [http_cb], edi
    mov dword [http_hops], 0
    call http_parse_url
    jc .badurl
.again:
    call http_once
    cmp eax, 301
    je .redir
    cmp eax, 302
    je .redir
    cmp eax, 303
    je .redir
    cmp eax, 307
    je .redir
    cmp eax, 308
    jne .r
.redir:
    cmp byte [http_loc], 0
    je .r                       ; no Location: the 3xx is the answer
    inc dword [http_hops]
    cmp dword [http_hops], HTTP_HOPS
    ja .loop
    mov esi, http_loc
    cmp byte [esi], '/'
    jne .abs
    call http_set_path          ; same host and port
    jc .badurl
    jmp .again
.abs:
    call http_parse_url
    jc .badurl
    jmp .again
.loop:
    mov eax, HTTP_ELOOP
.r:
    ret
.badurl:
    mov eax, HTTP_EURL
    ret

; esi = URL -> http_host, http_port, http_path; CF if it is not one
http_parse_url:
    push esi
    mov edi, http_scheme
    call http_prefixi
    jne .noscheme
    add esi, 7                  ; "http://"
    jmp .host
.noscheme:
    mov edi, http_scheme_s      ; "https://": we cannot
    call http_prefixi
    je .bad
.host:
    mov edi, http_host
    xor ecx, ecx
.hc:
    mov al, [esi]
    test al, al
    jz .hend
    cmp al, '/'
    je .hend
    cmp al, ':'
    je .hend
    cmp al, ' '
    jbe .bad
    cmp ecx, HTTP_HOSTMAX
    jae .bad
    stosb
    inc esi
    inc ecx
    jmp .hc
.hend:
    test ecx, ecx
    jz .bad
    mov byte [edi], 0
    mov dword [http_port], 80
    cmp byte [esi], ':'
    jne .path
    inc esi
    xor eax, eax
    xor ecx, ecx
.pd:
    movzx edx, byte [esi]
    sub edx, '0'
    cmp edx, 9
    ja .pend
    imul eax, eax, 10
    add eax, edx
    cmp eax, 65535
    ja .bad
    inc esi
    inc ecx
    jmp .pd
.pend:
    test ecx, ecx
    jz .bad
    test eax, eax
    jz .bad
    mov [http_port], eax
.path:
    cmp byte [esi], 0
    jne .p
    mov esi, http_slash
.p:
    cmp byte [esi], '/'
    jne .bad
    call http_set_path
    jc .bad
    pop esi
    clc
    ret
.bad:
    pop esi
    stc
    ret

; esi = path starting with '/' -> http_path, CF if too long or not printable
http_set_path:
    push esi
    mov edi, http_path
    xor ecx, ecx
.c:
    lodsb
    test al, al
    jz .end
    cmp al, ' '
    jbe .bad
    cmp ecx, HTTP_PATHMAX
    jae .bad
    stosb
    inc ecx
    jmp .c
.end:
    stosb
    pop esi
    clc
    ret
.bad:
    pop esi
    stc
    ret

; esi = text, edi = lower-case prefix -> ZF set if text starts with it
; (letters in any case). Keeps registers.
http_prefixi:
    push eax
    push esi
    push edi
.l:
    mov ah, [edi]
    test ah, ah
    jz .yes
    mov al, [esi]
    call http_lower
    cmp al, ah
    jne .no
    inc esi
    inc edi
    jmp .l
.yes:
    xor eax, eax                ; ZF
.no:
    pop edi
    pop esi
    pop eax
    ret

http_lower:
    cmp al, 'A'
    jb .r
    cmp al, 'Z'
    ja .r
    add al, 32
.r:
    ret

; One request to http_host:http_port for http_path -> eax = status or HTTP_E*.
http_once:
    mov dword [http_status], 0
    mov dword [http_clen], -1
    mov dword [http_got], 0
    mov byte [http_chunked], 0
    mov byte [http_loc], 0
    mov dword [http_rpos], 0
    mov dword [http_rend], 0
    mov byte [http_eof], 0
    mov eax, SYS_NET
    mov ebx, NET_RESOLVE
    mov ecx, http_host
    int 0x80
    cmp eax, -1
    jne .addr
    mov eax, HTTP_EHOST
    ret
.addr:
    mov ecx, eax
    mov eax, SYS_NET
    mov ebx, NET_CONNECT
    mov edx, [http_port]
    int 0x80
    test eax, eax
    jz .conn
    mov eax, HTTP_ECONN
    ret
.conn:
    call http_request           ; ecx = its length
    mov eax, SYS_NET
    mov ebx, NET_SEND
    mov edx, ecx
    mov ecx, http_req
    int 0x80
    cmp eax, edx
    je .sent
    mov eax, HTTP_ECONN
    jmp .close
.sent:
    call http_status_line
    jc .proto
.hdr:
    call http_readline
    jc .proto
    cmp byte [http_lbuf], 0
    je .body
    call http_header
    jmp .hdr
.body:
    mov eax, [http_status]
    cmp eax, 200                ; 1xx, 204 and 304 have no body; a 3xx
    jb .done                    ; we follow is not read either
    cmp eax, 204
    je .done
    cmp eax, 304
    je .done
    cmp eax, 300
    jb .read
    cmp eax, 400
    jae .read
    cmp byte [http_loc], 0
    jne .done
.read:
    cmp byte [http_chunked], 0
    jne .chunked
    mov ecx, [http_clen]
    cmp ecx, -1
    je .toclose
    call http_body_n
    jc .bodyerr
    jmp .done
.toclose:
    call http_body_n            ; ecx = -1: until the server closes
    jnc .done
    cmp byte [http_eof], 0      ; the end of the stream is the end here
    jne .done
    jmp .bodyerr
.chunked:
    call http_readline
    jc .proto
    mov esi, http_lbuf
    call http_hex               ; ecx = chunk size
    jc .proto
    test ecx, ecx
    jz .trailer
    call http_body_n
    jc .bodyerr
    call http_readline          ; the CRLF after the data
    jc .proto
    jmp .chunked
.trailer:
    call http_readline
    jc .done                    ; a server may close without the last CRLF
    cmp byte [http_lbuf], 0
    jne .trailer
.done:
    mov eax, [http_status]
    jmp .close
.bodyerr:
    mov eax, HTTP_ESTOP
    cmp byte [http_stopped], 0
    jne .close
.proto:
    mov eax, HTTP_EPROTO
.close:
    push eax
    mov eax, SYS_NET
    mov ebx, NET_CLOSE
    int 0x80
    pop eax
    ret

; Writes the request into http_req -> ecx = its length
http_request:
    mov edi, http_req
    mov esi, http_r_get
    call http_cat
    mov esi, http_path
    call http_cat
    mov esi, http_r_host
    call http_cat
    mov esi, http_host
    call http_cat
    cmp dword [http_port], 80
    je .ua
    mov byte [edi], ':'
    inc edi
    mov eax, [http_port]
    call net_utoa
.ua:
    mov esi, http_r_tail
    call http_cat
    mov ecx, edi
    sub ecx, http_req
    ret

; esi = ASCIIZ -> copied to edi (without the zero), edi advanced
http_cat:
    lodsb
    test al, al
    jz .r
    stosb
    jmp http_cat
.r:
    ret

; -> al = the next byte of the reply, CF at the end (http_eof set) or on
; a receive error
http_byte:
    mov eax, [http_rpos]
    cmp eax, [http_rend]
    jb .have
    call http_fill
    jc .r
    mov eax, [http_rpos]
.have:
    inc dword [http_rpos]
    mov al, [http_rbuf + eax]
    clc
.r:
    ret

; Refill http_rbuf -> CF at the end of the stream (http_eof = 1), or when
; nothing came for a long time
http_fill:
    push ebx
    push ecx
    push edx
    mov dword [http_rpos], 0
    mov dword [http_rend], 0
    cmp byte [http_eof], 0
    jne .end
    mov ebx, 5                  ; NET_RECV waits three seconds; five of those
.again:
    push ebx
    mov eax, SYS_NET
    mov ebx, NET_RECV
    mov ecx, http_rbuf
    mov edx, HTTP_RBUF
    int 0x80
    pop ebx
    cmp eax, -2
    jne .got
    dec ebx
    jnz .again
    jmp .fail
.got:
    test eax, eax
    jz .closed
    js .fail
    mov [http_rend], eax
    pop edx
    pop ecx
    pop ebx
    clc
    ret
.closed:
    mov byte [http_eof], 1
.end:
.fail:
    pop edx
    pop ecx
    pop ebx
    stc
    ret

; Reads one line without its CR LF into http_lbuf (cut to HTTP_LINE - 1)
; -> CF if the stream ended before a line feed
http_readline:
    mov edi, http_lbuf
    xor ecx, ecx
.c:
    call http_byte
    jc .r
    cmp al, 10
    je .end
    cmp al, 13
    je .c
    cmp ecx, HTTP_LINE - 1
    jae .c
    mov [edi + ecx], al
    inc ecx
    jmp .c
.end:
    mov byte [edi + ecx], 0
    clc
.r:
    ret

; "HTTP/1.x NNN reason" -> http_status, CF if it is not that
http_status_line:
    call http_readline
    jc .r
    mov esi, http_lbuf
    mov edi, http_v
    call http_prefixi
    jne .bad
    add esi, 5
.v:                             ; the version: digits and a dot
    lodsb
    cmp al, ' '
    je .code
    test al, al
    jz .bad
    jmp .v
.code:
    xor eax, eax
    mov ecx, 3
.d:
    movzx edx, byte [esi]
    sub edx, '0'
    cmp edx, 9
    ja .bad
    imul eax, eax, 10
    add eax, edx
    inc esi
    loop .d
    cmp eax, 100
    jb .bad
    cmp eax, 599
    ja .bad
    mov [http_status], eax
    clc
    ret
.bad:
    stc
.r:
    ret

; A header line in http_lbuf: Content-Length, Transfer-Encoding: chunked,
; Location are kept; the rest is ignored.
http_header:
    mov esi, http_lbuf
    mov edi, http_h_len
    call http_prefixi
    jne .te
    add esi, http_h_len_end - http_h_len - 1
    call http_skipsp
    xor eax, eax
    xor ecx, ecx
.d:
    movzx edx, byte [esi]
    sub edx, '0'
    cmp edx, 9
    ja .dend
    imul eax, eax, 10
    add eax, edx
    inc esi
    inc ecx
    jmp .d
.dend:
    test ecx, ecx
    jz .r
    mov [http_clen], eax
    ret
.te:
    mov edi, http_h_te
    call http_prefixi
    jne .loc
.find:                          ; "chunked" anywhere in the value
    cmp byte [esi], 0
    je .r
    mov edi, http_chunk_word
    call http_prefixi
    je .ch
    inc esi
    jmp .find
.ch:
    mov byte [http_chunked], 1
    ret
.loc:
    mov edi, http_h_loc
    call http_prefixi
    jne .r
    add esi, http_h_loc_end - http_h_loc - 1
    call http_skipsp
    mov edi, http_loc
    mov ecx, HTTP_PATHMAX + HTTP_HOSTMAX + 16
.lc:
    lodsb
    cmp al, ' '
    jbe .le
    stosb
    loop .lc
.le:
    mov byte [edi], 0
.r:
    ret

http_skipsp:
    cmp byte [esi], ' '
    jne .r
    inc esi
    jmp http_skipsp
.r:
    ret

; esi = hex digits (a chunk-size line) -> ecx, CF if there are none.
; Stops at ';' (an extension), a space or the end.
http_hex:
    xor ecx, ecx
    xor edx, edx                ; digits seen
.d:
    movzx eax, byte [esi]
    call http_lower
    sub eax, '0'
    cmp eax, 9
    jbe .add
    sub eax, 'a' - '0'
    cmp eax, 5
    ja .end
    add eax, 10
.add:
    cmp ecx, 0x0FFFFFFF
    ja .bad
    shl ecx, 4
    add ecx, eax
    inc esi
    inc edx
    jmp .d
.end:
    test edx, edx
    jz .bad
    clc
    ret
.bad:
    stc
    ret

; ecx = bytes of body to hand to the callback (-1: until the end).
; -> CF if the stream ended first (http_eof) or the callback said stop
; (http_stopped).
http_body_n:
    mov byte [http_stopped], 0
    mov [http_left], ecx
.l:
    cmp dword [http_left], 0
    je .ok
    mov eax, [http_rpos]
    cmp eax, [http_rend]
    jb .have
    call http_fill
    jc .r
.have:
    mov ecx, [http_rend]
    sub ecx, [http_rpos]
    cmp ecx, [http_left]
    jbe .n
    mov ecx, [http_left]
.n:
    mov esi, [http_rpos]
    add esi, http_rbuf
    add [http_rpos], ecx
    cmp dword [http_left], -1
    je .nocount
    sub [http_left], ecx
.nocount:
    add [http_got], ecx
    call [http_cb]
    jnc .l
    mov byte [http_stopped], 1
    stc
.r:
    ret
.ok:
    clc
    ret

http_scheme db 'http://', 0
http_scheme_s db 'https://', 0
http_slash db '/', 0
http_v      db 'http/', 0
http_h_len  db 'content-length:', 0
http_h_len_end:
http_h_te   db 'transfer-encoding:', 0
http_h_loc  db 'location:', 0
http_h_loc_end:
http_chunk_word db 'chunked', 0
http_r_get  db 'GET ', 0
http_r_host db ' HTTP/1.1', 13, 10, 'Host: ', 0
http_r_tail db 13, 10, 'User-Agent: SquirrelOS2-wget/3.0', 13, 10
            db 'Accept: */*', 13, 10, 'Connection: close', 13, 10, 13, 10, 0

%macro HTTP_BSS 0
alignb 4
http_cb     resd 1
http_hops   resd 1
http_port   resd 1
http_status resd 1
http_clen   resd 1
http_got    resd 1
http_left   resd 1
http_rpos   resd 1
http_rend   resd 1
http_chunked resb 1
http_eof    resb 1
http_stopped resb 1
http_host   resb HTTP_HOSTMAX + 1
http_path   resb HTTP_PATHMAX + 1
http_loc    resb HTTP_PATHMAX + HTTP_HOSTMAX + 20
http_lbuf   resb HTTP_LINE
http_req    resb HTTP_PATHMAX + HTTP_HOSTMAX + 160
alignb 4
http_rbuf   resb HTTP_RBUF
%endmacro
