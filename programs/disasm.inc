; Squirrel-OS/2 — x86 (32-bit) disassembler for the debugger (A.4).
; Original code. Include it in a program's code part; it needs nothing
; from the system, so it also runs in a host test harness.
;
;   esi = the instruction's bytes (at least 15 readable), ebx = its address
;   call dis_one
;   -> eax = its length (1..15), dis_text = ASCIIZ Intel-syntax text
;
; Branch targets are printed as addresses. When the including program
; defines DIS_SYMBOLS, dis_one calls dis_symname (eax = address -> esi =
; ASCIIZ name or 0, keeping other registers) and adds " <name>" after a
; branch target that has a symbol.
;
; Covers the one-byte opcode map (all general-purpose instructions), the
; common 0F two-byte ones (Jcc near, SETcc, CMOVcc, MOVZX/MOVSX, IMUL,
; BT*, BSF/BSR, SHLD/SHRD, XADD, CMPXCHG, BSWAP, CPUID, RDTSC, ...) and
; the x87 escapes D8-DF. Prefixes: operand size (66), segment overrides,
; LOCK, REP/REPNE. Anything else, and the 67 address-size prefix, is
; shown as "db 0xNN" with length 1.

; operand forms (second byte of each table entry)
F_BAD       equ 0
F_NONE      equ 1
F_EbGb      equ 2
F_EvGv      equ 3
F_GbEb      equ 4
F_GvEv      equ 5
F_ALIb      equ 6
F_eAXIv     equ 7
F_Zv        equ 8           ; register in the opcode's low 3 bits
F_ZbIb      equ 9
F_ZvIv      equ 10
F_Jb        equ 11
F_Jv        equ 12
F_Ib        equ 13
F_Iv        equ 14
F_Iw        equ 15
F_G1EbIb    equ 16          ; groups: the mnemonic byte is the group
F_G1EvIv    equ 17
F_G1EvIb    equ 18
F_G2EbIb    equ 19
F_G2EvIb    equ 20
F_G2Eb1     equ 21
F_G2Ev1     equ 22
F_G2EbCL    equ 23
F_G2EvCL    equ 24
F_G3Eb      equ 25
F_G3Ev      equ 26
F_G4        equ 27
F_G5        equ 28
F_GvM       equ 29
F_EvSw      equ 30
F_SwEw      equ 31
F_ALOb      equ 32
F_eAXOv     equ 33
F_ObAL      equ 34
F_OveAX     equ 35
F_GvEvIv    equ 36
F_GvEvIb    equ 37
F_EbIb      equ 38
F_EvIv      equ 39
F_INAI      equ 40          ; in al/eax, imm8
F_OUTIA     equ 41
F_INAD      equ 42          ; in al/eax, dx
F_OUTDA     equ 43
F_IwIb      equ 44
F_Ap        equ 45
F_Ev        equ 46
F_eAXZv     equ 47
F_SB        equ 48          ; string op, byte: mnemonic + 'b'
F_SV        equ 49          ; string op, word/dword: + 'w' / 'd'
F_X87       equ 50
F_ESC       equ 51          ; 0F
F_Eb        equ 52
F_GvEw      equ 53          ; movzx/movsx with a 16-bit source
F_GvEb      equ 54
F_EvGvIb    equ 55
F_EvGvCL    equ 56
F_G8EvIb    equ 57
F_CW        equ 58          ; cwde / cbw (mnemonic: the 32-bit name, +1 the 16-bit)
F_SEG       equ 59          ; push/pop of a segment register: reg in the table's group
F_Jcxz      equ 60
F_ACCDX     equ 61          ; (unused)

; ---------- mnemonics: 8 bytes each ----------
%assign dis_mn_n 0
%macro MN 2
M_%1 equ dis_mn_n
%%s: db %2
    times 8-($-%%s) db 0
%assign dis_mn_n dis_mn_n+1
%endmacro

