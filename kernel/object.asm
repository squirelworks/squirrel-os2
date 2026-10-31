; Squirrel-OS/2 — object model: classes and messages (1.7.0)
; Included from pm.asm. Original code.
;
; A class is a record in kernel data: name, parent class (0 for none) and
; a method table of (selector, handler) pairs ending with selector 0.
; Selectors are ASCIIZ names. An object is a slot in a fixed table whose
; first dword points at its class. obj_send looks the selector up in the
; object's class, then in each parent in turn.
; See documentation/kernel/objects.md.

CLS_NAME    equ 0
CLS_PARENT  equ 4
CLS_METHODS equ 8
CLS_FIELDS  equ 12                  ; this class's own field names (1.7.1)
CLS_SIZE    equ 16

OBJ_CLASS   equ 0
OBJ_FIELD0  equ 4                   ; the fields follow the class pointer
OBJ_SIZE    equ 32
OBJ_MAXF    equ (OBJ_SIZE - OBJ_FIELD0) / 4
OBJ_MAX     equ 32
OBJ_CLASSMAX equ 32

; esi = class record -> eax = the class, or 0 if the class table is full
; or the class has more fields than an object holds. Registering a class
; twice is harmless.
obj_class:
    push ecx
    mov eax, esi
    call obj_nfields
    cmp eax, OBJ_MAXF
    ja .toomany
    xor ecx, ecx
.f:
    cmp ecx, [obj_ncls]
    jae .add
    cmp [obj_classes+ecx*4], esi
    je .ok
    inc ecx
    jmp .f
.add:
    cmp ecx, OBJ_CLASSMAX
    jae .full
    mov [obj_classes+ecx*4], esi
    inc dword [obj_ncls]
.ok:
    mov eax, esi
    pop ecx
    ret
.full:
.toomany:
    xor eax, eax
    pop ecx
    ret

; eax = class -> eax = its number of fields, the parents' included
obj_nfields:
    push esi
    push edi
    mov edi, eax
    xor eax, eax
.cls:
    test edi, edi
    jz .out
    mov esi, [edi+CLS_FIELDS]
    test esi, esi
    jz .up
.f:
    cmp dword [esi], 0
    je .up
    inc eax
    add esi, 4
    jmp .f
.up:
    mov edi, [edi+CLS_PARENT]
    jmp .cls
.out:
    pop edi
    pop esi
    ret

; eax = object, esi = field name -> eax = its index, CF clear; or CF set.
; A class's own fields come after all of its parent's, so an index found
; through a parent means the same field in every subclass.
obj_field:
    push ebx
    push ecx
    push edx
    push edi
    test eax, eax
    jz .none
    mov edi, [eax+OBJ_CLASS]
.cls:
    test edi, edi
    jz .none
    mov edx, [edi+CLS_FIELDS]
    test edx, edx
    jz .up
    xor ecx, ecx
.f:
    mov ebx, [edx+ecx*4]
    test ebx, ebx
    jz .up
    push edi
    mov edi, ebx
    call streq
    pop edi
    je .found
    inc ecx
    jmp .f
.up:
    mov edi, [edi+CLS_PARENT]
    jmp .cls
.found:
    mov eax, [edi+CLS_PARENT]   ; index = the parent's count + position
    call obj_nfields
    add eax, ecx
    pop edi
    pop edx
    pop ecx
    pop ebx
    clc
    ret
.none:
    pop edi
    pop edx
    pop ecx
    pop ebx
    mov eax, -1
    stc
    ret

; eax = object, ebx = field index -> CF set if the class has no such field
obj_check:
    push eax
    mov eax, [eax+OBJ_CLASS]
    call obj_nfields
    cmp ebx, eax
    pop eax
    jae .bad
    clc
    ret
.bad:
    stc
    ret

; eax = object, ebx = field index -> eax = the value, CF clear; or CF set
obj_get:
    call obj_check
    jc .bad
    mov eax, [eax+OBJ_FIELD0+ebx*4]
    ret
