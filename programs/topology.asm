; Squirrel-OS/2 — Topology calculator (C.9 topo, OS2-APPS)
; Original code. run topology   |   run topology test
;
; Simplicial complexes up to dimension 3 on at most 16 vertices: the face
; counts, the Euler characteristic and the Betti numbers b0, b1, b2 of
; simplicial homology over Z/2 and over Q. Where the two differ the
; homology has 2-torsion (RP2, the Klein bottle).
;
; A complex is given by its maximal simplices, as vertex numbers 0-15:
; "0 1 2, 0 2 3" is two triangles sharing an edge. The window lists
; ready-made complexes and draws the 1-skeleton with the vertices on a
; circle.
;
;   Up, Down     choose a complex (it is computed at once)
;   Enter or Tab: "Custom", typing simplices (the last complex's text to
;                start from; Delete clears it); Enter computes, Esc stops
;   Esc          quit
;
; Ranks: over Z/2 with bit vectors (each boundary column reduced against
; a basis kept by pivot bit); over Q by Gaussian elimination with partial
; pivoting on doubles (entries are 0 and +-1, a pivot below 1e-9 is 0).
; "run topology test" checks every ready-made complex against its known
; Betti numbers and prints "topology: PASS". See documentation/apps/topology.md.

%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"

MAXV        equ 16
MAXS        equ 128             ; simplices of one dimension at most
WORDS       equ MAXS / 32       ; a Z/2 column: MAXS bits
TEXT_MAX    equ 200
LIST_X      equ 4
LIST_Y      equ 1 + WIN_TITLE_H + 4
LIST_W      equ 70
ROW_H       equ CELL_H + 2
DRAW_CX     equ 210             ; the 1-skeleton's circle
DRAW_CY     equ 62
DRAW_R      equ 46
RES_X       equ 84
RES_Y       equ 118

main:
    mov esi, [esp+4]
    mov [arg], esi
    fninit
    mov eax, SYS_SBRK           ; room for a dense matrix over Q
    mov ebx, MAXS * MAXS * 8
    int 0x80
    cmp eax, -1
    je .nogfx
    mov [dense], eax
    call gui_open
    jc .nogfx
    mov esi, [arg]
    cmp dword [esi], 'test'
    je selftest
    mov dword [sel], 6          ; the torus
    call load_preset
.draw:
    call draw
.key:
    xor ecx, ecx
    call gui_event
    cmp eax, EV_CLICK
    je .click
    cmp ah, K_ESC
    je .quit
    cmp ah, K_UP
    je .up
    cmp ah, K_DOWN
    je .down
    cmp ah, K_ENTER
    je .edit
    cmp ah, K_TAB
    je .edit
    jmp .key
.up:
    cmp dword [sel], 0
    je .key
    dec dword [sel]
    jmp .pick
.down:
    cmp dword [sel], PRESETS
    jae .key
    inc dword [sel]
.pick:
    call load_preset
    jmp .draw
.click:
    mov eax, [gui_mx]
    sub eax, LIST_X
    jb .key
    cmp eax, LIST_W
    jae .key
    mov eax, [gui_my]
    sub eax, LIST_Y
    jb .key
    xor edx, edx
    mov ecx, ROW_H
    div ecx
    cmp eax, PRESETS
    ja .key
    mov [sel], eax
    jmp .pick
.edit:
    mov dword [sel], PRESETS    ; Custom
    call edit
    jmp .draw
.quit:
    call gui_close
    xor eax, eax
    ret
.nogfx:
    mov esi, m_nogfx
    call gui_puts
    mov eax, 1
    ret

; The chosen ready-made complex (or the custom text) -> text, computed.
load_preset:
    pushad
    mov eax, [sel]
    cmp eax, PRESETS
    jae .custom
    mov esi, [preset_text+eax*4]
    mov edi, text
    call scopy
.custom:
    call compute
    popad
    ret

; Edits text on the bottom row; Enter computes, Esc stops.
edit:
    pushad
    mov byte [editing], 1
    mov edi, text
    xor ecx, ecx
.len:
    cmp byte [text+ecx], 0
    je .d
    inc ecx
    jmp .len
.d:
    call draw
