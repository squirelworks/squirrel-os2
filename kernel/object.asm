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
CLS_TEXT    equ 16                  ; bit i: own field i holds text (1.8.0)
CLS_SIZE    equ 20

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

; eax = object -> CF set if it is not a live object in the table (1.7.3).
; Its slot is free for obj_new again.
obj_free:
    push eax
    sub eax, obj_table
    jb .bad
    cmp eax, OBJ_MAX * OBJ_SIZE
    jae .bad
    test eax, OBJ_SIZE - 1
    jnz .bad
    pop eax
    cmp dword [eax+OBJ_CLASS], 0
    je .bad2
    mov dword [eax+OBJ_CLASS], 0
    clc
    ret
.bad:
    pop eax
.bad2:
    stc
    ret

; objs: the classes with their parents, then the live objects (1.7.3)
cmd_objs_run:
    mov esi, os_classes
    call puts
    xor ecx, ecx
.c:
    cmp ecx, [obj_ncls]
    jae .objs
    mov edi, [obj_classes+ecx*4]
    mov esi, os_indent
    call puts
    mov esi, [edi+CLS_NAME]
    call puts
    mov edi, [edi+CLS_PARENT]
    test edi, edi
    jz .cn
    mov esi, os_under
    call puts
    mov esi, [edi+CLS_NAME]
    call puts
.cn:
    mov al, 10
    call putc
    inc ecx
    jmp .c
.objs:
    mov esi, os_objects
    call puts
    xor ecx, ecx                ; slot
    xor edx, edx                ; live ones
.o:
    cmp ecx, OBJ_MAX
    jae .count
    mov edi, ecx
    imul edi, OBJ_SIZE
    add edi, obj_table
    mov edi, [edi+OBJ_CLASS]
    test edi, edi
    jz .on
    inc edx
    mov esi, os_indent
    call puts
    mov eax, ecx
    push ecx
    push edx
    push edi
    call itoa                   ; (uses edi)
    pop edi
    pop edx
    pop ecx
    mov esi, num_buf
    call puts
    mov esi, os_colon
    call puts
    mov esi, [edi+CLS_NAME]
    call puts
    mov al, 10
    call putc
.on:
    inc ecx
    jmp .o
.count:
    mov eax, edx
    call itoa
    mov esi, num_buf
    call puts
    mov esi, os_live
    jmp puts

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

; ---------- object files (1.8.0) ----------
; 'SQOB', the class name in 16 bytes (zero-padded), the field count (byte),
; then each field: 0 and a dword, or 1, a length byte and that much text.
OBJ_FMAX    equ 256
OBJ_TEXTMAX equ 31
OBJ_POOL    equ 512

; eax = class, ebx = field index -> CF set if that field holds text
obj_istext:
    pushad
    mov edi, eax
.c:
    test edi, edi
    jz .no
    mov eax, [edi+CLS_PARENT]
    call obj_nfields            ; the parents' fields come first
    cmp ebx, eax
    jb .up
    sub ebx, eax
    mov eax, [edi+CLS_TEXT]
    bt eax, ebx
    jc .yes
    jmp .no
.up:
    mov edi, [edi+CLS_PARENT]
    jmp .c
.yes:
    popad
    stc
    ret
.no:
    popad
    clc
    ret

; eax = object, esi = path -> CF set if it could not be written
obj_save:
    pushad
    mov [os_obj], eax
    mov [os_path], esi
    mov edi, obj_fbuf
    mov eax, 'SQOB'
    stosd
    push edi
    xor eax, eax
    mov ecx, 4
    rep stosd
    pop edi
    mov ebx, [os_obj]
    mov ebx, [ebx+OBJ_CLASS]
    mov esi, [ebx+CLS_NAME]
    push edi
    mov ecx, 15
.n:
    lodsb
    test al, al
    jz .nd
    stosb
    loop .n
.nd:
    pop edi
    add edi, 16
    mov eax, ebx
    call obj_nfields
    mov [os_n], eax
    stosb
    xor ebx, ebx
.f:
    cmp ebx, [os_n]
    jae .write
    mov eax, [os_obj]
    mov eax, [eax+OBJ_CLASS]
    call obj_istext
    jc .text
    mov al, 0
    stosb
    mov eax, [os_obj]
    mov eax, [eax+OBJ_FIELD0+ebx*4]
    stosd
    jmp .nx
.text:
    mov al, 1
    stosb
    mov esi, [os_obj]
    mov esi, [esi+OBJ_FIELD0+ebx*4]
    mov edx, edi                ; the length byte
    inc edi
    xor ecx, ecx
    test esi, esi
    jz .tend