.bad:
    mov eax, -1
    ret

; eax = object, ebx = field index, ecx = value -> CF set if no such field
obj_set:
    call obj_check
    jc .r
    mov [eax+OBJ_FIELD0+ebx*4], ecx
.r:
    ret

; eax = class -> eax = a new object (fields zero), or 0 if none are free
obj_new:
    push ecx
    push edi
    mov edi, obj_table
    mov ecx, OBJ_MAX
.f:
    cmp dword [edi+OBJ_CLASS], 0
    je .got
    add edi, OBJ_SIZE
    loop .f
    xor eax, eax
    jmp .out
.got:
    push eax
    push edi
    push ecx
    xor eax, eax
    mov ecx, OBJ_SIZE / 4
    rep stosd
    pop ecx
    pop edi
    pop eax
    mov [edi+OBJ_CLASS], eax
    mov eax, edi
.out:
    pop edi
    pop ecx
    ret

; eax = object, esi = selector; ebx, ecx, edx are the arguments.
; The method runs with eax = the object (self) and the arguments as given;
; what it returns in eax comes back. CF set and eax = -1 when no class in
; the chain has the selector (or eax is not an object).
obj_send:
    push edi
    push ebp
    test eax, eax
    jz .none
    mov edi, [eax+OBJ_CLASS]
.cls:
    test edi, edi
    jz .none
    mov ebp, [edi+CLS_METHODS]
.m:
    cmp dword [ebp], 0
    je .up
    push eax
    push edi
    mov edi, [ebp]
    call streq
    pop edi
    pop eax
    je .found
    add ebp, 8
    jmp .m
.up:
    mov edi, [edi+CLS_PARENT]
    jmp .cls
.found:
    mov ebp, [ebp+4]
    mov edi, ebp
    pop ebp
    call edi                    ; edi is free for the method to use
    pop edi
    clc
    ret
.none:
    pop ebp
    pop edi
    mov eax, -1
    stc
    ret

; ---------- objtest ----------
; Shape: name -> "shape", area -> 0, describe -> 100 + (area sent to self).
; Square under Shape overrides area only: ebx * ebx.

ot_shape:
    dd ot_n_shape, 0, ot_shape_m, ot_shape_f
ot_square:
    dd ot_n_square, ot_shape, ot_square_m, ot_square_f
ot_shape_m:
    dd ot_s_name, ot_shape_name
    dd ot_s_area, ot_shape_area
    dd ot_s_describe, ot_shape_describe
    dd ot_s_resize, ot_shape_resize
    dd 0
ot_square_m:
    dd ot_s_area, ot_square_area
    dd ot_s_perimeter, ot_square_perimeter
    dd 0
ot_shape_f:
    dd ot_f_size, 0
ot_square_f:
    dd ot_f_colour, 0

; Shape's resize: ebx -> its size field, found by name (1.7.1)
ot_shape_resize:
    push esi
    push eax
    mov esi, ot_f_size
    call obj_field
    mov edx, eax
    pop eax
    pop esi
    jc .r
    mov ecx, ebx
    mov ebx, edx
    call obj_set
.r:
    ret
; Square's perimeter: 4 * the size field that Shape declared (index 0)
ot_square_perimeter:
    xor ebx, ebx
    call obj_get
    shl eax, 2
    ret

ot_shape_name:
    mov eax, ot_n_shape
    ret
ot_shape_area:
    xor eax, eax
    ret
ot_square_area:
    mov eax, ebx
    imul eax, ebx
    ret
ot_shape_describe:              ; self is in eax: sends it area
    push esi
    mov esi, ot_s_area
    call obj_send
    pop esi
    add eax, 100
    ret