.k:
    call gui_getkey
    cmp ah, K_ESC
    je .done
    cmp ah, K_ENTER
    je .enter
    cmp ah, K_BKSP
    je .bs
    cmp ah, K_DEL
    je .clr
    cmp al, ' '
    jb .k
    cmp al, '~'
    ja .k
    cmp ecx, TEXT_MAX
    jae .k
    mov [text+ecx], al
    inc ecx
    mov byte [text+ecx], 0
    jmp .d
.bs:
    jecxz .k
    dec ecx
    mov byte [text+ecx], 0
    jmp .d
.clr:                           ; Delete: the whole line
    xor ecx, ecx
    mov byte [text], 0
    jmp .d
.enter:
    push ecx
    call compute
    pop ecx
    jmp .d
.done:
    mov byte [editing], 0
    popad
    ret

; ---------- the complex ----------
; text -> the simplices of each dimension (as vertex masks), the counts,
; the ranks and the Betti numbers. CF and msg if the text is not a complex.
compute:
    pushad
    mov dword [msg], 0
    mov dword [nmax], 0
    xor eax, eax
    mov edi, count
    mov ecx, 4
    rep stosd
    mov esi, text
.simplex:
    call skip
    cmp byte [esi], 0
    je .parsed
    xor ebx, ebx                ; this simplex's mask
    xor ecx, ecx                ; its vertices
.vert:
    call skip
    mov al, [esi]
    cmp al, ','
    je .end
    test al, al
    jz .end
    call number
    jc .bad
    cmp eax, MAXV
    jae .bigv
    bts ebx, eax
    jc .bad                     ; a vertex twice
    inc ecx
    cmp ecx, 4
    ja .bigdim
    jmp .vert
.end:
    cmp byte [esi], ','
    jne .store
    inc esi
.store:
    test ebx, ebx
    jz .bad
    mov eax, [nmax]
    cmp eax, MAXS
    jae .big
    mov [maxs+eax*4], ebx
    inc dword [nmax]
    jmp .simplex
.parsed:
    cmp dword [nmax], 0
    je .bad
    ; every face of every maximal simplex, into its dimension's list
    xor ebp, ebp
.each:
    cmp ebp, [nmax]
    jae .faces_done
    mov ebx, [maxs+ebp*4]
    mov edx, ebx                ; subsets of ebx: d = (d - 1) & ebx
.sub:
    call add_face
    jc .big
    dec edx
    and edx, ebx
    jnz .sub
    inc ebp
    jmp .each
.faces_done:
    call ranks
    jmp .r
.bad:
    mov dword [msg], m_bad
    jmp .clear
.bigv:
    mov dword [msg], m_bigv
    jmp .clear
.bigdim:
    mov dword [msg], m_bigdim
    jmp .clear
.big:
    mov dword [msg], m_big
.clear:
    xor eax, eax
    mov edi, count
    mov ecx, 4
    rep stosd
    mov dword [nmax], 0
.r:
    popad
    ret

; edx = a face mask -> into simp[dim] unless it is there (CF if full)
add_face:
    pushad
    xor eax, eax                ; dimension = vertices - 1
    mov ecx, edx
.bits:
    bsf ebx, ecx
    jz .counted
    btr ecx, ebx
    inc eax
    jmp .bits
.counted:
    dec eax
    mov ecx, [count+eax*4]
    mov edi, eax
    shl edi, 9                  ; MAXS * 4 bytes a dimension
    add edi, simp
    xor esi, esi
.f:
    cmp esi, ecx
    jae .add
    cmp [edi+esi*4], edx
    je .ok
    inc esi
    jmp .f
.add:
    cmp ecx, MAXS
    jae .full
    mov [edi+ecx*4], edx
    inc dword [count+eax*4]
.ok:
    popad
    clc
    ret
.full:
    popad
    stc
    ret

; eax = dimension, edx = mask -> ecx = its index in simp[dim] (or -1)
find:
    push edi
    push esi
    mov edi, eax
    shl edi, 9
    add edi, simp
    xor ecx, ecx
.f:
    cmp ecx, [count+eax*4]
    jae .no
    cmp [edi+ecx*4], edx
    je .r
    inc ecx
    jmp .f
.no:
    or ecx, -1
.r:
    pop esi
    pop edi
    ret

