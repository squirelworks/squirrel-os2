; dosvga.inc — VGA mode 13h for dosrun (P.8). Original code.
;
; INT 10h AX=0013h puts the screen in graphics (SYS_GUI): the DOS
; program's A000:0000 is its 320 x 200 screen, one byte a pixel, and
; dosrun copies it to the display (through the colour table below) when
; the program waits for a key, reads the clock or the retrace port, ends,
; and at least every VGA_SLICE instructions. The BIOS teletype writes in
; graphics with the kernel's 5 x 7 font in 6 x 8 cells (53 x 25), into
; A000 like a real BIOS. Colours: the program's 256-entry DAC (INT 10h
; AX=1010h/1012h, ports 3C8h/3C9h) goes to the display's entries 64-255
; as they are; entries 0-63 show as the nearest of the display's fixed
; 64 EGA colours. Any other mode goes back to text.

SYS_GUI_    equ 35
VG_ENTER    equ 0
VG_LEAVE    equ 1
VG_BLIT     equ 2
VG_KEY      equ 4
VG_FONT     equ 6
VG_TICKS    equ 7
VG_PALETTE  equ 11
VGA_SEG     equ 0xA000
VGA_COLS    equ 53
VGA_ROWS    equ 25
VGA_SLICE   equ 200000

; INT 10h AH=00h: AL = mode
vga_setmode:
    mov al, [rAX]
    and al, 0x7F
    cmp al, 0x13
    je .gfx
    jmp vga_leave
.gfx:
    cmp byte [vmode], 0x13
    je .clear
    cmp dword [vframe], 0
    jne .have
    mov eax, SYS_SBRK           ; the display copy and the font
    mov ebx, 64000 + 96*7
    int 0x80
    cmp eax, -1
    je .r
    mov [vframe], eax
    add eax, 64000
    mov [vfont], eax
    mov ecx, eax
    mov eax, SYS_GUI_
    mov ebx, VG_FONT
    int 0x80
.have:
    mov eax, SYS_GUI_
    mov ebx, VG_ENTER
    int 0x80
    test eax, eax
    jnz .r                      ; no graphics: the program stays in text
    mov byte [vmode], 0x13
    call vga_default_dac
.clear:
    mov dword [vcur], 0
    test byte [rAX], 0x80       ; bit 7: keep the screen
    jnz .flush
    mov edi, [mem]
    add edi, VGA_SEG*16
    mov ecx, 64000/4
    xor eax, eax
    rep stosd
.flush:
    jmp vga_flush
.r:
    ret

