; Squirrel-OS/2 — BMP files for programs (A.2, OS2-APPS)
; Original code, from the published BMP layout (BITMAPFILEHEADER and
; BITMAPINFOHEADER). Include after gui.inc; put BMP_BSS after GUI_BSS.
;
; bmp_load reads an uncompressed 8-bit (palette) or 24-bit BMP into memory
; from SYS_SBRK; bmp_rgb then gives any pixel as 0x00RRGGBB. bmp_free gives
; the memory back. bmp_save16 writes an 8-bit BMP with a 16-colour palette
; (the EGA colours of gui.inc) from an image of EGA colour bytes.

BMP_HDR     equ 14 + 40         ; file header + info header

; esi = file name -> CF and eax = reason (BMP_E*) on failure; otherwise
; bmp_w, bmp_h, bmp_bpp are set and bmp_rgb works.
BMP_ENOENT  equ 1               ; not found
BMP_EFORMAT equ 2               ; not a BMP this reads
BMP_ENOMEM  equ 3

bmp_load:
    pushad
    call bmp_free
    mov eax, SYS_OPEN
    mov ebx, esi
    xor ecx, ecx
    int 0x80
    test eax, eax
    js .noent
    mov [bmp_fd], eax
    mov ebx, eax                ; size: seek to the end and back
    mov eax, SYS_SEEK
    xor ecx, ecx
    mov edx, 2
    int 0x80
    test eax, eax
    jle .format_close
    mov [bmp_size], eax
    mov eax, SYS_SEEK
    xor ecx, ecx
    xor edx, edx
    int 0x80
    mov eax, SYS_SBRK
    mov ebx, [bmp_size]
    add ebx, 4 + 3              ; a byte to spare: 24-bit pixels are read
    and ebx, ~3                 ; as dwords
    mov [bmp_alloc], ebx
    int 0x80
    cmp eax, -1
    je .nomem_close
    mov [bmp_data], eax
    mov eax, SYS_READ
    mov ebx, [bmp_fd]
    mov ecx, [bmp_data]
    mov edx, [bmp_size]
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    int 0x80
    pop eax
    cmp eax, [bmp_size]
    jne .format
    ; headers
    mov esi, [bmp_data]
    cmp dword [bmp_size], BMP_HDR
    jb .format
    cmp word [esi], 'BM'
    jne .format
    cmp dword [esi+14], 40      ; info header size: 40 or larger (v4, v5)
    jb .format
    cmp dword [esi+30], 0       ; uncompressed only
    jne .format
    mov eax, [esi+18]
    mov [bmp_w], eax
    mov eax, [esi+22]
    mov byte [bmp_down], 0      ; positive height: rows bottom-up
    test eax, eax
    jns .h
    neg eax
    mov byte [bmp_down], 1
.h:
    mov [bmp_h], eax
    movzx eax, word [esi+28]
    mov [bmp_bpp], eax
    cmp dword [bmp_w], 0
    jle .format
    cmp dword [bmp_h], 0
    jle .format
    cmp dword [bmp_w], 4096
    ja .format
    cmp dword [bmp_h], 4096
    ja .format
    ; bytes per row, padded to 4
    mov ecx, [bmp_w]
    cmp eax, 8
    je .b8
    cmp eax, 24
    jne .format
    lea ecx, [ecx+ecx*2]
.b8:
    add ecx, 3
    and ecx, ~3
    mov [bmp_stride], ecx
    imul ecx, [bmp_h]
    mov eax, [esi+10]           ; where the pixels start
    mov [bmp_pix], eax
    add eax, ecx
    jc .format
    cmp eax, [bmp_size]
    ja .format
    mov eax, [esi+14]           ; the palette follows the info header
    add eax, 14
    mov [bmp_pal], eax
    cmp dword [bmp_bpp], 8
    jne .ok
    mov ecx, [esi+46]           ; colours used (0: all 256)
    test ecx, ecx
    jnz .cu
    mov ecx, 256