; The ranks of the boundary maps d1..d3 over Z/2 and Q, then
; b_k = count_k - rank d_k - rank d_k+1 for both, and chi.
ranks:
    pushad
    xor eax, eax
    mov edi, rk2
    mov ecx, 10
    rep stosd
    mov ebp, 1
.k:
    cmp dword [count+ebp*4], 0
    je .next
    call rank_z2
    mov [rk2+ebp*4], eax
    call rank_q
    mov [rkq+ebp*4], eax
.next:
    inc ebp
    cmp ebp, 4
    jb .k
    xor ebp, ebp
.b:
    mov eax, [count+ebp*4]
    sub eax, [rk2+ebp*4]
    sub eax, [rk2+ebp*4+4]
    mov [b2+ebp*4], eax
    mov eax, [count+ebp*4]
    sub eax, [rkq+ebp*4]
    sub eax, [rkq+ebp*4+4]
    mov [bq+ebp*4], eax
    inc ebp
    cmp ebp, 3
    jb .b
    mov eax, [count]
    sub eax, [count+4]
    add eax, [count+8]
    sub eax, [count+12]
    mov [chi], eax
    popad
    ret

; ebp = k -> eax = rank of d_k over Z/2. Each k-simplex's boundary is a
; bit vector over the (k-1)-simplices, reduced by the basis kept by
; leading bit (basis2: one vector per possible pivot).
rank_z2:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    xor eax, eax
    mov edi, basis_used
    mov ecx, MAXS
    rep stosb
    xor ebx, ebx                ; rank
    xor esi, esi                ; column
.col:
    cmp esi, [count+ebp*4]
    jae .done
    call boundary_bits          ; -> vec
.reduce:
    call vec_top                ; eax = highest set bit, or -1
    test eax, eax
    js .zero
    cmp byte [basis_used+eax], 0
    je .newpivot
    mov edx, eax                ; vec ^= basis[eax]
    shl edx, 4                  ; WORDS * 4 bytes a basis vector
    xor ecx, ecx
.x:
    mov edi, [basis2+edx+ecx*4]
    xor [vec+ecx*4], edi
    inc ecx
    cmp ecx, WORDS
    jb .x
    jmp .reduce
.newpivot:
    mov byte [basis_used+eax], 1
    mov edx, eax
    shl edx, 4
    xor ecx, ecx
.cp:
    mov edi, [vec+ecx*4]
    mov [basis2+edx+ecx*4], edi
    inc ecx
    cmp ecx, WORDS
    jb .cp
    inc ebx
.zero:
    inc esi
    jmp .col
.done:
    mov eax, ebx
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ebp = k, esi = a k-simplex's index -> vec: the bits of its faces
boundary_bits:
    pushad
    xor eax, eax
    mov edi, vec
    mov ecx, WORDS
    rep stosd
    mov eax, ebp
    shl eax, 9
    mov ebx, [simp+eax+esi*4]   ; the simplex
    mov esi, ebx
.v:
    bsf ecx, esi                ; each vertex in turn
    jz .r
    btr esi, ecx
    mov edx, ebx
    btr edx, ecx                ; the face without it
    lea eax, [ebp-1]
    call find
    test ecx, ecx
    js .v
    bts [vec], ecx
    jmp .v
.r:
    popad
    ret

; -> eax = the highest set bit of vec, or -1
vec_top:
    push ecx
    mov ecx, WORDS - 1
.w:
    bsr eax, [vec+ecx*4]
    jnz .f
    dec ecx
    jns .w
    or eax, -1
    pop ecx
    ret
.f:
    shl ecx, 5
    add eax, ecx
    pop ecx
    ret

; ebp = k -> eax = rank of d_k over Q. The matrix has a row per
; (k-1)-simplex and a column per k-simplex; the entry for the face
; without the i-th vertex (counted from the lowest) is (-1)^i.
rank_q:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    mov eax, [count+ebp*4-4]
    mov [nrow], eax
    mov eax, [count+ebp*4]
    mov [ncol], eax
    mov edi, [dense]            ; zero it
    mov ecx, [nrow]
    imul ecx, MAXS * 2          ; dwords: rows * MAXS * 8 / 4
    xor eax, eax
    rep stosd
    xor esi, esi                ; column
