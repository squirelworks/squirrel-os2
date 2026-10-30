; Squirrel-OS/2 — in-memory FS + apps
; Commands: ls, cat <name>, run <name>
; Editors: edit (normal), vedit (verbose) — basic buffer + insert
; Syscalls (0.1.1): int 0x80 gate, see syscall.asm; test with systest / keys
; Original code.
BITS 16
ORG 0x8000

; Memory map (see documentation/kernel/memory-map.md)
KSCRATCH equ 0x20000            ; 64 KB kernel scratch (driver/FS buffers)
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

    ; IDT (timer + keyboard)
    mov edi, idt
    mov ecx, 256
.fill:
    mov eax, default_isr
    call set_gate
    add edi, 8
    loop .fill
    ; CPU exceptions 0..31 report and halt instead of looping
    mov edi, idt
    mov esi, exc_stubs
    mov ecx, 32
.exc:
    mov eax, esi
    call set_gate
    add edi, 8
    add esi, EXC_STUB_SIZE
    loop .exc
    mov edi, idt+0x20*8
    mov eax, timer_isr
    call set_gate
    mov edi, idt+0x21*8
    mov eax, kbd_isr
    call set_gate
    call syscall_init
    lidt [idt_desc]
    call proc_init
    call ata_init

    ; PIC + PIT
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
    mov esi, prompt
    call puts
    sti

.cmdloop:
    ; keyboard IRQ only queues scancodes; they are handled here, outside
    ; interrupt context, so commands may block in syscalls such as getc
    cli
    call kbd_dequeue
    jnc .key
    sti
    call proc_idle
    jmp .cmdloop
.key:
    sti
    call kbd_dispatch
    jmp .cmdloop

; ---------- file system ----------
; Flat table: name (8 bytes), data ptr, length
fs_list:
    mov esi, fs_header
    call puts
    mov ecx, [file_count]
    mov ebx, file_table
.l:
    mov esi, ebx
    call puts
    mov al, 10
    call putc
    add ebx, 16
    loop .l
    ret

fs_cat:                       ; esi = name
    call fs_find
    test eax, eax
    jz .nf
    mov esi, [eax+8]          ; data ptr
    call puts
    ret
.nf:
    mov esi, notfound
    call puts
    ret

fs_find:                      ; esi = name, returns eax = entry or 0
    push ecx
    push ebx
    mov ecx, [file_count]
    mov ebx, file_table
.s:
    push esi
    push ebx
    mov edi, ebx
    mov ecx, 8
    repe cmpsb
    pop ebx
    pop esi
    je .found
    add ebx, 16
    loop .s
    xor eax, eax
    jmp .out
.found:
    mov eax, ebx
.out:
    pop ebx
    pop ecx
    ret

; ---------- apps ----------
run_calc:
    mov byte [calc_mode], 1
    call cls
    mov esi, calc_banner
    call puts
    mov esi, calc_help
    call puts
    mov dword [calc_len], 0
    mov byte [calc_buf], 0
    mov esi, calc_prompt
    call puts
    ret

run_sci:
    mov esi, sci_banner
    call puts
    mov esi, sci_stub
    call puts
    ret

run_graph:
    mov esi, graph_banner
    call puts
    mov esi, graph_stub
    call puts
    ret

run_matrix:
    mov esi, matrix_banner
    call puts
    mov esi, matrix_stub
    call puts
    ret

run_diff:
    mov esi, diff_banner
    call puts
    mov esi, diff_stub
    call puts
    ret

run_topo:
    mov esi, topo_banner
    call puts
    mov esi, topo_stub
    call puts
    ret

; ---------- basic calculator evaluator ----------
; Expects expression in calc_buf of length calc_len
; Supports: number op number   where op is + - * / %
; % means percent of first number: a % b  => a * b / 100
calc_eval:
    push eax
    push ebx
    push ecx
    push edx
    push esi
    ; simple parse: skip leading spaces, atoi, skip spaces, get op, skip spaces, atoi
    mov esi, calc_buf
    mov ecx, [calc_len]
    ; skip spaces
.skip1:
    cmp ecx, 0
    je .err
    cmp byte [esi], ' '
    jne .num1
    inc esi
    dec ecx
    jmp .skip1
.num1:
    call atoi
    mov ebx, eax          ; first number in ebx
    ; skip spaces
