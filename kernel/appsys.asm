; Squirrel-OS/2 — graphics for programs: SYS_GUI (2.1, OS2-APPS)
; Included from pm.asm. Original code.
;
; One system call, SYS_GUI, gives a program on the data disk what the
; built-in graphical apps use: the 320 x 200 graphics mode, copies between
; a buffer in the program's memory and the screen, keys with their
; scancodes, the mouse, the kernel font, the clock and the sci engine.
; The program draws into its own buffer (programs/gui.inc) and copies it
; to the screen with GUI_BLIT. See documentation/kernel/syscalls.md.
;
; ebx = operation, ecx / edx = its arguments; the result is in eax.

GUI_ENTER   equ 0               ; -> 0, or -1 (no memory for the text copy)
GUI_LEAVE   equ 1               ; -> 0: text mode, the screen as it was
GUI_BLIT    equ 2               ; ecx = rect block: buffer -> screen
GUI_READ    equ 3               ; ecx = rect block: screen -> buffer
GUI_KEY     equ 4               ; -> 0 none, else ASCII | scancode << 8 | Ctrl << 16
GUI_MOUSE   equ 5               ; -> x | y << 10 | buttons << 20, or -1
GUI_FONT    equ 6               ; ecx = buffer -> bytes copied (FONT_H per glyph)
GUI_TICKS   equ 7               ; -> timer ticks (100 a second)
GUI_TIME    equ 8               ; -> hours << 16 | minutes << 8 | seconds
GUI_DATE    equ 9               ; -> year << 16 | month << 8 | day
GUI_EVAL    equ 10              ; ecx = eval block -> 0, or -1 with the message
GUI_PALETTE equ 11              ; ecx = first | count << 16, edx = RGB bytes (0-63)
GUI_SYSINFO equ 12              ; edx = part, ecx = buffer or argument (sysinfo.asm, A.5)
GUI_OPS     equ 13

; Rect block: dd x, y, width, height, buffer, pitch (bytes per buffer row).
; One byte per pixel. The part of the rectangle off the screen is skipped.
GB_X        equ 0
GB_Y        equ 4
GB_W        equ 8
GB_H        equ 12
GB_BUF      equ 16
GB_PITCH    equ 20

; Eval block (GUI_EVAL)
GE_EXPR     equ 0               ; dd: the expression, zero-terminated
GE_FLAGS    equ 4               ; dd: bits 0-1 variables (0 none, 1 x, 2 x and y),
                                ;     bit 8 degrees, bit 9 store the result as ans
GE_X        equ 8               ; dq
GE_Y        equ 16              ; dq
GE_RESULT   equ 24              ; dq (out)
GE_TEXT     equ 32              ; dd: 40-byte buffer for the result as text,
                                ;     or the error message (0: none)
GE_COL      equ 36              ; dd (out): column of a syntax error, from 1

sys_gui:
    cmp ebx, GUI_OPS
    jae .bad
    jmp [gui_ops+ebx*4]
.bad:
    or eax, -1
    ret

gui_ops:
    dd gui_enter, gui_leave, gui_blit, gui_read, gui_key, gui_mouse
    dd gui_font, gui_ticks, gui_time, gui_date, gui_eval, gui_palette
    dd gui_sysinfo

gui_enter:
    call gfx_mode13
    sbb eax, eax                ; CF -> -1
    ret

gui_leave:
    call gfx_text
    xor eax, eax
    ret

; ecx = rect block. Both copies walk the rectangle pixel by pixel through
; gfx_putpixel / gfx_getpixel, which skip what is off the screen.
; The block is copied to the stack first, so a ring-3 caller's buffer is
; checked (pitch * (height - 1) + width bytes) on the values then used.
; Width and height up to 4096, pitch up to 65536; otherwise -> -1.
gui_blit:
    xor eax, eax
    jmp gui_rect
gui_read:
    mov eax, 1
gui_rect:
    sub esp, 28
    mov [esp+24], eax           ; direction: 0 blit, 1 read
    mov esi, ecx
    mov edi, esp
    mov ecx, 6
    rep movsd
    mov ebp, esp
    mov ecx, [ebp+GB_W]
    test ecx, ecx
    jle .done
    mov edx, [ebp+GB_H]
    test edx, edx
    jle .done
    cmp ecx, 4096
    ja .bad
    cmp edx, 4096
    ja .bad
    mov eax, [ebp+GB_PITCH]
    cmp eax, 65536
    ja .bad
    call gui_ring3
    jz .go
    dec edx
    imul edx, eax
    add ecx, edx
    mov esi, [ebp+GB_BUF]
    call ua_range
    jc .bad