.col:
    cmp esi, [ncol]
    jae .elim
    mov eax, ebp
    shl eax, 9
    mov ebx, [simp+eax+esi*4]
    mov edi, ebx
    xor ecx, ecx                ; vertex position i
.v:
    bsf eax, edi
    jz .ncol
    btr edi, eax
    mov edx, ebx
    btr edx, eax
    push ecx
    lea eax, [ebp-1]
    call find                   ; ecx = row
    mov eax, ecx
    pop ecx
    test eax, eax
    js .skipv
    shl eax, 7                  ; row * MAXS
    add eax, esi
    shl eax, 3
    add eax, [dense]
    fld1
    test ecx, 1
    jz .pos
    fchs
.pos:
    fstp qword [eax]
.skipv:
    inc ecx
    jmp .v
.ncol:
    inc esi
    jmp .col
.elim:
    ; Gaussian elimination: for each column find the largest pivot among
    ; the rows not used yet
    xor ebx, ebx                ; rank = rows used
    xor esi, esi                ; column
.ecol:
    cmp esi, [ncol]
    jae .edone
    cmp ebx, [nrow]
    jae .edone
    ; best row in [ebx, nrow)
    or edx, -1
    fldz                        ; best |a|
    mov ecx, ebx
.find:
    cmp ecx, [nrow]
    jae .found
    call cell                   ; eax = &a[ecx][esi]
    fld qword [eax]
    fabs
    fcomi st0, st1
    jbe .notbig
    fstp st1
    mov edx, ecx
    jmp .nf
.notbig:
    fstp st0
.nf:
    inc ecx
    jmp .find
.found:
    fld qword [f_eps]
    fcomip st0, st1
    fstp st0
    jae .nextcol                ; no pivot in this column
    ; swap rows edx and ebx
    cmp edx, ebx
    je .swapped
    push esi
    mov eax, edx
    shl eax, 10                 ; row * MAXS * 8
    add eax, [dense]
    mov edi, ebx
    shl edi, 10
    add edi, [dense]
    mov ecx, MAXS * 2
.sw:
    mov esi, [eax]
    xchg esi, [edi]
    mov [eax], esi
    add eax, 4
    add edi, 4
    loop .sw
    pop esi
.swapped:
    ; eliminate below: row r -= (a[r][c] / a[p][c]) * row p
    lea ecx, [ebx+1]
.erow:
    cmp ecx, [nrow]
    jae .eok
    call cell
    fld qword [eax]
    push ecx
    mov ecx, ebx
    call cell
    pop ecx
    fdiv qword [eax]            ; factor
    fldz
    fcomip st0, st1
    je .nofac
    push ecx
    push esi
    mov edi, ecx
    shl edi, 10
    add edi, [dense]
    mov eax, ebx
    shl eax, 10
    add eax, [dense]
    mov ecx, [ncol]
.ec:
    fld qword [eax]
    fmul st0, st1
    fsubr qword [edi]
    fstp qword [edi]
    add eax, 8
    add edi, 8
    loop .ec
    pop esi
    pop ecx
.nofac:
    fstp st0
    inc ecx
    jmp .erow
.eok:
    inc ebx
.nextcol:
    inc esi
    jmp .ecol
.edone:
    mov eax, ebx
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; ecx = row, esi = column -> eax = the address of that cell
cell:
    mov eax, ecx
    shl eax, 7
    add eax, esi
    shl eax, 3
    add eax, [dense]
    ret

; esi -> eax = a decimal number (CF if there is no digit); esi past it
number:
    xor eax, eax
    movzx edx, byte [esi]
    sub edx, '0'
    cmp edx, 9
    ja .no
.d:
    movzx edx, byte [esi]
    sub edx, '0'
    cmp edx, 9
    ja .ok
    imul eax, 10
    add eax, edx
    inc esi
    cmp eax, 1000
    jb .d
.ok:
    clc
    ret
.no:
    stc
    ret

skip:
    cmp byte [esi], ' '
    jne .r
    inc esi
    jmp skip
.r:
    ret

scopy:
    lodsb
    stosb
    test al, al
    jnz scopy
    dec edi
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
    ; the list
    xor ebp, ebp
