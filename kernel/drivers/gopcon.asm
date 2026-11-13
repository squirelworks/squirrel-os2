; Squirrel-OS/2 — text console on a UEFI GOP framebuffer, H.2 (OS2-HW)
; Included from pm.asm (high image). Original code.
;
; A PC started by UEFI firmware (boot/uefi/) may have no VGA text mode:
; the screen is a linear framebuffer that GOP left in some graphics mode.
; The kernel still writes its 80 x 25 text screen to 0xB8000 everywhere.
; gopcon_init points those eight pages at RAM instead (GOP_SHADOW), in
; the kernel's low page table, which every address space copies, so all
; that code keeps working unchanged. gopcon_tick (timer, every other
; tick) draws each character cell that changed since the last time into
; the framebuffer with the kernel's 5 x 7 bitmap font (font.inc): 8 x 16
; pixel cells, the glyph doubled in height, on screens of 640 x 400 or
; more; 6 x 8 cells otherwise; both zoomed by the largest whole number
; that still fits 80 x 25 cells on the screen (2 at 1280 x 800). The cursor is an underline at [cur].
; CP437 box-drawing characters are drawn as single lines, the block
; characters as solid cells. Graphics-mode programs are not shown yet.
; The loader leaves the framebuffer's description in UEFI_INFO.
; See documentation/kernel/hardware.md.

UEFI_INFO       equ 0x1300          ; after E820_BUF; written by the UEFI loader
UI_MAGIC        equ 0
UI_FB           equ 4
UI_WIDTH        equ 8
UI_HEIGHT       equ 12
UI_PITCH        equ 16              ; bytes per scan line
UI_FORMAT       equ 20              ; 0: R,G,B,x bytes; 1: B,G,R,x bytes
UEFI_MAGIC      equ 0x46453253      ; 'S2EF'
GOP_SHADOW      equ KHIGH_BASE+KHIGH_MAX-0x8000 ; 32 KB of RAM for 0xB8000-0xBFFFF
GOP_COLS        equ 80
GOP_ROWS        equ 25

gopcon_init:
    pushad
    cmp dword [UEFI_INFO+UI_MAGIC], UEFI_MAGIC
    jne .out
    mov eax, [UEFI_INFO+UI_FB]
    test eax, eax
    jz .out
    mov ecx, [UEFI_INFO+UI_PITCH]
    imul ecx, [UEFI_INFO+UI_HEIGHT]
    call hw_map_mmio
    jc .out
    ; the text pages become RAM: 0xB8000 + i * 4 KB -> GOP_SHADOW + i * 4 KB
    mov edi, [kernel_pt]
    add edi, (0xB8000 >> 12) * 4
    mov eax, GOP_SHADOW|PG_P|PG_W
    mov ecx, 8
.pte:
    stosd
    add eax, 0x1000
    loop .pte
    mov eax, [kernel_pd]
    mov cr3, eax
    ; cell size
    mov dword [gop_cw], 6
    mov dword [gop_ch], 8
    mov dword [gop_shift], 1
    cmp dword [UEFI_INFO+UI_WIDTH], GOP_COLS*8
    jb .small
    cmp dword [UEFI_INFO+UI_HEIGHT], GOP_ROWS*16
    jb .small
    mov dword [gop_cw], 8
    mov dword [gop_ch], 16
    mov dword [gop_shift], 2
.small:
    ; whole-number zoom so the 80 x 25 cells fill as much of the screen as they can
    mov eax, [UEFI_INFO+UI_WIDTH]
    xor edx, edx
    mov ecx, [gop_cw]
    imul ecx, GOP_COLS
    div ecx
    mov ebx, eax
    mov eax, [UEFI_INFO+UI_HEIGHT]
    xor edx, edx
    mov ecx, [gop_ch]
    imul ecx, GOP_ROWS
    div ecx
    cmp eax, ebx
    jbe .z
    mov eax, ebx
.z:
    test eax, eax
    jnz .zok
    inc eax
.zok:
    mov [gop_zoom], eax
    ; palette in the framebuffer's byte order
    mov esi, gop_vga_rgb
    mov edi, gop_pal
    mov ecx, 16