.cu:
    cmp ecx, 256
    ja .format
    mov [bmp_ncol], ecx
    lea ecx, [eax+ecx*4]
    cmp ecx, [bmp_size]
    ja .format
.ok:
    popad
    clc
    ret
.noent:
    popad
    mov eax, BMP_ENOENT
    stc
    ret
.format_close:
    mov eax, SYS_CLOSE
    mov ebx, [bmp_fd]
    int 0x80
.format:
    call bmp_free
    popad
    mov eax, BMP_EFORMAT
    stc
    ret
.nomem_close:
    mov eax, SYS_CLOSE
    mov ebx, [bmp_fd]
    int 0x80
    popad
    mov eax, BMP_ENOMEM
    stc
    ret

; Gives back the loaded file's memory (it must be the heap's last block).
bmp_free:
    pushad
    mov ebx, [bmp_alloc]
    test ebx, ebx
    jz .r
    neg ebx
    mov eax, SYS_SBRK
    int 0x80
    mov dword [bmp_alloc], 0
    mov dword [bmp_data], 0
.r:
    popad
    ret

; eax = x, ebx = y (row 0 at the top) -> eax = 0x00RRGGBB.
; Off the image: 0.
bmp_rgb:
    push ebx
    push ecx
    push esi
    cmp eax, [bmp_w]
    jae .zero
    cmp ebx, [bmp_h]
    jae .zero
    cmp byte [bmp_down], 0
    jne .row
    neg ebx                     ; bottom-up: file row h - 1 - y
    add ebx, [bmp_h]
    dec ebx
.row:
    imul ebx, [bmp_stride]
    add ebx, [bmp_pix]
    add ebx, [bmp_data]
    cmp dword [bmp_bpp], 8
    jne .rgb
    movzx eax, byte [ebx+eax]
    cmp eax, [bmp_ncol]
    jae .zero
    mov esi, [bmp_data]
    add esi, [bmp_pal]
    mov eax, [esi+eax*4]        ; B, G, R, 0
    and eax, 0x00FFFFFF
    jmp .r
.rgb:
    lea eax, [eax+eax*2]
    mov eax, [ebx+eax]          ; B, G, R, (next): 0x??RRGGBB
    and eax, 0x00FFFFFF
.r:
    pop esi
    pop ecx
    pop ebx
    ret
.zero:
    xor eax, eax
    jmp .r

; ---------- the 16 EGA colours ----------
; ega_rgb: the 16 colour bytes of gui.inc and their 0x00RRGGBB values
bmp_ega:
    db C_BLACK, C_BLUE, C_GREEN, C_CYAN, C_RED, C_MAGENTA, C_BROWN, C_LGREY
    db C_DGREY, C_LBLUE, C_LGREEN, C_LCYAN, C_LRED, C_LMAGENTA, C_YELLOW, C_WHITE
bmp_ega_rgb:
    dd 0x000000, 0x0000AA, 0x00AA00, 0x00AAAA, 0xAA0000, 0xAA00AA, 0xAAAA00, 0xAAAAAA
    dd 0x555555, 0x5555FF, 0x55FF55, 0x55FFFF, 0xFF5555, 0xFF55FF, 0xFFFF55, 0xFFFFFF

; eax = 0x00RRGGBB -> al = the nearest of the 16 EGA colour bytes
bmp_near16:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov esi, eax
    mov edi, 0x7FFFFFFF         ; best distance
    xor ecx, ecx
.c:
    mov eax, esi
    mov ebx, [bmp_ega_rgb+ecx*4]
    call bmp_dist
    cmp eax, edi
    jae .n
    mov edi, eax
    mov edx, ecx
.n:
    inc ecx
    cmp ecx, 16
    jb .c
    movzx eax, byte [bmp_ega+edx]
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; eax, ebx = two 0x00RRGGBB -> eax = the squared distance
bmp_dist:
    push ecx
    push edx
    push esi
    xor esi, esi
    mov ecx, 3