.item:
    mov eax, LIST_X
    imul ebx, ebp, ROW_H
    add ebx, LIST_Y
    mov ecx, LIST_W
    mov edx, ROW_H
    mov byte [gui_ink], C_WHITE
    mov byte [gui_bg], C_WHITE
    cmp ebp, [sel]
    jne .ib
    mov byte [gui_ink], C_BLUE
    mov byte [gui_bg], C_BLUE
.ib:
    call gui_fill
    mov byte [gui_ink], C_BLACK
    cmp ebp, [sel]
    jne .it
    mov byte [gui_ink], C_WHITE
.it:
    add eax, 2
    inc ebx
    mov esi, [preset_name+ebp*4]
    call gui_text
    inc ebp
    cmp ebp, PRESETS
    jbe .item
    ; the drawing area
    mov eax, RES_X
    mov ebx, LIST_Y
    mov ecx, SCR_W - RES_X - 4
    mov edx, RES_Y - LIST_Y - 4
    mov byte [gui_ink], C_WHITE
    call gui_fill
    call skeleton
    ; the results
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    mov ebx, RES_Y
    mov esi, [msg]
    test esi, esi
    jz .res
    mov eax, RES_X
    call gui_text
    jmp .bottom
.res:
    mov edi, line               ; "V 7  E 21  F 14  T 0"
    mov esi, s_v
    mov ebp, 0
    call cnt
    mov esi, s_e
    mov ebp, 1
    call cnt
    mov esi, s_f
    mov ebp, 2
    call cnt
    mov esi, s_t
    mov ebp, 3
    call cnt
    call out_line
    mov edi, line
    mov esi, s_chi
    call scopy
    mov eax, [chi]
    call gui_itoa
    call out_line
    mov edi, line
    mov esi, s_bz2
    mov ebp, b2
    call bettis
    call out_line
    mov edi, line
    mov esi, s_bq
    mov ebp, bq
    call bettis
    call out_line
    mov edi, line               ; a difference means 2-torsion
    mov esi, s_notors
    mov eax, [b2]
    cmp eax, [bq]
    jne .tors
    mov eax, [b2+4]
    cmp eax, [bq+4]
    jne .tors
    mov eax, [b2+8]
    cmp eax, [bq+8]
    je .ts
.tors:
    mov esi, s_tors
.ts:
    call scopy
    call out_line
.bottom:
    ; the simplices / the editor
    mov eax, LIST_X
    mov ebx, SCR_H - 2 * CELL_H - 6
    mov ecx, SCR_W - 8
    mov edx, CELL_H + 2
    mov byte [gui_ink], C_WHITE
    call gui_fill
    mov edi, line
    mov esi, text
    call scopy
    cmp byte [editing], 0
    je .nc
    mov al, '_'
    stosb
    mov byte [edi], 0
.nc:
    mov esi, line
    add eax, 2
    inc ebx
    mov ecx, SCR_W - 12
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_WHITE
    call gui_textn
    mov esi, s_help
    cmp byte [editing], 0
    je .h
    mov esi, s_help_edit
.h:
    mov eax, LIST_X
    mov ebx, SCR_H - CELL_H - 3
    mov byte [gui_bg], C_LGREY
    call gui_text
    call gui_flip
    popad
    ret

; esi = label, ebp = dimension: "label n  " at edi
cnt:
    call scopy
    mov eax, [count+ebp*4]
    call gui_utoa
    mov ax, '  '
    stosw
    mov byte [edi], 0
    ret

; esi = label, ebp = three Betti numbers: "label b0 b1 b2" at edi
bettis:
    call scopy
    xor ecx, ecx
.b:
    mov eax, [ebp+ecx*4]
    call gui_itoa
    mov al, ' '
    stosb
    inc ecx
    cmp ecx, 3
    jb .b
    mov byte [edi], 0
    ret

; line at RES_X, ebx; ebx moves down a row
out_line:
    pushad
    mov eax, RES_X
    mov esi, line
    call gui_text
    popad
    add ebx, CELL_H + 1
    ret