; back to text mode (any mode but 13h, and the program's end)
vga_leave:
    cmp byte [vmode], 0x13
    jne .r
    call vga_flush
    mov eax, SYS_GUI_
    mov ebx, VG_LEAVE
    int 0x80
    mov byte [vmode], 3
.r:
    ret

; the DAC a VGA starts mode 13h with: 16 EGA colours, 16 greys, then
; 24 hues in nine brightness and saturation steps (made here, not copied)
vga_default_dac:
    pushad
    mov esi, vga_ega16
    mov edi, vdac
    mov ecx, 16*3
    rep movsb
    xor eax, eax                ; 16-31: grey 0 .. 63
.grey:
    imul ebx, eax, 63
    push eax
    mov eax, ebx
    xor edx, edx
    mov ebx, 15
    div ebx
    mov bl, al
    pop eax
    mov [edi], bl
    mov [edi+1], bl
    mov [edi+2], bl
    add edi, 3
    inc eax
    cmp eax, 16
    jb .grey
    xor ebp, ebp                ; 32-255: step 0..8, hue 0..23
.step:
    xor edx, edx
.hue:
    ; a ramp up/down for each primary: hue 0..23 around the wheel
    mov eax, edx
    call .ramp                  ; red: hue
    mov [edi], al
    lea eax, [edx+16]
    call .ramp                  ; green: hue - 8
    mov [edi+1], al
    lea eax, [edx+8]
    call .ramp                  ; blue: hue - 16
    mov [edi+2], al
    ; brightness: steps 0-2 full, 3-5 two thirds, 6-8 a third; each
    ; group from saturated to pale
    mov ecx, 3
.ch:
    movzx eax, byte [edi+ecx-1]
    mov ebx, ebp
    push edx
    xor edx, edx
    push eax
    mov eax, ebx
    mov ebx, 3
    div ebx                     ; eax = group, edx = paleness
    mov ebx, edx
    mov edx, eax
    pop eax
    imul ebx, 21                ; pale: lift towards white
    push ecx
    mov ecx, 63
    sub ecx, eax
    imul ecx, ebx
    shr ecx, 6
    add eax, ecx
    pop ecx
    mov ebx, 3                  ; dim by the group
    sub ebx, edx
    imul eax, ebx
    xor edx, edx
    push ecx
    mov ecx, 3
    div ecx
    pop ecx
    pop edx
    mov [edi+ecx-1], al
    loop .ch
    add edi, 3
    inc edx
    cmp edx, 24
    jb .hue
    inc ebp
    cmp ebp, 9
    jb .step
    popad
    jmp vga_lut
; eax = hue position (mod 24) -> al = 0..63: 0-3 rise, 4-11 full, 12-15 fall
.ramp:
    push edx
    xor edx, edx
    push ecx
    mov ecx, 24
    div ecx
    pop ecx
    mov eax, edx
    pop edx
    cmp eax, 4
    jb .up
    cmp eax, 12
    jb .full
    cmp eax, 16
    jb .down
    xor eax, eax
    ret
.up:
    imul eax, 16
    ret
.full:
    mov eax, 63
    ret
.down:
    sub eax, 16
    neg eax
    imul eax, 16
    cmp eax, 63
    jbe .d
    mov eax, 63
.d:
    ret

; the display's colours from the DAC: 64-255 as they are, 0-63 nearest
vga_lut:
    pushad
    xor ebx, ebx                ; DOS colour
.c:
    cmp ebx, 64
    jae .same
    lea esi, [vdac+ebx*2]
    add esi, ebx                ; its r, g, b
    mov ebp, 0x7FFFFFFF         ; best distance
    xor edi, edi                ; candidate 0..63
.cand:
    ; EGA 64: bit 2/5 red, 1/4 green, 0/3 blue; low bits 42, high bits 21
    xor edx, edx                ; distance
    mov ecx, 2                  ; red: bits 2 and 5
    call .dist
    mov ecx, 1
    call .dist
    xor ecx, ecx
    call .dist
    cmp edx, ebp
    jae .worse
    mov ebp, edx
    mov eax, edi
    mov [vlut+ebx], al
.worse:
    inc edi
    cmp edi, 64
    jb .cand
    jmp .nx
.same:
    mov [vlut+ebx], bl
.nx:
    inc ebx
    cmp ebx, 256
    jb .c
    cmp byte [vmode], 0x13
    jne .r
    mov eax, SYS_GUI_
    mov ebx, VG_PALETTE
    mov ecx, 64 | (192 << 16)
    mov edx, vdac+64*3
    int 0x80
.r:
    popad
    ret
; ecx = 2 red, 1 green, 0 blue; edi = candidate, esi = r g b: edx += d*d
.dist:
    xor eax, eax
    bt edi, ecx
    jnc .lo
    add eax, 42
.lo:
    add ecx, 3
    bt edi, ecx
    jnc .hi
    add eax, 21
.hi:
    sub ecx, 3
    push ebx
    mov ebx, 2
    sub ebx, ecx                ; r at +0, g +1, b +2
    movzx ebx, byte [esi+ebx]
    sub eax, ebx
    pop ebx
    imul eax, eax
    add edx, eax
    ret

; the screen to the display, now
vga_flush:
    cmp byte [vmode], 0x13
    jne .r
    pushad
    mov esi, [mem]
    add esi, VGA_SEG*16
    mov edi, [vframe]
    mov ecx, 64000
    xor eax, eax
.t:
    lodsb
    mov al, [vlut+eax]
    stosb
    loop .t
    mov eax, [vframe]
    mov [vrect+16], eax
    mov eax, SYS_GUI_
    mov ebx, VG_BLIT
    mov ecx, vrect
    int 0x80
    mov eax, SYS_GUI_
    mov ebx, VG_TICKS
    int 0x80
    mov [vticks], eax
    mov dword [vslice], VGA_SLICE
    popad
.r:
    ret

; a flush when a tick has passed since the last one
vga_tick:
    cmp byte [vmode], 0x13
    jne .r
    push eax
    push ebx
    mov eax, SYS_GUI_
    mov ebx, VG_TICKS
    int 0x80
    cmp eax, [vticks]
    pop ebx
    pop eax
    je .r
    call vga_flush
.r:
    ret

; al = character, bl = colour: the BIOS teletype in graphics
vga_tty:
    pushad
    movzx eax, al
    movzx edx, word [vcur]      ; column
    movzx ecx, word [vcur+2]    ; row
    cmp al, 13
    je .cr
    cmp al, 10
    je .lf
    cmp al, 8
    je .bs
    cmp al, 7
    je .done
    call vga_glyph
    inc edx
    cmp edx, VGA_COLS
    jb .done
    xor edx, edx
    jmp .lf
.cr:
    xor edx, edx
    jmp .done
.bs:
    test edx, edx
    jz .done
    dec edx
    jmp .done
.lf:
    inc ecx
    cmp ecx, VGA_ROWS
    jb .done
    dec ecx
    push ecx                    ; scroll A000 up one text row
    mov edi, [mem]
    add edi, VGA_SEG*16
    lea esi, [edi+320*8]
    mov ecx, 320*192/4
    rep movsd
    mov ecx, 320*8/4
    xor eax, eax
    rep stosd
    pop ecx
.done:
    mov [vcur], dx
    mov [vcur+2], cx
    popad
    ret

; eax = character, bl = ink, edx = column, ecx = row: one 6 x 8 cell
vga_glyph:
    pushad
    imul edi, ecx, 320*8
    imul edx, 6
    add edi, edx
    add edi, [mem]
    add edi, VGA_SEG*16
    sub eax, 0x20
    cmp eax, 0x7E-0x20
    jbe .ok
    xor eax, eax                ; no glyph: a blank
.ok:
    imul esi, eax, 7
    add esi, [vfont]
    test bl, bl
    jnz .ink
    mov bl, 15
.ink:
    mov ecx, 8
.row:
    xor eax, eax
    cmp ecx, 1                  ; the eighth row is spacing
    je .bits
    lodsb
.bits:
    mov edx, 0x10
    push edi
.px:
    mov byte [edi], 0
    test eax, edx
    jz .bg
    mov [edi], bl
.bg:
    inc edi
    shr edx, 1
    jnz .px
    mov byte [edi], 0           ; the spacing column
    pop edi
    add edi, 320
    loop .row
    popad
    ret

; INT 10h 0Ch: AL colour at CX, DX; 0Dh: read it
vga_pixel:
    movzx eax, word [rCX]
    movzx edx, word [rDX]
    cmp eax, 320
    jae .r
    cmp edx, 200
    jae .r
    imul edx, 320
    add edx, eax
    add edx, [mem]
    add edx, VGA_SEG*16
    cmp byte [rAX+1], 0x0D
    je .get
    mov al, [rAX]
    mov [edx], al
.r:
    ret
.get:
    mov al, [edx]
    mov [rAX], al
    ret

; INT 10h AH=10h: AL 10h one DAC entry (BX, DH CH CL), 12h a block
; (BX first, CX count, ES:DX), 15h/17h read them back
vga_dac:
    movzx ebx, word [rBX]
    and ebx, 0xFF
    lea edi, [vdac+ebx*2]
    add edi, ebx
    mov al, [rAX]
    cmp al, 0x10
    je .one
    cmp al, 0x15
    je .get1
    cmp al, 0x12
    je .block
    cmp al, 0x17
    je .block
    ret
.one:
    mov al, [rDX+1]
    mov [edi], al
    mov al, [rCX+1]
    mov [edi+1], al
    mov al, [rCX]
    mov [edi+2], al
    jmp .chg
.get1:
    mov al, [edi]
    mov [rDX+1], al
    mov al, [edi+1]
    mov [rCX+1], al
    mov al, [edi+2]
    mov [rCX], al
    ret
.block:
    movzx ecx, word [rCX]
    mov eax, 256
    sub eax, ebx
    cmp ecx, eax
    jbe .n
    mov ecx, eax
.n:
    imul ecx, 3
    mov ax, [sES]
    mov dx, [rDX]
    call lin
    mov esi, eax
    cmp byte [rAX], 0x17
    je .read
    rep movsb
    jmp .chg
.read:
    xchg esi, edi
    rep movsb
    ret
.chg:
    jmp vga_lut

; port I/O: edx = port, al = byte written (OUT) or returned (IN)
vga_out:
    cmp dx, 0x3C8
    jne .data
    mov [vdac_idx], al
    mov byte [vdac_rgb], 0
    ret
.data:
    cmp dx, 0x3C9
    jne .r
    and al, 63
    movzx ecx, byte [vdac_idx]
    lea ecx, [ecx*2+ecx]
    movzx ebx, byte [vdac_rgb]
    mov [vdac+ecx+ebx], al
    inc ebx
    cmp ebx, 3
    jb .keep
    xor ebx, ebx
    inc byte [vdac_idx]
    call vga_lut                ; one entry done
.keep:
    mov [vdac_rgb], bl
.r:
    ret
vga_in:                          ; -> al
    cmp dx, 0x3DA               ; input status: retrace bits toggle, so
    jne .dac                    ; "wait for the retrace" loops end
    xor byte [vretrace], 0x09
    mov al, [vretrace]
    jmp vga_tick
.dac:
    mov al, 0xFF
    cmp dx, 0x3C9
    jne .r
    movzx ecx, byte [vdac_idx]
    lea ecx, [ecx*2+ecx]
    movzx ebx, byte [vdac_rgb]
    mov al, [vdac+ecx+ebx]
    inc ebx
    cmp ebx, 3
    jb .k
    xor ebx, ebx
    inc byte [vdac_idx]
.k:
    mov [vdac_rgb], bl
.r:
    ret

; graphics keyboard: -> eax = 0 when none, else scan << 8 | ASCII
vga_key:
    push ebx
    mov eax, SYS_GUI_
    mov ebx, VG_KEY
    int 0x80
    pop ebx
    and eax, 0xFFFF
    cmp al, 10
    jne .r
    mov al, 13
.r:
    ret

vga_ega16 db 0,0,0, 0,0,42, 0,42,0, 0,42,42, 42,0,0, 42,0,42, 42,21,0, 42,42,42
          db 21,21,21, 21,21,63, 21,63,21, 21,63,63, 63,21,21, 63,21,63, 63,63,21, 63,63,63
vrect dd 0, 0, 320, 200, 0, 320
vmode db 3
vink db 15
align 4, db 0
vslice dd VGA_SLICE