.pal:
    lodsd
    cmp dword [UEFI_INFO+UI_FORMAT], 0
    jne .bgr
    bswap eax                       ; 00RRGGBB -> BBGGRR00
    shr eax, 8                      ; -> 00BBGGRR: bytes R, G, B
.bgr:
    stosd
    loop .pal
    ; black screen, every cell drawn on the first tick
    mov edi, [UEFI_INFO+UI_FB]
    mov ecx, [UEFI_INFO+UI_PITCH]
    imul ecx, [UEFI_INFO+UI_HEIGHT]
    shr ecx, 2
    xor eax, eax
    rep stosd
    mov edi, gop_last
    mov ecx, GOP_COLS*GOP_ROWS/2
    mov eax, -1
    rep stosd
    mov dword [gop_lastcur], 0
    mov byte [gop_up], 1
.out:
    popad
    ret

; Timer hook (interrupts off): redraw the cells that changed
gopcon_tick:
    cmp byte [gop_up], 0
    je .r
    test byte [ticks], 1
    jnz .r
    cmp byte [gfx_saved], 0
    jne .r                          ; a graphics program owns the screen
    pushad
    mov ecx, [cur]
    cmp ecx, [gop_lastcur]
    je .cells
    mov eax, [gop_lastcur]          ; the cursor moved: redraw both cells
    mov word [gop_last+eax*2], 0xFFFF
    mov word [gop_last+ecx*2], 0xFFFF
    mov [gop_lastcur], ecx
.cells:
    xor ecx, ecx
.c:
    mov ax, [0xB8000+ecx*2]
    cmp ax, [gop_last+ecx*2]
    je .n
    mov [gop_last+ecx*2], ax
    call gop_cell
.n:
    inc ecx
    cmp ecx, GOP_COLS*GOP_ROWS
    jb .c
    popad
.r:
    ret

; ecx = cell index, ax = character | attribute << 8: draws it
gop_cell:
    pushad
    ; the cell's pixel mask, one dword per row (bit cw-1 = leftmost)
    mov edi, gop_mask
    push ecx
    push eax
    mov ecx, 16
    xor eax, eax
    rep stosd
    pop eax
    pop ecx
    movzx ebx, al
    cmp bl, FONT_FIRST
    jb .special
    cmp bl, FONT_LAST
    ja .special
    ; font glyph: 7 rows of 5 bits
    lea esi, [ebx-FONT_FIRST]
    imul esi, FONT_H
    add esi, font5x7
    push ecx
    mov ecx, [gop_shift]
    xor edx, edx                    ; glyph row
.g:
    movzx ebx, byte [esi+edx]
    shl ebx, cl
    cmp dword [gop_ch], 16
    jne .g1
    mov [gop_mask+4+edx*8], ebx     ; rows 1+2r and 2+2r
    mov [gop_mask+8+edx*8], ebx
    jmp .gn
.g1:
    mov [gop_mask+edx*4], ebx
.gn:
    inc edx
    cmp edx, FONT_H
    jb .g
    pop ecx
    jmp .cursor
.special:
    cmp bl, 0xDB                    ; full block, and the shades: solid
    je .solid
    cmp bl, 0xB0
    jb .cursor
    cmp bl, 0xB2
    jbe .solid
    cmp bl, 0xDA
    ja .cursor
    ; box drawing B3..DA: lines from the centre (bits: 1 up, 2 down, 4 left, 8 right)
    movzx ebx, byte [gop_box+ebx-0xB3]
    push ecx
    mov edx, [gop_cw]
    shr edx, 1                      ; centre column
    mov ecx, [gop_cw]
    dec ecx
    sub ecx, edx
    mov esi, 1
    shl esi, cl                     ; its bit
    mov ebp, [gop_ch]
    shr ebp, 1                      ; centre row
    xor ecx, ecx
.vrow:
    cmp ecx, ebp
    ja .vlow
    test bl, 1
    jz .vnext
    jmp .vset
.vlow:
    test bl, 2
    jz .vnext
.vset:
    or [gop_mask+ecx*4], esi
.vnext:
    cmp ecx, ebp
    jne .vn
    test bl, 3                      ; the centre row is in both halves
    jz .vn
    or [gop_mask+ecx*4], esi
