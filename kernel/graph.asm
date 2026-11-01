; Squirrel-OS/2 — graphing calculator (graph), 1.3.3
; Included from pm.asm. Original code.
;
; Plots y = f(x) in graphics mode with the 1.3 primitives (gfx.asm). f is a
; sci expression in x, evaluated by diff_f_at for each of the 320 columns.
; The window is x and y from -10 to 10. See documentation/apps/calculators.md.

GR_LABEL_MAX equ 50             ; characters of "y = f" drawn on the plot

run_graph:
    call cls
    mov esi, graph_banner
    call puts
    mov esi, graph_help
    call puts
.prompt:
    mov esi, graph_prompt
    call puts
    call calc_readline
    jc .quit
    mov esi, calc_line
    call calc_skip
    cmp byte [esi], 0
    je .prompt
    mov edi, calc_kw_q
    call streq
    je .quit
    mov edi, calc_kw_quit
    call streq
    je .quit
    mov al, [sci_deg]           ; sin(x) and friends take radians here
    push eax
    mov byte [sci_deg], 0
    call graph_command
    pop ebx
    mov [sci_deg], bl
    jc .error
    jmp .prompt
.error:
    fninit
    mov esi, [lstr+LS_CALC_ERRPRE*4]
    call puts
    mov esi, [calc_errmsg]
    call puts
    lcmp calc_errmsg, LS_CALC_E_SYNTAX
    jne .errnl
    mov eax, [calc_errpos]
    sub eax, calc_line
    inc eax
    call itoa
    mov esi, num_buf
    call puts
.errnl:
    mov al, 10
    call putc
    jmp .prompt
.quit:
    call app_home
    xor eax, eax
    ret

; esi = command line: "y = f" or just "f". Plots it, waits for a key and
; prints a summary line; CF with calc_errmsg on a syntax error (checked at
; x = 0 before the screen changes) or when there is no memory for graphics.
graph_command:
    fninit
    cmp byte [esi], 'y'
    jne .expr
    push esi
    inc esi
    call calc_skip
    cmp byte [esi], '='
    pop eax
    jne .expr
    lea esi, [eax+1]
    call calc_skip
    inc esi                     ; past '='
    call calc_skip
.expr:
    cmp byte [esi], 0
    je calc_syntax
    mov [diff_f], esi
    mov byte [diff_vars], 1     ; x only
    fldz                        ; syntax check before anything is drawn;
    call diff_f_at              ; a domain error at 0 (1/x, ln(x)) is fine
    jnc .syntaxok
    lcmp calc_errmsg, LS_CALC_E_SYNTAX
    stc
    je .r
.syntaxok:
    fninit
    ; the label "y = f", cut to what fits on the plot
    mov edi, gr_label + 4
    mov esi, [diff_f]
    mov ecx, GR_LABEL_MAX
.lab:
    lodsb
    stosb
    test al, al
    jz .labok
    loop .lab
    mov byte [edi], 0
.labok:
    call gfx_mode13
    jnc .draw
    mov dword [calc_errmsg], gr_e_nomem
    stc
.r:
    ret
.draw:
    call graph_plot
    call fb_waitkey             ; any key: back to text
    call gfx_text
    mov esi, gr_done            ; "Plotted y = f for x from -10 to 10: "
    call puts
    mov esi, gr_label + 4
    call puts
    mov esi, gr_done2
    call puts
    mov eax, GFX_W
    sub eax, [gr_undef]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, gr_done3           ; " points, "
    call puts
    mov eax, [gr_shown]
    call itoa
    mov esi, num_buf
    call puts
    mov esi, gr_done4           ; " on screen"
    call puts
    clc
    ret

; Axes, the curve, then the label and the range on top. Consecutive
; points are joined by a line; a point where f is undefined (or far off
; screen) breaks the curve.
graph_plot:
    xor eax, eax
    xor ebx, ebx
    mov ecx, GFX_W
    mov edx, GFX_H
    mov byte [gfx_colour], 0
    call gfx_fillrect
    mov byte [gfx_colour], GR_AXIS
    xor eax, eax                ; x axis
    mov ebx, GR_Y0
    mov ecx, GFX_W - 1
    mov edx, GR_Y0
    call gfx_line
    mov eax, GR_X0              ; y axis
    xor ebx, ebx
    mov ecx, GR_X0
    mov edx, GFX_H - 1
    call gfx_line
    mov byte [gfx_colour], GR_CURVE
    mov dword [gr_undef], 0
    mov dword [gr_shown], 0
    mov byte [gr_have], 0
    xor esi, esi                ; column