.skip2:
    cmp ecx, 0
    je .err
    cmp byte [esi], ' '
    jne .op
    inc esi
    dec ecx
    jmp .skip2
.op:
    mov al, [esi]
    mov byte [calc_op], al
    inc esi
    dec ecx
    ; skip spaces
.skip3:
    cmp ecx, 0
    je .err
    cmp byte [esi], ' '
    jne .num2
    inc esi
    dec ecx
    jmp .skip3
.num2:
    call atoi
    mov edx, eax          ; second number
    ; compute
    mov al, [calc_op]
    cmp al, '+'
    je .add
    cmp al, '-'
    je .sub
    cmp al, '*'
    je .mul
    cmp al, '/'
    je .div
    cmp al, '%'
    je .pct
    jmp .err
.add:
    add ebx, edx
    jmp .print
.sub:
    sub ebx, edx
    jmp .print
.mul:
    mov eax, ebx
    imul edx
    mov ebx, eax
    jmp .print
.div:
    test edx, edx
    jz .div0
    mov ecx, edx              ; cdq overwrites edx
    mov eax, ebx
    cdq
    idiv ecx
    mov ebx, eax
    jmp .print
.pct:
    ; a % b = a * b / 100
    mov eax, ebx
    imul edx
    mov ebx, 100
    cdq
    idiv ebx
    mov ebx, eax
    jmp .print
.print:
    mov esi, calc_result_prefix
    call puts
    mov eax, ebx
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    jmp .done
.div0:
    mov esi, div0_msg
    call puts
    jmp .done
.err:
    mov esi, calc_err
    call puts
.done:
    pop esi
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

; atoi: esi points to digits, ecx remaining length, returns eax = number, advances esi/ecx
atoi:
    push ebx
    xor eax, eax
    xor ebx, ebx
.al:
    cmp ecx, 0
    je .adone
    mov bl, [esi]
    cmp bl, '0'
    jb .adone
    cmp bl, '9'
    ja .adone
    imul eax, 10
    sub bl, '0'
    add eax, ebx
    inc esi
    dec ecx
    jmp .al
.adone:
    pop ebx
    ret

; itoa: eax = number, writes to num_buf (null terminated)
itoa:                         ; signed
    push ebx
    push ecx
    push edx
    mov edi, num_buf
    mov ecx, 0
    test eax, eax
    jns .nonneg
    mov byte [edi], '-'
    inc edi
    neg eax
.nonneg:
    test eax, eax
    jnz .pos
    mov byte [edi], '0'
    mov byte [edi+1], 0
    jmp .idone
.pos:
    ; reverse digits
    mov ebx, 10
.il:
    xor edx, edx
    div ebx
    add dl, '0'
    push edx
    inc ecx
    test eax, eax
    jnz .il
.ip:
    pop edx
    mov [edi], dl
    inc edi
    loop .ip
    mov byte [edi], 0
.idone:
    pop edx
    pop ecx
    pop ebx
    ret

run_edit:
    mov byte [editor_mode], 1
    mov byte [editor_verbose], 0
    jmp editor_enter

run_vedit:
    mov byte [editor_mode], 2
    mov byte [editor_verbose], 1
    jmp editor_enter

editor_enter:
    call cls
    mov esi, edit_banner
    cmp byte [editor_verbose], 0
    je .norm
    mov esi, vedit_banner
.norm:
    call puts
    ; init buffer with sample
    mov esi, edit_sample
    mov edi, edit_buf
    mov ecx, 24
    rep movsb
    mov dword [edit_len], 24
    mov dword [edit_pos], 24
    call editor_redraw
    ret

editor_redraw:
    ; simple: reprint buffer on new line
    mov al, 10
    call putc
    mov esi, edit_buf
    mov ecx, [edit_len]
    test ecx, ecx
    jz .empty
.l:
    lodsb
    call putc
    loop .l
.empty:
    mov al, 10
    call putc
    cmp byte [editor_verbose], 0
    je .done
    ; verbose status
    mov esi, vedit_status
    call puts
.done:
    mov esi, edit_prompt
    call puts
    ret

run_draw:
    mov byte [draw_mode], 1
    call cls
    mov esi, draw_banner
    call puts
    mov esi, draw_help
    call puts
    ; init canvas to spaces
    mov edi, draw_canvas
    mov ecx, 32*10
    mov al, ' '
    rep stosb
    mov byte [draw_cx], 0
    mov byte [draw_cy], 0
    call draw_redraw
    ret