dis_mn:
MN bad, 'db'
MN add, 'add'
MN or, 'or'
MN adc, 'adc'
MN sbb, 'sbb'
MN and, 'and'
MN sub, 'sub'
MN xor, 'xor'
MN cmp, 'cmp'
MN rol, 'rol'
MN ror, 'ror'
MN rcl, 'rcl'
MN rcr, 'rcr'
MN shl, 'shl'
MN shr, 'shr'
MN sal, 'sal'
MN sar, 'sar'
MN test, 'test'
MN not, 'not'
MN neg, 'neg'
MN mul, 'mul'
MN imul, 'imul'
MN div, 'div'
MN idiv, 'idiv'
MN inc, 'inc'
MN dec, 'dec'
MN call, 'call'
MN callf, 'call far'
MN jmp, 'jmp'
MN jmpf, 'jmp far'
MN push, 'push'
MN pop, 'pop'
MN mov, 'mov'
MN lea, 'lea'
MN xchg, 'xchg'
MN nop, 'nop'
MN daa, 'daa'
MN das, 'das'
MN aaa, 'aaa'
MN aas, 'aas'
MN pushad, 'pushad'
MN popad, 'popad'
MN bound, 'bound'
MN arpl, 'arpl'
MN ins, 'ins'
MN outs, 'outs'
MN jo, 'jo'
MN jno, 'jno'
MN jc, 'jc'
MN jnc, 'jnc'
MN jz, 'jz'
MN jnz, 'jnz'
MN jna, 'jna'
MN ja, 'ja'
MN js, 'js'
MN jns, 'jns'
MN jpe, 'jpe'
MN jpo, 'jpo'
MN jl, 'jl'
MN jnl, 'jnl'
MN jng, 'jng'
MN jg, 'jg'
MN cwde, 'cwde'
MN cbw, 'cbw'
MN cdq, 'cdq'
MN cwd, 'cwd'
MN wait, 'wait'
MN pushfd, 'pushfd'
MN popfd, 'popfd'
MN sahf, 'sahf'
MN lahf, 'lahf'
MN movs, 'movs'
MN cmps, 'cmps'
MN stos, 'stos'
MN lods, 'lods'
MN scas, 'scas'
MN ret, 'ret'
MN retf, 'retf'
MN les, 'les'
MN lds, 'lds'
MN enter, 'enter'
MN leave, 'leave'
MN int3, 'int3'
MN int, 'int'
MN into, 'into'
MN iretd, 'iretd'
MN aam, 'aam'
MN aad, 'aad'
MN salc, 'salc'
MN xlatb, 'xlatb'
MN loopne, 'loopne'
MN loope, 'loope'
MN loop, 'loop'
MN jecxz, 'jecxz'
MN in, 'in'
MN out, 'out'
MN int1, 'int1'
MN hlt, 'hlt'
MN cmc, 'cmc'
MN clc, 'clc'
MN stc, 'stc'
MN cli, 'cli'
MN sti, 'sti'
MN cld, 'cld'
MN std, 'std'
MN seto, 'seto'
MN setno, 'setno'
MN setc, 'setc'
MN setnc, 'setnc'
MN setz, 'setz'
MN setnz, 'setnz'
MN setna, 'setna'
MN seta, 'seta'
MN sets, 'sets'
MN setns, 'setns'
MN setpe, 'setpe'
MN setpo, 'setpo'
MN setl, 'setl'
MN setnl, 'setnl'
MN setng, 'setng'
MN setg, 'setg'
MN cmovo, 'cmovo'
MN cmovno, 'cmovno'
MN cmovc, 'cmovc'
MN cmovnc, 'cmovnc'
MN cmovz, 'cmovz'
MN cmovnz, 'cmovnz'
MN cmovna, 'cmovna'
MN cmova, 'cmova'
MN cmovs, 'cmovs'
MN cmovns, 'cmovns'
MN cmovpe, 'cmovpe'
MN cmovpo, 'cmovpo'
MN cmovl, 'cmovl'
MN cmovnl, 'cmovnl'
MN cmovng, 'cmovng'
MN cmovg, 'cmovg'
MN movzx, 'movzx'
MN movsx, 'movsx'
MN bt, 'bt'
MN bts, 'bts'
MN btr, 'btr'
MN btc, 'btc'
MN bsf, 'bsf'
MN bsr, 'bsr'
MN shld, 'shld'
MN shrd, 'shrd'
MN xadd, 'xadd'
MN cmpxchg, 'cmpxchg'
MN bswap, 'bswap'
MN cpuid, 'cpuid'
MN rdtsc, 'rdtsc'
MN ud2, 'ud2'
MN clts, 'clts'
MN invd, 'invd'
MN wbinvd, 'wbinvd'
MN rdmsr, 'rdmsr'
MN wrmsr, 'wrmsr'
MN pause, 'pause'
MN fadd, 'fadd'
MN fmul, 'fmul'
MN fcom, 'fcom'
MN fcomp, 'fcomp'
MN fsub, 'fsub'
MN fsubr, 'fsubr'
MN fdiv, 'fdiv'
MN fdivr, 'fdivr'
MN fld, 'fld'
MN fst, 'fst'
MN fstp, 'fstp'
MN fldenv, 'fldenv'
MN fldcw, 'fldcw'
MN fnstenv, 'fnstenv'
MN fnstcw, 'fnstcw'
MN fiadd, 'fiadd'
MN fimul, 'fimul'
MN ficom, 'ficom'
MN ficomp, 'ficomp'
MN fisub, 'fisub'
MN fisubr, 'fisubr'
MN fidiv, 'fidiv'
MN fidivr, 'fidivr'
MN fild, 'fild'
MN fisttp, 'fisttp'
MN fist, 'fist'
MN fistp, 'fistp'
MN frstor, 'frstor'
MN fnsave, 'fnsave'
MN fnstsw, 'fnstsw'
MN fbld, 'fbld'
MN fbstp, 'fbstp'
MN fxch, 'fxch'
MN fnop, 'fnop'
MN fchs, 'fchs'
MN fabs, 'fabs'
MN ftst, 'ftst'
MN fxam, 'fxam'
MN fld1, 'fld1'
MN fldl2t, 'fldl2t'
MN fldl2e, 'fldl2e'
MN fldpi, 'fldpi'
MN fldlg2, 'fldlg2'
MN fldln2, 'fldln2'
MN fldz, 'fldz'
MN f2xm1, 'f2xm1'
MN fyl2x, 'fyl2x'
MN fptan, 'fptan'
MN fpatan, 'fpatan'
MN fxtract, 'fxtract'
MN fprem1, 'fprem1'
MN fdecstp, 'fdecstp'
MN fincstp, 'fincstp'
MN fprem, 'fprem'
MN fyl2xp1, 'fyl2xp1'
MN fsqrt, 'fsqrt'
MN fsincos, 'fsincos'
MN frndint, 'frndint'
MN fscale, 'fscale'
MN fsin, 'fsin'
MN fcos, 'fcos'
MN fnclex, 'fnclex'
MN fninit, 'fninit'
MN ffree, 'ffree'
MN faddp, 'faddp'
MN fmulp, 'fmulp'
MN fsubrp, 'fsubrp'
MN fsubp, 'fsubp'
MN fdivrp, 'fdivrp'
MN fdivp, 'fdivp'
MN fcompp, 'fcompp'
MN fucom, 'fucom'
MN fucomp, 'fucomp'
MN fucompp, 'fucompp'
MN movsd_, 'movsd'

; groups: 8 mnemonics each, chosen by the ModRM reg field
dis_groups:
G_1 equ 0
    db M_add, M_or, M_adc, M_sbb, M_and, M_sub, M_xor, M_cmp
G_2 equ 1
    db M_rol, M_ror, M_rcl, M_rcr, M_shl, M_shr, M_sal, M_sar
G_3 equ 2
    db M_test, M_test, M_not, M_neg, M_mul, M_imul, M_div, M_idiv
G_4 equ 3
    db M_inc, M_dec, M_bad, M_bad, M_bad, M_bad, M_bad, M_bad
G_5 equ 4
    db M_inc, M_dec, M_call, M_callf, M_jmp, M_jmpf, M_push, M_bad
G_8 equ 5
    db M_bad, M_bad, M_bad, M_bad, M_bt, M_bts, M_btr, M_btc
G_8F equ 6
    db M_pop, M_bad, M_bad, M_bad, M_bad, M_bad, M_bad, M_bad
G_C6 equ 7
    db M_mov, M_bad, M_bad, M_bad, M_bad, M_bad, M_bad, M_bad

; ---------- the one-byte map: mnemonic, form ----------
%macro ALU 1                    ; the six forms of 00-05 style opcodes
    db M_%1, F_EbGb, M_%1, F_EvGv, M_%1, F_GbEb, M_%1, F_GvEv
    db M_%1, F_ALIb, M_%1, F_eAXIv
%endmacro
dis_map1:
    ALU add                                     ; 00
    db 0, F_SEG, 4, F_SEG                       ; 06 push es, 07 pop es (group: seg | pop<<2)
    ALU or                                      ; 08
    db 1, F_SEG, M_bad, F_ESC                   ; 0E push cs, 0F
    ALU adc                                     ; 10
    db 2, F_SEG, 6, F_SEG                       ; 16 push ss, 17 pop ss
    ALU sbb                                     ; 18
    db 3, F_SEG, 7, F_SEG                       ; 1E push ds, 1F pop ds
    ALU and                                     ; 20
    db M_bad, F_BAD, M_daa, F_NONE              ; 26 (es:), 27
    ALU sub                                     ; 28
    db M_bad, F_BAD, M_das, F_NONE              ; 2E (cs:), 2F
    ALU xor                                     ; 30
    db M_bad, F_BAD, M_aaa, F_NONE              ; 36 (ss:), 37
    ALU cmp                                     ; 38
    db M_bad, F_BAD, M_aas, F_NONE              ; 3E (ds:), 3F
    times 8 db M_inc, F_Zv                      ; 40
    times 8 db M_dec, F_Zv                      ; 48
    times 8 db M_push, F_Zv                     ; 50
    times 8 db M_pop, F_Zv                      ; 58
    db M_pushad, F_NONE, M_popad, F_NONE        ; 60
    db M_bound, F_GvM, M_arpl, F_EvGv           ; 62 (arpl: Ew,Gw shown as Ev,Gv)
    db M_bad, F_BAD, M_bad, F_BAD, M_bad, F_BAD, M_bad, F_BAD   ; 64-67 prefixes
    db M_push, F_Iv, M_imul, F_GvEvIv           ; 68
    db M_push, F_Ib, M_imul, F_GvEvIb           ; 6A
    db M_ins, F_SB, M_ins, F_SV, M_outs, F_SB, M_outs, F_SV ; 6C
    db M_jo, F_Jb, M_jno, F_Jb, M_jc, F_Jb, M_jnc, F_Jb     ; 70
    db M_jz, F_Jb, M_jnz, F_Jb, M_jna, F_Jb, M_ja, F_Jb
    db M_js, F_Jb, M_jns, F_Jb, M_jpe, F_Jb, M_jpo, F_Jb
    db M_jl, F_Jb, M_jnl, F_Jb, M_jng, F_Jb, M_jg, F_Jb
    db G_1, F_G1EbIb, G_1, F_G1EvIv, G_1, F_G1EbIb, G_1, F_G1EvIb  ; 80
    db M_test, F_EbGb, M_test, F_EvGv, M_xchg, F_EbGb, M_xchg, F_EvGv ; 84
    db M_mov, F_EbGb, M_mov, F_EvGv, M_mov, F_GbEb, M_mov, F_GvEv ; 88
    db M_mov, F_EvSw, M_lea, F_GvM, M_mov, F_SwEw, G_8F, F_Ev     ; 8C
    db M_nop, F_NONE                            ; 90
    times 7 db M_xchg, F_eAXZv                  ; 91
    db M_cwde, F_CW, M_cdq, F_CW                ; 98
    db M_callf, F_Ap, M_wait, F_NONE            ; 9A
    db M_pushfd, F_NONE, M_popfd, F_NONE, M_sahf, F_NONE, M_lahf, F_NONE ; 9C
    db M_mov, F_ALOb, M_mov, F_eAXOv, M_mov, F_ObAL, M_mov, F_OveAX ; A0
    db M_movs, F_SB, M_movs, F_SV, M_cmps, F_SB, M_cmps, F_SV ; A4
    db M_test, F_ALIb, M_test, F_eAXIv          ; A8
    db M_stos, F_SB, M_stos, F_SV, M_lods, F_SB, M_lods, F_SV ; AA
    db M_scas, F_SB, M_scas, F_SV               ; AE
    times 8 db M_mov, F_ZbIb                    ; B0
    times 8 db M_mov, F_ZvIv                    ; B8
    db G_2, F_G2EbIb, G_2, F_G2EvIb             ; C0
    db M_ret, F_Iw, M_ret, F_NONE               ; C2
    db M_les, F_GvM, M_lds, F_GvM               ; C4
    db G_C6, F_EbIb, G_C6, F_EvIv               ; C6
    db M_enter, F_IwIb, M_leave, F_NONE         ; C8
    db M_retf, F_Iw, M_retf, F_NONE             ; CA
    db M_int3, F_NONE, M_int, F_Ib, M_into, F_NONE, M_iretd, F_NONE ; CC
    db G_2, F_G2Eb1, G_2, F_G2Ev1, G_2, F_G2EbCL, G_2, F_G2EvCL ; D0
    db M_aam, F_Ib, M_aad, F_Ib, M_salc, F_NONE, M_xlatb, F_NONE ; D4
    times 8 db M_bad, F_X87                     ; D8
    db M_loopne, F_Jb, M_loope, F_Jb, M_loop, F_Jb, M_jecxz, F_Jcxz ; E0
    db M_in, F_INAI, M_in, F_INAI, M_out, F_OUTIA, M_out, F_OUTIA ; E4
    db M_call, F_Jv, M_jmp, F_Jv, M_jmpf, F_Ap, M_jmp, F_Jb ; E8
    db M_in, F_INAD, M_in, F_INAD, M_out, F_OUTDA, M_out, F_OUTDA ; EC
    db M_bad, F_BAD, M_int1, F_NONE, M_bad, F_BAD, M_bad, F_BAD ; F0 (lock), F1, F2/F3 (rep)
    db M_hlt, F_NONE, M_cmc, F_NONE, G_3, F_G3Eb, G_3, F_G3Ev ; F4
    db M_clc, F_NONE, M_stc, F_NONE, M_cli, F_NONE, M_sti, F_NONE ; F8
    db M_cld, F_NONE, M_std, F_NONE, G_4, F_G4, G_5, F_G5 ; FC
%if $-dis_map1 != 512
%error dis_map1 needs 256 entries
%endif

; ---------- 0F xx ----------
dis_map2:
    times 6 db M_bad, F_BAD                     ; 00-05
    db M_clts, F_NONE, M_bad, F_BAD             ; 06
    db M_invd, F_NONE, M_wbinvd, F_NONE         ; 08
    db M_bad, F_BAD, M_ud2, F_NONE              ; 0A
    times 4 db M_bad, F_BAD                     ; 0C
    times 15 db M_bad, F_BAD                    ; 10-1E
    db M_nop, F_Ev                              ; 1F
    times 16 db M_bad, F_BAD                    ; 20-2F
    db M_wrmsr, F_NONE, M_rdtsc, F_NONE, M_rdmsr, F_NONE ; 30
    times 13 db M_bad, F_BAD                    ; 33-3F
    db M_cmovo, F_GvEv, M_cmovno, F_GvEv, M_cmovc, F_GvEv, M_cmovnc, F_GvEv ; 40
    db M_cmovz, F_GvEv, M_cmovnz, F_GvEv, M_cmovna, F_GvEv, M_cmova, F_GvEv
    db M_cmovs, F_GvEv, M_cmovns, F_GvEv, M_cmovpe, F_GvEv, M_cmovpo, F_GvEv
    db M_cmovl, F_GvEv, M_cmovnl, F_GvEv, M_cmovng, F_GvEv, M_cmovg, F_GvEv
    times 48 db M_bad, F_BAD                    ; 50-7F
    db M_jo, F_Jv, M_jno, F_Jv, M_jc, F_Jv, M_jnc, F_Jv     ; 80
    db M_jz, F_Jv, M_jnz, F_Jv, M_jna, F_Jv, M_ja, F_Jv
    db M_js, F_Jv, M_jns, F_Jv, M_jpe, F_Jv, M_jpo, F_Jv
    db M_jl, F_Jv, M_jnl, F_Jv, M_jng, F_Jv, M_jg, F_Jv
    db M_seto, F_Eb, M_setno, F_Eb, M_setc, F_Eb, M_setnc, F_Eb ; 90
    db M_setz, F_Eb, M_setnz, F_Eb, M_setna, F_Eb, M_seta, F_Eb
    db M_sets, F_Eb, M_setns, F_Eb, M_setpe, F_Eb, M_setpo, F_Eb
    db M_setl, F_Eb, M_setnl, F_Eb, M_setng, F_Eb, M_setg, F_Eb
    db 8|4, F_SEG, 8|4|16, F_SEG                ; A0 push fs, A1 pop fs (|8: fs/gs)
    db M_cpuid, F_NONE, M_bt, F_EvGv            ; A2
    db M_shld, F_EvGvIb, M_shld, F_EvGvCL       ; A4
    db M_bad, F_BAD, M_bad, F_BAD               ; A6
    db 8|5, F_SEG, 8|5|16, F_SEG                ; A8 push gs, A9 pop gs
    db M_bad, F_BAD, M_bts, F_EvGv              ; AA
    db M_shrd, F_EvGvIb, M_shrd, F_EvGvCL       ; AC
    db M_bad, F_BAD, M_imul, F_GvEv             ; AE
    db M_cmpxchg, F_EbGb, M_cmpxchg, F_EvGv     ; B0
    db M_bad, F_BAD, M_btr, F_EvGv              ; B2
    db M_bad, F_BAD, M_bad, F_BAD               ; B4
    db M_movzx, F_GvEb, M_movzx, F_GvEw         ; B6
    db M_bad, F_BAD, M_bad, F_BAD               ; B8
    db G_8, F_G8EvIb, M_btc, F_EvGv             ; BA
    db M_bsf, F_GvEv, M_bsr, F_GvEv             ; BC
    db M_movsx, F_GvEb, M_movsx, F_GvEw         ; BE
    db M_xadd, F_EbGb, M_xadd, F_EvGv           ; C0
    times 6 db M_bad, F_BAD                     ; C2-C7
    times 8 db M_bswap, F_Zv                    ; C8
    times 48 db M_bad, F_BAD                    ; D0-FF
%if $-dis_map2 != 512
%error dis_map2 needs 256 entries
%endif

; x87 with a memory operand: [escape - D8][reg] -> mnemonic, size (0 none,
; 1 byte, 2 word, 4 dword, 8 qword, 10 tword)
dis_fpu_mem:
    db M_fadd,4, M_fmul,4, M_fcom,4, M_fcomp,4, M_fsub,4, M_fsubr,4, M_fdiv,4, M_fdivr,4
    db M_fld,4, M_bad,0, M_fst,4, M_fstp,4, M_fldenv,0, M_fldcw,2, M_fnstenv,0, M_fnstcw,2
    db M_fiadd,4, M_fimul,4, M_ficom,4, M_ficomp,4, M_fisub,4, M_fisubr,4, M_fidiv,4, M_fidivr,4
    db M_fild,4, M_fisttp,4, M_fist,4, M_fistp,4, M_bad,0, M_fld,10, M_bad,0, M_fstp,10
    db M_fadd,8, M_fmul,8, M_fcom,8, M_fcomp,8, M_fsub,8, M_fsubr,8, M_fdiv,8, M_fdivr,8
    db M_fld,8, M_fisttp,8, M_fst,8, M_fstp,8, M_frstor,0, M_bad,0, M_fnsave,0, M_fnstsw,2
    db M_fiadd,2, M_fimul,2, M_ficom,2, M_ficomp,2, M_fisub,2, M_fisubr,2, M_fidiv,2, M_fidivr,2
    db M_fild,2, M_fisttp,2, M_fist,2, M_fistp,2, M_fbld,10, M_fild,8, M_fbstp,10, M_fistp,8
; D9 E0-FF
dis_fpu_d9:
    db M_fchs, M_fabs, M_bad, M_bad, M_ftst, M_fxam, M_bad, M_bad
    db M_fld1, M_fldl2t, M_fldl2e, M_fldpi, M_fldlg2, M_fldln2, M_fldz, M_bad
    db M_f2xm1, M_fyl2x, M_fptan, M_fpatan, M_fxtract, M_fprem1, M_fdecstp, M_fincstp
    db M_fprem, M_fyl2xp1, M_fsqrt, M_fsincos, M_frndint, M_fscale, M_fsin, M_fcos
dis_fpu_arith:                  ; D8 / DC register forms
    db M_fadd, M_fmul, M_fcom, M_fcomp, M_fsub, M_fsubr, M_fdiv, M_fdivr
dis_fpu_arithp:                 ; DE register forms
    db M_faddp, M_fmulp, M_bad, M_bad, M_fsubrp, M_fsubp, M_fdivrp, M_fdivp

dis_reg32 db 'eaxecxedxebxespebpesiedi'
dis_reg16 db 'axcxdxbxspbpsidi'
dis_reg8  db 'alcldlblahchdhbh'
dis_sreg  db 'escsssdsfsgs????'

; ---------- state ----------
dis_text times 96 db 0
dis_addr dd 0               ; the instruction's address
dis_esp dd 0
dis_begin dd 0              ; its first byte
dis_opsz db 0               ; 1: a 66 prefix (16-bit operands)
dis_seg db 0                ; segment override + 1, 0 = none
dis_rep db 0                ; 0xF2 / 0xF3 / 0
dis_lock db 0
dis_op db 0                 ; the opcode byte (last one)
dis_mod db 0
dis_reg db 0
dis_rm db 0
dis_base db 0               ; memory operand: base reg, 8 = none
dis_index db 0              ; index reg, 8 = none
dis_scale db 0              ; 1, 2, 4, 8
dis_disp dd 0
dis_hasdisp db 0            ; 1: a displacement byte or dword was there
dis_imm dd 0
dis_imm2 dd 0

; esi = bytes, ebx = address -> eax = length, dis_text
dis_one:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    mov [dis_esp], esp          ; dis_one.bad may be reached from any depth
    mov [dis_addr], ebx
    mov [dis_begin], esi
    mov edi, dis_text
    xor eax, eax
    mov [dis_opsz], al
    mov [dis_seg], al
    mov [dis_rep], al
    mov [dis_lock], al
    mov ecx, 14                 ; prefixes before the opcode, at most
.prefix:
    mov al, [esi]
    cmp al, 0x66
    je .p66
    cmp al, 0xF0
    je .plock
    cmp al, 0xF2
    je .prep
    cmp al, 0xF3
    je .prep
    mov edx, dis_segpfx
.ps:
    cmp al, [edx]
    je .pseg
    inc edx
    cmp edx, dis_segpfx+6
    jb .ps
    jmp .opcode
.p66:
    mov byte [dis_opsz], 1
    jmp .pnext
.plock:
    mov byte [dis_lock], 1
    jmp .pnext
.prep:
    mov [dis_rep], al
    jmp .pnext
.pseg:
    sub edx, dis_segpfx-1
    mov [dis_seg], dl
.pnext:
    inc esi
    loop .prefix
    jmp .bad
.opcode:
    lodsb
    mov [dis_op], al
    movzx edx, al
    mov ah, [dis_map1+edx*2+1]  ; form
    mov al, [dis_map1+edx*2]    ; mnemonic
    cmp ah, F_ESC
    jne .have
    lodsb
    mov [dis_op], al
    movzx edx, al
    mov ah, [dis_map2+edx*2+1]
    mov al, [dis_map2+edx*2]
.have:
    cmp ah, F_BAD
    je .bad
    ; the lock and rep prefixes, as words
    cmp byte [dis_lock], 0
    je .nolock
    push esi
    mov esi, dis_s_lock
    call dis_puts
    pop esi
.nolock:
    cmp byte [dis_rep], 0
    je .norep
    cmp byte [dis_op], 0x90     ; F3 90: pause
    jne .rep
    cmp byte [dis_rep], 0xF3
    jne .rep
    mov al, M_pause
    mov ah, F_NONE
    jmp .norep
.rep:
    push esi
    mov esi, dis_s_rep
    cmp byte [dis_rep], 0xF3
    jne .rne
    mov dl, [dis_op]            ; cmps / scas repeat while equal
    and dl, 0xF6
    cmp dl, 0xA6
    jne .rp
    mov esi, dis_s_repe
    jmp .rp
.rne:
    mov esi, dis_s_repne
.rp:
    call dis_puts
    pop esi
.norep:
    movzx edx, ah
    cmp edx, F_Jcxz
    ja .bad
    jmp [dis_forms+edx*4]

; every form ends here: esi = the next instruction
dis_done:
    mov byte [edi], 0
    ; strip trailing blanks
.t:
    cmp edi, dis_text
    je .z
    cmp byte [edi-1], ' '
    jne .z
    dec edi
    mov byte [edi], 0
    jmp .t
.z:
    mov eax, esi
    sub eax, [dis_begin]
    cmp eax, 15
    ja dis_one.bad2
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

dis_one.bad:
dis_one.bad2:
    mov esp, [dis_esp]
    mov esi, [dis_begin]
    mov edi, dis_text
    push esi
    mov esi, dis_s_db
    call dis_puts
    pop esi
    movzx eax, byte [esi]
    call dis_hex
    inc esi
    jmp dis_done

dis_forms:
    dd dis_one.bad, f_none, f_ebgb, f_evgv, f_gbeb, f_gvev, f_alib, f_eaxiv
    dd f_zv, f_zbib, f_zviv, f_jb, f_jv, f_ib, f_iv, f_iw
    dd f_g1ebib, f_g1eviv, f_g1evib, f_g2ebib, f_g2evib, f_g2eb1, f_g2ev1, f_g2ebcl
    dd f_g2evcl, f_g3eb, f_g3ev, f_g4, f_g5, f_gvm, f_evsw, f_swew
    dd f_alob, f_eaxov, f_obal, f_oveax, f_gveviv, f_gvevib, f_ebib, f_eviv
    dd f_inai, f_outia, f_inad, f_outda, f_iwib, f_ap, f_ev, f_eaxzv
    dd f_sb, f_sv, f_x87, dis_one.bad, f_eb, f_gvew, f_gveb, f_evgvib
    dd f_evgvcl, f_g8evib, f_cw, f_seg, f_jcxz

; ---------- output helpers (edi = text) ----------

dis_putc:                       ; al
    stosb
    ret

dis_puts:                       ; esi = ASCIIZ
    push eax
.l: lodsb
    test al, al
    jz .r
    stosb
    jmp .l
.r: pop eax
    ret

; al = mnemonic number: its name and a blank
dis_mnem:
    push esi
    push ecx
    movzx esi, al
    shl esi, 3
    add esi, dis_mn
    mov ecx, 8
.l: lodsb
    test al, al
    jz .e
    stosb
    loop .l
.e: mov al, ' '
    stosb
    pop ecx
    pop esi
    ret

dis_comma:
    mov byte [edi], ','
    inc edi
    ret

; eax -> "0x" and hex digits, no leading zeros
dis_hex:
    push eax
    push ecx
    push edx
    mov edx, eax
    mov ax, '0x'
    stosw
    mov ecx, 8
.skip:
    cmp ecx, 1
    je .dig
    test edx, 0xF0000000
    jnz .dig
    shl edx, 4
    dec ecx
    jmp .skip
.dig:
    rol edx, 4
    mov al, dl
    and al, 15
    add al, '0'
    cmp al, '9'
    jbe .d
    add al, 'a'-'9'-1
.d: stosb
    loop .dig
    pop edx
    pop ecx
    pop eax
    ret

; eax = signed value -> "+0x.." or "-0x.."
dis_shex:
    push eax
    test eax, eax
    js .neg
    mov byte [edi], '+'
    inc edi
    call dis_hex
    pop eax
    ret
.neg:
    mov byte [edi], '-'
    inc edi
    neg eax
    call dis_hex
    pop eax
    ret

; eax = signed immediate: "0x5" or "-0x1"
dis_simm:
    test eax, eax
    jns dis_hex
    push eax
    mov byte [edi], '-'
    inc edi
    neg eax
    call dis_hex
    pop eax
    ret

; eax = register number, dl = size (1, 2, 4)
dis_regname:
    push eax
    push esi
    and eax, 7
    cmp dl, 4
    je .r32
    shl eax, 1
    lea esi, [dis_reg16+eax]
    cmp dl, 2
    je .two
    lea esi, [dis_reg8+eax]
.two:
    movsw
    pop esi
    pop eax
    ret
.r32:
    lea eax, [eax+eax*2]
    lea esi, [dis_reg32+eax]
    movsw
    movsb
    pop esi
    pop eax
    ret

; dl = 2 or 4 by the operand size
dis_vsize:
    mov dl, 4
    cmp byte [dis_opsz], 0
    je .r
    mov dl, 2
.r: ret

; size keyword: dl = 1 byte, 2 word, 4 dword, 8 qword, 10 tword
dis_sizekw:
    push esi
    mov esi, dis_s_byte
    cmp dl, 1
    je .p
    mov esi, dis_s_word
    cmp dl, 2
    je .p
    mov esi, dis_s_dword
    cmp dl, 4
    je .p
    mov esi, dis_s_qword
    cmp dl, 8
    je .p
    mov esi, dis_s_tword
.p: call dis_puts
    pop esi
    ret

; ---------- ModRM ----------

; reads ModRM (and SIB, displacement) at esi into dis_mod/reg/rm/base/
; index/scale/disp
dis_modrm:
    push eax
    push ebx
    push ecx
    lodsb
    mov ah, al
    shr al, 6
    mov [dis_mod], al
    mov al, ah
    shr al, 3
    and al, 7
    mov [dis_reg], al
    mov al, ah
    and al, 7
    mov [dis_rm], al
    mov byte [dis_base], 8
    mov byte [dis_index], 8
    mov byte [dis_scale], 1
    mov dword [dis_disp], 0
    mov byte [dis_hasdisp], 0
    cmp byte [dis_mod], 3
    je .r
    mov bl, [dis_rm]
    cmp bl, 4
    jne .nosib
    lodsb                       ; SIB
    mov ah, al
    shr al, 6
    mov cl, al
    mov al, 1
    shl al, cl
    mov [dis_scale], al
    mov al, ah
    shr al, 3
    and al, 7
    cmp al, 4
    je .noidx
    mov [dis_index], al
.noidx:
    mov bl, ah
    and bl, 7
    cmp bl, 5
    jne .base
    cmp byte [dis_mod], 0
    jne .base
    jmp .d32                    ; no base, disp32
.nosib:
    cmp bl, 5
    jne .base
    cmp byte [dis_mod], 0
    je .d32                     ; [disp32]
.base:
    mov [dis_base], bl
    cmp byte [dis_mod], 1
    je .d8
    cmp byte [dis_mod], 2
    je .d32
    jmp .r
.d8:
    lodsb
    movsx eax, al
    mov [dis_disp], eax
    mov byte [dis_hasdisp], 1
    jmp .r
.d32:
    lodsd
    mov [dis_disp], eax
    mov byte [dis_hasdisp], 1
.r: pop ecx
    pop ebx
    pop eax
    ret

; the r/m operand: dl = its size; dh = 1 to say the size for memory
dis_rmop:
    cmp byte [dis_mod], 3
    jne .mem
    movzx eax, byte [dis_rm]
    jmp dis_regname
.mem:
    test dh, dh
    jz dis_memop
    call dis_sizekw
; the memory operand: [seg:base+index*scale+disp]
dis_memop:
    push eax
    push ecx
    push edx
    mov al, '['
    stosb
    movzx eax, byte [dis_seg]
    test eax, eax
    jz .noseg
    dec eax
    push esi
    lea esi, [dis_sreg+eax*2]
    movsw
    pop esi
    mov al, ':'
    stosb
.noseg:
    xor ecx, ecx                ; 1 once something is printed
    mov dl, 4
    movzx eax, byte [dis_base]
    cmp al, 8
    je .noba
    call dis_regname
    inc ecx
.noba:
    movzx eax, byte [dis_index]
    cmp al, 8
    je .noix
    test ecx, ecx
    jz .ix
    mov byte [edi], '+'
    inc edi
.ix:
    call dis_regname
    inc ecx
    cmp byte [dis_scale], 1
    je .noix
    mov byte [edi], '*'
    inc edi
    mov al, [dis_scale]
    add al, '0'
    stosb
.noix:
    mov eax, [dis_disp]
    test ecx, ecx
    jz .abs
    cmp byte [dis_hasdisp], 0
    je .close
    test eax, eax
    jz .close
    call dis_shex
    jmp .close
.abs:
    call dis_hex
.close:
    mov al, ']'
    stosb
    pop edx
    pop ecx
    pop eax
    ret

; the reg operand of ModRM, dl = size
dis_regop:
    movzx eax, byte [dis_reg]
    jmp dis_regname

; ---------- immediates ----------
dis_ib:                         ; -> eax = unsigned byte
    movzx eax, byte [esi]
    inc esi
    ret
dis_ibs:                        ; -> eax = sign-extended byte
    movsx eax, byte [esi]
    inc esi
    ret
dis_iw:
    movzx eax, word [esi]
    add esi, 2
    ret
dis_iv:                         ; by the operand size
    cmp byte [dis_opsz], 0
    jne dis_iw
    lodsd
    ret

; eax = branch target: address, and <symbol>
dis_target:
    call dis_hex
%ifdef DIS_SYMBOLS
    push esi
    call dis_symname
    test esi, esi
    jz .r
    mov ax, ' <'
    stosw
    call dis_puts
    mov al, '>'
    stosb
.r: pop esi
%endif
    ret

; ---------- the forms ----------
f_none:
    call dis_mnem
    jmp dis_done

f_cw:                           ; cwde/cbw, cdq/cwd
    cmp byte [dis_opsz], 0
    je .m
    inc al
.m: call dis_mnem
    jmp dis_done

f_ebgb:
    call dis_mnem
    call dis_modrm
    mov dx, 1
    call dis_rmop
    call dis_comma
    call dis_regop
    jmp dis_done
f_evgv:
    call dis_mnem
    call dis_modrm
    call dis_vsize
    xor dh, dh
    call dis_rmop
    call dis_comma
    call dis_regop
    jmp dis_done
f_gbeb:
    call dis_mnem
    call dis_modrm
    mov dx, 1
    call dis_regop
    call dis_comma
    call dis_rmop
    jmp dis_done
f_gvev:
    call dis_mnem
    call dis_modrm
    call dis_vsize
    xor dh, dh
    call dis_regop
    call dis_comma
    call dis_rmop
    jmp dis_done
f_gvm:                          ; lea, les, lds, bound: no size
    call dis_mnem
    call dis_modrm
    cmp byte [dis_mod], 3
    je dis_one.bad
    call dis_vsize
    call dis_regop
    call dis_comma
    call dis_memop
    jmp dis_done
f_gveb:
    call dis_mnem
    call dis_modrm
    call dis_vsize
    call dis_regop
    call dis_comma
    mov dx, 0x0101
    call dis_rmop
    jmp dis_done
f_gvew:
    call dis_mnem
    call dis_modrm
    call dis_vsize
    call dis_regop
    call dis_comma
    mov dx, 0x0102
    call dis_rmop
    jmp dis_done
f_alib:
    call dis_mnem
    mov ax, 'al'
    stosw
    call dis_comma
    call dis_ib
    call dis_hex
    jmp dis_done
f_eaxiv:
    call dis_mnem
    call dis_vsize
    xor eax, eax
    call dis_regname
    call dis_comma
    call dis_iv
    call dis_hex
    jmp dis_done
f_zv:                           ; register in the low 3 bits
    call dis_mnem
    call dis_vsize
    movzx eax, byte [dis_op]
    call dis_regname
    jmp dis_done
f_eaxzv:
    call dis_mnem
    call dis_vsize
    xor eax, eax
    call dis_regname
    call dis_comma
    movzx eax, byte [dis_op]
    call dis_regname
    jmp dis_done
f_zbib:
    call dis_mnem
    mov dl, 1
    movzx eax, byte [dis_op]
    call dis_regname
    call dis_comma
    call dis_ib
    call dis_hex
    jmp dis_done
f_zviv:
    call dis_mnem
    call dis_vsize
    movzx eax, byte [dis_op]
    call dis_regname
    call dis_comma
    call dis_iv
    call dis_hex
    jmp dis_done
f_jb:
    call dis_mnem
    call dis_ibs
f_jrel:                         ; eax = displacement
    add eax, esi
    sub eax, [dis_begin]
    add eax, [dis_addr]
    call dis_target
    jmp dis_done
f_jv:
    call dis_mnem
    call dis_iv
    cmp byte [dis_opsz], 0
    je f_jrel
    movsx eax, ax
    jmp f_jrel
f_jcxz:
    cmp byte [dis_opsz], 0      ; (67 would be jcxz; not decoded)
    jmp f_jb
f_ib:
    call dis_mnem
    cmp byte [dis_op], 0x6A     ; push imm8: sign-extended
    je .s
    call dis_ib
    call dis_hex
    jmp dis_done
.s: call dis_ibs
    call dis_simm
    jmp dis_done
f_iv:
    call dis_mnem
    call dis_iv
    call dis_hex
    jmp dis_done
f_iw:
    call dis_mnem
    call dis_iw
    call dis_hex
    jmp dis_done
f_iwib:
    call dis_mnem
    call dis_iw
    call dis_hex
    call dis_comma
    call dis_ib
    call dis_hex
    jmp dis_done

; groups: al = group number -> al = the mnemonic for dis_reg (CF: none)
dis_group:
    movzx eax, al
    shl eax, 3
    movzx ecx, byte [dis_reg]
    add eax, ecx
    mov al, [dis_groups+eax]
    cmp al, M_bad
    je .no
    clc
    ret
.no:
    stc
    ret

f_g1ebib:
    call dis_modrm
    call dis_group
    call dis_mnem
    mov dx, 0x0101
    call dis_rmop
    call dis_comma
    call dis_ib
    call dis_hex
    jmp dis_done
f_g1eviv:
    call dis_modrm
    call dis_group
    call dis_mnem
    call dis_vsize
    mov dh, 1
    call dis_rmop
    call dis_comma
    call dis_iv
    call dis_hex
    jmp dis_done
f_g1evib:
    call dis_modrm
    call dis_group
    call dis_mnem
    call dis_vsize
    mov dh, 1
    call dis_rmop
    call dis_comma
    call dis_ibs
    call dis_simm
    jmp dis_done
f_ebib:                         ; mov Eb, Ib (C6 /0)
    call dis_modrm
    call dis_group
    jc dis_one.bad
    jmp f_g1ebib.mn
f_g1ebib.mn:
    call dis_mnem
    mov dx, 0x0101
    call dis_rmop
    call dis_comma
    call dis_ib
    call dis_hex
    jmp dis_done
f_eviv:
    call dis_modrm
    call dis_group
    jc dis_one.bad
    call dis_mnem
    call dis_vsize
    mov dh, 1
    call dis_rmop
    call dis_comma
    call dis_iv
    call dis_hex
    jmp dis_done
f_g2ebib:
    mov dx, 0x0101
    jmp f_g2ib
f_g2evib:
    call dis_vsize
    mov dh, 1
f_g2ib:
    call dis_modrm
    call dis_group
    call dis_mnem
    call dis_rmop
    call dis_comma
    call dis_ib
    call dis_hex
    jmp dis_done
f_g2eb1:
    mov dx, 0x0101
    jmp f_g21
f_g2ev1:
    call dis_vsize
    mov dh, 1
f_g21:
    call dis_modrm
    call dis_group
    call dis_mnem
    call dis_rmop
    call dis_comma
    mov al, '1'
    stosb
    jmp dis_done
f_g2ebcl:
    mov dx, 0x0101
    jmp f_g2cl
f_g2evcl:
    call dis_vsize
    mov dh, 1
f_g2cl:
    call dis_modrm
    call dis_group
    call dis_mnem
    call dis_rmop
    call dis_comma
    mov ax, 'cl'
    stosw
    jmp dis_done
f_g3eb:
    mov dx, 0x0101
    jmp f_g3
f_g3ev:
    call dis_vsize
    mov dh, 1
f_g3:
    call dis_modrm
    call dis_group
    call dis_mnem
    call dis_rmop
    cmp byte [dis_reg], 1
    ja dis_done                 ; test has an immediate
    call dis_comma
    cmp dl, 1
    je .b
    call dis_iv
    call dis_hex
    jmp dis_done
.b: call dis_ib
    call dis_hex
    jmp dis_done
f_g4:
    call dis_modrm
    call dis_group
    jc dis_one.bad
    call dis_mnem
    mov dx, 0x0101
    call dis_rmop
    jmp dis_done
f_g5:
    call dis_modrm
    call dis_group
    jc dis_one.bad
    call dis_mnem
    call dis_vsize
    mov dh, 1
    mov cl, [dis_reg]
    cmp cl, 2                   ; call/jmp: the size goes without saying
    je .ns
    cmp cl, 4
    je .ns
    cmp cl, 3
    je .far
    cmp cl, 5
    jne .op
.far:
    cmp byte [dis_mod], 3
    je dis_one.bad
.ns:
    xor dh, dh
.op:
    call dis_rmop
    jmp dis_done
f_ev:                           ; pop Ev (8F /0), nop Ev (0F 1F)
    cmp byte [dis_op], 0x1F
    je .nop
    call dis_modrm
    call dis_group
    jc dis_one.bad
    jmp .mn
.nop:
    call dis_modrm
.mn:
    call dis_mnem
    call dis_vsize
    mov dh, 1
    call dis_rmop
    jmp dis_done
f_eb:                           ; setcc
    call dis_mnem
    call dis_modrm
    mov dx, 0x0101
    call dis_rmop
    jmp dis_done
f_evsw:
    call dis_mnem
    call dis_modrm
    mov dx, 2                   ; a register destination: 16 bits as well
    cmp byte [dis_mod], 3
    jne .m
    call dis_vsize
.m: call dis_rmop
    call dis_comma
    call dis_sregop
    jmp dis_done
f_swew:
    call dis_mnem
    call dis_modrm
    call dis_sregop
    call dis_comma
    mov dx, 2
    cmp byte [dis_mod], 3
    jne .m
    call dis_vsize
.m: call dis_rmop
    jmp dis_done
dis_sregop:
    movzx eax, byte [dis_reg]
    cmp al, 5
    ja dis_one.bad
    push esi
    lea esi, [dis_sreg+eax*2]
    movsw
    pop esi
    ret
f_seg:                          ; al = segment | 4 push/pop... see the tables
    ; one-byte map: al = seg (0-3) or seg + 4 for pop; 0F map: 8|seg (|16 pop)
    mov cl, al
    mov al, M_push
    test cl, 8
    jnz .two
    test cl, 4
    jz .m
    mov al, M_pop
    and cl, 3
    jmp .m
.two:
    test cl, 16
    jz .t
    mov al, M_pop
.t: and cl, 7
.m: call dis_mnem
    movzx eax, cl
    push esi
    lea esi, [dis_sreg+eax*2]
    movsw
    pop esi
    jmp dis_done

dis_moffs:                      ; [seg:moffs32]
    mov byte [dis_base], 8
    mov byte [dis_index], 8
    lodsd
    mov [dis_disp], eax
    jmp dis_memop
f_alob:
    call dis_mnem
    mov ax, 'al'
    stosw
    call dis_comma
    call dis_moffs
    jmp dis_done
f_eaxov:
    call dis_mnem
    call dis_vsize
    xor eax, eax
    call dis_regname
    call dis_comma
    call dis_moffs
    jmp dis_done
f_obal:
    call dis_mnem
    call dis_moffs
    call dis_comma
    mov ax, 'al'
    stosw
    jmp dis_done
f_oveax:
    call dis_mnem
    call dis_moffs
    call dis_comma
    call dis_vsize
    xor eax, eax
    call dis_regname
    jmp dis_done
f_gveviv:
    call dis_mnem
    call dis_modrm
    call dis_vsize
    xor dh, dh
    call dis_regop
    call dis_comma
    call dis_rmop
    call dis_comma
    call dis_iv
    call dis_hex
    jmp dis_done