.vn:
    inc ecx
    cmp ecx, [gop_ch]
    jb .vrow
    ; horizontal: left half is the bits above the centre column's
    lea ecx, [esi+esi]
    neg ecx                         ; bits left of centre, and more
    mov edx, 1
    push ecx
    mov ecx, [gop_cw]
    shl edx, cl
    pop ecx
    dec edx                         ; all cw bits
    and ecx, edx                    ; left part
    xor eax, eax
    test bl, 4
    jz .nl
    or eax, ecx
    or eax, esi
.nl:
    test bl, 8
    jz .nr
    lea ecx, [esi-1]                ; bits right of centre
    or eax, ecx
    or eax, esi
.nr:
    or [gop_mask+ebp*4], eax
    pop ecx
    jmp .cursor
.solid:
    push ecx
    mov ecx, [gop_cw]
    mov edx, 1
    shl edx, cl
    dec edx
    mov edi, gop_mask
    mov eax, edx
    mov ecx, [gop_ch]
    rep stosd
    pop ecx
.cursor:
    cmp ecx, [cur]
    jne .draw
    mov edx, [gop_ch]
    mov eax, -1
    mov [gop_mask+edx*4-4], eax     ; underline: the last two rows
    mov [gop_mask+edx*4-8], eax
.draw:
    ; colours from the attribute
    mov eax, [esp+28]               ; the saved eax: char | attr << 8
    movzx ebx, ah
    mov edx, ebx
    and ebx, 0x0F
    mov ebx, [gop_pal+ebx*4]        ; foreground
    shr edx, 4
    and edx, 0x07
    mov edx, [gop_pal+edx*4]        ; background
    ; top-left pixel: fb + row * ch * pitch + col * cw * 4
    mov eax, ecx
    push edx
    xor edx, edx
    mov esi, GOP_COLS
    div esi                         ; eax = row, edx = column
    imul edx, [gop_cw]
    imul edx, [gop_zoom]
    shl edx, 2
    imul eax, [gop_ch]
    imul eax, [gop_zoom]
    imul eax, [UEFI_INFO+UI_PITCH]
    add eax, edx
    add eax, [UEFI_INFO+UI_FB]
    mov edi, eax
    pop edx
    xor esi, esi                    ; row
.row:
    mov ebp, [gop_zoom]             ; each mask row, zoom times
.rowz:
    mov eax, [gop_mask+esi*4]
    mov ecx, [gop_cw]
    push edi
.px:
    dec ecx
    mov [gop_col], ecx
    bt eax, ecx
    mov ecx, [gop_zoom]
    jnc .bg
.fg:
    mov [edi], ebx
    add edi, 4
    loop .fg
    jmp .pn
.bg:
    mov [edi], edx
    add edi, 4
    loop .bg
.pn:
    mov ecx, [gop_col]
    test ecx, ecx
    jnz .px
    pop edi
    add edi, [UEFI_INFO+UI_PITCH]
    dec ebp
    jnz .rowz
    inc esi
    cmp esi, [gop_ch]
    jb .row
    popad
    ret

; CP437 B3..DA: 1 up, 2 down, 4 left, 8 right
gop_box:
    db 3, 7, 7, 7, 6, 6, 7, 3, 6, 5, 5, 5, 6         ; B3-BF
    db 9, 13, 14, 11, 12, 15, 11, 11, 9, 10, 13, 14, 11, 12, 15, 13  ; C0-CF
    db 13, 14, 14, 9, 9, 10, 10, 15, 15, 5, 10       ; D0-DA
; the 16 text colours as 00RRGGBB
gop_vga_rgb:
    dd 0x000000, 0x0000AA, 0x00AA00, 0x00AAAA, 0xAA0000, 0xAA00AA, 0xAA5500, 0xAAAAAA
    dd 0x555555, 0x5555FF, 0x55FF55, 0x55FFFF, 0xFF5555, 0xFF55FF, 0xFFFF55, 0xFFFFFF

align 4
gop_up db 0
align 4
gop_cw dd 8
gop_ch dd 16
gop_shift dd 2
gop_zoom dd 1
gop_col dd 0
gop_lastcur dd 0
gop_pal times 16 dd 0
gop_mask times 16 dd 0
gop_last times GOP_COLS*GOP_ROWS dw 0