cmd_objtest_run:
    mov byte [ot_ok], 1
    mov esi, ot_shape
    call obj_class
    mov esi, ot_square
    call obj_class
    mov eax, ot_square
    call obj_new
    test eax, eax
    jz .fail
    mov [ot_sq], eax
    mov eax, ot_shape
    call obj_new
    test eax, eax
    jz .fail
    mov [ot_sh], eax
    ; inherited: Square has no name method
    mov eax, [ot_sq]
    mov esi, ot_s_name
    call obj_send
    jc .bad1
    cmp eax, ot_n_shape
    je .t2
.bad1:
    mov byte [ot_ok], 0
.t2:                            ; overridden: Square's area
    mov eax, [ot_sq]
    mov esi, ot_s_area
    mov ebx, 3
    call obj_send
    cmp eax, 9
    je .t3
    mov byte [ot_ok], 0
.t3:                            ; Shape's own area
    mov eax, [ot_sh]
    mov esi, ot_s_area
    mov ebx, 3
    call obj_send
    test eax, eax
    jz .t4
    mov byte [ot_ok], 0
.t4:                            ; inherited describe sends area to self
    mov eax, [ot_sq]
    mov esi, ot_s_describe
    mov ebx, 3
    call obj_send
    cmp eax, 109
    je .t5
    mov byte [ot_ok], 0
.t5:                            ; no class has colour
    mov eax, [ot_sq]
    mov esi, ot_s_colour
    call obj_send
    jc .t6
    mov byte [ot_ok], 0
.t6:
    mov esi, ot_pass
    cmp byte [ot_ok], 1
    je .p1
    mov esi, ot_fail
.p1:
    call puts
    ; 1.7.1: fields
    mov byte [ot_ok], 1
    mov eax, [ot_sq]            ; set through Shape's method...
    mov esi, ot_s_resize
    mov ebx, 5
    call obj_send
    mov eax, [ot_sq]            ; ...read through Square's
    mov esi, ot_s_perimeter
    call obj_send
    cmp eax, 20
    je .f2
    mov byte [ot_ok], 0
.f2:
    mov eax, [ot_sq]            ; Square's own field comes after Shape's
    mov esi, ot_f_colour
    call obj_field
    jc .f2bad
    cmp eax, 1
    je .f3
.f2bad:
    mov byte [ot_ok], 0
.f3:
    mov eax, [ot_sh]            ; a Shape has no colour
    mov esi, ot_f_colour
    call obj_field
    jc .f4
    mov byte [ot_ok], 0
.f4:
    mov eax, [ot_sh]            ; and only one field
    mov ebx, 1
    mov ecx, 7
    call obj_set
    jc .f5
    mov byte [ot_ok], 0
.f5:
    mov eax, [ot_sh]            ; the shape's size is its own: still 0
    xor ebx, ebx
    call obj_get
    jc .f5bad
    test eax, eax
    jz .f6
.f5bad:
    mov byte [ot_ok], 0
.f6:
    mov eax, [ot_sq]            ; give the slots back
    mov dword [eax+OBJ_CLASS], 0
    mov eax, [ot_sh]
    mov dword [eax+OBJ_CLASS], 0
    mov esi, ot_fpass
    cmp byte [ot_ok], 1
    je .say
    mov esi, ot_ffail
    jmp .say
.fail:
    mov esi, ot_fail
.say:
    jmp puts

ot_n_shape db 'Shape', 0
ot_n_square db 'Square', 0
ot_s_name db 'name', 0
ot_s_area db 'area', 0
ot_s_describe db 'describe', 0
ot_s_colour db 'colour', 0
ot_s_resize db 'resize', 0
ot_s_perimeter db 'perimeter', 0
ot_f_size db 'size', 0
ot_f_colour db 'colour', 0
ot_pass db 'obj: PASS', 10, 0
ot_fail db 'obj: FAIL', 10, 0
ot_fpass db 'obj fields: PASS', 10, 0
ot_ffail db 'obj fields: FAIL', 10, 0
align 4
ot_sq dd 0
ot_sh dd 0
ot_ok db 0
align 4
obj_ncls dd 0
obj_classes times OBJ_CLASSMAX dd 0
obj_table times OBJ_MAX * OBJ_SIZE db 0
