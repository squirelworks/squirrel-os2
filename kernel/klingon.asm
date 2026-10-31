; Squirrel-OS/2 — Klingon font (joke klingon-font branch)
; Included from pm.asm. Original code.
;
; Writes the pIqaD-style glyphs of klingon-font.inc over the VGA BIOS
; font in plane 2: letters, digits and the apostrophe, plus the digraph
; letters tlh, ch, gh and ng at 0x80-0x83 that tools/mkstrings.py puts
; into the Klingon strings. Punctuation and box drawing keep the BIOS
; shapes.

%include "klingon-font.inc"

klingon_font_load:
    pushad
    mov dx, 0x3C4
    mov ax, 0x0402              ; write plane 2 only
    out dx, ax
    mov ax, 0x0604              ; sequential addressing
    out dx, ax
    mov dx, 0x3CE
    mov ax, 0x0204              ; read plane 2
    out dx, ax
    mov ax, 0x0005              ; no odd/even
    out dx, ax
    mov ax, 0x0006              ; A0000, 64 KB
    out dx, ax

    mov esi, klingon_font
    mov ebx, KLINGON_GLYPHS
.glyph:
    movzx edi, byte [esi]
    inc esi
    shl edi, 5                  ; 32 bytes per glyph
    add edi, 0xA0000
    mov ecx, 4
    rep movsd
    dec ebx
    jnz .glyph

    mov dx, 0x3C4               ; back to text: planes 0 and 1, odd/even
    mov ax, 0x0302
    out dx, ax
    mov ax, 0x0204
    out dx, ax
    mov dx, 0x3CE
    mov ax, 0x0004
    out dx, ax
    mov ax, 0x1005
    out dx, ax
    mov ax, 0x0E06
    out dx, ax
    popad
    ret

klingon_lang db 'tlh', 0
