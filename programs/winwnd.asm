; winwnd — a Win32 GUI program, PE32 written by hand (P.6). Original code.
; Exercises winrun's USER32/GDI32: a window class and a window, WM_CREATE,
; WM_PAINT with TextOut, a brush and Rectangle, SetPixel/GetPixel, a line,
; a timer, the keyboard through TranslateMessage, DestroyWindow and
; PostQuitMessage.
;   run winwnd    a window "Acorn window"; Q checks and shows "winwnd: PASS"
;                 (or "winwnd: FAIL"), X closes it
; Build: nasm -f bin winwnd.asm -o winwnd
BITS 32

IMAGEBASE   equ 0x400000
SECT_RVA    equ 0x1000
%define RVA(x) ((x) - sect + SECT_RVA)
%define VA(x)  (RVA(x) + IMAGEBASE)

%assign NFIX 0
%macro FIX 0                    ; the last four bytes are an absolute address
fix_%[NFIX] equ $ - 4
%assign NFIX NFIX+1
%endmacro
%macro FIXB 1                   ; ... with %1 bytes after them
fix_%[NFIX] equ $ - 4 - %1
%assign NFIX NFIX+1
%endmacro
%macro CALLI 1                  ; call an import through the IAT
    call [VA(iat_%1)]
    FIX
%endmacro
%macro PUSHV 1                  ; push the address of a label
    push VA(%1)
    FIX
%endmacro

WM_CREATE equ 1
WM_DESTROY equ 2
WM_PAINT equ 0x0F
WM_CHAR equ 0x102
WM_TIMER equ 0x113

mz:
    dw 'MZ'
    times 0x3A db 0
    dd pe - mz
pe:
    db 'PE', 0, 0
    dw 0x14C, 1
    dd 0, 0, 0
    dw opt_end - opt
    dw 0x0102
opt:
    dw 0x10B
    db 1, 0
    dd sect_end - sect, 0, 0
    dd RVA(start)
    dd SECT_RVA, SECT_RVA
    dd IMAGEBASE
    dd 0x1000, 0x200
    dw 4, 0, 0, 0, 4, 0
    dd 0
    dd SECT_RVA + ((sect_end - sect + 0xFFF) & ~0xFFF)
    dd sect - mz
    dd 0
    dw 2                            ; IMAGE_SUBSYSTEM_WINDOWS_GUI
    dw 0x0040
    dd 0x100000, 0x1000, 0x100000, 0x1000
    dd 0, 16
    dd 0, 0
    dd RVA(imports), imports_end - imports
    dd 0, 0, 0, 0, 0, 0
    dd RVA(relocs), relocs_end - relocs
    times 10 dd 0, 0
opt_end:
    db '.text', 0, 0, 0
    dd sect_end - sect
    dd SECT_RVA
    dd sect_file_end - sect
    dd sect - mz
    dd 0, 0, 0
    dd 0xE0000060
    times 0x200 - ($ - mz) db 0

sect:
start:
    PUSHV wc
    CALLI RegisterClassA
    test eax, eax
    jz .bad
    push 0
    push 0
    push 0
    push 0
    push 0x80000000                 ; CW_USEDEFAULT x 4
    push 0x80000000
    push 0x80000000
    push 0x80000000
    push 0x00CF0000                 ; WS_OVERLAPPEDWINDOW
    PUSHV title
    PUSHV clsname
    push 0
    CALLI CreateWindowExA
    test eax, eax
    jz .bad
    mov [VA(hwnd)], eax
    FIX
    push 1                          ; SW_SHOWNORMAL
    push eax
    CALLI ShowWindow
    push dword [VA(hwnd)]
    FIX
    CALLI UpdateWindow
.loop:
    push 0
    push 0
    push 0
    PUSHV msg
    CALLI GetMessageA
    test eax, eax
    jz .quit
    PUSHV msg
    CALLI TranslateMessage
    PUSHV msg
    CALLI DispatchMessageA
    jmp .loop
.quit:
    push dword [VA(msg) + 8]        ; wParam of WM_QUIT
    FIX
    CALLI ExitProcess
.bad:
    push 2
    CALLI ExitProcess

; LRESULT wndproc(hwnd, msg, wParam, lParam)
wndproc:
    push ebx
    push esi
    push edi
    push ebp
    mov ebx, [esp+20]               ; hwnd
    mov eax, [esp+24]               ; msg
    cmp eax, WM_CREATE
    je .create
    cmp eax, WM_PAINT
    je .paint
    cmp eax, WM_TIMER
    je .timer
    cmp eax, WM_CHAR
    je .char
    cmp eax, WM_DESTROY
    je .destroy
    pop ebp
    pop edi
    pop esi
    pop ebx
    jmp [VA(iat_DefWindowProcA)]    ; the same four arguments
    FIX
.create:
    inc dword [VA(n_create)]
    FIX
    push 0
    push 50                         ; a timer every 50 ms
    push 1
    push ebx
    CALLI SetTimer
    jmp .zero
.timer:
    inc dword [VA(n_timer)]
    FIX
    jmp .zero