draw_redraw:
    ; print canvas with cursor marker
    mov al, 10
    call putc
    mov ebx, 0                  ; row
.rowloop:
    mov esi, draw_canvas
    mov eax, ebx
    shl eax, 5                  ; *32
    add esi, eax
    mov ecx, 32
    mov edx, 0                  ; col
.colloop:
    mov al, [esi]
    cmp dl, [draw_cx]
    jne .nocur
    cmp bl, [draw_cy]
    jne .nocur
    cmp al, ' '
    jne .keep
    mov al, '+'
.keep:
.nocur:
    push ebx
    push edx
    call putc
    pop edx
    pop ebx
    inc esi
    inc edx
    loop .colloop
    push ebx
    mov al, 10
    call putc
    pop ebx
    inc ebx
    cmp ebx, 10
    jl .rowloop
    ; status
    mov esi, draw_status
    call puts
    movzx eax, byte [draw_cx]
    call itoa
    mov esi, num_buf
    call puts
    mov al, ','
    call putc
    movzx eax, byte [draw_cy]
    call itoa
    mov esi, num_buf
    call puts
    mov al, 10
    call putc
    ret

; ---------- command processor (called from keyboard on Enter) ----------
do_command:
    mov esi, cmdline
    cmp byte [esi], 0
    je .empty
    ; ls
    mov edi, cmd_ls
    call streq
    je .ls
    ; cat
    mov edi, cmd_cat
    call streq_prefix
    je .cat
    ; systest
    mov edi, cmd_systest
    call streq
    je .systest
    ; trap (diagnostic: raises #UD to show the exception report)
    mov edi, cmd_trap
    call streq
    jne .notrap
    ud2
.notrap:
    ; disk
    mov edi, cmd_disk
    call streq
    je .disk
    ; blktest
    mov edi, cmd_blktest
    call streq
    je .blktest
    ; ps
    mov edi, cmd_ps
    call streq
    je .ps
    ; proctest
    mov edi, cmd_proctest
    call streq
    je .proctest
    ; keys
    mov edi, cmd_keys
    call streq
    je .keys
    ; run
    mov edi, cmd_run
    call streq_prefix
    je .run
    mov esi, unknown
    call puts
    jmp .empty
.ls:
    call fs_list
    jmp .empty
.systest:
    call cmd_systest_run
    jmp .empty
.keys:
    call cmd_keys_run
    jmp .empty
.cat:
    ; skip "cat "
    add esi, 4
    call fs_cat
    jmp .empty
.run:
    add esi, 4
    mov ebx, run_table
.rfind:
    mov edi, [ebx]
    test edi, edi
    jz .rnone
    call streq
    je .rgo
    add ebx, 8
    jmp .rfind
.rnone:
    mov esi, unknown
    call puts
    jmp .empty
.rgo:
    ; the app runs as its own process; the shell waits for it
    mov ecx, [ebx+4]
    mov ebx, app_host
    mov eax, SYS_SPAWN
    int SYSCALL_VEC
    cmp eax, -1
    je .rfull
    mov ebx, eax
    mov eax, SYS_WAIT
    int SYSCALL_VEC
    jmp .empty
.rfull:
    mov esi, proc_full
    call puts
    jmp .empty
.ps:
    call cmd_ps_run
    jmp .empty
.disk:
    call cmd_disk_run
    jmp .empty
.blktest:
    call cmd_blktest_run
    jmp .empty
.proctest:
    call cmd_proctest_run
    jmp .empty
.empty:
    mov esi, prompt
    call puts
    mov byte [cmdline], 0
    mov dword [cmdpos], 0
    ret

streq:                        ; esi, edi
    push esi
    push edi
.l:
    lodsb
    mov ah, [edi]
    inc edi
    cmp al, ah
    jne .ne
    or al, al
    jnz .l
    pop edi
    pop esi
    xor eax, eax
    ret
.ne:
    pop edi
    pop esi
    or eax, 1
    ret

streq_prefix:
    push esi
    push edi
.p:
    mov al, [edi]
    or al, al
    jz .yes
    cmp al, [esi]
    jne .no
    inc esi
    inc edi
    jmp .p
.yes:
    pop edi
    pop esi
    xor eax, eax
    ret
.no:
    pop edi
    pop esi
    or eax, 1
    ret

; ---------- console ----------
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
    call cursor_sync
    ret

puts:
    lodsb
    or al, al
    jz .d
    call putc
    jmp puts
.d:
    ret

putc:                         ; al = char; preserves all registers
    push eax
    push ebx
    push edx
    cmp al, 10
    je .nl
    cmp al, 8
    je .bs
    mov ebx, [cur]
    mov ah, 0x07
    mov [0xB8000+ebx*2], ax
    inc dword [cur]
    jmp .wrap
.nl:
    mov eax, [cur]
    xor edx, edx
    mov ebx, 80
    div ebx
    inc eax
    mul ebx
    mov [cur], eax
    jmp .wrap
.bs:
    mov ebx, [cur]
    test ebx, ebx
    jz .r
    dec ebx
    mov [cur], ebx
    mov word [0xB8000+ebx*2], 0x0720
    jmp .r
.wrap:
    cmp dword [cur], 80*25
    jb .r
    call scroll_up
.r:
    call cursor_sync
    pop edx
    pop ebx
    pop eax
    ret

; Moves the text screen up one row and blanks the last row.
scroll_up:
    push ecx
    push esi
    push edi
    mov esi, 0xB8000+160
    mov edi, 0xB8000
    mov ecx, 80*24/2
    rep movsd
    mov eax, 0x07200720
    mov ecx, 80/2
    rep stosd
    sub dword [cur], 80
    pop edi
    pop esi
    pop ecx
    ret

; Puts the blinking hardware cursor at [cur].
cursor_sync:
    push eax
    push edx
    mov dx, 0x3D4
    mov al, 0x0F
    out dx, al
    inc dx
    mov al, [cur]
    out dx, al
    dec dx
    mov al, 0x0E
    out dx, al
    inc dx
    mov al, [cur+1]
    out dx, al
    pop edx
    pop eax
    ret

; ---------- ISRs ----------
timer_isr:
    push eax
    inc dword [ticks]
    mov al, 0x20
    out 0x20, al
    pop eax
    iretd

; IRQ1: queue the raw scancode (dropped if the ring is full)
kbd_isr:
    push eax
    push ebx
    push ecx
    in al, 0x60
    mov ebx, [kbd_head]
    lea ecx, [ebx+1]
    and ecx, KBD_RING_SIZE-1
    cmp ecx, [kbd_tail]
    je .full
    mov [kbd_ring+ebx], al
    mov [kbd_head], ecx
.full:
    mov al, 0x20
    out 0x20, al
    pop ecx
    pop ebx
    pop eax
    iretd

; Pops one scancode into al; CF set if the ring is empty. Clobbers ebx.
; Call with interrupts disabled.
kbd_dequeue:
    mov ebx, [kbd_tail]
    cmp ebx, [kbd_head]
    je .empty
    mov al, [kbd_ring+ebx]
    inc ebx
    and ebx, KBD_RING_SIZE-1
    mov [kbd_tail], ebx
    clc
    ret
.empty:
    stc
    ret

; Tracks Shift. Returns ZF set if al was a Shift make/break code
; (the caller should then ignore it).
kbd_shift_track:
    cmp al, 0x2A
    je .down
    cmp al, 0x36
    je .down
    cmp al, 0xAA
    je .up
    cmp al, 0xB6
    je .up
    ret                       ; ZF clear: not a shift key
.down:
    mov byte [kbd_shift], 1
    cmp al, al
    ret
.up:
    mov byte [kbd_shift], 0
    cmp al, al
    ret

; al = make code -> al = ASCII (0 if unmapped), honouring Shift.
kbd_ascii:
    push ebx
    movzx ebx, al
    and ebx, 0x7F
    cmp byte [kbd_shift], 0
    jne .sh
    mov al, [scancode_map+ebx]
    pop ebx
    ret
.sh:
    mov al, [scancode_map_shift+ebx]
    pop ebx
    ret

; Handles one scancode (al) for the shell or the active app.
kbd_dispatch:
    push eax
    push ebx
    call kbd_shift_track
    je .e
    cmp al, 0x80
    jae .e
    cmp byte [calc_mode], 0
    jne .calc
    cmp byte [editor_mode], 0
    jne .editor
    cmp byte [draw_mode], 0
    jne .draw
    ; command mode
    cmp al, 0x1C             ; Enter
    je .enter
    cmp al, 0x0E             ; Backspace
    je .cmd_bs
    call kbd_ascii
    or al, al
    jz .e
    mov ebx, [cmdpos]
    cmp ebx, 60
    jae .e
    mov [cmdline+ebx], al
    mov byte [cmdline+ebx+1], 0
    inc dword [cmdpos]
    call putc
    jmp .e
.enter:
    mov al, 10
    call putc
    call do_command
    jmp .e
.cmd_bs:
    mov ebx, [cmdpos]
    test ebx, ebx
    jz .e
    dec ebx
    mov [cmdpos], ebx
    mov byte [cmdline+ebx], 0
    mov al, 8
    call putc
    jmp .e
.calc:
    cmp al, 0x01             ; Esc
    je .exit_calc
    cmp al, 0x0E             ; Backspace
    je .calc_bs
    cmp al, 0x1C             ; Enter
    je .calc_enter
    call kbd_ascii
    or al, al
    jz .e
    ; insert into calc_buf
    mov ebx, [calc_len]
    cmp ebx, 60
    jae .e
    mov [calc_buf+ebx], al
    inc dword [calc_len]
    call putc
    jmp .e
.calc_bs:
    mov ebx, [calc_len]
    test ebx, ebx
    jz .e
    dec dword [calc_len]
    ; erase char (simple: backspace space backspace)
    mov al, 8
    call putc
    mov al, ' '
    call putc
    mov al, 8
    call putc
    jmp .e
.calc_enter:
    mov al, 10
    call putc
    call calc_eval
    mov dword [calc_len], 0
    mov esi, calc_prompt
    call puts
    jmp .e
.exit_calc:
    mov byte [calc_mode], 0
    call cls
    mov esi, banner
    call puts
    jmp .e
.editor:
    cmp al, 0x01             ; Esc
    je .exit_edit
    cmp al, 0x0E             ; Backspace
    je .bs
    cmp al, 0x1C             ; Enter
    je .nl
    call kbd_ascii
    or al, al
    jz .e
    ; insert char
    mov ebx, [edit_len]
    cmp ebx, 250
    jae .e
    mov [edit_buf+ebx], al
    inc dword [edit_len]
    inc dword [edit_pos]
    call editor_redraw
    jmp .e
.bs:
    mov ebx, [edit_len]
    test ebx, ebx
    jz .e
    dec dword [edit_len]
    dec dword [edit_pos]
    call editor_redraw
    jmp .e
.nl:
    ; treat as newline in buffer (limited)
    mov ebx, [edit_len]
    cmp ebx, 250
    jae .e
    mov byte [edit_buf+ebx], 10
    inc dword [edit_len]
    call editor_redraw
    jmp .e
.exit_edit:
    mov byte [editor_mode], 0
    call cls
    mov esi, banner
    call puts
    jmp .e
.draw:
    cmp al, 0x01             ; Esc
    je .exit_draw
    cmp al, 0x48             ; Up
    je .draw_up
    cmp al, 0x50             ; Down
    je .draw_down
    cmp al, 0x4B             ; Left
    je .draw_left
    cmp al, 0x4D             ; Right
    je .draw_right
    cmp al, 0x39             ; Space
    je .draw_plot
    cmp al, 0x2D             ; x (scancode for x is 0x2D)
    je .draw_erase
    cmp al, 0x2E             ; c
    je .draw_clear
    jmp .e
.draw_up:
    cmp byte [draw_cy], 0
    je .e
    dec byte [draw_cy]
    call draw_redraw
    jmp .e
.draw_down:
    cmp byte [draw_cy], 9
    jae .e
    inc byte [draw_cy]
    call draw_redraw
    jmp .e
.draw_left:
    cmp byte [draw_cx], 0
    je .e
    dec byte [draw_cx]
    call draw_redraw
    jmp .e
.draw_right:
    cmp byte [draw_cx], 31
    jae .e
    inc byte [draw_cx]
    call draw_redraw
    jmp .e
.draw_plot:
    ; plot * at cursor
    movzx eax, byte [draw_cy]
    shl eax, 5
    movzx ebx, byte [draw_cx]
    add eax, ebx
    mov byte [draw_canvas+eax], '*'
    call draw_redraw
    jmp .e
.draw_erase:
    movzx eax, byte [draw_cy]
    shl eax, 5
    movzx ebx, byte [draw_cx]
    add eax, ebx
    mov byte [draw_canvas+eax], ' '
    call draw_redraw
    jmp .e
.draw_clear:
    mov edi, draw_canvas
    mov ecx, 32*10
    mov al, ' '
    rep stosb
    call draw_redraw
    jmp .e
.exit_draw:
    mov byte [draw_mode], 0
    call cls
    mov esi, banner
    call puts
    jmp .e
.e:
    pop ebx
    pop eax
    ret

default_isr:
    iretd

; ---------- data ----------
banner db 'Squirrel-OS/2 — in-memory FS + apps', 10
       db 'Commands: ls | cat <name> | run <name> | ps | disk', 10
       db 'Tests: systest | proctest | blktest | keys', 10
       db 'Apps: calc, sci, graph, matrix, diff, topo, edit, vedit, draw', 10, 0
prompt db '> ', 0
fs_header db 'Files:', 10, 0
notfound db 'Not found', 10, 0
unknown db 'Unknown command', 10, 0
cmd_ls db 'ls', 0
cmd_cat db 'cat ', 0
cmd_run db 'run ', 0
cmd_systest db 'systest', 0
cmd_keys db 'keys', 0
cmd_trap db 'trap', 0
cmd_ps db 'ps', 0
cmd_disk db 'disk', 0
cmd_blktest db 'blktest', 0
cmd_proctest db 'proctest', 0
proc_full db 'Too many processes', 10, 0

; run <name>: app start routines, each hosted in its own process
run_table:
    dd name_calc, run_calc
    dd name_sci, run_sci
    dd name_graph, run_graph
    dd name_matrix, run_matrix
    dd name_diff, run_diff
    dd name_topo, run_topo
    dd name_edit, run_edit
    dd name_vedit, run_vedit
    dd name_draw, run_draw
    dd 0, 0
name_calc db 'calc', 0
name_edit db 'edit', 0
name_vedit db 'vedit', 0
name_draw db 'draw', 0
name_sci db 'sci', 0
name_graph db 'graph', 0
name_matrix db 'matrix', 0
name_diff db 'diff', 0
name_topo db 'topo', 0

calc_banner db 'Basic Calculator (Esc to exit)', 10, 0
calc_help db 'Enter: number +|-|*|/|% number', 10, 'Example: 100 + 15%  or  50 * 3', 10, 0
calc_prompt db 'calc> ', 0
calc_result_prefix db 'Result: ', 0
calc_err db 'Error: bad expression', 10, 0
div0_msg db 'Error: division by zero', 10, 0
sci_banner db 'Scientific Calculator', 10, 0
sci_stub db 'Scaffolded. Floating-point and transcendentals pending FPU support.', 10, 'See documentation/apps/calculators.md', 10, 0
graph_banner db 'Graphing Calculator', 10, 0
graph_stub db 'Scaffolded. Requires graphics primitives (milestone 1.3).', 10, 'See documentation/apps/calculators.md', 10, 0
matrix_banner db 'Matrix Calculator', 10, 0
matrix_stub db 'Scaffolded. Linear algebra (add, mul, det, inv) pending.', 10, 'See documentation/apps/calculators.md', 10, 0
diff_banner db 'DiffEq / Calculus Calculator', 10, 0
diff_stub db 'Scaffolded. Numerical derivatives, integrals, ODEs pending.', 10, 'See documentation/apps/calculators.md', 10, 0
topo_banner db 'Topology Calculator', 10, 0
topo_stub db 'Scaffolded. Simplicial homology sketches (long-term).', 10, 'See documentation/apps/calculators.md', 10, 0
edit_banner db 'Text Editor (Esc to exit)', 10, 0
edit_sample db 'Hello from Squirrel-OS/2', 10, 0
vedit_banner db 'Verbose Editor (Esc to exit)', 10, 0
vedit_sample db 'Line 1, col 1, byte 0, char 0x48 ', 39, 'H', 39, 10
             db 'Insert mode, unmodified, size 0/4096', 10, 0
vedit_status db 'Status: len=', 0
edit_prompt db 'edit> ', 0
draw_banner db 'Drawing Program (Esc to exit)', 10, 0
draw_help db 'Arrows: move  Space: plot *  x: erase  c: clear', 10, 0
draw_status db 'Pos: ', 0
draw_art db '  *  ', 10, ' *** ', 10, '*****', 10, 0

file_count dd 10
file_table:
    db 'calc', 0, 0, 0, 0
    dd calc_help
    dd 70
    db 'sci', 0, 0, 0, 0, 0
    dd sci_stub
    dd 90
    db 'graph', 0, 0, 0
    dd graph_stub
    dd 80
    db 'matrix', 0, 0
    dd matrix_stub
    dd 80
    db 'diff', 0, 0, 0, 0
    dd diff_stub
    dd 80
    db 'topo', 0, 0, 0, 0
    dd topo_stub
    dd 70
    db 'edit', 0, 0, 0, 0
    dd edit_sample
    dd 24
    db 'vedit', 0, 0, 0
    dd vedit_sample
    dd 62
    db 'draw', 0, 0, 0, 0
    dd draw_art
    dd 18
    db 'help', 0, 0, 0, 0
    dd banner
    dd 80

KBD_RING_SIZE equ 64
kbd_ring times KBD_RING_SIZE db 0
kbd_head dd 0
kbd_tail dd 0
cmdline times 64 db 0
cmdpos dd 0
cur dd 0
ticks dd 0
editor_mode db 0
editor_verbose db 0
edit_buf times 256 db 0
edit_len dd 0
edit_pos dd 0
draw_mode db 0
draw_canvas times 320 db ' '
draw_cx db 0
draw_cy db 0
calc_mode db 0
calc_buf times 64 db 0
calc_len dd 0
calc_op db 0
num_buf times 16 db 0

kbd_shift db 0

; Set-1 make codes 0x00..0x7F. Keypad * - + are mapped; other keypad
; keys stay 0 so arrows (0x48/0x4B/0x4D/0x50) remain free for apps.
scancode_map:
    db 0,0,'1','2','3','4','5','6','7','8','9','0','-','=',0,0
    db 'q','w','e','r','t','y','u','i','o','p','[',']',10,0
    db 'a','s','d','f','g','h','j','k','l',';',39,'`',0,'\'
    db 'z','x','c','v','b','n','m',',','.','/',0,'*',0,' '
    times 0x4A-($-scancode_map) db 0
    db '-',0,0,0,'+'
    times 128-($-scancode_map) db 0
scancode_map_shift:
    db 0,0,'!','@','#','$','%','^','&','*','(',')','_','+',0,0
    db 'Q','W','E','R','T','Y','U','I','O','P','{','}',10,0
    db 'A','S','D','F','G','H','J','K','L',':','"','~',0,'|'
    db 'Z','X','C','V','B','N','M','<','>','?',0,'*',0,' '
    times 0x4A-($-scancode_map_shift) db 0
    db '-',0,0,0,'+'
    times 128-($-scancode_map_shift) db 0

; ---------- CPU exceptions ----------
; One fixed-size stub per vector pushes its number; the report prints
; it with the faulting EIP and halts. (Vectors with an error code push
; it first, so EIP is read from the right slot for those.)
EXC_STUB_SIZE equ 8
exc_stubs:
%assign v 0
%rep 32
    push dword v
    jmp exc_report
    times exc_stubs+(v+1)*EXC_STUB_SIZE-$ nop
%assign v v+1
%endrep

exc_report:
    cli
    mov ebx, [esp]            ; vector
    mov eax, 1
    mov ecx, ebx
    shl eax, cl
    test eax, EXC_ERRCODE_MASK
    mov edx, [esp+4]          ; eip without error code
    jz .noerr
    mov edx, [esp+8]
.noerr:
    mov esi, exc_msg
    call puts
    mov eax, ebx
    call itoa
    mov esi, num_buf
    call puts
    mov esi, exc_at
    call puts
    mov eax, edx
    call puthex
    mov al, 10
    call putc
.halt:
    hlt
    jmp .halt

; eax -> 8 hex digits on the console
puthex:
    push ecx
    push edx
    mov edx, eax
    mov ecx, 8
.h:
    rol edx, 4
    mov al, dl
    and al, 0x0F
    add al, '0'
    cmp al, '9'
    jbe .d
    add al, 'A'-'9'-1
.d:
    call putc
    loop .h
    pop edx
    pop ecx
    ret

; #DF #TS #NP #SS #GP #PF #AC push an error code
EXC_ERRCODE_MASK equ (1<<8)|(1<<10)|(1<<11)|(1<<12)|(1<<13)|(1<<14)|(1<<17)
exc_msg db 10, '*** CPU exception ', 0
exc_at db ' at EIP 0x', 0

%include "syscall.asm"
%include "proc.asm"
%include "ata.asm"

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
times 16384-($-$$) db 0