.tl:
    cmp ecx, OBJ_TEXTMAX
    jae .tend
    lodsb
    test al, al
    jz .tend
    stosb
    inc ecx
    jmp .tl
.tend:
    mov [edx], cl
.nx:
    inc ebx
    jmp .f
.write:
    sub edi, obj_fbuf
    mov [os_len], edi
    cmp byte [fs_mounted], 0
    je .no
    mov esi, [os_path]
    mov ecx, O_CREATE|O_TRUNC
    call fs_open
    cmp eax, -1
    je .no
    mov ebx, eax
    mov esi, obj_fbuf
    mov ecx, [os_len]
    call fs_write
    mov edx, eax
    call fs_close
    cmp edx, [os_len]
    jne .no
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; esi = path -> eax = a new object read from it, CF clear; or CF set if
; the file is missing or malformed, its class is not recorded or has
; another number of fields, or no slot is free.
obj_load:
    pushad
    cmp byte [fs_mounted], 0
    je .no
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .no
    mov ebx, eax
    mov edi, obj_fbuf
    mov ecx, OBJ_FMAX
    call fs_read
    mov edx, eax
    call fs_close
    cmp edx, 21
    jl .no
    add edx, obj_fbuf
    mov [os_end], edx
    cmp dword [obj_fbuf], 'SQOB'
    jne .no
    mov byte [obj_fbuf+19], 0
    xor ecx, ecx
.c:
    cmp ecx, [obj_ncls]
    jae .no
    mov edi, [obj_classes+ecx*4]
    mov edi, [edi+CLS_NAME]
    mov esi, obj_fbuf+4
    call streq
    je .found
    inc ecx
    jmp .c
.found:
    mov ebx, [obj_classes+ecx*4]
    mov eax, ebx
    call obj_nfields
    movzx edx, byte [obj_fbuf+20]
    cmp eax, edx
    jne .no
    mov [os_n], eax
    mov eax, ebx
    call obj_new
    test eax, eax
    jz .no
    mov [os_obj], eax
    mov esi, obj_fbuf+21
    xor ebx, ebx
.f:
    cmp ebx, [os_n]
    jae .ok
    cmp esi, [os_end]
    jae .bad
    lodsb
    cmp al, 1
    je .tx
    test al, al
    jne .bad
    lea eax, [esi+4]
    cmp eax, [os_end]
    ja .bad
    lodsd
    mov ecx, eax
    jmp .set
.tx:
    cmp esi, [os_end]
    jae .bad
    movzx ecx, byte [esi]
    inc esi
    cmp ecx, OBJ_TEXTMAX
    ja .bad
    lea eax, [esi+ecx]
    cmp eax, [os_end]
    ja .bad
    call obj_intern
    jc .bad
    mov ecx, eax
.set:
    mov eax, [os_obj]
    call obj_set
    inc ebx
    jmp .f
.ok:
    mov eax, [os_obj]
    mov [esp+28], eax           ; popad's eax
    popad
    clc
    ret
.bad:
    mov eax, [os_obj]
    call obj_free
.no:
    popad
    mov eax, -1
    stc
    ret

; esi = text, ecx = its length (at most OBJ_TEXTMAX) -> eax = the same text
; in the object text pool, which keeps one copy of each; esi moves past it.
; CF set when the pool is full.
obj_intern:
    push ecx
    push edx
    push edi
    mov edi, obj_tmp
    rep movsb
    mov byte [edi], 0
    mov edx, obj_pool
.s:
    cmp edx, [obj_poolp]
    jae .add
    push esi
    mov esi, obj_tmp
    mov edi, edx
    call streq
    pop esi
    je .hit
.sk:
    inc edx
    cmp byte [edx-1], 0
    jne .sk
    jmp .s
.hit:
    mov eax, edx
    clc
    jmp .out
.add:
    push esi
    mov esi, obj_tmp
    call strlen                 ; eax = length
    pop esi
    mov edx, [obj_poolp]
    lea ecx, [edx+eax+1]
    cmp ecx, obj_pool + OBJ_POOL
    ja .full
    push esi
    mov esi, obj_tmp
    mov edi, edx
    lea ecx, [eax+1]
    rep movsb
    pop esi
    mov [obj_poolp], edi
    mov eax, edx
    clc
    jmp .out
.full:
    stc
.out:
    pop edi
    pop edx
    pop ecx
    ret

; ---------- objtest ----------
; Shape: name -> "shape", area -> 0, describe -> 100 + (area sent to self).
; Square under Shape overrides area only: ebx * ebx.

ot_shape:
    dd ot_n_shape, 0, ot_shape_m, ot_shape_f, 0
ot_square:
    dd ot_n_square, ot_shape, ot_square_m, ot_square_f, 1  ; colour is text