; The vertices that occur, on a circle, with every edge as a line.
skeleton:
    pushad
    mov eax, RES_X
    mov ebx, LIST_Y
    mov ecx, SCR_W - RES_X - 4
    mov edx, RES_Y - LIST_Y - 4
    call gui_clip
    ; the vertices that occur, evenly round the circle from the top:
    ; vertex number i of n at the angle pi / 2 + 2 pi i / n
    xor edx, edx                ; the mask of all vertices
    xor ebp, ebp
.m:
    cmp ebp, [count]
    jae .mdone
    or edx, [simp+ebp*4]
    inc ebp
    jmp .m
.mdone:
    xor ebp, ebp                ; vertex number
    xor esi, esi                ; i
.p:
    bt edx, ebp
    jnc .np
    mov [tmp], esi
    fild dword [tmp]
    fldpi
    fmulp st1, st0
    fadd st0, st0
    fidiv dword [count]         ; 2 pi i / n
    fldpi
    fmul dword [f_half]
    faddp st1, st0
    fsincos
    mov dword [tmp], DRAW_R
    fimul dword [tmp]
    fistp dword [tmp]
    mov eax, [tmp]
    add eax, DRAW_CX
    mov [vx+ebp*4], eax
    mov dword [tmp], DRAW_R
    fimul dword [tmp]
    fistp dword [tmp]
    mov eax, DRAW_CY
    sub eax, [tmp]
    mov [vy+ebp*4], eax
    inc esi
.np:
    inc ebp
    cmp ebp, MAXV
    jb .p
    ; edges
    mov byte [gui_ink], C_BLUE
    xor ebp, ebp
.e:
    cmp ebp, [count+4]
    jae .verts
    mov edx, [simp+512+ebp*4]
    bsf esi, edx
    bsr edi, edx
    mov eax, [vx+esi*4]
    mov ebx, [vy+esi*4]
    mov ecx, [vx+edi*4]
    mov edx, [vy+edi*4]
    call gui_line
    inc ebp
    jmp .e
.verts:
    xor ebp, ebp
.v:
    cmp ebp, [count]
    jae .r
    mov edx, [simp+ebp*4]
    bsf esi, edx
    mov eax, [vx+esi*4]
    mov ebx, [vy+esi*4]
    sub eax, 3
    sub ebx, 4
    mov byte [gui_ink], C_WHITE
    mov byte [gui_bg], C_RED
    mov edx, esi
    cmp dl, 10
    jb .dec
    add dl, 'a' - 10 - '0'
.dec:
    add dl, '0'
    call gui_char
    inc ebp
    jmp .v
.r:
    call gui_noclip
    popad
    ret

; ---------- self-check ----------
selftest:
    xor ebp, ebp
.p:
    mov [sel], ebp
    call load_preset
    cmp dword [msg], 0
    jne .fail
    lea esi, [expect+ebp*8]     ; b0 b1 b2 over Z/2, b0 b1 b2 over Q, chi
    mov ecx, 3
    xor edi, edi
.c:
    movzx eax, byte [esi+edi]
    cmp eax, [b2+edi*4]
    jne .fail
    movzx eax, byte [esi+edi+3]
    cmp eax, [bq+edi*4]
    jne .fail
    inc edi
    loop .c
    movsx eax, byte [esi+6]
    cmp eax, [chi]
    jne .fail
    inc ebp
    cmp ebp, PRESETS
    jb .p
    ; a custom complex with an error: vertex 16
    mov esi, t_bad
    mov edi, text
    call scopy
    call compute
    mov ebp, PRESETS
    cmp dword [msg], m_bigv
    jne .fail
    call gui_close
    mov esi, pass
    call gui_puts
    xor eax, eax
    ret
.fail:
    call gui_close
    mov esi, fail
    call gui_puts
    mov eax, ebp
    mov edi, line
    call gui_utoa
    mov word [edi], 10
    mov esi, line
    call gui_puts
    mov eax, 1
    ret

