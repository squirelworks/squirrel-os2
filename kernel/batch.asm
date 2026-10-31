; Squirrel-OS/2 — batch files (0.5.2)
; Included from pm.asm. Original code.
;
; "batch <file>" (or "run <file>.bat") queues a script; the shell runs
; its lines one by one once the current command line has finished, so a
; script line may itself use pipes and redirection. Lines starting with
; # are comments, @ hides the echo of a line, Esc between lines stops
; the script. A script that starts another one hands over to it.
; autoexec.bat runs at boot when the data disk has one.
; See documentation/kernel/shell.md.

BAT_BUF     equ KSCRATCH+0x3000     ; 4 KB script text
BAT_MAX     equ 0x1000

; esi = file name: loads it as the pending script (message if missing)
bat_start:
    cmp byte [fs_mounted], 0
    je .missing
    push esi
    xor ecx, ecx
    call fs_open
    pop esi
    cmp eax, -1
    je .missing
    mov ebx, eax
    mov edi, BAT_BUF
    mov ecx, BAT_MAX-1
    call fs_read
    mov edx, eax
    call fs_close
    cmp edx, -1
    je .missing
    mov byte [BAT_BUF+edx], 0
    mov dword [bat_pos], BAT_BUF
    mov byte [bat_active], 1
    ret
.missing:
    cmp byte [bat_quiet], 0
    jne .r
    push esi
    mov esi, sh_m_nofile
    call puts
    pop esi
    call puts
    mov al, 10
    call putc
.r:
    ret

; batch <file>
cmd_batch_run:
    jmp bat_start

; Runs the queued script, if any, line by line.
bat_run_pending:
    cmp byte [bat_active], 0
    je .r
.line:
    mov esi, [bat_pos]
    cmp byte [esi], 0
    je .end
    ; copy one line, dropping CR, cut at SH_LINE-8 characters
    mov edi, bat_line
    xor ecx, ecx
.c:
    lodsb
    test al, al
    jz .eol0
    cmp al, 10
    je .eol
    cmp al, 13
    je .c
    cmp ecx, SH_LINE-8
    jae .c
    mov [edi+ecx], al
    inc ecx
    jmp .c
.eol0:
    dec esi                     ; stay on the terminator
.eol:
    mov byte [edi+ecx], 0
    mov [bat_pos], esi
    ; Esc waiting in the keyboard queue stops the script
    call bat_esc_pending
    jc .stopped
    mov esi, bat_line
    call sh_trim
    mov al, [esi]
    test al, al
    jz .line
    cmp al, '#'
    je .line
    cmp al, '@'
    je .quiet
    push esi
    mov esi, [lstr+LS_PROMPT*4]
    call puts
    pop esi
    push esi
    call puts
    pop esi
    mov al, 10
    call putc
    jmp .run
.quiet:
    inc esi
.run:
    call sh_run_line
    cmp byte [bat_active], 0
    jne .line
    ret
.stopped:
    mov esi, bat_m_stopped
    call puts
.end:
    mov byte [bat_active], 0
.r:
    ret

; CF set (and the key taken) when the next queued key is Esc
bat_esc_pending:
    cli
    mov ebx, [kbd_tail]
    cmp ebx, [kbd_head]
    je .no
    cmp byte [kbd_ring+ebx], 0x01
    jne .no
    call kbd_dequeue
    sti
    stc
    ret
.no:
    sti
    clc
    ret

; At boot: runs autoexec.bat silently skipping it when absent.
bat_autoexec:
    mov byte [bat_quiet], 1
    mov esi, bat_autoname
    call bat_start
    mov byte [bat_quiet], 0
    jmp bat_run_pending

bat_autoname db 'autoexec.bat', 0
bat_m_stopped db 'Batch stopped', 10, 0
bat_active db 0
bat_quiet db 0
align 4
bat_pos dd 0
bat_line times SH_LINE db 0
