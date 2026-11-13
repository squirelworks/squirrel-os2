; Squirrel-OS/2 — System Monitor: CPU, memory and processes (A.5,
; OS2-APPS). Original code. run sysmon  |  run sysmon test
;
; Twice a second it takes a snapshot through GUI_SYSINFO (kernel/
; sysinfo.asm) and shows:
;   - the CPU: how busy it was since the last snapshot (the ticks the
;     timer did not find it halted in the idle loop), and a graph of the
;     last 64 snapshots;
;   - memory: the 4 KB pages the kernel manages, used and free;
;   - the processes: pid, state, priority, their share of the CPU since
;     the last snapshot, the CPU time they have used, their memory (their
;     own address space; "kernel" for the shell and built-in apps) and
;     name.
;
;   Up/Down (or a click): pick a process.  + / -: raise or lower its
;   priority (0 to 3; higher runs first).  Esc: quit
;
; "run sysmon test" checks the snapshot against what the program knows
; (its own pid, name, state, priority changes, its CPU time while it
; spins and idle time while it yields, the kernel log) and prints
; "sysmon: PASS". See documentation/apps/sysmon.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"
%include "sysinfo.inc"

HIST_N      equ 64              ; CPU graph samples
PERIOD      equ 50              ; ticks between snapshots
COLS        equ 52

GR_X        equ 4               ; the CPU graph
GR_Y        equ WIN_TITLE_H + 22
GR_W        equ HIST_N * 2
GR_H        equ 40
MEM_X       equ GR_X + GR_W + 10
TB_Y        equ GR_Y + GR_H + 6 ; the process table: header, then rows
ROW_Y       equ TB_Y + CELL_H + 2
STAT_Y      equ SCR_H - CELL_H - 2

main:
    mov esi, [esp+4]
    test esi, esi
    jz .gui
    cmp dword [esi], 'test'
    jne .gui
    cmp byte [esi+4], 0
    je selftest
.gui:
    call gui_open
    jc .nogfx
    mov eax, SYS_GETPID
    int 0x80
    mov [mypid], eax
    mov dword [sel], -1
.sample:
    call sample
.draw:
    call draw
    mov ecx, PERIOD
    call gui_event
    test eax, eax
    jz .sample
    cmp eax, EV_CLICK
    je .click
    test eax, EV_DRAG
    jnz .draw
    call key
    jnc .draw
    call gui_close
    xor eax, eax
    ret
.click:
    mov eax, [gui_my]
    sub eax, ROW_Y
    jb .draw
    xor edx, edx
    mov ecx, CELL_H
    div ecx
    cmp eax, [nvis]
    jae .draw
    mov [sel], eax
    jmp .draw
.nogfx:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
    ret

; eax = key -> CF to quit
key:
    pushad
    movzx ebx, ah
    cmp bl, K_ESC
    je .quit
    cmp bl, K_UP
    je .up
    cmp bl, K_DOWN
    je .down
    cmp al, '+'
    je .more
    cmp al, '='
    je .more
    cmp al, '-'
    je .less
    jmp .ok
.up:
    mov eax, [sel]
    test eax, eax
    jle .ok
    dec dword [sel]
    jmp .ok
.down:
    mov eax, [sel]
    inc eax
    cmp eax, [nvis]
    jae .ok
    mov [sel], eax
    jmp .ok
.more:
    mov edx, 1
    jmp .prio
.less:
    mov edx, -1
.prio:
    call sel_row
    jc .ok
    mov eax, [edi+SI_PRIO]
    add eax, edx
    cmp eax, 3
    ja .ok                      ; (below 0 wraps: also above 3)
    mov ecx, eax
    shl ecx, 16
    or ecx, [edi+SI_PID]
    mov eax, SYS_GUI
    mov ebx, GUI_SYSINFO
    mov edx, SI_PART_PRIO
    int 0x80
    call sample_rows
.ok:
    popad
    clc
    ret
.quit:
    popad
    stc
    ret

; -> edi = the picked process's row, or CF
sel_row:
    mov eax, [sel]
    cmp eax, [nvis]
    jae .no
    mov eax, [vis+eax*4]
    imul edi, eax, SI_ROW
    add edi, rows
    clc
    ret
.no:
    stc
    ret