; ---------- data ----------
PRESETS equ 11
preset_name dd n0, n1, n2, n3, n4, n5, n6, n7, n8, n9, n10, n_custom
preset_text dd p0, p1, p2, p3, p4, p5, p6, p7, p8, p9, p10
n0 db 'Point', 0
n1 db 'Interval', 0
n2 db 'Circle', 0
n3 db 'Figure 8', 0
n4 db 'Disk', 0
n5 db 'Sphere', 0
n6 db 'Torus', 0
n7 db 'Moebius', 0
n8 db 'RP2', 0
n9 db 'Klein', 0
n10 db '3-sphere', 0
n_custom db 'Custom', 0
p0 db '0', 0
p1 db '0 1', 0
p2 db '0 1, 1 2, 2 0', 0
p3 db '0 1, 1 2, 2 0, 0 3, 3 4, 4 0', 0
p4 db '0 1 2', 0
p5 db '0 1 2, 0 1 3, 0 2 3, 1 2 3', 0
p6 db '0 1 3, 1 2 4, 2 3 5, 3 4 6, 4 5 0, 5 6 1, 6 0 2, '
   db '0 2 3, 1 3 4, 2 4 5, 3 5 6, 4 6 0, 5 0 1, 6 1 2', 0
p7 db '0 1 2, 1 2 3, 2 3 4, 3 4 0, 4 0 1', 0
p8 db '0 1 2, 0 2 3, 0 3 4, 0 4 5, 0 5 1, 1 2 4, 2 3 5, 3 4 1, 4 5 2, 5 1 3', 0
p9 db '0 3 4, 0 1 4, 1 4 5, 1 2 5, 2 5 6, 2 0 6, 3 6 7, 3 4 7, 4 7 8, '
   db '4 5 8, 5 8 3, 5 6 3, 6 0 1, 6 7 1, 7 1 2, 7 8 2, 8 2 0, 8 3 0', 0
p10 db '0 1 2 3, 0 1 2 4, 0 1 3 4, 0 2 3 4, 1 2 3 4', 0
; expected: Betti over Z/2 (3), over Q (3), chi, pad
expect:
    db 1,0,0, 1,0,0, 1, 0       ; point
    db 1,0,0, 1,0,0, 1, 0       ; interval
    db 1,1,0, 1,1,0, 0, 0       ; circle
    db 1,2,0, 1,2,0, -1, 0      ; figure 8
    db 1,0,0, 1,0,0, 1, 0       ; disk
    db 1,0,1, 1,0,1, 2, 0       ; sphere
    db 1,2,1, 1,2,1, 0, 0       ; torus
    db 1,1,0, 1,1,0, 0, 0       ; Moebius band
    db 1,1,1, 1,0,0, 1, 0       ; RP2
    db 1,2,1, 1,1,0, 0, 0       ; Klein bottle
    db 1,0,0, 1,0,0, 0, 0       ; 3-sphere (b3 is not shown)
f_eps dq 0.000000001
f_half dd 0.5
title db 'Topology', 0
s_v db 'V ', 0
s_e db 'E ', 0
s_f db 'F ', 0
s_t db 'T ', 0
s_chi db 'Euler characteristic ', 0
s_bz2 db 'Betti over Z/2: ', 0
s_bq db 'Betti over Q:   ', 0
s_tors db 'Z/2 and Q differ: 2-torsion', 0
s_notors db 'No 2-torsion', 0
s_help db 'Up/Down: complex  Tab: custom  Esc: quit', 0
s_help_edit db '0 1 2, 0 2 3  Enter  Del: clear  Esc', 0
m_bad db 'Not a complex: e.g. 0 1 2, 1 2 3', 0
m_bigv db 'Vertices are 0 to 15', 0
m_bigdim db 'At most 4 vertices a simplex', 0
m_big db 'Too large (128 simplices a dimension)', 0
m_nogfx db 'topology: no graphics', 10, 0
t_bad db '0 1 16', 0
pass db 'topology: PASS', 10, 0
fail db 'topology: FAIL at complex ', 0

SQX_BSS
GUI_BSS
arg resd 1
dense resd 1
sel resd 1
msg resd 1
nmax resd 1
nrow resd 1
ncol resd 1
tmp resd 1
chi resd 1
count resd 4
rk2 resd 5
rkq resd 5
b2 resd 3
bq resd 3
vx resd MAXV
vy resd MAXV
vec resd WORDS
editing resb 4
maxs resd MAXS
simp resd 4 * MAXS
basis2 resd MAXS * WORDS
basis_used resb MAXS
text resb TEXT_MAX + 2
line resb TEXT_MAX + 8
SQX_END
