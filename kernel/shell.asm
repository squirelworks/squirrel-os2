; Squirrel-OS/2 — shell pipelines and redirection (0.5.0)
; Included from pm.asm. Original code.
;
;   cmd > file    output to a file (replaced)      cmd >> file  appended
;   cmd < file    input from a file                a | b | c    pipes
;
; Each stage runs to completion before the next starts. A stage's output
; is captured in memory (32 KB) by the console's putc; the next stage
; reads it as its input through SYS_GETC (and the calculators' line
; reader). Two buffers alternate, so pipelines can be any length.
; See documentation/kernel/shell.md.

SH_BUF0     equ 0x60000
SH_BUF1     equ 0x68000
SH_BUFMAX   equ 0x8000
SH_LINE     equ 128

; Runs the command line in cmdline, then shows the prompt again.
do_command:
    mov esi, cmdline
    mov edi, sh_line
    mov ecx, SH_LINE-1
.copy:
    lodsb
    stosb
    test al, al
    jz .copied
    loop .copy
    mov byte [edi], 0
.copied:
    mov dword [sh_stage], 0
    mov dword [sh_inlen], -1    ; no piped input for the first stage
    mov esi, sh_line
.stage:
    ; cut this stage at the next '|'
    mov [sh_seg], esi
    mov byte [sh_last], 1
.find:
    mov al, [esi]
    test al, al
    jz .cut
    cmp al, '|'
    je .pipe
    inc esi
    jmp .find
.pipe:
    mov byte [esi], 0
    inc esi
    mov byte [sh_last], 0
.cut:
    mov [sh_next], esi
    mov esi, [sh_seg]
    call sh_redirs
    jc .badredir
    call sh_trim                ; esi = command text
    cmp byte [esi], 0
    je .empty_stage
    mov [sh_seg], esi
    ; input: a file named with '<', else the previous stage's output
    mov eax, [sh_stage]
    inc eax
    and eax, 1
    shl eax, 15
    add eax, SH_BUF0            ; the buffer this stage reads
    mov [in_ptr], eax
    cmp byte [sh_inname], 0
    je .piped
    call sh_load_input
    jc .done
    jmp .inon
.piped:
    mov ecx, [sh_inlen]
    cmp ecx, -1
    je .noin
.inon:
    add ecx, [in_ptr]
    mov [in_end], ecx
    mov byte [in_on], 1
.noin:
    ; output: captured unless this is the last stage without '>'
    mov eax, [sh_stage]
    and eax, 1
    shl eax, 15
    add eax, SH_BUF0
    mov [cap_base], eax
    mov dword [cap_len], 0
    mov dword [cap_col], 0
    mov byte [cap_over], 0
    cmp byte [sh_last], 0
    je .capture
    cmp byte [sh_outname], 0
    je .run
.capture:
    mov byte [cap_on], 1
.run:
    mov esi, [sh_seg]
    call run_simple
    mov byte [cap_on], 0
    mov byte [in_on], 0
    cmp byte [cap_over], 0
    je .fitted
    mov esi, sh_m_trunc
    call puts
.fitted:
    cmp byte [sh_outname], 0
    je .nofile
    call sh_save_output
    jc .done
    mov dword [sh_inlen], 0     ; a stage after '>' gets empty input
    jmp .advance
.nofile:
    mov eax, [cap_len]
    mov [sh_inlen], eax
.advance:
    cmp byte [sh_last], 0
    jne .done
    inc dword [sh_stage]
    mov esi, [sh_next]
    jmp .stage
.badredir:
    mov esi, sh_m_redir
    call puts
    jmp .done
.empty_stage:
    ; a blank line is fine; an empty side of a pipe is not
    cmp dword [sh_stage], 0
    jne .emptypipe
    cmp byte [sh_last], 0
    jne .done
.emptypipe:
    mov esi, sh_m_pipe
    call puts
.done:
    mov byte [cap_on], 0
    mov byte [in_on], 0
    mov esi, prompt
    call puts
    mov byte [cmdline], 0
    mov dword [cmdpos], 0
    ret

; esi = stage text: removes "< name", "> name" and ">> name", copying
; the names to sh_inname / sh_outname (sh_append set for >>).
; CF when a redirection has no file name.
sh_redirs:
    mov byte [sh_inname], 0
    mov byte [sh_outname], 0
    mov byte [sh_append], 0
    mov edi, esi
.scan:
    mov al, [edi]
    test al, al
    jz .ok
    cmp al, '<'
    je .in
    cmp al, '>'
    je .out
    inc edi
    jmp .scan
.in:
    mov byte [edi], 0
    inc edi
    mov edx, sh_inname
    jmp .name
.out:
    mov byte [edi], 0
    inc edi
    mov edx, sh_outname
    cmp byte [edi], '>'
    jne .name
    mov byte [sh_append], 1
    inc edi
.name:
    cmp byte [edi], ' '
    jne .first
    inc edi
    jmp .name