; ---------- snapshots ----------
sample:
    pushad
    mov eax, SYS_GUI
    mov ebx, GUI_SYSINFO
    mov edx, SI_PART_SYS
    mov ecx, sys
    int 0x80
    mov ecx, [sys+SI_TICKS]     ; ticks since the last one
    sub ecx, [prev_ticks]
    mov [dticks], ecx
    jz .same
    mov eax, [sys+SI_IDLE]
    sub eax, [prev_idle]
    mov edx, 100
    mul edx
    div ecx
    cmp eax, 100
    jbe .i
    mov eax, 100
.i:
    neg eax
    add eax, 100
    mov [cpu_pct], eax
    mov edi, hist               ; the graph moves left
    lea esi, [edi+1]
    mov ecx, HIST_N - 1
    rep movsb
    mov [hist+HIST_N-1], al
    cmp dword [nhist], HIST_N
    jae .same
    inc dword [nhist]
.same:
    mov eax, [sys+SI_TICKS]
    mov [prev_ticks], eax
    mov eax, [sys+SI_IDLE]
    mov [prev_idle], eax
    call sample_rows
    popad
    ret

; the process table, each one's share of the CPU since the last
; snapshot, and the visible rows
sample_rows:
    pushad
    mov eax, SYS_GUI
    mov ebx, GUI_SYSINFO
    mov edx, SI_PART_PROCS
    mov ecx, rows
    int 0x80
    xor ebx, ebx                ; slot
    xor ebp, ebp                ; visible rows
.s:
    imul edi, ebx, SI_ROW
    add edi, rows
    mov eax, [edi+SI_CPU]
    mov edx, [edi+SI_PID]
    cmp edx, [prev_pid+ebx*4]
    je .delta
    mov dword [prev_cpu+ebx*4], 0
.delta:
    mov [prev_pid+ebx*4], edx
    mov ecx, [dticks]
    test ecx, ecx
    jz .keep
    sub eax, [prev_cpu+ebx*4]
    mov edx, 100
    mul edx
    div ecx
    cmp eax, 100
    jbe .p
    mov eax, 100
.p:
    mov [pct+ebx*4], eax
.keep:
    mov eax, [edi+SI_CPU]
    mov [prev_cpu+ebx*4], eax
    cmp dword [edi+SI_STATE], PS_FREE
    je .n
    mov [vis+ebp*4], ebx
    inc ebp
.n:
    inc ebx
    cmp ebx, SI_SLOTS_MAX
    jb .s
    mov [nvis], ebp
    mov eax, [sel]              ; the pick stays on the table
    cmp eax, ebp
    jl .r
    lea eax, [ebp-1]
    mov [sel], eax
.r:
    cmp dword [sel], 0
    jge .r2
    cmp ebp, 0
    je .r2
    call sel_self
.r2:
    popad
    ret

; the first pick: this program's own row
sel_self:
    xor ecx, ecx
.f:
    cmp ecx, [nvis]
    jae .r
    mov eax, [vis+ecx*4]
    imul eax, SI_ROW
    mov eax, [rows+eax+SI_PID]
    cmp eax, [mypid]
    je .got
    inc ecx
    jmp .f
.got:
    mov [sel], ecx
.r:
    ret

; ---------- drawing ----------
draw:
    pushad
    xor eax, eax
    xor ebx, ebx
    mov ecx, SCR_W
    mov edx, SCR_H
    mov esi, title
    call gui_window
    call draw_top
    call draw_graph
    call draw_mem
    call draw_table
    mov byte [gui_ink], C_BLACK
    mov esi, s_keys
    mov eax, 4
    mov ebx, STAT_Y
    call gui_text
    call gui_flip
    popad
    ret

; "CPU 12%   Up 0:01:23   Processes 3 of 8"
draw_top:
    pushad
    call ln_clear
    mov esi, s_cpu
    xor ecx, ecx
    call ln_put
    mov eax, [cpu_pct]
    mov ecx, 4
    call ln_num
    mov byte [edi], '%'
    mov esi, s_up
    mov ecx, 11
    call ln_put
    mov eax, [sys+SI_TICKS]
    xor edx, edx
    mov ebx, 100
    div ebx                     ; seconds
    xor edx, edx
    mov ebx, 3600
    div ebx
    push edx
    mov ecx, 14
    call ln_num
    mov byte [edi], ':'
    pop eax
    xor edx, edx
    mov ebx, 60
    div ebx
    push edx
    lea ecx, [edi-ln+1]
    call ln_num2
    mov byte [edi], ':'
    pop eax
    lea ecx, [edi-ln+1]
    call ln_num2
    mov esi, s_procs
    mov ecx, 26
    call ln_put
    mov eax, [sys+SI_PROCS]
    mov ecx, 36
    call ln_num
    mov esi, s_of
    lea ecx, [edi-ln]
    call ln_put
    mov eax, [sys+SI_SLOTS]
    lea ecx, [edi-ln]
    call ln_num
    mov eax, 4
    mov ebx, WIN_TITLE_H + 3
    call ln_show
    popad
    ret