.char:
    mov eax, [esp+28]
    cmp al, 'x'
    je .close
    cmp al, 'q'
    jne .zero
    mov ecx, VA(failtext)           ; everything seen so far?
    FIX
    cmp dword [VA(n_create)], 1
    FIXB 1
    jne .v
    cmp dword [VA(n_paint)], 0
    FIXB 1
    je .v
    cmp dword [VA(n_timer)], 0
    FIXB 1
    je .v
    cmp dword [VA(pix_ok)], 3
    FIXB 1
    jne .v
    mov ecx, VA(passtext)
    FIX
.v:
    mov [VA(verdict)], ecx
    FIX
    push 1
    push 0
    push ebx
    CALLI InvalidateRect
    jmp .zero
.close:
    push ebx
    CALLI DestroyWindow
    jmp .zero
.destroy:
    push 0
    CALLI PostQuitMessage
    jmp .zero
.paint:
    inc dword [VA(n_paint)]
    FIX
    PUSHV ps
    push ebx
    CALLI BeginPaint
    mov esi, eax                    ; hdc
    push 20
    PUSHV hello
    push 4
    push 4
    push esi
    CALLI TextOutA
    push 0x000000FF                 ; red
    CALLI CreateSolidBrush
    push eax
    push esi
    CALLI SelectObject
    push 50
    push 60
    push 20
    push 10
    push esi
    CALLI Rectangle                 ; 10,20 - 60,50: black edge, red inside
    push 0x00FF0000                 ; blue
    push 30
    push 100
    push esi
    CALLI SetPixel
    mov edi, eax
    push 30
    push 100
    push esi
    CALLI GetPixel
    xor ebp, ebp
    cmp eax, edi
    jne .p1
    cmp eax, 0x00FF0000
    jne .p1
    inc ebp
.p1:
    push 35
    push 30
    push esi
    CALLI GetPixel
    cmp eax, 0x000000FF
    jne .p2
    inc ebp
.p2:
    push 20                         ; the top edge: the black pen
    push 30
    push esi
    CALLI GetPixel
    test eax, eax
    jnz .p3
    inc ebp
.p3:
    mov [VA(pix_ok)], ebp
    FIX
    push 0
    push 40
    push 120
    push esi
    CALLI MoveToEx
    push 70
    push 200
    push esi
    CALLI LineTo
    mov eax, [VA(verdict)]
    FIX
    test eax, eax
    jz .nov
    push 12
    push eax
    push 80
    push 4
    push esi
    CALLI TextOutA
.nov:
    PUSHV ps
    push ebx
    CALLI EndPaint
.zero:
    xor eax, eax
    pop ebp
    pop edi
    pop esi
    pop ebx
    ret 16

wc dd 0, VA(wndproc), 0, 0, 0, 0, 0, 6, 0, VA(clsname)
fix_%[NFIX] equ wc + 4
%assign NFIX NFIX+1
fix_%[NFIX] equ wc + 36
%assign NFIX NFIX+1
clsname db 'AcornClass', 0
title db 'Acorn window', 0
hello db 'Hello from Win32 GUI'
passtext db 'winwnd: PASS'
failtext db 'winwnd: FAIL'
align 4
hwnd dd 0
n_create dd 0
n_paint dd 0
n_timer dd 0
pix_ok dd 0
verdict dd 0
msg times 7 dd 0
ps times 16 dd 0

; ---------- imports: three DLLs ----------
%macro DLL 2-*                      ; tag, functions...
%define DLLTAG %1
%rotate 1
ilt_%[DLLTAG]:
%rep %0-1
    dd RVA(hn_%1)
%rotate 1
%endrep
%rotate 1                       ; past the tag
    dd 0
iat_start_%[DLLTAG]:
%rep %0-1
iat_%1: dd RVA(hn_%1)
%rotate 1
%endrep
%rotate 1                       ; past the tag
    dd 0
%rep %0-1
hn_%1: dw 0
    db %str(%1), 0
    align 2, db 0
%rotate 1
%endrep
%rotate 1                       ; past the tag
%endmacro
    align 4, db 0
imports:
    dd RVA(ilt_k), 0, 0, RVA(n_k), RVA(iat_start_k)
    dd RVA(ilt_u), 0, 0, RVA(n_u), RVA(iat_start_u)
    dd RVA(ilt_g), 0, 0, RVA(n_g), RVA(iat_start_g)
    dd 0, 0, 0, 0, 0
imports_end:
DLL k, ExitProcess
DLL u, RegisterClassA, CreateWindowExA, ShowWindow, UpdateWindow, GetMessageA, TranslateMessage, DispatchMessageA, DefWindowProcA, SetTimer, InvalidateRect, DestroyWindow, PostQuitMessage, BeginPaint, EndPaint
DLL g, TextOutA, CreateSolidBrush, SelectObject, Rectangle, SetPixel, GetPixel, MoveToEx, LineTo
n_k db 'KERNEL32.dll', 0
n_u db 'USER32.dll', 0
n_g db 'GDI32.dll', 0

; ---------- base relocations: one block for the section's first page ----------
    align 4, db 0
relocs:
    dd SECT_RVA, relocs_end - relocs
%assign i 0
%rep NFIX
    dw 0x3000 | (fix_%[i] - sect)
%assign i i+1
%endrep
    align 4, db 0
relocs_end:
%if relocs_end - sect > 0x1000
%error the section outgrew the single relocation block
%endif
sect_end:
    times (0x200 - ($ - sect) % 0x200) % 0x200 db 0
sect_file_end:
