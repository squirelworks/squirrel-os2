; dosrun — DOS programs on Squirrel-OS/2 (P.8). Original code: an 8086
; (plus the common 80186 additions) interpreter and a DOS/BIOS service
; layer, written from the public descriptions of the 8086 instruction
; set, the PSP, the MZ format and the INT 21h interface. No DOSBox,
; FreeDOS, ReactOS NTVDM or other DOS code.
;
;   run dosrun prog.com [arguments]
;   run dosrun prog.exe [arguments]     (an MZ program without a PE header)
;
; The design (documentation/architecture/dos-personality.md) prefers V86
; mode; that needs the first megabyte of every address space free of the
; kernel's low image, which 2.4 has not done yet. This interpreter is the
; fallback the design keeps for long mode, so it serves now and later.
;
; Memory: 1 MB + 64 KB of the program's heap is the DOS address space;
; linear address = segment * 16 + offset, wrapped at 1 MB. The program's
; PSP is at segment 0x1000, a .COM image at 0x1000:0100, an .EXE image at
; 0x1010:0000. Interrupt vectors start out pointing at F000:n*4; a
; program may replace them (INT 21h AH=25h) and chain to the old ones.
; Arithmetic runs on the host CPU, so the flags are exactly the 8086's.
;
; Not provided: the FPU, direct video memory (B800) on the screen, the
; timer interrupts, BIOS disk services, ports (IN reads FFh, OUT is
; ignored). An instruction it does not know ends the program with its
; address and exit code 3.
%include "sqx.inc"
SQX_HEADER main

DOS_MEM     equ 0x110000        ; 1 MB + the 64 KB above it (HMA)
PSP_SEG     equ 0x1000
MEM_TOP     equ 0xA000          ; conventional memory ends at 640 KB
BIOS_SEG    equ 0xF000          ; default interrupt vectors point here
H_FIRST     equ 5               ; DOS handle = native fd + 5
F_CF        equ 0x0001
F_PF        equ 0x0004
F_AF        equ 0x0010
F_ZF        equ 0x0040
F_SF        equ 0x0080
F_TF        equ 0x0100
F_IF        equ 0x0200
F_DF        equ 0x0400
F_OF        equ 0x0800
F_ARITH     equ F_CF|F_PF|F_AF|F_ZF|F_SF|F_OF

; register file: rAX..rDI in ModRM order, then ES CS SS DS
%define rAX regs+0
%define rCX regs+2
%define rDX regs+4
%define rBX regs+6
%define rSP regs+8
%define rBP regs+10
%define rSI regs+12
%define rDI regs+14
%define sES sregs+0
%define sCS sregs+2
%define sSS sregs+4
%define sDS sregs+6

main:
    push ebx
    push esi
    push edi
    push ebp
    mov esi, [esp+20]
    call setup
    jc .out
    call run
    movzx eax, byte [exit_code]
.out:
    pop ebp
    pop edi
    pop esi
    pop ebx
    ret

; ======================== loading ========================

; esi = argument text: "<file> [arguments]" -> CF and eax = 1 on error
setup:
    cld
    mov edi, exe_name
    xor ecx, ecx
.nm:
    lodsb
    cmp al, ' '
    je .nmz
    test al, al
    jz .nmz0
    cmp ecx, 31
    jae .nm
    mov [edi+ecx], al
    inc ecx
    jmp .nm
.nmz0:
    dec esi
    jmp .nmz1
.nmz:
    dec esi                     ; the tail starts at the space, as in DOS
.nmz1:
    mov byte [edi+ecx], 0
    mov [tail], esi
    test ecx, ecx
    jz .usage
    ; DOS memory from the heap, page aligned
    mov eax, SYS_SBRK
    xor ebx, ebx
    int 0x80
    neg eax
    and eax, 0xFFF
    mov ebx, eax
    mov eax, SYS_SBRK
    int 0x80
    mov eax, SYS_SBRK
    mov ebx, DOS_MEM+16
    int 0x80
    cmp eax, -1
    je .nomem
    mov [mem], eax
    ; interrupt vectors: F000:n*4
    mov edi, eax
    xor ecx, ecx
.ivt:
    lea eax, [ecx*4]
    mov [edi+ecx*4], ax
    mov word [edi+ecx*4+2], BIOS_SEG
    inc ecx
    cmp ecx, 256
    jb .ivt
    ; BIOS data area: 80 columns, 25 rows
    mov word [edi+0x44A], 80
    mov byte [edi+0x484], 24
    mov word [edi+0x413], 640
    call make_psp
    ; the program file
    mov eax, SYS_OPEN
    mov ebx, exe_name
    xor ecx, ecx
    int 0x80
    cmp eax, -1
    je .open
    mov [fd], eax
    mov ebx, eax
    mov eax, SYS_READ
    mov ecx, hdr
    mov edx, 28
    int 0x80
    cmp eax, 2
    jb .read_com
    cmp word [hdr], 'MZ'
    je .exe
    cmp word [hdr], 'ZM'
    je .exe
.read_com:
    ; .COM: the whole file at PSP:0100
    mov eax, SYS_SEEK
    mov ebx, [fd]
    xor ecx, ecx
    xor edx, edx
    int 0x80
    mov eax, SYS_READ
    mov ebx, [fd]
    mov ecx, PSP_SEG*16+0x100
    add ecx, [mem]
    mov edx, 0xFF00
    int 0x80
    cmp eax, -1
    je .open
    call close_fd
    mov ax, PSP_SEG
    mov [sCS], ax
    mov [sDS], ax
    mov [sES], ax
    mov [sSS], ax
    mov word [ip], 0x100
    mov word [rSP], 0xFFFE
    mov eax, [mem]              ; RET at the end returns to PSP:0000 (INT 20h)
    mov word [eax+PSP_SEG*16+0xFFFE], 0
    jmp .regs
.exe:
    call load_exe
    jc .format
.regs:
    mov word [flags], 0x7202    ; IF, and the always-one bits
    mov word [alloc_seg], MEM_TOP
    clc
    ret
.usage:
    mov ebx, m_usage
    jmp .err
.nomem:
    mov ebx, m_nomem
    jmp .err
.open:
    mov ebx, m_open
    jmp .err
.format:
    call close_fd
    mov ebx, m_format
.err:
    call say
    mov eax, 1
    stc
    ret

close_fd:
    mov eax, SYS_CLOSE
    mov ebx, [fd]
    int 0x80
    ret

; PSP at PSP_SEG: INT 20h at 0, memory top at 2, the command tail at 80h
make_psp:
    mov edi, [mem]
    add edi, PSP_SEG*16
    mov word [edi], 0x20CD
    mov word [edi+2], MEM_TOP
    mov word [edi+0x2C], 0      ; no environment
    mov word [edi+0x50], 0x21CD ; INT 21h / RETF at 50h (the CP/M-style entry)
    mov byte [edi+0x52], 0xCB
    ; tail: " arguments" CR, length in front
    mov esi, [tail]
    lea ebx, [edi+0x81]
    xor ecx, ecx
.t:
    lodsb
    test al, al
    jz .tz
    cmp ecx, 126
    jae .tz
    mov [ebx+ecx], al
    inc ecx
    jmp .t
.tz:
    mov byte [ebx+ecx], 13
    mov [edi+0x80], cl
    mov dword [dta], PSP_SEG*16+0x80
    ret

; MZ .EXE at [fd], header in hdr -> CF on a bad header
load_exe:
    movzx eax, word [hdr+4]     ; pages of 512 bytes
    shl eax, 9
    movzx ecx, word [hdr+2]     ; bytes in the last page (0 = all)
    jecxz .full
    sub eax, 512
    add eax, ecx
.full:
    movzx ecx, word [hdr+8]     ; header paragraphs
    shl ecx, 4
    sub eax, ecx
    jbe .bad
    cmp eax, (MEM_TOP-PSP_SEG-0x10)*16
    ja .bad
    mov [img_len], eax
    mov eax, SYS_SEEK
    mov ebx, [fd]
    xor edx, edx
    int 0x80
    mov eax, SYS_READ
    mov ebx, [fd]
    mov ecx, (PSP_SEG+0x10)*16
    add ecx, [mem]
    mov edx, [img_len]
    int 0x80
    cmp eax, -1
    je .bad
    ; relocations: segment words of the image get the load segment added
    movzx ebp, word [hdr+6]
    mov eax, SYS_SEEK
    mov ebx, [fd]
    movzx ecx, word [hdr+0x18]
    xor edx, edx
    int 0x80
.rel:
    test ebp, ebp
    jz .reldone
    mov eax, SYS_READ
    mov ebx, [fd]
    mov ecx, relent
    mov edx, 4
    int 0x80
    cmp eax, 4
    jne .bad
    movzx eax, word [relent+2]
    add eax, PSP_SEG+0x10
    shl eax, 4
    movzx ecx, word [relent]
    add eax, ecx
    and eax, 0xFFFFF
    add eax, [mem]
    add word [eax], PSP_SEG+0x10
    dec ebp
    jmp .rel
.reldone:
    call close_fd
    mov ax, PSP_SEG
    mov [sDS], ax
    mov [sES], ax
    mov ax, [hdr+0x16]
    add ax, PSP_SEG+0x10
    mov [sCS], ax
    mov ax, [hdr+0x14]
    mov [ip], ax
    mov ax, [hdr+0x0E]
    add ax, PSP_SEG+0x10
    mov [sSS], ax
    mov ax, [hdr+0x10]
    mov [rSP], ax
    clc
    ret
.bad:
    stc
    ret

; ======================== memory and stack ========================

; eax = segment, edx = offset -> eax = host pointer (wraps at 1 MB)
lin:
    movzx eax, ax
    shl eax, 4
    movzx edx, dx
    add eax, edx
    and eax, 0xFFFFF
    add eax, [mem]
    ret

; byte/word at CS:IP, IP advanced -> eax (zero-extended)
fetch8:
    push edx
    mov ax, [sCS]
    mov dx, [ip]
    call lin
    movzx eax, byte [eax]
    inc word [ip]
    pop edx
    ret
fetch16:
    push edx
    mov ax, [sCS]
    mov dx, [ip]
    call lin
    movzx eax, word [eax]
    add word [ip], 2
    pop edx
    ret

; ax = word -> pushed on SS:SP
push16:
    push edx
    push eax
    sub word [rSP], 2
    mov ax, [sSS]
    mov dx, [rSP]
    call lin
    pop edx
    mov [eax], dx
    mov eax, edx
    pop edx
    ret
; -> eax = word popped from SS:SP
pop16:
    push edx
    mov ax, [sSS]
    mov dx, [rSP]
    call lin
    movzx eax, word [eax]
    add word [rSP], 2
    pop edx
    ret

; the segment a memory operand uses: the override, else ax (DS or SS)
; -> ax = segment value
seg_of:
    cmp byte [ovr], 0xFF
    je .r
    movzx eax, byte [ovr]
    mov ax, [sregs+eax*2]
.r:
    ret

; ======================== ModRM ========================

; reads the ModRM byte (and displacement). [w] = operand width (0 byte,
; 1 word). -> edi = host pointer of the r/m operand (register or memory),
; [mreg] = the reg field, [ea_off] = the offset (memory forms)
modrm:
    call fetch8
    mov ecx, eax
    shr eax, 3
    and eax, 7
    mov [mreg], al
    mov eax, ecx
    shr ecx, 6                  ; mod
    and eax, 7                  ; rm
    cmp ecx, 3
    je .reg
    mov [mrm_rm], al
    xor edx, edx                ; the offset
    mov byte [mrm_ss], 0
    cmp ecx, 0
    jne .base
    cmp eax, 6
    jne .base
    call fetch16                ; [disp16]
    mov edx, eax
    jmp .seg
.base:
    movzx eax, byte [mrm_rm]
    jmp [.rm+eax*4]
.rm dd .bx_si, .bx_di, .bp_si, .bp_di, .si, .di, .bp, .bx
.bx_si:
    mov dx, [rBX]
    add dx, [rSI]
    jmp .disp
.bx_di:
    mov dx, [rBX]
    add dx, [rDI]
    jmp .disp
.bp_si:
    mov dx, [rBP]
    add dx, [rSI]
    mov byte [mrm_ss], 1
    jmp .disp
.bp_di:
    mov dx, [rBP]
    add dx, [rDI]
    mov byte [mrm_ss], 1
    jmp .disp
.si:
    mov dx, [rSI]
    jmp .disp
.di:
    mov dx, [rDI]
    jmp .disp
.bp:
    mov dx, [rBP]
    mov byte [mrm_ss], 1
    jmp .disp
.bx:
    mov dx, [rBX]
.disp:
    cmp ecx, 1
    jb .seg
    ja .d16
    call fetch8
    movsx eax, al
    add dx, ax
    jmp .seg
.d16:
    call fetch16
    add dx, ax
.seg:
    mov [ea_off], dx
    mov ax, [sDS]
    cmp byte [mrm_ss], 0
    je .s
    mov ax, [sSS]
.s:
    call seg_of
    mov [ea_seg], ax
    call lin
    mov edi, eax
    mov byte [mrm_mem], 1
    ret
.reg:
    mov byte [mrm_mem], 0
    call regptr
    mov edi, eax
    ret

; eax = register number, [w] -> eax = host pointer of that register
regptr:
    cmp byte [w], 0
    jne .w
    cmp eax, 4
    jb .lo
    lea eax, [regs+(eax-4)*2+1]   ; AH CH DH BH
    ret
.lo:
    lea eax, [regs+eax*2]
    ret
.w:
    lea eax, [regs+eax*2]
    ret

; -> esi = host pointer of the reg-field register
greg:
    movzx eax, byte [mreg]
    call regptr
    mov esi, eax
    ret

; ======================== flags and ALU on the host ========================

; puts the 8086 arithmetic flags into the host's (DF and TF stay clear)
%macro LOADF 0
    push eax
    movzx eax, word [flags]
    and eax, F_ARITH
    push eax
    popfd
    pop eax
%endmacro
; takes the host's arithmetic flags back
%macro SAVEF 0
    pushfd
    push eax
    mov eax, [esp+4]
    and eax, F_ARITH
    and word [flags], ~F_ARITH
    or [flags], ax
    pop eax
    add esp, 4
%endmacro

; ecx = operation 0..7 (add or adc sbb and sub xor cmp), edi = destination
; pointer, edx = source value, [w] -> result stored (but for cmp), flags set
alu:
    cmp byte [w], 0
    je .b
    mov ax, [edi]
    LOADF
    call [alu16+ecx*4]
    SAVEF
    cmp ecx, 7
    je .r
    mov [edi], ax
.r:
    ret
.b:
    mov al, [edi]
    LOADF
    call [alu8+ecx*4]
    SAVEF
    cmp ecx, 7
    je .r
    mov [edi], al
    ret

alu8  dd a8_add, a8_or, a8_adc, a8_sbb, a8_and, a8_sub, a8_xor, a8_sub
alu16 dd a16_add, a16_or, a16_adc, a16_sbb, a16_and, a16_sub, a16_xor, a16_sub
a8_add: add al, dl
        ret
a8_or:  or al, dl
        ret
a8_adc: adc al, dl
        ret
a8_sbb: sbb al, dl
        ret
a8_and: and al, dl
        ret
a8_sub: sub al, dl
        ret
a8_xor: xor al, dl
        ret
a16_add: add ax, dx
        ret
a16_or: or ax, dx
        ret
a16_adc: adc ax, dx
        ret
a16_sbb: sbb ax, dx
        ret
a16_and: and ax, dx
        ret
a16_sub: sub ax, dx
        ret
a16_xor: xor ax, dx
        ret

; shifts and rotates: ecx = operation 0..7 (rol ror rcl rcr shl shr sal
; sar), edi = operand, dl = count
shift:
    push ecx
    mov ebx, ecx
    mov cl, dl
    and cl, 0x1F
    cmp byte [w], 0
    je .b
    mov ax, [edi]
    LOADF
    call [sh16+ebx*4]
    SAVEF
    mov [edi], ax
    pop ecx
    ret
.b:
    mov al, [edi]
    LOADF
    call [sh8+ebx*4]
    SAVEF
    mov [edi], al
    pop ecx
    ret
sh8  dd s8_rol, s8_ror, s8_rcl, s8_rcr, s8_shl, s8_shr, s8_shl, s8_sar
sh16 dd s16_rol, s16_ror, s16_rcl, s16_rcr, s16_shl, s16_shr, s16_shl, s16_sar
s8_rol: rol al, cl
        ret
s8_ror: ror al, cl
        ret
s8_rcl: rcl al, cl
        ret
s8_rcr: rcr al, cl
        ret
s8_shl: shl al, cl
        ret
s8_shr: shr al, cl
        ret
s8_sar: sar al, cl
        ret
s16_rol: rol ax, cl
        ret
s16_ror: ror ax, cl
        ret
s16_rcl: rcl ax, cl
        ret
s16_rcr: rcr ax, cl
        ret
s16_shl: shl ax, cl
        ret
s16_shr: shr ax, cl
        ret
s16_sar: sar ax, cl
        ret

; condition 0..15 (o no b nb z nz be a s ns p np l ge le g) -> al = 1 if true
cond:
    LOADF
    jmp [.t+eax*4]
.t dd .o, .no, .b, .nb, .z, .nz, .be, .a, .s, .ns, .p, .np, .l, .ge, .le, .g
.o:  seto al
     ret
.no: setno al
     ret
.b:  setb al
     ret
.nb: setnb al
     ret
.z:  setz al
     ret
.nz: setnz al
     ret
.be: setbe al
     ret
.a:  seta al
     ret
.s:  sets al
     ret
.ns: setns al
     ret
.p:  setp al
     ret
.np: setnp al
     ret
.l:  setl al
     ret
.ge: setge al
     ret
.le: setle al
     ret
.g:  setg al
     ret

; ======================== the main loop ========================

run:
.next:
    cmp byte [done], 0
    jne .r
    mov byte [ovr], 0xFF
    mov byte [repp], 0
    mov ax, [sCS]
    mov [op_cs], ax
    mov ax, [ip]
    mov [op_ip], ax
    cmp word [sCS], BIOS_SEG
    je .bios
.prefix:
    call fetch8
    mov [opc], al
    call [optab+eax*4]
    jmp .next
.bios:
    call bios_entry
    jmp .next
.r:
    ret

; prefixes: note them and decode the next byte
pf_es:  mov byte [ovr], 0
        jmp op_prefix
pf_cs:  mov byte [ovr], 1
        jmp op_prefix
pf_ss:  mov byte [ovr], 2
        jmp op_prefix
pf_ds:  mov byte [ovr], 3
        jmp op_prefix
op_repne:
        mov byte [repp], 0xF2
        jmp op_prefix
op_repe:
        mov byte [repp], 0xF3
        jmp op_prefix
op_lock:
op_prefix:
    call fetch8
    mov [opc], al
    jmp [optab+eax*4]

; anything not decoded: report and stop
op_bad:
    mov ebx, m_badop
    call say
    movzx eax, byte [opc]
    call hex2
    mov ebx, m_at
    call say
    mov ax, [op_cs]
    call hex4
    mov al, ':'
    call putch
    mov ax, [op_ip]
    call hex4
    mov al, 10
    call putch
    mov byte [exit_code], 3
    mov byte [done], 1
    ret

; ---------- 00..3F: ALU forms ----------
op_alu:
    movzx ecx, byte [opc]
    mov ebx, ecx
    shr ecx, 3
    and ecx, 7                  ; operation
    and ebx, 7                  ; form
    mov eax, ebx
    and eax, 1
    mov [w], al
    cmp ebx, 4
    jae .acc
    push ecx
    push ebx
    call modrm
    call greg
    pop ebx
    pop ecx
    cmp ebx, 2
    jae .tog
    ; E, G: destination r/m
    movzx edx, word [esi]
    jmp alu
.tog:                           ; G, E: destination the register
    movzx edx, word [edi]
    mov edi, esi
    jmp alu
.acc:                           ; AL/AX, immediate
    cmp byte [w], 0
    je .ib
    call fetch16
    jmp .ai
.ib:
    call fetch8
.ai:
    mov edx, eax
    mov edi, rAX
    jmp alu

; push / pop segment registers (06 07 0E 16 17 1E 1F)
op_pushseg:
    movzx eax, byte [opc]
    shr eax, 3
    mov ax, [sregs+eax*2]
    jmp push16
op_popseg:
    movzx ebx, byte [opc]
    shr ebx, 3
    call pop16
    mov [sregs+ebx*2], ax
    ret

; DAA DAS AAA AAS on the host
op_daa:
    mov ax, [rAX]
    LOADF
    daa
    jmp op_bcd_end
op_das:
    mov ax, [rAX]
    LOADF
    das
    jmp op_bcd_end
op_aaa:
    mov ax, [rAX]
    LOADF
    aaa
    jmp op_bcd_end
op_aas:
    mov ax, [rAX]
    LOADF
    aas
op_bcd_end:
    SAVEF
    mov [rAX], ax
    ret

; 40..4F: inc/dec r16
op_incdec:
    movzx eax, byte [opc]
    mov ecx, eax
    and eax, 7
    lea edi, [regs+eax*2]
    mov ax, [edi]
    test ecx, 8
    jnz .dec
    LOADF
    inc ax
    jmp .s
.dec:
    LOADF
    dec ax
.s:
    SAVEF
    mov [edi], ax
    ret

; 50..57 push r16, 58..5F pop r16
op_pushr:
    movzx eax, byte [opc]
    and eax, 7
    mov ax, [regs+eax*2]
    cmp byte [opc], 0x54        ; push sp: the 8086 pushes the new value
    jne push16
    sub ax, 2
    jmp push16
op_popr:
    movzx ebx, byte [opc]
    and ebx, 7
    call pop16
    mov [regs+ebx*2], ax
    ret

; 60 pusha, 61 popa (80186)
op_pusha:
    mov bx, [rSP]
    xor ecx, ecx
.l:
    mov ax, [regs+ecx*2]
    cmp ecx, 4
    jne .p
    mov ax, bx
.p:
    call push16
    inc ecx
    cmp ecx, 8
    jb .l
    ret
op_popa:
    mov ecx, 7
.l:
    call pop16
    cmp ecx, 4
    je .skip                    ; SP is not loaded
    mov [regs+ecx*2], ax
.skip:
    dec ecx
    jns .l
    ret

; 68 push iw, 6A push ib (sign-extended)
op_pushiw:
    call fetch16
    jmp push16
op_pushib:
    call fetch8
    movsx eax, al
    jmp push16

; 69 imul r16, E, iw / 6B imul r16, E, ib
op_imul3:
    mov byte [w], 1
    call modrm
    call greg
    cmp byte [opc], 0x6B
    je .ib
    call fetch16
    jmp .go
.ib:
    call fetch8
    movsx eax, al
.go:
    mov dx, ax
    mov ax, [edi]
    LOADF
    imul ax, dx
    SAVEF
    mov [esi], ax
    ret

; 70..7F: jcc short
op_jcc:
    call fetch8
    movsx edx, al
    movzx eax, byte [opc]
    and eax, 15
    call cond
    test al, al
    jz .r
    add [ip], dx
.r:
    ret

; 0F 80..8F: the 386 near jcc (rel16), which assemblers emit for far
; conditional jumps; the rest of the 0F page stays unsupported
op_0f:
    call fetch8
    mov ah, al
    and ah, 0xF0
    cmp ah, 0x80
    jne op_bad
    and eax, 15
    push eax
    call fetch16
    movsx edx, ax
    pop eax
    call cond
    test al, al
    jz .r
    add [ip], dx
.r:
    ret

; 80 81 82 83: ALU E, immediate
op_grp1:
    movzx eax, byte [opc]
    and eax, 1
    mov [w], al
    call modrm
    movzx ecx, byte [mreg]
    cmp byte [opc], 0x81
    je .iw
    call fetch8
    cmp byte [opc], 0x83
    jne .go
    movsx eax, al
    jmp .go
.iw:
    call fetch16
.go:
    mov edx, eax
    jmp alu

; 84 85 test E, G
op_testeg:
    movzx eax, byte [opc]
    and eax, 1
    mov [w], al
    call modrm
    call greg
    movzx edx, word [esi]
    mov ecx, 4                  ; and, but nothing stored
    jmp test_core
; ecx = 4, edi = operand, edx = mask: flags of an AND, no store
test_core:
    cmp byte [w], 0
    je .b
    mov ax, [edi]
    LOADF
    and ax, dx
    SAVEF
    ret
.b:
    mov al, [edi]
    LOADF
    and al, dl
    SAVEF
    ret

; 86 87 xchg E, G
op_xchg:
    movzx eax, byte [opc]
    and eax, 1
    mov [w], al
    call modrm
    call greg
    cmp byte [w], 0
    je .b
    mov ax, [edi]
    mov dx, [esi]
    mov [edi], dx
    mov [esi], ax
    ret
.b:
    mov al, [edi]
    mov dl, [esi]
    mov [edi], dl
    mov [esi], al
    ret

; 88..8B mov
op_mov:
    movzx eax, byte [opc]
    mov ebx, eax
    and eax, 1
    mov [w], al
    call modrm
    call greg
    test ebx, 2
    jz .eg
    xchg esi, edi               ; 8A 8B: G <- E
.eg:
    cmp byte [w], 0
    je .b
    mov ax, [esi]
    mov [edi], ax
    ret
.b:
    mov al, [esi]
    mov [edi], al
    ret

; 8C mov Ew, Sreg / 8E mov Sreg, Ew
op_movsr:
    mov byte [w], 1
    call modrm
    movzx eax, byte [mreg]
    and eax, 3
    lea esi, [sregs+eax*2]
    cmp byte [opc], 0x8E
    jne .to_e
    xchg esi, edi
.to_e:
    mov ax, [esi]
    mov [edi], ax
    ret

; 8D lea
op_lea:
    mov byte [w], 1
    call modrm
    call greg
    mov ax, [ea_off]
    mov [esi], ax
    ret

; 8F pop Ew
op_popew:
    mov byte [w], 1
    call pop16
    push eax
    call modrm
    pop eax
    mov [edi], ax
    ret

; 90..97 xchg ax, r16 (90 = nop)
op_xchgax:
    movzx eax, byte [opc]
    and eax, 7
    mov dx, [regs+eax*2]
    mov cx, [rAX]
    mov [regs+eax*2], cx
    mov [rAX], dx
    ret

op_cbw:
    movsx ax, byte [rAX]
    mov [rAX], ax
    ret
op_cwd:
    movsx eax, word [rAX]
    shr eax, 16
    mov [rDX], ax
    ret

; 9A call far ptr16:16
op_callf:
    call fetch16
    mov ebx, eax
    call fetch16
    mov ecx, eax
far_call:                       ; bx = offset, cx = segment
    mov ax, [sCS]
    call push16
    mov ax, [ip]
    call push16
    mov [sCS], cx
    mov [ip], bx
    ret

op_nop:
op_wait:
    ret

op_pushf:
    mov ax, [flags]
    jmp push16
op_popf:
    call pop16
    or ax, 0xF002
    mov [flags], ax
    ret
op_sahf:
    mov al, [rAX+1]
    and al, F_CF|F_PF|F_AF|F_ZF|F_SF
    and byte [flags], ~(F_CF|F_PF|F_AF|F_ZF|F_SF)
    or [flags], al
    ret
op_lahf:
    mov al, [flags]
    mov [rAX+1], al
    ret

; A0..A3 mov AL/AX <-> [moffs]
op_movmoff:
    call fetch16
    mov edx, eax
    mov ax, [sDS]
    call seg_of
    call lin
    test byte [opc], 2
    jnz .store
    test byte [opc], 1
    jz .lb
    mov ax, [eax]
    mov [rAX], ax
    ret
.lb:
    mov al, [eax]
    mov [rAX], al
    ret
.store:
    test byte [opc], 1
    jz .sb
    mov dx, [rAX]
    mov [eax], dx
    ret
.sb:
    mov dl, [rAX]
    mov [eax], dl
    ret

; A8 A9 test AL/AX, immediate
op_testai:
    movzx eax, byte [opc]
    and eax, 1
    mov [w], al
    jz .ib
    call fetch16
    jmp .go
.ib:
    call fetch8
.go:
    mov edx, eax
    mov edi, rAX
    jmp test_core

; ---------- string instructions ----------
; ebx = step (1/2, negative when DF)
str_step:
    movzx ebx, byte [w]
    inc ebx
    test word [flags], F_DF
    jz .r
    neg ebx
.r:
    ret
; -> esi = host pointer of DS:SI (override), edi = ES:DI
str_src:
    mov ax, [sDS]
    call seg_of
    mov dx, [rSI]
    call lin
    mov esi, eax
    ret
str_dst:
    mov ax, [sES]
    mov dx, [rDI]
    call lin
    mov edi, eax
    ret

; one instruction, repeated under REP: [str_fn] does one element and sets
; CF when a REPE/REPNE condition ends the repeat
op_string:
    movzx eax, byte [opc]
    mov ecx, eax
    and eax, 1
    mov [w], al
    sub ecx, 0xA4
    shr ecx, 1                  ; 0 movs, 1 cmps, 3 stos, 4 lods, 5 scas
    mov eax, [strtab+ecx*4]
    mov [str_fn], eax
    cmp byte [repp], 0
    jne .rep
    jmp [str_fn]
.rep:
    cmp word [rCX], 0
    je .r
    call [str_fn]
    dec word [rCX]
    mov al, [opc]
    and al, 0xFE
    cmp al, 0xA6                ; cmps and scas look at ZF
    je .z
    cmp al, 0xAE
    jne .rep
.z:
    test word [flags], F_ZF
    setnz al
    cmp byte [repp], 0xF3        ; REPE: go on while ZF = 1
    sete ah
    cmp al, ah
    je .rep
.r:
    ret
strtab dd s_movs, s_cmps, 0, s_stos, s_lods, s_scas
s_movs:
    call str_src
    call str_dst
    call str_step
    mov ax, [esi]
    cmp byte [w], 0
    je .b
    mov [edi], ax
    jmp .adv
.b:
    mov [edi], al
.adv:
    add [rSI], bx
    add [rDI], bx
    ret
s_cmps:
    call str_src
    call str_dst
    call str_step
    push ebx
    movzx edx, word [edi]
    mov edi, esi
    mov ecx, 7
    call alu
    pop ebx
    add [rSI], bx
    add [rDI], bx
    ret
s_stos:
    call str_dst
    call str_step
    mov ax, [rAX]
    cmp byte [w], 0
    je .b
    mov [edi], ax
    jmp .adv
.b:
    mov [edi], al
.adv:
    add [rDI], bx
    ret
s_lods:
    call str_src
    call str_step
    cmp byte [w], 0
    je .b
    mov ax, [esi]
    mov [rAX], ax
    jmp .adv
.b:
    mov al, [esi]
    mov [rAX], al
.adv:
    add [rSI], bx
    ret
s_scas:
    call str_dst
    call str_step
    push ebx
    movzx edx, word [edi]
    mov edi, rAX
    mov ecx, 7
    call alu
    pop ebx
    add [rDI], bx
    ret

; B0..B7 mov r8, ib; B8..BF mov r16, iw
op_movri:
    movzx ebx, byte [opc]
    mov eax, ebx
    shr eax, 3
    and eax, 1
    mov [w], al
    and ebx, 7
    mov eax, ebx
    call regptr
    mov edi, eax
    cmp byte [w], 0
    je .b
    call fetch16
    mov [edi], ax
    ret
.b:
    call fetch8
    mov [edi], al
    ret

; C0 C1 D0..D3: shift group
op_grp2:
    movzx eax, byte [opc]
    and eax, 1
    mov [w], al
    call modrm
    movzx ecx, byte [mreg]
    mov al, [opc]
    cmp al, 0xC2
    jb .imm
    mov dl, 1
    cmp al, 0xD2
    jb .go
    mov dl, [rCX]
    jmp .go
.imm:
    push ecx
    call fetch8
    pop ecx
    mov dl, al
.go:
    jmp shift

; C2 ret iw, C3 ret, CA retf iw, CB retf
op_ret:
    call pop16
    mov [ip], ax
    cmp byte [opc], 0xC2
    jne .r
    call fetch16_at_old
    add [rSP], ax
.r:
    ret
op_retf:
    call pop16
    mov [ip], ax
    call pop16
    mov [sCS], ax
    cmp byte [opc], 0xCA
    jne .r
    call fetch16_at_old
    add [rSP], ax
.r:
    ret
; the immediate of a RET iw, read from where the RET was
fetch16_at_old:
    push edx
    mov ax, [op_cs]
    mov dx, [op_ip]
    inc dx
    call lin
    movzx eax, word [eax]
    pop edx
    ret

; C4 les, C5 lds
op_lxs:
    mov byte [w], 1
    call modrm
    call greg
    mov ax, [edi]
    mov [esi], ax
    mov ax, [edi+2]
    mov ebx, 3                  ; DS
    cmp byte [opc], 0xC4
    jne .s
    xor ebx, ebx                ; ES
.s:
    mov [sregs+ebx*2], ax
    ret

; C6 C7 mov E, immediate
op_movei:
    movzx eax, byte [opc]
    and eax, 1
    mov [w], al
    call modrm
    cmp byte [w], 0
    je .b
    call fetch16
    mov [edi], ax
    ret
.b:
    call fetch8
    mov [edi], al
    ret

; C8 enter iw, ib (level 0 only) / C9 leave
op_enter:
    call fetch16
    push eax
    call fetch8
    mov ax, [rBP]
    call push16
    mov ax, [rSP]
    mov [rBP], ax
    pop eax
    sub [rSP], ax
    ret
op_leave:
    mov ax, [rBP]
    mov [rSP], ax
    call pop16
    mov [rBP], ax
    ret

; CC int3, CD int ib, CE into
op_int3:
    mov eax, 3
    jmp do_int
op_int:
    call fetch8
    jmp do_int
op_into:
    test word [flags], F_OF
    jz .r
    mov eax, 4
    jmp do_int
.r:
    ret

; CF iret
op_iret:
    call pop16
    mov [ip], ax
    call pop16
    mov [sCS], ax
    call pop16
    or ax, 0xF002
    mov [flags], ax
    ret

; D4 aam ib, D5 aad ib
op_aam:
    call fetch8
    test al, al
    jz div_error
    mov cl, al
    movzx eax, byte [rAX]
    div cl                      ; ah = al mod n, al = al / n
    xchg al, ah
    mov [rAX], ax
    jmp setf_al
op_aad:
    call fetch8
    mov cl, al
    mov al, [rAX+1]
    mul cl
    add al, [rAX]
    mov ah, 0
    mov [rAX], ax
setf_al:                        ; SZP from AL
    mov al, [rAX]
    LOADF
    or al, al
    SAVEF
    ret

; D7 xlat
op_xlat:
    mov ax, [sDS]
    call seg_of
    movzx edx, byte [rAX]
    add dx, [rBX]
    call lin
    mov al, [eax]
    mov [rAX], al
    ret

; D8..DF: FPU, not provided
op_fpu:
    mov ebx, m_fpu
    call say
    mov byte [exit_code], 3
    mov byte [done], 1
    ret

; E0 loopnz, E1 loopz, E2 loop, E3 jcxz
op_loop:
    call fetch8
    movsx edx, al
    mov al, [opc]
    cmp al, 0xE3
    je .jcxz
    dec word [rCX]
    jz .r
    cmp al, 0xE2
    je .jump
    test word [flags], F_ZF
    setnz cl
    cmp al, 0xE1                ; loopz: go on while ZF
    sete ch
    cmp cl, ch
    jne .r
.jump:
    add [ip], dx
.r:
    ret
.jcxz:
    cmp word [rCX], 0
    je .jump
    ret

; E4 E5 EC ED in: no devices; E6 E7 EE EF out: ignored
op_in:
    cmp byte [opc], 0xEC
    jae .dx
    call fetch8                 ; the port number
.dx:
    mov byte [rAX], 0xFF
    test byte [opc], 1
    jz .r
    mov byte [rAX+1], 0xFF
.r:
    ret
op_out:
    mov al, [opc]
    cmp al, 0xEE
    jae .r
    call fetch8
.r:
    ret

; E8 call rel16, E9 jmp rel16, EA jmp far, EB jmp rel8
op_call:
    call fetch16
    push eax
    mov ax, [ip]
    call push16
    pop eax
    add [ip], ax
    ret
op_jmp:
    call fetch16
    add [ip], ax
    ret
op_jmpf:
    call fetch16
    mov ebx, eax
    call fetch16
    mov [sCS], ax
    mov [ip], bx
    ret
op_jmps:
    call fetch8
    movsx eax, al
    add [ip], ax
    ret

; F4 hlt: waits for nothing; F5 cmc; F8..FD flag bits
op_hlt:
    mov eax, SYS_YIELD
    int 0x80
    ret
op_cmc:
    xor word [flags], F_CF
    ret
op_clc:
    and word [flags], ~F_CF
    ret
op_stc:
    or word [flags], F_CF
    ret
op_cli:
    and word [flags], ~F_IF
    ret
op_sti:
    or word [flags], F_IF
    ret
op_cld:
    and word [flags], ~F_DF
    ret
op_std:
    or word [flags], F_DF
    ret

; F6 F7: test not neg mul imul div idiv
op_grp3:
    movzx eax, byte [opc]
    and eax, 1
    mov [w], al
    call modrm
    movzx eax, byte [mreg]
    jmp [.t+eax*4]
.t dd .test, .test, .not, .neg, .mul, .imul, .div, .idiv
.test:
    cmp byte [w], 0
    je .tb
    call fetch16
    jmp .tgo
.tb:
    call fetch8
.tgo:
    mov edx, eax
    jmp test_core
.not:
    cmp byte [w], 0
    je .nb
    not word [edi]
    ret
.nb:
    not byte [edi]
    ret
.neg:
    cmp byte [w], 0
    je .ngb
    mov ax, [edi]
    LOADF
    neg ax
    SAVEF
    mov [edi], ax
    ret
.ngb:
    mov al, [edi]
    LOADF
    neg al
    SAVEF
    mov [edi], al
    ret
.mul:
    cmp byte [w], 0
    je .mb
    mov ax, [rAX]
    LOADF
    mul word [edi]
    SAVEF
    mov [rAX], ax
    mov [rDX], dx
    ret
.mb:
    mov al, [rAX]
    LOADF
    mul byte [edi]
    SAVEF
    mov [rAX], ax
    ret
.imul:
    cmp byte [w], 0
    je .ib
    mov ax, [rAX]
    LOADF
    imul word [edi]
    SAVEF
    mov [rAX], ax
    mov [rDX], dx
    ret
.ib:
    mov al, [rAX]
    LOADF
    imul byte [edi]
    SAVEF
    mov [rAX], ax
    ret
.div:
    cmp byte [w], 0
    je .db
    movzx ecx, word [edi]
    test ecx, ecx
    jz div_error
    movzx eax, word [rDX]
    shl eax, 16
    mov ax, [rAX]
    xor edx, edx
    div ecx
    cmp eax, 0xFFFF
    ja div_error
    mov [rAX], ax
    mov [rDX], dx
    ret
.db:
    movzx ecx, byte [edi]
    test ecx, ecx
    jz div_error
    movzx eax, word [rAX]
    xor edx, edx
    div ecx
    cmp eax, 0xFF
    ja div_error
    mov [rAX], al
    mov [rAX+1], dl
    ret
.idiv:
    cmp byte [w], 0
    je .idb
    movsx ecx, word [edi]
    test ecx, ecx
    jz div_error
    movzx eax, word [rDX]
    shl eax, 16
    mov ax, [rAX]
    cmp eax, 0x80000000
    jne .idok
    cmp ecx, -1
    je div_error
.idok:
    cdq
    idiv ecx
    cmp eax, 32767
    jg div_error
    cmp eax, -32768
    jl div_error
    mov [rAX], ax
    mov [rDX], dx
    ret
.idb:
    movsx ecx, byte [edi]
    test ecx, ecx
    jz div_error
    movsx eax, word [rAX]
    cdq
    idiv ecx
    cmp eax, 127
    jg div_error
    cmp eax, -128
    jl div_error
    mov [rAX], al
    mov [rAX+1], dl
    ret

; the 8086 raises INT 0 with IP at the faulting instruction's start
div_error:
    mov ax, [op_ip]
    mov [ip], ax
    xor eax, eax
    jmp do_int

; FE: inc/dec Eb; FF: inc dec call callf jmp jmpf push
op_grp4:
    mov byte [w], 0
    jmp grp45
op_grp5:
    mov byte [w], 1
grp45:
    call modrm
    movzx eax, byte [mreg]
    cmp eax, 2
    jae .other
    cmp byte [w], 0
    je .b
    mov dx, [edi]
    test eax, eax
    jnz .dw
    LOADF
    inc dx
    jmp .sw
.dw:
    LOADF
    dec dx
.sw:
    SAVEF
    mov [edi], dx
    ret
.b:
    mov dl, [edi]
    test eax, eax
    jnz .db
    LOADF
    inc dl
    jmp .sb
.db:
    LOADF
    dec dl
.sb:
    SAVEF
    mov [edi], dl
    ret
.other:
    cmp byte [w], 0
    je op_bad
    jmp [.t+eax*4-8]
.t dd .call, .callf, .jmp, .jmpf, .push, op_bad
.call:
    mov ax, [ip]
    call push16
    mov ax, [edi]
    mov [ip], ax
    ret
.callf:
    mov bx, [edi]
    mov cx, [edi+2]
    jmp far_call
.jmp:
    mov ax, [edi]
    mov [ip], ax
    ret
.jmpf:
    mov ax, [edi]
    mov [ip], ax
    mov ax, [edi+2]
    mov [sCS], ax
    ret
.push:
    mov ax, [edi]
    jmp push16

; ======================== interrupts ========================

; eax = vector: through the vector table; the default vectors (F000:n*4)
; are served here at once, as if the BIOS/DOS code ran and returned
do_int:
    and eax, 0xFF
    mov ebx, [mem]
    cmp word [ebx+eax*4+2], BIOS_SEG
    jne .real
    lea ecx, [eax*4]
    cmp [ebx+eax*4], cx
    jne .real
    jmp service
.real:
    push eax
    mov ax, [flags]
    call push16
    mov ax, [sCS]
    call push16
    mov ax, [ip]
    call push16
    and word [flags], ~(F_IF|F_TF)
    pop eax
    mov ebx, [mem]
    mov dx, [ebx+eax*4]
    mov [ip], dx
    mov dx, [ebx+eax*4+2]
    mov [sCS], dx
    ret

; CS = F000: a program jumped into a default vector (chaining to the old
; handler of an interrupt it hooked). Serve it, then IRET, keeping the
; carry and zero flags the service set.
bios_entry:
    movzx eax, word [ip]
    shr eax, 2
    call service
    call pop16
    mov [ip], ax
    call pop16
    mov [sCS], ax
    call pop16
    and ax, ~(F_CF|F_ZF)
    mov dx, [flags]
    and dx, F_CF|F_ZF
    or ax, dx
    or ax, 0xF002
    mov [flags], ax
    ret

; eax = vector: the built-in BIOS and DOS services
service:
    cmp eax, 0x21
    je int21
    cmp eax, 0x10
    je int10
    cmp eax, 0x16
    je int16
    cmp eax, 0x20
    je dos_exit0
    cmp eax, 0x29
    je .fastput
    cmp eax, 0x1A
    je int1a
    cmp eax, 0x11
    je .equip
    cmp eax, 0x12
    je .memsize
    cmp eax, 0x2F
    je .mux
    cmp eax, 0x33
    je .mouse
    cmp eax, 0x15
    je .sys
    test eax, eax
    jz .div0
    cmp eax, 0x13
    je .disk
    ret                         ; the rest: an IRET that does nothing
.fastput:
    mov al, [rAX]
    jmp putch
.equip:
    mov word [rAX], 0x0021      ; 80x25 colour, no floppies, FPU bit clear
    ret
.memsize:
    mov word [rAX], 640
    ret
.mux:
    mov byte [rAX], 0           ; nothing installed
    ret
.mouse:
    mov word [rAX], 0           ; no mouse driver
    ret
.sys:
    mov byte [rAX+1], 0x86      ; not supported
    or word [flags], F_CF
    ret
.div0:
    mov ebx, m_div0
    jmp stop_msg
.disk:
    mov ebx, m_disk
stop_msg:
    call say
    mov byte [exit_code], 3
    mov byte [done], 1
    ret

dos_exit0:
    mov byte [exit_code], 0
    mov byte [done], 1
    ret

; ---------- INT 10h: video, the teletype subset ----------
int10:
    mov al, [rAX+1]
    cmp al, 0x0E
    je .tty
    cmp al, 0x09
    je .rep
    cmp al, 0x0A
    je .rep
    cmp al, 0x0F
    je .mode
    cmp al, 0x03
    je .cursor
    cmp al, 0x08
    je .read
    cmp al, 0x13
    je .str
    ret                         ; set mode, cursor, scroll, palette: ignored
.tty:
    mov al, [rAX]
    jmp putch
.rep:
    movzx ecx, word [rCX]
.rl:
    jecxz .r
    mov al, [rAX]
    call putch
    dec ecx
    jmp .rl
.r:
    ret
.mode:
    mov word [rAX], 0x5003      ; 80 columns, mode 3
    mov byte [rBX+1], 0
    ret
.cursor:
    mov word [rDX], 0
    mov word [rCX], 0x0607
    ret
.read:
    mov word [rAX], 0x0720
    ret
.str:                           ; ES:BP, CX characters
    mov ax, [sES]
    mov dx, [rBP]
    call lin
    mov esi, eax
    movzx ecx, word [rCX]
.sl:
    jecxz .r
    lodsb
    call putch
    dec ecx
    jmp .sl

; ---------- INT 16h: keyboard ----------
int16:
    mov al, [rAX+1]
    and al, 0xEF                ; 10h/11h like 00h/01h
    cmp al, 1
    je .peek
    test al, al
    jne .r
    call key_get
    mov [rAX], ax
.r:
    ret
.peek:                          ; waits for a key, keeps it for 00h
    call key_peek
    mov [rAX], ax
    and word [flags], ~F_ZF
    ret

; -> ax = the next key (AH scan code 0, AL ASCII); Enter is CR
key_get:
    cmp word [key_held], 0
    je .read
    mov ax, [key_held]
    mov word [key_held], 0
    ret
.read:
    mov eax, SYS_GETC
    int 0x80
    cmp eax, -1
    jne .k
    mov eax, 0x1A               ; end of redirected input: Ctrl-Z
.k:
    cmp al, 10
    jne .m
    mov al, 13
.m:
    movzx eax, al
    ret
key_peek:
    cmp word [key_held], 0
    jne .h
    call key_get
    mov [key_held], ax
.h:
    mov ax, [key_held]
    ret

; ---------- INT 1Ah: time ----------
int1a:
    cmp byte [rAX+1], 0
    jne .r
    add dword [fake_ticks], 1   ; no clock call: a count that moves
    mov eax, [fake_ticks]
    mov [rDX], ax
    shr eax, 16
    mov [rCX], ax
    mov byte [rAX], 0
.r:
    ret

; ---------- INT 21h: DOS ----------
int21:
    and word [flags], ~F_CF
    movzx eax, byte [rAX+1]
    mov ecx, dos_tab
.f:
    cmp byte [ecx], 0xFF
    je .unknown
    cmp [ecx], al
    je .hit
    add ecx, 5
    jmp .f
.hit:
    jmp [ecx+1]
.unknown:
    mov ebx, m_int21
    call say
    mov al, [rAX+1]
    call hex2
    mov ebx, m_notsup
    call say
    mov ax, 1                   ; invalid function
    jmp dos_fail

%macro DOSFN 2
    db %1
    dd %2
%endmacro
dos_tab:
    DOSFN 0x00, dos_exit0
    DOSFN 0x01, d_getche
    DOSFN 0x02, d_putc
    DOSFN 0x06, d_dcio
    DOSFN 0x07, d_getch
    DOSFN 0x08, d_getch
    DOSFN 0x09, d_puts
    DOSFN 0x0A, d_gets
    DOSFN 0x0B, d_kbhit
    DOSFN 0x0C, d_flushin
    DOSFN 0x0D, d_ok
    DOSFN 0x0E, d_seldisk
    DOSFN 0x19, d_curdisk
    DOSFN 0x1A, d_setdta
    DOSFN 0x25, d_setvec
    DOSFN 0x2A, d_date
    DOSFN 0x2C, d_time
    DOSFN 0x2F, d_getdta
    DOSFN 0x30, d_version
    DOSFN 0x33, d_break
    DOSFN 0x35, d_getvec
    DOSFN 0x3C, d_create
    DOSFN 0x3D, d_open
    DOSFN 0x3E, d_close
    DOSFN 0x3F, d_read
    DOSFN 0x40, d_write
    DOSFN 0x41, d_delete
    DOSFN 0x42, d_seek
    DOSFN 0x43, d_attr
    DOSFN 0x44, d_ioctl
    DOSFN 0x47, d_getcwd
    DOSFN 0x48, d_alloc
    DOSFN 0x49, d_ok
    DOSFN 0x4A, d_resize
    DOSFN 0x4C, d_exit
    DOSFN 0x4E, d_nofiles
    DOSFN 0x4F, d_nofiles
    DOSFN 0x51, d_psp
    DOSFN 0x56, d_rename
    DOSFN 0x62, d_psp
    db 0xFF

; ax = DOS error code -> CF set, AX = code
dos_fail:
    mov [rAX], ax
    or word [flags], F_CF
    ret

d_ok:
    ret

d_exit:
    mov al, [rAX]
    mov [exit_code], al
    mov byte [done], 1
    ret

d_getche:                       ; 01: key with echo
    call key_get
    mov [rAX], al
    jmp putch
d_getch:                        ; 07/08: key, no echo
    call key_get
    mov [rAX], al
    ret
d_putc:                         ; 02: DL
    mov al, [rDX]
    mov [rAX], al
    jmp putch
d_dcio:                         ; 06: DL = FF reads (waits), else writes
    cmp byte [rDX], 0xFF
    jne d_putc
    call key_get
    mov [rAX], al
    and word [flags], ~F_ZF
    ret
d_puts:                         ; 09: DS:DX up to '$'
    mov ax, [sDS]
    mov dx, [rDX]
    call lin
    mov esi, eax
    mov ecx, 0x10000
.l:
    lodsb
    cmp al, '$'
    je .r
    call putch
    loop .l
.r:
    mov byte [rAX], '$'
    ret
d_kbhit:                        ; 0B: say a key is there; reading it waits
    mov byte [rAX], 0xFF
    ret
d_flushin:                      ; 0C: then the function in AL
    mov word [key_held], 0
    mov al, [rAX]
    mov [rAX+1], al
    cmp al, 0x0A
    je d_gets
    cmp al, 0x01
    je d_getche
    cmp al, 0x07
    je d_getch
    cmp al, 0x08
    je d_getch
    ret
d_gets:                         ; 0A: buffered line at DS:DX
    mov ax, [sDS]
    mov dx, [rDX]
    call lin
    mov edi, eax
    movzx ebx, byte [edi]       ; room
    test ebx, ebx
    jz .r
    dec ebx                     ; the CR takes one
    xor ecx, ecx
.k:
    push ecx
    call key_get
    pop ecx
    cmp al, 13
    je .cr
    cmp al, 0x1A
    je .cr
    cmp al, 8
    je .bs
    cmp ecx, ebx
    jae .k
    mov [edi+2+ecx], al
    inc ecx
    call putch
    jmp .k
.bs:
    jecxz .k
    dec ecx
    call putch
    jmp .k
.cr:
    mov byte [edi+2+ecx], 13
    mov [edi+1], cl
    mov al, 10
    call putch
.r:
    ret
d_seldisk:
    mov byte [rAX], 3           ; drives A: to C:
    ret
d_curdisk:
    mov byte [rAX], 2           ; C:
    ret
d_setdta:
    mov ax, [sDS]
    movzx eax, ax
    shl eax, 4
    movzx edx, word [rDX]
    add eax, edx
    mov [dta], eax
    mov ax, [sDS]
    mov [dta_far+2], ax
    mov ax, [rDX]
    mov [dta_far], ax
    ret
d_getdta:
    mov ax, [dta_far]
    test ax, ax
    jnz .s
    cmp word [dta_far+2], 0
    jne .s
    mov word [rBX], 0x80        ; still the default: PSP:0080
    mov word [sES], PSP_SEG
    ret
.s:
    mov [rBX], ax
    mov ax, [dta_far+2]
    mov [sES], ax
    ret
d_setvec:                       ; 25: AL = vector, DS:DX = handler
    movzx eax, byte [rAX]
    mov ebx, [mem]
    mov dx, [rDX]
    mov [ebx+eax*4], dx
    mov dx, [sDS]
    mov [ebx+eax*4+2], dx
    ret
d_getvec:                       ; 35: -> ES:BX
    movzx eax, byte [rAX]
    mov ebx, [mem]
    mov dx, [ebx+eax*4]
    mov [rBX], dx
    mov dx, [ebx+eax*4+2]
    mov [sES], dx
    ret
d_date:                         ; 2A: no clock call yet: 1 Jan 1980
    mov word [rCX], 1980
    mov word [rDX], 0x0101
    mov byte [rAX], 2           ; Tuesday
    ret
d_time:                         ; 2C: midnight
    mov word [rCX], 0
    mov word [rDX], 0
    ret
d_version:
    mov word [rAX], 0x0005      ; DOS 5.0
    mov word [rBX], 0
    mov word [rCX], 0
    ret
d_break:
    mov byte [rDX], 0
    ret
d_psp:
    mov word [rBX], PSP_SEG
    ret
d_getcwd:                       ; 47: DS:SI <- "" (the root)
    mov ax, [sDS]
    mov dx, [rSI]
    call lin
    mov byte [eax], 0
    mov word [rAX], 0x0100
    ret
d_nofiles:                      ; 4E/4F: no directory search yet
    mov ax, 0x12
    jmp dos_fail

; DS:DX -> fname (lower case, at most 31 characters)
name_dsdx:
    mov ax, [sDS]
    mov dx, [rDX]
; ax:dx -> fname
name_at:
    call lin
    mov esi, eax
    mov edi, fname
    xor ecx, ecx
.c:
    lodsb
    cmp al, 'A'
    jb .s
    cmp al, 'Z'
    ja .s
    or al, 0x20
.s:
    cmp ecx, 31
    jae .z
    mov [edi+ecx], al
    inc ecx
    test al, al
    jnz .c
    ret
.z:
    mov byte [edi+ecx], 0
    ret

; open/create: ecx = native flags -> AX = handle, or CF and AX = 2
open_common:
    push ecx
    call name_dsdx
    pop ecx
    mov eax, SYS_OPEN
    mov ebx, fname
    int 0x80
    cmp eax, -1
    je .no
    add eax, H_FIRST
    mov [rAX], ax
    ret
.no:
    mov ax, 2
    jmp dos_fail
d_create:
    mov ecx, O_CREATE|O_TRUNC
    jmp open_common
d_open:
    xor ecx, ecx
    jmp open_common

; BX = handle -> ebx = native fd, CF for the console handles 0..4
dos_fd:
    movzx ebx, word [rBX]
    sub ebx, H_FIRST
    ret

d_close:
    call dos_fd
    jc .r
    mov eax, SYS_CLOSE
    int 0x80
    cmp eax, -1
    je bad_handle
.r:
    ret
bad_handle:
    mov ax, 6
    jmp dos_fail

; 3F: read CX bytes to DS:DX
d_read:
    mov ax, [sDS]
    mov dx, [rDX]
    call lin
    mov edi, eax
    movzx edx, word [rCX]
    call dos_fd
    jnc .file
    cmp word [rBX], 0
    jne bad_handle
    ; the console: one line, CR LF at its end
    xor ecx, ecx
.k:
    cmp ecx, edx
    jae .kd
    push ecx
    push edx
    call key_get
    pop edx
    pop ecx
    cmp al, 0x1A
    je .kd
    cmp al, 8
    jne .st
    jecxz .k
    dec ecx
    call putch
    jmp .k
.st:
    mov [edi+ecx], al
    inc ecx
    cmp al, 13
    jne .echo
    mov al, 10
    call putch
    cmp ecx, edx
    jae .kd
    mov byte [edi+ecx], 10
    inc ecx
    jmp .kd
.echo:
    call putch
    jmp .k
.kd:
    mov [rAX], cx
    ret
.file:
    mov eax, SYS_READ
    mov ecx, edi
    int 0x80
    cmp eax, -1
    je bad_handle
    mov [rAX], ax
    ret

; 40: write CX bytes from DS:DX
d_write:
    mov ax, [sDS]
    mov dx, [rDX]
    call lin
    mov esi, eax
    movzx edx, word [rCX]
    call dos_fd
    jnc .file
    mov ecx, edx
.c:
    jecxz .cd
    lodsb
    call putch
    dec ecx
    jmp .c
.cd:
    mov [rAX], dx
    ret
.file:
    mov eax, SYS_WRITE
    mov ecx, esi
    int 0x80
    cmp eax, -1
    je bad_handle
    mov [rAX], ax
    ret

d_delete:
    call name_dsdx
    mov eax, SYS_DELETE
    mov ebx, fname
    int 0x80
    cmp eax, -1
    jne .r
    mov ax, 2
    jmp dos_fail
.r:
    ret

; 42: AL = whence, CX:DX = offset -> DX:AX
d_seek:
    call dos_fd
    jc bad_handle
    movzx ecx, word [rCX]
    shl ecx, 16
    mov cx, [rDX]
    movzx edx, byte [rAX]
    mov eax, SYS_SEEK
    int 0x80
    cmp eax, -1
    je .bad
    mov [rAX], ax
    shr eax, 16
    mov [rDX], ax
    ret