draw_graph:
    pushad
    mov eax, GR_X - 1
    mov ebx, GR_Y - 1
    mov ecx, GR_W + 2
    mov edx, GR_H + 2
    mov byte [gui_ink], C_DGREY
    call gui_box
    mov eax, GR_X
    mov ebx, GR_Y
    mov ecx, GR_W
    mov edx, GR_H
    mov byte [gui_ink], C_BLACK
    call gui_fill
    mov byte [gui_ink], C_GREEN ; 25 %, 50 %, 75 % lines
    mov esi, 1
.grid:
    mov eax, GR_H
    imul eax, esi
    shr eax, 2
    mov ebx, GR_Y + GR_H
    sub ebx, eax
    mov eax, GR_X
    mov ecx, GR_W
    mov edx, 1
    call gui_fill
    inc esi
    cmp esi, 4
    jb .grid
    mov byte [gui_ink], C_LGREEN
    xor esi, esi                ; the samples, the newest on the right
.b:
    cmp esi, HIST_N
    jae .done
    mov eax, HIST_N
    sub eax, esi
    cmp eax, [nhist]
    ja .nb
    movzx edx, byte [hist+esi]
    imul edx, GR_H
    mov ecx, 100
    mov eax, edx
    xor edx, edx
    div ecx
    test eax, eax
    jz .nb
    mov edx, eax                ; height
    mov ebx, GR_Y + GR_H
    sub ebx, edx
    lea eax, [GR_X+esi*2]
    mov ecx, 2
    call gui_fill
.nb:
    inc esi
    jmp .b
.done:
    mov byte [gui_ink], C_BLACK
    mov esi, s_graph
    mov eax, GR_X
    mov ebx, GR_Y - CELL_H - 2
    call gui_text
    popad
    ret

draw_mem:
    pushad
    mov byte [gui_ink], C_BLACK
    mov esi, s_memory
    mov eax, MEM_X
    mov ebx, GR_Y - CELL_H - 2
    call gui_text
    mov eax, MEM_X              ; a bar: used of all
    mov ebx, GR_Y
    mov ecx, SCR_W - 6 - MEM_X
    mov edx, 10
    mov byte [gui_ink], C_WHITE
    call gui_fill
    mov byte [gui_ink], C_DGREY
    call gui_box
    mov eax, [sys+SI_PAGES]
    sub eax, [sys+SI_FREE]
    mov ecx, SCR_W - 8 - MEM_X
    mul ecx
    mov ecx, [sys+SI_PAGES]
    test ecx, ecx
    jz .nob
    div ecx
    test eax, eax
    jz .nob
    mov ecx, eax
    mov eax, MEM_X + 1
    mov ebx, GR_Y + 1
    mov edx, 8
    mov byte [gui_ink], C_LBLUE
    call gui_fill
.nob:
    mov byte [gui_ink], C_BLACK
    call ln_clear               ; "Used 1234 KB"
    mov esi, s_used
    xor ecx, ecx
    call ln_put
    mov eax, [sys+SI_PAGES]
    sub eax, [sys+SI_FREE]
    shl eax, 2
    mov ecx, 11
    call ln_num
    mov esi, s_kb
    lea ecx, [edi-ln]
    call ln_put
    mov eax, MEM_X
    mov ebx, GR_Y + 14
    call ln_show
    call ln_clear
    mov esi, s_free
    xor ecx, ecx
    call ln_put
    mov eax, [sys+SI_FREE]
    shl eax, 2
    mov ecx, 11
    call ln_num
    mov esi, s_kb
    lea ecx, [edi-ln]
    call ln_put
    mov eax, MEM_X
    mov ebx, GR_Y + 14 + CELL_H
    call ln_show
    call ln_clear
    mov esi, s_total
    xor ecx, ecx
    call ln_put
    mov eax, [sys+SI_PAGES]
    shl eax, 2
    mov ecx, 11
    call ln_num
    mov esi, s_kb
    lea ecx, [edi-ln]
    call ln_put
    mov eax, MEM_X
    mov ebx, GR_Y + 14 + 2 * CELL_H
    call ln_show
    call ln_clear
    mov esi, s_switch
    xor ecx, ecx
    call ln_put
    mov eax, [sys+SI_SWITCHES]
    mov ecx, 11
    call ln_num
    mov eax, MEM_X
    mov ebx, GR_Y + 14 + 3 * CELL_H
    call ln_show
    popad
    ret

