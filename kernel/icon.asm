; Icons (2.3-icons): an original 32 x 32, 16-colour format (SQIC, see
; tools/mkicon.py and documentation/kernel/icons.md). The built-in icons
; come from tools/icons/*.txt through kernel/icons.inc.

ICO_MAGIC equ 'SQIC'
ICO_W     equ 4
ICO_H     equ 5
ICO_MAP   equ 8                 ; 16 palette indices, one per nibble value
ICO_DATA  equ 24

; esi = icon, eax, ebx = top left. Nibble 0 is transparent; the others are
; drawn in their palette colour through gfx_putpixel (clip, occluders).
; CF set (nothing drawn) if esi is not an SQIC icon or its width is odd.
gfx_drawicon:
    cmp dword [esi], ICO_MAGIC
    jne .bad
    test byte [esi+ICO_W], 1
    jnz .bad
    pushad
    mov [ico_x], eax
    lea edi, [esi+ICO_DATA]     ; the pixels
    xor edx, edx                ; row
.row:
    movzx eax, byte [esi+ICO_H]
    cmp edx, eax
    jae .done
    xor ebp, ebp                ; column
.col:
    movzx eax, byte [esi+ICO_W]
    cmp ebp, eax
    jae .nextrow
    movzx ecx, byte [edi]
    test ebp, 1
    jnz .low
    shr ecx, 4                  ; the left pixel: high nibble
    jmp .nib
.low:
    and ecx, 0x0F
    inc edi                     ; the byte's second pixel: next byte after
.nib:
    jecxz .skip                 ; transparent
    mov cl, [esi+ICO_MAP+ecx]
    mov eax, [ico_x]
    add eax, ebp
    call gfx_putpixel           ; eax = x, ebx = y, cl = colour
.skip:
    inc ebp
    jmp .col
.nextrow:
    inc ebx
    inc edx
    jmp .row
.done:
    popad
    clc
    ret
.bad:
    stc
    ret

; esi = a name ('folder', 'calc', ...) -> esi = the built-in icon, or CF
; set and esi unchanged if there is none by that name.
icon_byname:
    push eax
    push ecx
    push edi
    xor ecx, ecx
.next:
    cmp ecx, ICON_COUNT
    jae .none
    mov edi, [icon_table+ecx*8]
    call streq
    je .found
    inc ecx
    jmp .next
.found:
    mov esi, [icon_table+ecx*8+4]
    pop edi
    pop ecx
    pop eax
    clc
    ret
.none:
    pop edi
    pop ecx
    pop eax
    stc
    ret

ico_x dd 0

; icontest: two built-in icons drawn on a desktop-coloured band, pixels
; read back (transparent corners show the band, outline, fill and a calc
; key keep their colours), a damaged icon refused, icon_byname checked.
ICT_X equ 20
ICT_Y equ 120
cmd_icontest_run:
    call gfx_mode13
    mov byte [gfxt_ok], 1
    mov byte [gfx_colour], TH_DESKTOP
    xor eax, eax
    mov ebx, GFX_SAFE_Y
    mov ecx, GFX_W
    mov edx, GFX_H - GFX_SAFE_Y
    call gfx_fillrect
    mov esi, ict_folder
    call icon_byname
    jc .bad
    cmp esi, icon_folder
    jne .bad
    mov eax, ICT_X
    mov ebx, ICT_Y
    call gfx_drawicon
    jc .bad
    mov esi, ict_calc
    call icon_byname
    jc .bad
    mov eax, ICT_X + 40
    call gfx_drawicon
    jc .bad
    mov esi, ict_nosuch
    call icon_byname
    jnc .bad
    cmp esi, ict_nosuch         ; unchanged
    jne .bad
    mov esi, ict_broken         ; not SQIC: refused, nothing drawn
    mov eax, ICT_X + 80
    call gfx_drawicon
    jnc .bad
    mov esi, ict_expect
    call gfx_expect
    jmp .end
.bad:
    mov byte [gfxt_ok], 0
.end:
    call gfx_text
    mov esi, ict_pass
    cmp byte [gfxt_ok], 1
    je .say
    mov esi, ict_fail
.say:
    jmp puts

; x (dd), y (dd), expected colour (db); x = -1 ends the list
ict_expect:
    dd ICT_X, ICT_Y
    db TH_DESKTOP               ; folder: top left corner is transparent
    dd ICT_X + 2, ICT_Y + 9
    db 0x00                     ; folder: outline, black
    dd ICT_X + 10, ICT_Y + 15
    db 0x3E                     ; folder: body, yellow
    dd ICT_X + 3, ICT_Y + 10
    db 0x3F                     ; folder: highlight, white
    dd ICT_X + 40 + 10, ICT_Y + 5
    db 0x3A                     ; calc: display, light green
    dd ICT_X + 40 + 20, ICT_Y + 26
    db 0x3C                     ; calc: the last key, light red
    dd ICT_X + 40 + 31, ICT_Y + 31
    db TH_DESKTOP               ; calc: bottom right corner, transparent
    dd ICT_X + 80, ICT_Y + 2
    db TH_DESKTOP               ; the broken icon drew nothing
    dd -1

ict_folder db 'folder', 0
ict_calc db 'calc', 0
ict_nosuch db 'nosuch', 0
ict_broken db 'SQIX', 32, 32, 0, 0
    times 16 db 0x0F
    times 512 db 0x11
ict_pass db 'icon: PASS', 10, 0
ict_fail db 'icon: FAIL', 10, 0

%include "icons.inc"