.ch:
    movzx edx, al
    push ebx
    and ebx, 0xFF
    sub edx, ebx
    pop ebx
    imul edx, edx
    add esi, edx
    shr eax, 8
    shr ebx, 8
    loop .ch
    mov eax, esi
    pop esi
    pop edx
    pop ecx
    ret

; al = EGA colour byte -> eax = its index 0..15 (0 if it is not one)
bmp_ega_index:
    push ecx
    xor ecx, ecx
.c:
    cmp [bmp_ega+ecx], al
    je .f
    inc ecx
    cmp ecx, 16
    jb .c
    xor ecx, ecx
.f:
    mov eax, ecx
    pop ecx
    ret

; esi = file name, edi = image (EGA colour bytes, row 0 at the top),
; ecx = width (a multiple of 4), edx = height -> CF if it was not written.
; An 8-bit BMP with the 16-colour palette, rows bottom-up.
bmp_save16:
    pushad
    mov [bmp_w], ecx
    mov [bmp_h], edx
    mov [bmp_img], edi
    mov eax, SYS_OPEN
    mov ebx, esi
    mov ecx, O_CREATE | O_TRUNC
    int 0x80
    test eax, eax
    js .fail
    mov [bmp_fd], eax
    ; the headers and the palette into bmp_row
    mov edi, bmp_row
    xor eax, eax
    mov ecx, (BMP_HDR + 64) / 4
    push edi
    rep stosd
    pop edi
    mov word [edi], 'BM'
    mov eax, [bmp_w]
    imul eax, [bmp_h]
    mov [edi+34], eax           ; image size
    add eax, BMP_HDR + 64
    mov [edi+2], eax            ; file size
    mov dword [edi+10], BMP_HDR + 64
    mov dword [edi+14], 40
    mov eax, [bmp_w]
    mov [edi+18], eax
    mov eax, [bmp_h]
    mov [edi+22], eax
    mov word [edi+26], 1        ; planes
    mov word [edi+28], 8        ; bits a pixel
    mov dword [edi+38], 2835    ; 72 dpi
    mov dword [edi+42], 2835
    mov dword [edi+46], 16      ; colours used
    mov dword [edi+50], 16
    xor ecx, ecx
.pal:
    mov eax, [bmp_ega_rgb+ecx*4]
    mov [edi+BMP_HDR+ecx*4], eax ; B, G, R, 0 in memory order
    inc ecx
    cmp ecx, 16
    jb .pal
    mov eax, SYS_WRITE
    mov ebx, [bmp_fd]
    mov ecx, bmp_row
    mov edx, BMP_HDR + 64
    int 0x80
    cmp eax, edx
    jne .fail_close
    ; rows, bottom first, as palette indices
    mov ebp, [bmp_h]
.row:
    dec ebp
    js .done
    mov esi, ebp
    imul esi, [bmp_w]
    add esi, [bmp_img]
    mov edi, bmp_row
    mov ecx, [bmp_w]
.px:
    lodsb
    call bmp_ega_index
    stosb
    loop .px
    mov eax, SYS_WRITE
    mov ebx, [bmp_fd]
    mov ecx, bmp_row
    mov edx, [bmp_w]
    int 0x80
    cmp eax, edx
    jne .fail_close
    jmp .row
.done:
    mov eax, SYS_CLOSE
    mov ebx, [bmp_fd]
    int 0x80
    popad
    clc
    ret
.fail_close:
    mov eax, SYS_CLOSE
    mov ebx, [bmp_fd]
    int 0x80
.fail:
    popad
    stc
    ret

%macro BMP_BSS 0
alignb 4
bmp_w       resd 1
bmp_h       resd 1
bmp_bpp     resd 1
bmp_stride  resd 1
bmp_pix     resd 1
bmp_pal     resd 1
bmp_ncol    resd 1
bmp_size    resd 1
bmp_alloc   resd 1
bmp_data    resd 1
bmp_fd      resd 1
bmp_img     resd 1
bmp_down    resb 4
bmp_row     resb 1024
%endmacro