; PID STATE    PRI CPU%    TIME  MEMORY NAME
draw_table:
    pushad
    mov byte [gui_ink], C_BLACK
    mov esi, s_head
    mov eax, 4
    mov ebx, TB_Y
    call gui_text
    mov eax, 2
    mov ebx, TB_Y + CELL_H
    mov ecx, SCR_W - 4
    mov edx, 1
    mov byte [gui_ink], C_DGREY
    call gui_fill
    xor ebp, ebp
.r:
    cmp ebp, [nvis]
    jae .done
    mov ebx, [vis+ebp*4]
    imul edi, ebx, SI_ROW
    add edi, rows
    call ln_clear
    mov eax, [edi+SI_PID]
    mov ecx, 2
    push edi
    call ln_num
    pop edi
    mov eax, [edi+SI_STATE]
    cmp eax, PS_STOPPED
    jbe .st
    xor eax, eax
.st:
    mov esi, [state_names+eax*4]
    mov ecx, 4
    push edi
    call ln_put
    pop edi
    mov eax, [edi+SI_PRIO]
    mov ecx, 15
    push edi
    call ln_num
    pop edi
    mov eax, [pct+ebx*4]
    mov ecx, 19
    push edi
    call ln_num
    mov byte [edi], '%'
    pop edi
    mov eax, [edi+SI_CPU]       ; time: seconds.hundredths
    xor edx, edx
    push ebx
    mov ebx, 100
    div ebx
    pop ebx
    push edx
    mov ecx, 25
    push edi
    call ln_num
    mov byte [edi], '.'
    lea ecx, [edi-ln+1]
    pop edi
    pop eax
    push edi
    call ln_num2
    pop edi
    mov eax, [edi+SI_KB]
    cmp eax, -1
    je .kern
    mov ecx, 33
    push edi
    call ln_num
    mov esi, s_k
    lea ecx, [edi-ln]
    call ln_put
    pop edi
    jmp .name
.kern:
    mov esi, s_kernel
    mov ecx, 31
    push edi
    call ln_put
    pop edi
.name:
    lea esi, [edi+SI_NAME]
    cmp byte [esi], 0
    jne .nm
    mov esi, s_dash
.nm:
    mov ecx, 38
    call ln_put
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    cmp ebp, [sel]
    jne .show
    mov eax, 2                  ; the pick: white on blue
    imul ebx, ebp, CELL_H
    add ebx, ROW_Y - 1
    mov ecx, SCR_W - 4
    mov edx, CELL_H
    mov byte [gui_ink], C_BLUE
    call gui_fill
    mov byte [gui_ink], C_WHITE
    mov byte [gui_bg], C_BLUE
.show:
    mov eax, 4
    imul ebx, ebp, CELL_H
    add ebx, ROW_Y
    call ln_show
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    inc ebp
    jmp .r
.done:
    popad
    ret

; ---------- the line being made ----------
ln_clear:
    push edi
    push ecx
    push eax
    mov edi, ln
    mov ecx, COLS
    mov al, ' '
    rep stosb
    mov byte [edi], 0
    pop eax
    pop ecx
    pop edi
    ret
; esi = text at column ecx -> edi after it
ln_put:
    lea edi, [ln+ecx]
.c:
    lodsb
    test al, al
    jz .r
    cmp edi, ln + COLS
    jae .r
    stosb
    jmp .c
.r:
    ret
; eax = number, right-aligned to end at column ecx -> edi after it
ln_num:
    push esi
    push edi
    mov edi, nbuf
    call gui_utoa
    mov esi, edi
    sub esi, nbuf               ; its length
    pop edi
    lea edi, [ln+ecx+1]
    sub edi, esi
    cmp edi, ln
    jae .ok
    mov edi, ln