.first:
    xor ecx, ecx
.nc:
    mov al, [edi]
    test al, al
    jz .ndone
    cmp al, ' '
    je .ndone
    cmp al, '<'
    je .ndone
    cmp al, '>'
    je .ndone
    cmp ecx, FS_NAMELEN-1
    jae .skip
    mov [edx+ecx], al
    inc ecx
.skip:
    inc edi
    jmp .nc
.ndone:
    mov byte [edx+ecx], 0
    test ecx, ecx
    jnz .scan
    stc
    ret
.ok:
    clc
    ret

; esi = text -> esi past leading spaces, trailing spaces removed
sh_trim:
    cmp byte [esi], ' '
    jne .end
    inc esi
    jmp sh_trim
.end:
    push eax
    call strlen
.t:
    test eax, eax
    jz .r
    cmp byte [esi+eax-1], ' '
    jne .r
    dec eax
    mov byte [esi+eax], 0
    jmp .t
.r:
    pop eax
    ret

; reads sh_inname into [in_ptr] -> ecx = length, CF (message shown) on error
sh_load_input:
    cmp byte [fs_mounted], 0
    je .missing
    mov esi, sh_inname
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .missing
    mov ebx, eax
    mov edi, [in_ptr]
    mov ecx, SH_BUFMAX
    call fs_read
    mov edx, eax
    call fs_close
    cmp edx, -1
    je .missing
    mov ecx, edx
    clc
    ret
.missing:
    mov esi, sh_m_nofile
    call puts
    mov esi, sh_inname
    call puts
    mov al, 10
    call putc
    stc
    ret

; writes the captured output to sh_outname; CF (message shown) on error
sh_save_output:
    cmp byte [fs_mounted], 0
    je .err
    mov esi, sh_outname
    mov ecx, O_CREATE|O_TRUNC
    cmp byte [sh_append], 0
    je .open
    mov ecx, O_CREATE|O_APPEND
.open:
    call fs_open
    cmp eax, -1
    je .err
    mov ebx, eax
    mov esi, [cap_base]
    mov ecx, [cap_len]
    call fs_write
    mov edx, eax
    call fs_close
    cmp edx, [cap_len]
    jne .err
    clc
    ret
.err:
    mov esi, sh_m_wfail
    call puts
    mov esi, sh_outname
    call puts
    mov al, 10
    call putc
    stc
    ret

; putc's capture path: al = char; preserves all registers
cap_putc:
    push ebx
    inc dword [cap_col]
    cmp al, 10
    jne .notnl
    mov dword [cap_col], 0
.notnl:
    mov ebx, [cap_len]
    cmp al, 8
    je .bs
    cmp ebx, SH_BUFMAX
    jae .over
    add ebx, [cap_base]
    mov [ebx], al
    inc dword [cap_len]
    pop ebx
    ret
.bs:
    sub dword [cap_col], 2
    jns .bsok
    mov dword [cap_col], 0
.bsok:
    test ebx, ebx
    jz .r
    dec dword [cap_len]
.r:
    pop ebx
    ret
.over:
    mov byte [cap_over], 1
    pop ebx
    ret

; -> eax = column the next character lands in (screen or captured text)
con_column:
    cmp byte [cap_on], 0
    jne .cap
    push edx
    push ebx
    mov eax, [cur]
    xor edx, edx
    mov ebx, 80
    div ebx
    mov eax, edx
    pop ebx
    pop edx
    ret
.cap:
    mov eax, [cap_col]
    ret

; next redirected input byte -> eax, or -1 at the end
in_getc:
    push esi
    mov esi, [in_ptr]
    cmp esi, [in_end]
    jae .eof
    movzx eax, byte [esi]
    inc dword [in_ptr]
    pop esi
    ret
.eof:
    mov eax, -1
    pop esi
    ret

; An app returning to the shell: clear the screen and show the banner,
; unless its output is being captured (then nothing is added).
app_home:
    cmp byte [cap_on], 0
    jne .r
    call cls
    push esi
    mov esi, banner
    call puts
    pop esi
.r:
    ret

; echo <text>
cmd_echo_run:
    call puts
    mov al, 10
    jmp putc

sh_m_redir db 'Redirection needs a file name', 10, 0
sh_m_pipe db 'A pipe needs a command on both sides', 10, 0
sh_m_nofile db 'Cannot read ', 0
sh_m_wfail db 'Cannot write ', 0
sh_m_trunc db '(output cut at 32 KB)', 10, 0

cap_on db 0
cap_over db 0
in_on db 0
sh_last db 0
sh_append db 0
align 4
cap_base dd 0
cap_len dd 0
cap_col dd 0
in_ptr dd 0
in_end dd 0
sh_stage dd 0
sh_inlen dd 0
sh_seg dd 0
sh_next dd 0
sh_inname times 16 db 0         ; FS_NAMELEN
sh_outname times 16 db 0
sh_line times SH_LINE db 0