.col:
    mov [gr_px], esi
    fild dword [gr_px]          ; x = -10 + column * 20 / 320
    fmul qword [gr_xstep]
    fadd qword [gr_min]
    fnclex
    call diff_f_at              ; CF: a domain error such as sqrt(-1) (the
    jc .error                   ; syntax was checked at x = 0)
    fnstsw ax
    test al, FPU_IE | FPU_ZE | FPU_OE
    jnz .undef
    fmul qword [gr_yscale]      ; row = 100 - y * 10
    fsubr qword [gr_yrow0]
    fcom qword [gr_far_lo]
    fnstsw ax
    sahf
    jb .far
    fcom qword [gr_far_hi]
    fnstsw ax
    sahf
    ja .far
    fistp dword [gr_py]
    mov eax, [gr_py]
    cmp eax, GFX_H
    jae .drawn
    inc dword [gr_shown]
.drawn:
    cmp byte [gr_have], 0
    je .dot
    mov eax, [gr_lastx]
    mov ebx, [gr_lasty]
    mov ecx, esi
    mov edx, [gr_py]
    call gfx_line
    jmp .keep
.dot:
    mov eax, esi
    mov ebx, [gr_py]
    mov cl, [gfx_colour]
    call gfx_putpixel
.keep:
    mov [gr_lastx], esi
    mov eax, [gr_py]
    mov [gr_lasty], eax
    mov byte [gr_have], 1
    jmp .next
.error:
    fninit                      ; sci may leave its operands on the stack
    inc dword [gr_undef]
    mov byte [gr_have], 0
    jmp .next
.undef:
    inc dword [gr_undef]
.far:
    fstp st0
    mov byte [gr_have], 0
.next:
    inc esi
    cmp esi, GFX_W
    jb .col
    fninit
    mov byte [gfx_colour], GR_TEXT  ; last, so the curve does not cover it
    mov byte [gfx_bg], 0
    mov esi, gr_label
    mov eax, 2
    mov ebx, 2
    call gfx_drawstr
    mov esi, gr_range
    mov ebx, GFX_H - GFX_CELL_H - 1
    call gfx_drawstr
    ret

GR_X0 equ GFX_W / 2             ; screen column of x = 0
GR_Y0 equ GFX_H / 2             ; screen row of y = 0
; The DAC keeps the text mode's 64 EGA colours, where the bright ones sit
; at 0x38-0x3F (the text attribute controller maps 8-15 there).
GR_AXIS equ 0x38                ; dark grey
GR_TEXT equ 0x3F                ; white
GR_CURVE equ 0x3E               ; yellow

graph_banner db 'Graphing Calculator (Esc to exit)', 10, 0
graph_help db 'y = <f(x)>   plots f for x and y from -10 to 10, e.g.  y = sin(x)', 10
           db 'Any key returns from the plot. f is a sci expression in x;', 10
           db 'angles are radians. q quits', 10, 0
graph_help_len equ $ - graph_help - 1
graph_prompt db 'graph> ', 0
gr_label db 'y = '
         times GR_LABEL_MAX + 1 db 0
gr_range db 'x, y: -10 to 10', 0
gr_done db 'Plotted y = ', 0
gr_done2 db ' for x from -10 to 10: ', 0
gr_done3 db ' points, ', 0
gr_done4 db ' on screen', 10, 0
gr_e_nomem db 'not enough memory for graphics', 0

align 8
gr_min dq -10.0
gr_xstep dq 0.0625              ; 20 / 320
gr_yscale dq 10.0               ; rows per unit
gr_yrow0 dq 100.0               ; row of y = 0
gr_far_lo dq -1000.0            ; rows past these break the curve
gr_far_hi dq 1200.0
gr_px dd 0
gr_py dd 0
gr_lastx dd 0
gr_lasty dd 0
gr_undef dd 0
gr_shown dd 0
gr_have db 0