.ok:
    mov esi, nbuf
.c:
    lodsb
    test al, al
    jz .r
    stosb
    jmp .c
.r:
    pop esi
    ret
; eax = 0..99 as two digits at column ecx -> edi after them
ln_num2:
    push edx
    push ebx
    xor edx, edx
    mov ebx, 10
    div ebx
    lea edi, [ln+ecx]
    add al, '0'
    stosb
    mov al, dl
    add al, '0'
    stosb
    pop ebx
    pop edx
    ret
; eax = x, ebx = y: the line, without its trailing spaces
ln_show:
    push esi
    push edi
    mov edi, ln + COLS
.t:
    cmp edi, ln
    je .s
    cmp byte [edi-1], ' '
    jne .s
    dec edi
    jmp .t
.s:
    mov byte [edi], 0
    mov esi, ln
    call gui_text
    pop edi
    pop esi
    ret

; ---------- self-test ----------
selftest:
    mov eax, SYS_GETPID
    int 0x80
    mov [mypid], eax
    mov byte [bad], 'a'         ; a: the system block
    mov eax, SYS_GUI
    mov ebx, GUI_SYSINFO
    mov edx, SI_PART_SYS
    mov ecx, sys
    int 0x80
    test eax, eax
    jnz fail
    mov eax, [sys+SI_PAGES]
    test eax, eax
    jz fail
    cmp [sys+SI_FREE], eax
    ja fail
    cmp dword [sys+SI_SLOTS], SI_SLOTS_MAX
    jne fail
    cmp dword [sys+SI_PROCS], 2 ; the shell and this program
    jb fail
    inc byte [bad]              ; b: this program's row
    call find_me
    jc fail
    cmp dword [edi+SI_STATE], PS_RUNNING
    jne fail
    cmp dword [edi+SI_NAME], 'sysm'
    jne fail
    cmp word [edi+SI_NAME+4], 'on'
    jne fail
    cmp dword [edi+SI_KB], 0
    jle fail
    inc byte [bad]              ; c: spinning counts as its CPU time
    mov eax, [edi+SI_CPU]
    mov [t0], eax
    call ticks
    mov [t1], eax
.spin:
    call ticks
    sub eax, [t1]
    cmp eax, 30
    jb .spin
    call find_me
    mov eax, [edi+SI_CPU]
    sub eax, [t0]
    cmp eax, 20
    jb fail
    inc byte [bad]              ; d: yielding with nobody else ready is idle
    call get_sys
    mov eax, [sys+SI_IDLE]
    mov [t0], eax
    call ticks
    mov [t1], eax
.idle:
    mov eax, SYS_YIELD
    int 0x80
    call ticks
    sub eax, [t1]
    cmp eax, 30
    jb .idle
    call get_sys
    mov eax, [sys+SI_IDLE]
    sub eax, [t0]
    cmp eax, 10
    jb fail
    inc byte [bad]              ; e: priorities
    mov ecx, [mypid]
    or ecx, 2 << 16
    call set_prio
    test eax, eax
    jnz fail
    call find_me
    cmp dword [edi+SI_PRIO], 2
    jne fail
    mov ecx, [mypid]
    or ecx, 1 << 16
    call set_prio
    call find_me
    cmp dword [edi+SI_PRIO], 1
    jne fail
    mov ecx, [mypid]            ; no priority 9, no pid 9999
    or ecx, 9 << 16
    call set_prio
    cmp eax, -1
    jne fail
    mov ecx, 9999 | 1 << 16
    call set_prio
    cmp eax, -1
    jne fail
    inc byte [bad]              ; f: the kernel log
    mov eax, SYS_SBRK
    mov ebx, KLOG_SIZE + 1
    int 0x80
    cmp eax, -1
    je fail
    mov [logb], eax
    mov ecx, eax
    mov eax, SYS_GUI
    mov ebx, GUI_SYSINFO
    mov edx, SI_PART_LOG
    int 0x80
    test eax, eax
    jle fail
    cmp eax, KLOG_SIZE
    ja fail
    mov edi, [logb]
    mov byte [edi+eax], 0
    mov esi, s_boot
    call contains
    jc fail
    mov esi, s_me
    call contains
    jc fail
    inc byte [bad]              ; g: an unknown part
    mov eax, SYS_GUI
    mov ebx, GUI_SYSINFO
    mov edx, 7
    mov ecx, sys
    int 0x80
    cmp eax, -1
    jne fail
    inc byte [bad]              ; h: the CPU share of a snapshot
    mov dword [sel], -1
    call sample
    call ticks
    mov [t1], eax