ot_ghost:                       ; never recorded: its file must not load
    dd ot_n_ghost, 0, ot_ghost_m, 0, 0
ot_ghost_m:
    dd 0
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
    mov eax, [ot_sq]            ; give the slots back (1.7.3: obj_free)
    call obj_free
    jnc .fr2
    mov byte [ot_ok], 0
.fr2:
    mov eax, [ot_sh]
    call obj_free
    jnc .fr3
    mov byte [ot_ok], 0
.fr3:
    mov eax, [ot_sh]            ; a second free is refused
    call obj_free
    jc .fr4
    mov byte [ot_ok], 0
.fr4:
    mov esi, ot_fpass
    cmp byte [ot_ok], 1
    je .fsay
    mov esi, ot_ffail
.fsay:
    call puts
    jmp ot_storetest
.fail:
    mov esi, ot_fail
.say:
    jmp puts

; 1.8.0: a square saved, freed and loaded back; a Ghost's file refused
ot_storetest:
    mov byte [ot_ok], 1
    mov eax, ot_square
    call obj_new
    test eax, eax
    jz .bad
    mov [ot_sq], eax
    mov esi, ot_s_resize
    mov ebx, 5
    call obj_send
    mov eax, [ot_sq]
    mov ebx, 1
    mov ecx, ot_red
    call obj_set                ; colour: text
    mov eax, [ot_sq]
    mov esi, ot_file
    call obj_save
    jc .bad
    mov eax, [ot_sq]
    call obj_free
    mov esi, ot_file
    call obj_load
    jc .bad
    mov [ot_sq], eax
    mov esi, ot_s_perimeter
    call obj_send
    cmp eax, 20
    jne .badf
    mov eax, ot_square          ; a second file, loaded over the first's
    call obj_new                ; read buffer: the first keeps its text
    test eax, eax
    jz .badf
    mov ebx, 1
    mov ecx, ot_blue
    call obj_set
    mov esi, ot_bfile
    call obj_save
    pushf
    call obj_free
    popf
    jc .badf
    mov esi, ot_bfile
    call obj_load
    jc .badf
    mov ebx, 1
    push eax
    call obj_get
    mov esi, eax
    mov edi, ot_blue
    call streq
    pop eax
    pushf
    call obj_free
    popf
    jne .badf
    mov eax, [ot_sq]
    mov ebx, 1
    call obj_get
    cmp eax, ot_red
    je .badf                    ; must be a copy of the text, not the address
    mov esi, eax
    mov edi, ot_red
    call streq
    jne .badf
    mov eax, [ot_sq]
    call obj_free
    mov eax, ot_ghost
    call obj_new
    test eax, eax
    jz .bad
    mov [ot_sh], eax
    mov esi, ot_gfile
    call obj_save
    pushf
    mov eax, [ot_sh]
    call obj_free
    popf
    jc .bad
    mov esi, ot_gfile
    call obj_load
    jc .say
    call obj_free
    jmp .bad
.badf:
    mov eax, [ot_sq]
    call obj_free
.bad:
    mov byte [ot_ok], 0
.say:
    mov esi, ot_spass
    cmp byte [ot_ok], 1
    je .p
    mov esi, ot_sfail
.p:
    jmp puts

ot_n_shape db 'Shape', 0
ot_n_ghost db 'Ghost', 0
ot_red db 'red', 0
ot_file db 'objtest.obj', 0
ot_gfile db 'ghost.obj', 0
ot_blue db 'blue', 0
ot_bfile db 'blue.obj', 0
ot_spass db 'obj store: PASS', 10, 0
ot_sfail db 'obj store: FAIL', 10, 0
ot_n_square db 'Square', 0
ot_s_name db 'name', 0
ot_s_area db 'area', 0
ot_s_describe db 'describe', 0
ot_s_colour db 'colour', 0
ot_s_resize db 'resize', 0
ot_s_perimeter db 'perimeter', 0
ot_f_size db 'size', 0
ot_f_colour db 'colour', 0
os_classes db 'Classes:', 10, 0
os_objects db 'Objects:', 10, 0
os_indent db '  ', 0
os_under db ' < ', 0
os_colon db ': ', 0
os_live db ' live', 10, 0
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
os_obj dd 0
os_path dd 0
os_n dd 0
os_len dd 0
os_end dd 0
obj_poolp dd obj_pool
obj_fbuf times OBJ_FMAX db 0
obj_tmp times OBJ_TEXTMAX + 1 db 0
obj_pool times OBJ_POOL db 0
obj_classes times OBJ_CLASSMAX dd 0
obj_table times OBJ_MAX * OBJ_SIZE db 0