f_gvevib:
    call dis_mnem
    call dis_modrm
    call dis_vsize
    xor dh, dh
    call dis_regop
    call dis_comma
    call dis_rmop
    call dis_comma
    call dis_ibs
    call dis_simm
    jmp dis_done
f_evgvib:
    call dis_mnem
    call dis_modrm
    call dis_vsize
    xor dh, dh
    call dis_rmop
    call dis_comma
    call dis_regop
    call dis_comma
    call dis_ib
    call dis_hex
    jmp dis_done
f_evgvcl:
    call dis_mnem
    call dis_modrm
    call dis_vsize
    xor dh, dh
    call dis_rmop
    call dis_comma
    call dis_regop
    call dis_comma
    mov ax, 'cl'
    stosw
    jmp dis_done
f_g8evib:
    call dis_modrm
    call dis_group
    jc dis_one.bad
    call dis_mnem
    call dis_vsize
    mov dh, 1
    call dis_rmop
    call dis_comma
    call dis_ib
    call dis_hex
    jmp dis_done

dis_acc:                        ; al or eax/ax by the opcode's low bit
    test byte [dis_op], 1
    jnz .v
    mov ax, 'al'
    stosw
    ret
.v: call dis_vsize
    xor eax, eax
    jmp dis_regname
f_inai:
    call dis_mnem
    call dis_acc
    call dis_comma
    call dis_ib
    call dis_hex
    jmp dis_done
f_outia:
    call dis_mnem
    call dis_ib
    call dis_hex
    call dis_comma
    call dis_acc
    jmp dis_done
f_inad:
    call dis_mnem
    call dis_acc
    call dis_comma
    mov ax, 'dx'
    stosw
    jmp dis_done
f_outda:
    call dis_mnem
    mov ax, 'dx'
    stosw
    call dis_comma
    call dis_acc
    jmp dis_done
f_ap:                           ; far pointer: selector:offset
    call dis_mnem
    call dis_iv
    mov edx, eax
    call dis_iw
    call dis_hex
    mov al, ':'
    stosb
    mov eax, edx
    call dis_hex
    jmp dis_done
f_sb:                           ; movsb ...
    call dis_mnem
    dec edi
    mov al, 'b'
    stosb
    jmp dis_done
f_sv:                           ; movsd / movsw ...
    call dis_mnem
    dec edi
    mov al, 'd'
    cmp byte [dis_opsz], 0
    je .d
    mov al, 'w'
.d: stosb
    jmp dis_done

f_x87:
    call dis_modrm
    movzx ecx, byte [dis_op]
    sub ecx, 0xD8               ; 0..7
    cmp byte [dis_mod], 3
    je .reg
    lea eax, [ecx*8]
    movzx edx, byte [dis_reg]
    add eax, edx
    mov dl, [dis_fpu_mem+eax*2+1]
    mov al, [dis_fpu_mem+eax*2]
    cmp al, M_bad
    je dis_one.bad
    call dis_mnem
    mov dh, dl
    test dl, dl
    jz .nosz
    call dis_sizekw
.nosz:
    call dis_memop
    jmp dis_done
.reg:
    movzx edx, byte [dis_reg]
    movzx ebx, byte [dis_rm]
    cmp ecx, 0
    je .arith                   ; D8: op st0,st(i)
    cmp ecx, 4
    je .arithr                  ; DC: op st(i),st0
    cmp ecx, 6
    je .arithp
    cmp ecx, 1
    je .d9
    cmp ecx, 3
    je .db
    cmp ecx, 5
    je .dd
    cmp ecx, 7
    je .df
    jmp dis_one.bad
.arith:
    mov al, [dis_fpu_arith+edx]
    call dis_mnem
    call dis_st0
    call dis_comma
    call dis_sti
    jmp dis_done
.arithr:
    cmp edx, 2
    je .arith                   ; fcom/fcomp alias
    cmp edx, 3
    je .arith
    cmp edx, 4                  ; DC E0+ is fsubr, E8+ fsub, F0+ fdivr, F8+ fdiv
    jb .ar0
    xor edx, 1
.ar0:
    mov al, [dis_fpu_arith+edx]
    call dis_mnem
    call dis_sti
    call dis_comma
    call dis_st0
    jmp dis_done
.arithp:
    cmp edx, 3
    jne .ap
    cmp ebx, 1
    jne dis_one.bad
    mov al, M_fcompp
    jmp .bare
.ap:
    mov al, [dis_fpu_arithp+edx]
    cmp al, M_bad
    je dis_one.bad
    call dis_mnem
    call dis_sti
    call dis_comma
    call dis_st0
    jmp dis_done
.d9:
    cmp edx, 0
    je .fld
    cmp edx, 1
    je .fxch
    cmp edx, 2
    jne .d9t
    cmp ebx, 0
    jne dis_one.bad
    mov al, M_fnop
    jmp .bare
.d9t:
    cmp edx, 4
    jb dis_one.bad
    lea eax, [edx*8-32]
    add eax, ebx
    mov al, [dis_fpu_d9+eax]
    cmp al, M_bad
    je dis_one.bad
.bare:
    call dis_mnem
    jmp dis_done
.fld:
    mov al, M_fld
    jmp .one
.fxch:
    mov al, M_fxch
.one:
    call dis_mnem
    call dis_sti
    jmp dis_done
.db:
    cmp edx, 4
    jne dis_one.bad
    mov al, M_fnclex
    cmp ebx, 2
    je .bare
    mov al, M_fninit
    cmp ebx, 3
    je .bare
    jmp dis_one.bad
.dd:
    mov al, M_ffree
    cmp edx, 0
    je .one
    mov al, M_fst
    cmp edx, 2
    je .one
    mov al, M_fstp
    cmp edx, 3
    je .one
    mov al, M_fucom
    cmp edx, 4
    je .one
    mov al, M_fucomp
    cmp edx, 5
    je .one
    jmp dis_one.bad
.df:
    cmp edx, 4
    jne dis_one.bad
    cmp ebx, 0
    jne dis_one.bad
    mov al, M_fnstsw
    call dis_mnem
    mov ax, 'ax'
    stosw
    jmp dis_done

dis_st0:
    mov eax, 'st0'
    stosw
    shr eax, 16
    stosb
    ret
dis_sti:                        ; st(i) from dis_rm -> "st1" ...
    mov ax, 'st'
    stosw
    mov al, [dis_rm]
    add al, '0'
    stosb
    ret

dis_segpfx db 0x26, 0x2E, 0x36, 0x3E, 0x64, 0x65   ; es cs ss ds fs gs
dis_s_lock db 'lock ', 0
dis_s_rep db 'rep ', 0
dis_s_repne db 'repne ', 0
dis_s_repe db 'repe ', 0
dis_s_db db 'db ', 0
dis_s_byte db 'byte ', 0
dis_s_word db 'word ', 0
dis_s_dword db 'dword ', 0
dis_s_qword db 'qword ', 0
dis_s_tword db 'tword ', 0