.spin2:
    call ticks
    sub eax, [t1]
    cmp eax, 20
    jb .spin2
    call sample
    cmp dword [cpu_pct], 50
    jb fail
    call sel_row                ; picked: this program, mostly busy
    jc fail
    mov eax, [edi+SI_PID]
    cmp eax, [mypid]
    jne fail
    mov eax, [sel]
    mov eax, [vis+eax*4]
    cmp dword [pct+eax*4], 50
    jb fail
    mov esi, pass
    call gui_puts
    xor eax, eax
    ret
fail:
    mov esi, failm
    call gui_puts
    mov eax, 1
    ret

; -> edi = this program's row, or CF
find_me:
    mov eax, SYS_GUI
    mov ebx, GUI_SYSINFO
    mov edx, SI_PART_PROCS
    mov ecx, rows
    int 0x80
    mov edi, rows
    mov ecx, SI_SLOTS_MAX
.f:
    cmp dword [edi+SI_STATE], PS_FREE
    je .n
    mov eax, [edi+SI_PID]
    cmp eax, [mypid]
    je .y
.n:
    add edi, SI_ROW
    loop .f
    stc
    ret
.y:
    clc
    ret
get_sys:
    mov eax, SYS_GUI
    mov ebx, GUI_SYSINFO
    mov edx, SI_PART_SYS
    mov ecx, sys
    int 0x80
    ret
set_prio:
    mov eax, SYS_GUI
    mov ebx, GUI_SYSINFO
    mov edx, SI_PART_PRIO
    int 0x80
    ret
ticks:
    push ebx
    mov eax, SYS_GUI
    mov ebx, GUI_TICKS
    int 0x80
    pop ebx
    ret
; edi = text, esi = word -> CF if the word is not in it
contains:
    push edi
.s:
    cmp byte [edi], 0
    je .no
    push esi
    push edi
.c:
    mov al, [esi]
    test al, al
    jz .yes
    cmp al, [edi]
    jne .nx
    inc esi
    inc edi
    jmp .c
.nx:
    pop edi
    pop esi
    inc edi
    jmp .s
.yes:
    pop edi
    pop esi
    pop edi
    clc
    ret
.no:
    pop edi
    stc
    ret

; ---------- data ----------
title db 'System Monitor', 0
s_keys db 'Up/Down: pick   +/-: priority   Esc: quit', 0
s_cpu db 'CPU', 0
s_up db 'Up', 0
s_procs db 'Processes', 0
s_of db ' of ', 0
s_graph db 'CPU use', 0
s_memory db 'Memory', 0
s_used db 'Used', 0
s_free db 'Free', 0
s_total db 'All', 0
s_kb db ' KB', 0
s_k db ' K', 0
s_switch db 'Switches', 0
s_head db 'PID STATE    PRI CPU%    TIME  MEMORY NAME', 0
s_kernel db 'kernel', 0
s_dash db '-', 0
st_free db 'free', 0
st_ready db 'ready', 0
st_run db 'running', 0
st_wait db 'waiting', 0
st_zombie db 'zombie', 0
st_stopped db 'stopped', 0
state_names dd st_free, st_ready, st_run, st_wait, st_zombie, st_run, st_stopped    ; 5: on an AP
s_boot db 'Squirrel-OS/2 started', 0
s_me db 'started sysmon', 0
m_nogfx db 'sysmon: no graphics', 10, 0
pass db 'sysmon: PASS', 10, 0
failm db 'sysmon: FAIL '
bad db '?', 10, 0

SQX_BSS
GUI_BSS
mypid resd 1
sel resd 1
nvis resd 1
cpu_pct resd 1
dticks resd 1
prev_ticks resd 1
prev_idle resd 1
nhist resd 1
t0 resd 1
t1 resd 1
logb resd 1
sys resb SI_SYS_SIZE
rows resb SI_SLOTS_MAX * SI_ROW
prev_pid resd SI_SLOTS_MAX
prev_cpu resd SI_SLOTS_MAX
pct resd SI_SLOTS_MAX
vis resd SI_SLOTS_MAX
hist resb HIST_N
nbuf resb 16
ln resb COLS + 4
SQX_END