.go:
    mov esi, [ebp+GB_BUF]
    xor edx, edx                ; row
.row:
    cmp edx, [ebp+GB_H]
    jge .done
    xor edi, edi                ; column
.col:
    cmp edi, [ebp+GB_W]
    jge .next
    mov eax, [ebp+GB_X]
    add eax, edi
    mov ebx, [ebp+GB_Y]
    add ebx, edx
    cmp byte [ebp+24], 0
    jne .rd
    mov cl, [esi+edi]
    call gfx_putpixel
    jmp .on
.rd:
    call gfx_getpixel
    mov [esi+edi], cl
.on:
    inc edi
    jmp .col
.next:
    add esi, [ebp+GB_PITCH]
    inc edx
    jmp .row
.done:
    xor eax, eax
.r:
    add esp, 28
    ret
.bad:
    or eax, -1
    jmp .r

; -> ZF clear when the caller is a ring-3 program (it has an address
; space of its own, ring3.md). Keeps every register.
gui_ring3:
    push eax
    mov eax, [proc_cur]
    cmp dword [eax+PCB_AS], 0
    pop eax
    ret

; Ring-3 pointer checks for SYS_GUI (sys_uargs, kind UA_GUI): ebx = op,
; ecx / edx its arguments -> CF if a buffer is not the caller's. The
; rect block's buffer and the eval block's strings are checked by the
; operations themselves, on their own copies of the pointers.
gui_uargs:
    pushad
    mov esi, ecx
    cmp ebx, GUI_BLIT
    je .rect
    cmp ebx, GUI_READ
    je .rect
    cmp ebx, GUI_FONT
    je .font
    cmp ebx, GUI_EVAL
    je .eval
    cmp ebx, GUI_SYSINFO
    je .sysinfo
    cmp ebx, GUI_PALETTE
    jne .ok
    shr ecx, 16                 ; count
    cmp ecx, 256
    ja .ok                      ; GUI_PALETTE refuses it itself
    lea ecx, [ecx+ecx*2]
    mov esi, edx
    jmp .range
.rect:
    mov ecx, 24
    jmp .range
.font:
    mov ecx, (FONT_LAST - FONT_FIRST + 1) * FONT_H
    jmp .range
.eval:
    mov ecx, 40
.range:
    call ua_range
    jc .bad
    jmp .ok
.sysinfo:
    call gui_sysinfo_uargs
    jc .bad
.ok:
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; A key press without waiting. Releases, Shift and Ctrl give 0 (Shift and
; Ctrl are tracked, as for SYS_GETC). Esc and Backspace give 27 and 8.
gui_key:
    cli
    call kbd_dequeue
    sti
    jc .none
    call kbd_shift_track
    je .none
    cmp al, 0x80
    jae .none
    movzx edx, al
    cmp al, 0x01
    mov cl, 27
    je .got
    cmp al, 0x0E
    mov cl, 8
    je .got
    call kbd_ascii
    mov cl, al
.got:
    movzx eax, cl
    mov ah, dl
    cmp byte [kbd_ctrl], 0
    je .r
    or eax, 1 << 16
.r:
    ret
.none:
    xor eax, eax
    ret

gui_mouse:
    call mouse_poll
    or eax, -1
    cmp byte [mouse_up], 0
    je .r
    mov eax, [mouse_y]
    shl eax, 10
    or eax, [mouse_x]
    movzx ebx, byte [mouse_btns]
    shl ebx, 20
    or eax, ebx
.r:
    ret

gui_font:
    mov edi, ecx
    mov esi, font5x7
    mov ecx, (FONT_LAST - FONT_FIRST + 1) * FONT_H
    mov eax, ecx
    rep movsb
    ret

gui_ticks:
    mov eax, [ticks]
    ret

; CMOS clock: registers 0 (seconds), 2, 4 / 7 (day), 8, 9 and 0x32 (century).
gui_time:
    mov esi, gui_rtc_time
    jmp gui_rtc