.bad:
    mov ax, 0x19                ; seek error
    jmp dos_fail

; 43: AL = 0 get attributes (the file must exist), 1 set (accepted)
d_attr:
    call name_dsdx
    mov eax, SYS_OPEN
    mov ebx, fname
    xor ecx, ecx
    int 0x80
    cmp eax, -1
    je .no
    mov ebx, eax
    mov eax, SYS_CLOSE
    int 0x80
    mov word [rCX], 0x20        ; archive
    ret
.no:
    mov ax, 2
    jmp dos_fail

; 44: IOCTL. AL = 0 device information, 1 set it (accepted), 7 ready
d_ioctl:
    mov al, [rAX]
    cmp al, 0
    je .info
    cmp al, 7
    je .ready
    ret
.ready:
    mov byte [rAX], 0xFF
    ret
.info:
    cmp word [rBX], H_FIRST
    jae .file
    mov word [rDX], 0x80D3      ; a character device, the console
    ret
.file:
    mov word [rDX], 0x0002      ; a file on drive C:
    ret

; 48: BX paragraphs -> AX = segment, from MEM_TOP down... above the
; program: the .COM/.EXE owns PSP..alloc_seg, blocks come from there up
d_alloc:
    movzx eax, word [alloc_seg]
    movzx ecx, word [rBX]
    add ecx, eax
    cmp ecx, MEM_TOP
    ja .no
    cmp eax, MEM_TOP
    jb .ok
.no:
    mov eax, MEM_TOP
    sub ax, [alloc_seg]
    jae .bx
    xor eax, eax
.bx:
    mov [rBX], ax
    mov ax, 8
    jmp dos_fail
.ok:
    mov [rAX], ax
    mov [alloc_seg], cx
    ret

; 4A: ES = block, BX = new size; shrinking the program's own block frees
; memory for 48h
d_resize:
    movzx eax, word [sES]
    movzx ecx, word [rBX]
    add ecx, eax
    cmp ecx, MEM_TOP
    ja .no
    cmp eax, PSP_SEG
    jne .r
    mov [alloc_seg], cx
.r:
    ret
.no:
    mov eax, MEM_TOP
    sub ax, [sES]
    mov [rBX], ax
    mov ax, 8
    jmp dos_fail

; 56: rename DS:DX -> ES:DI
d_rename:
    call name_dsdx
    mov esi, fname
    mov edi, fname2
    mov ecx, 32
    rep movsb
    mov ax, [sES]
    mov dx, [rDI]
    call name_at
    mov eax, SYS_RENAME
    mov ebx, fname2
    mov ecx, fname
    int 0x80
    cmp eax, -1
    jne .r
    mov ax, 2
    jmp dos_fail
.r:
    ret

; ======================== output helpers ========================

putch:                          ; al -> the console; keeps registers
    pushad
    movzx ebx, al
    cmp bl, 13                  ; CR alone does nothing on this console
    je .r
    mov eax, SYS_PUTC
    int 0x80
.r:
    popad
    ret
say:                            ; ebx = ASCIIZ
    push eax
    mov eax, SYS_PUTS
    int 0x80
    pop eax
    ret
hex4:                           ; ax
    push eax
    mov al, ah
    call hex2
    pop eax
hex2:                           ; al
    push eax
    shr al, 4
    call .d
    pop eax
.d:
    push eax
    and al, 15
    add al, '0'
    cmp al, '9'
    jbe .p
    add al, 7
.p:
    call putch
    pop eax
    ret

; ======================== the opcode table ========================

%macro OPS 2                    ; count, handler
%rep %1
    dd %2
%endrep
%endmacro
%macro ALUROW 0                 ; xx0..xx5: the six ALU forms
    OPS 6, op_alu
%endmacro

optab:
    ALUROW                      ; 00-05 add
    dd op_pushseg, op_popseg    ; 06 07 es
    ALUROW                      ; 08-0D or
    dd op_pushseg, op_0f        ; 0E push cs, 0F: 386 near jcc only
    ALUROW                      ; 10-15 adc
    dd op_pushseg, op_popseg    ; 16 17 ss
    ALUROW                      ; 18-1D sbb
    dd op_pushseg, op_popseg    ; 1E 1F ds
    ALUROW                      ; 20-25 and
    dd pf_es, op_daa            ; 26 27
    ALUROW                      ; 28-2D sub
    dd pf_cs, op_das            ; 2E 2F
    ALUROW                      ; 30-35 xor
    dd pf_ss, op_aaa            ; 36 37
    ALUROW                      ; 38-3D cmp
    dd pf_ds, op_aas            ; 3E 3F
    OPS 16, op_incdec           ; 40-4F
    OPS 8, op_pushr             ; 50-57
    OPS 8, op_popr              ; 58-5F
    dd op_pusha, op_popa        ; 60 61
    OPS 6, op_bad               ; 62-67
    dd op_pushiw, op_imul3, op_pushib, op_imul3   ; 68-6B
    OPS 4, op_bad               ; 6C-6F ins/outs
    OPS 16, op_jcc              ; 70-7F
    OPS 4, op_grp1              ; 80-83
    dd op_testeg, op_testeg, op_xchg, op_xchg     ; 84-87
    OPS 4, op_mov               ; 88-8B
    dd op_movsr, op_lea, op_movsr, op_popew       ; 8C-8F
    OPS 8, op_xchgax            ; 90-97
    dd op_cbw, op_cwd, op_callf, op_wait          ; 98-9B
    dd op_pushf, op_popf, op_sahf, op_lahf        ; 9C-9F
    OPS 4, op_movmoff           ; A0-A3
    OPS 4, op_string            ; A4-A7 movs cmps
    dd op_testai, op_testai     ; A8 A9
    OPS 6, op_string            ; AA-AF stos lods scas
    OPS 16, op_movri            ; B0-BF
    dd op_grp2, op_grp2, op_ret, op_ret           ; C0-C3
    dd op_lxs, op_lxs, op_movei, op_movei         ; C4-C7
    dd op_enter, op_leave, op_retf, op_retf       ; C8-CB
    dd op_int3, op_int, op_into, op_iret          ; CC-CF
    OPS 4, op_grp2              ; D0-D3
    dd op_aam, op_aad, op_bad, op_xlat            ; D4-D7
    OPS 8, op_fpu               ; D8-DF
    OPS 4, op_loop              ; E0-E3
    dd op_in, op_in, op_out, op_out               ; E4-E7
    dd op_call, op_jmp, op_jmpf, op_jmps          ; E8-EB
    dd op_in, op_in, op_out, op_out               ; EC-EF
    dd op_lock, op_bad, op_repne, op_repe         ; F0-F3
    dd op_hlt, op_cmc, op_grp3, op_grp3           ; F4-F7
    dd op_clc, op_stc, op_cli, op_sti             ; F8-FB
    dd op_cld, op_std, op_grp4, op_grp5           ; FC-FF
%if $-optab != 256*4
%error the opcode table needs 256 entries
%endif

m_usage db 'usage: run dosrun prog.com [arguments]', 10, 0
m_nomem db 'dosrun: not enough memory for DOS', 10, 0
m_open db 'dosrun: cannot open the program file', 10, 0
m_format db 'dosrun: not a DOS program (bad MZ header)', 10, 0
m_badop db 'dosrun: unsupported instruction ', 0
m_at db ' at ', 0
m_fpu db 'dosrun: the program needs a floating-point unit (not provided)', 10, 0
m_div0 db 'dosrun: divide error', 10, 0
m_disk db 'dosrun: BIOS disk services (INT 13h) are not provided', 10, 0
m_int21 db 'dosrun: INT 21h AH=', 0
m_notsup db ' is not supported', 10, 0

SQX_BSS
mem resd 1
fd resd 1
tail resd 1
img_len resd 1
dta resd 1
dta_far resd 1
str_fn resd 1
fake_ticks resd 1
regs resw 8
sregs resw 4
ip resw 1
flags resw 1
op_cs resw 1
op_ip resw 1
ea_off resw 1
ea_seg resw 1
alloc_seg resw 1
key_held resw 1
opc resb 1
ovr resb 1
repp resb 1
w resb 1
mreg resb 1
mrm_rm resb 1
mrm_ss resb 1
mrm_mem resb 1
done resb 1
exit_code resb 1
alignb 4
relent resb 4
hdr resb 32
exe_name resb 32
fname resb 32
fname2 resb 32
SQX_END