gui_date:
    mov esi, gui_rtc_date
gui_rtc:
.wait:
    mov al, 0x0A                ; not while the clock is updating
    out 0x70, al
    in al, 0x71
    test al, 0x80
    jnz .wait
    xor eax, eax
    mov ecx, 3
.reg:
    shl eax, 8
    lodsb                       ; al was 0 after the shift
    out 0x70, al
    in al, 0x71
    call gui_bcd
    loop .reg
    cmp esi, gui_rtc_date + 3
    jne .r
    mov ebx, eax                ; date so far: yy << 16 | month << 8 | day
    mov al, 0x32
    out 0x70, al
    in al, 0x71
    call gui_bcd
    movzx eax, al
    test eax, eax
    jnz .cent
    mov al, 20                  ; no century register
.cent:
    imul eax, eax, 100
    mov ecx, ebx
    shr ecx, 16
    add eax, ecx                ; century * 100 + yy
    and ebx, 0xFFFF
    shl eax, 16
    or eax, ebx
.r:
    ret

; al = register value -> al binary (the clock may count in BCD: register B
; bit 2 clear). Only al changes.
gui_bcd:
    push ecx
    mov cl, al
    mov al, 0x0B
    out 0x70, al
    in al, 0x71
    test al, 4
    mov al, cl
    jnz .r
    shr cl, 4                   ; tens
    and al, 0x0F
    add cl, cl
    add al, cl
    shl cl, 2
    add al, cl                  ; units + tens * (2 + 8)
.r:
    pop ecx
    ret

gui_rtc_time db 4, 2, 0
gui_rtc_date db 9, 8, 7

; ecx = eval block. Uses the sci engine (sci.asm) with x and y as diff's
; functions do. Resets the FPU.
gui_eval:
    mov ebp, ecx
    mov eax, [ebp+GE_TEXT]      ; the pointers, read once
    mov [gui_ev_text], eax
    mov esi, [ebp+GE_EXPR]
    mov [gui_ev_expr], esi
    call gui_ring3
    jz .checked
    call ua_str
    jc .bad
    test eax, eax
    jz .checked
    mov esi, eax
    mov ecx, 40
    call ua_range
    jc .bad
.checked:
    fninit
    mov al, [sci_deg]
    push eax
    mov eax, [ebp+GE_FLAGS]
    mov [diff_vars], al
    and byte [diff_vars], 3
    shr eax, 8
    and al, 1
    mov [sci_deg], al
    fld qword [ebp+GE_Y]
    fstp qword [sci_y]
    mov eax, [gui_ev_expr]
    mov [diff_f], eax
    fld qword [ebp+GE_X]
    call diff_f_at
    jc .err
    call diff_status
    jc .err
    fst qword [ebp+GE_RESULT]
    test dword [ebp+GE_FLAGS], 1 << 9
    jz .noans
    fst qword [sci_ans]
.noans:
    call sci_fmt                ; pops st0 into sci_out
    mov esi, sci_out
    xor ebx, ebx
    jmp .text
.err:
    fninit
    mov eax, [calc_errpos]
    sub eax, [gui_ev_expr]
    inc eax
    mov [ebp+GE_COL], eax
    mov esi, [calc_errmsg]
    or ebx, -1
.text:
    pop eax
    mov [sci_deg], al
    mov edi, [gui_ev_text]
    test edi, edi
    jz .r
    mov ecx, 39
.copy:
    lodsb
    stosb
    test al, al
    loopnz .copy
    mov byte [edi], 0
.r:
    mov eax, ebx
    ret
.bad:
    or eax, -1
    ret

; ecx = first entry | count << 16, edx = 3 bytes (red, green, blue, 0-63)
; an entry. Only DAC entries 64-255 may change: the text mode uses 0-63,
; so the text screen comes back with its colours. -> 0, or -1.
gui_palette:
    movzx eax, cx               ; first
    shr ecx, 16                 ; count
    cmp eax, 64
    jb .bad
    lea ebx, [eax+ecx]
    cmp ebx, 256
    ja .bad
    mov esi, edx
    mov dx, 0x3C8
    out dx, al
    inc dx
    lea ecx, [ecx+ecx*2]
    rep outsb
    xor eax, eax
    ret
.bad:
    or eax, -1
    ret

gui_ev_expr dd 0
gui_ev_text dd 0
