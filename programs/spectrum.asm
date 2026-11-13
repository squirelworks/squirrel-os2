; spectrum — spectrum analyser (A.6, 3.0 OS2-NET-AUDIO)
; Original code.
;   run spectrum <file.wav>         play the file and show its spectrum
;   run spectrum live               show the spectrum of the sound input
;   run spectrum <file.wav> test    print the strongest frequency of the
;                                   file's first FFT_N frames (no graphics, no sound)
; Each block of FFT_N frames (mixed to mono) gets a Hann window and a
; radix-2 FFT (x87, doubles); the window shows 64 bars (the magnitude in
; decibels over 8 bins each, 0 to 90 dB) and the strongest frequency,
; found from the peak bin and its neighbours (a parabola through the
; three). Esc stops. See documentation/apps/audio.md.
%include "sqx.inc"
SQX_HEADER main
%include "gui.inc"
%include "audio.inc"

FFT_N       equ 1024
FFT_LOG     equ 10
NBARS       equ 64
BIN_PER_BAR equ FFT_N / 2 / NBARS
WIN_W       equ 300
WIN_H       equ 156
WIN_X       equ (SCR_W - WIN_W) / 2
WIN_Y       equ (SCR_H - WIN_H) / 2
PLOT_X      equ WIN_X + 22
PLOT_Y      equ WIN_Y + WIN_TITLE_H + 16
PLOT_H      equ 100
BAR_W       equ 4
LIVE_RATE   equ 22050

main:
    finit
    mov esi, [esp+4]
    call skipsp
    cmp byte [esi], 0
    je usage
    mov edi, w_live
    call word_is
    je live
    mov [name], esi
.c:
    cmp byte [esi], ' '
    jbe .cut
    inc esi
    jmp .c
.cut:
    cmp byte [esi], 0
    je .open
    mov byte [esi], 0
    inc esi
    call skipsp
    mov edi, w_test
    call word_is
    jne .open
    mov byte [testmode], 1
.open:
    mov eax, SYS_OPEN
    mov ebx, [name]
    xor ecx, ecx
    int 0x80
    cmp eax, -1
    je .noopen
    mov [fd], eax
    mov ebx, eax
    call wav_read_header
    jc .notwav
    mov eax, [wav_ch]
    imul eax, [wav_bits]
    shr eax, 3
    mov [fsize], eax
    imul eax, FFT_N
    mov [blkbytes], eax             ; a block of the file
    mov eax, [wav_rate]
    mov [rate], eax
    cmp byte [testmode], 0
    jne test
    ; play it, a block at a time, drawing each block's spectrum
    mov byte [playing], 0
    mov eax, SYS_AUDIO
    mov ebx, AU_OPEN
    mov ecx, [wav_rate]
    mov edx, [wav_bits]
    shl edx, 8
    or edx, [wav_ch]
    int 0x80
    test eax, eax
    jnz .silent                     ; no device: show it without sound
    mov byte [playing], 1
.silent:
    call gui_open
    jc .nogfx
    mov eax, [wav_bytes]
    mov [left], eax
.blk:
    mov edx, [left]
    cmp edx, [blkbytes]
    jb .end                         ; the last part block is not shown
    mov edx, [blkbytes]
    mov eax, SYS_READ
    mov ebx, [fd]
    mov ecx, buf
    int 0x80
    cmp eax, edx
    jne .end
    sub [left], eax
    call load_block
    call analyse
    call draw
    cmp byte [playing], 0
    je .wait
    mov eax, SYS_AUDIO              ; the write paces the drawing
    mov ebx, AU_WRITE
    mov ecx, buf
    mov edx, [blkbytes]
    int 0x80
    jmp .key
.wait:
    mov ecx, 5
    call gui_waitkey
    jmp .k2
.key:
    call gui_pollkey
.k2:
    shr eax, 8
    cmp al, K_ESC
    je .stop
    jmp .blk
.end:
    cmp byte [playing], 0
    je .hold
    mov eax, SYS_AUDIO
    mov ebx, AU_DRAIN
    int 0x80
.hold:
    mov ecx, 300                    ; the last picture stays a moment
    call gui_waitkey
.stop:
    cmp byte [playing], 0
    je .close
    mov eax, SYS_AUDIO
    mov ebx, AU_CLOSE
    int 0x80
.close:
    call gui_close
    xor eax, eax
    ret
.noopen:
    mov ebx, m_noopen
    jmp fail
.notwav:
    mov ebx, m_notwav
    jmp fail
.nogfx:
    mov ebx, m_nogfx
    jmp fail
usage:
    mov ebx, m_usage
fail:
    mov eax, SYS_PUTS
    int 0x80
    mov eax, 1
    ret

; test: the first block's strongest frequency, as text
test:
    mov edx, [blkbytes]
    cmp edx, [wav_bytes]
    ja .short
    mov eax, SYS_READ
    mov ebx, [fd]
    mov ecx, buf
    int 0x80
    cmp eax, edx
    jne .short
    call load_block
    call analyse
    mov edi, line
    mov esi, m_tpeak
    call cat
    mov eax, [peakhz]
    call utoa
    mov esi, m_thz
    call cat
    mov eax, [peakdb]
    call utoa
    mov esi, m_tdb
    call cat
    mov eax, SYS_PUTS
    mov ebx, line
    int 0x80
    xor eax, eax
    ret
.short:
    mov ebx, m_short
    jmp fail

; live: record blocks from the input and show them
live:
    mov dword [rate], LIVE_RATE
    mov eax, SYS_AUDIO
    mov ebx, AU_OPEN
    mov ecx, LIVE_RATE
    mov edx, 2 | (16 << 8)
    int 0x80
    test eax, eax
    jnz .nodev
    mov dword [wav_ch], 2
    mov dword [wav_bits], 16
    mov dword [fsize], 4
    mov dword [blkbytes], FFT_N * 4
    mov byte [live_on], 1
    call gui_open
    jc .nogfx
.l:
    mov eax, SYS_AUDIO
    mov ebx, AU_RECORD
    mov ecx, buf
    mov edx, FFT_N * 4
    int 0x80
    cmp eax, FFT_N * 4
    jne .stop
    call load_block
    call analyse
    call draw
    call gui_pollkey
    shr eax, 8
    cmp al, K_ESC
    jne .l
.stop:
    call gui_close
    mov eax, SYS_AUDIO
    mov ebx, AU_CLOSE
    int 0x80
    xor eax, eax
    ret
.nodev:
    mov ebx, m_nodev
    jmp fail
.nogfx:
    mov ebx, m_nogfx
    jmp fail

; buf (FFT_N frames in the file's format) -> re[] (mono, -1..1, Hann
; window), im[] = 0
load_block:
    pushad
    mov esi, buf
    xor ecx, ecx
.f:
    ; one channel's sample as a double, or the mean of two
    call sample                     ; st0 = first channel
    cmp dword [wav_ch], 1
    je .mono
    call sample
    faddp st1, st0
    fmul qword [half]
.mono:
    ; Hann: 0.5 - 0.5 cos(2 pi n / (N - 1))
    mov [tmp], ecx
    fild dword [tmp]
    fmul qword [twopi_n1]
    fcos
    fmul qword [half]
    fsubr qword [half]
    fmulp st1, st0
    fstp qword [re + ecx * 8]
    fldz
    fstp qword [im + ecx * 8]
    inc ecx
    cmp ecx, FFT_N
    jb .f
    popad
    ret

; esi -> st0 = the sample at esi as -1..1, esi moves past it
sample:
    cmp dword [wav_bits], 8
    je .b8
    movsx eax, word [esi]
    add esi, 2
    mov [tmp], eax
    fild dword [tmp]
    fmul qword [inv32k]
    ret
.b8:
    movzx eax, byte [esi]
    inc esi
    sub eax, 128
    mov [tmp], eax
    fild dword [tmp]
    fmul qword [inv128]
    ret

; FFT of re/im in place, then mag[k] (k < N/2) in dB, the bars, the peak
analyse:
    pushad
    call fft
    ; magnitudes: 20 log10(|X| * 2 / (N / 2)) + 90, at least 0
    xor ecx, ecx
.m:
    fld qword [re + ecx * 8]
    fmul st0, st0
    fld qword [im + ecx * 8]
    fmul st0, st0
    faddp st1, st0
    fsqrt
    fmul qword [magscale]
    fadd qword [tiny]
    fld qword [db20log2]            ; 20 log10(x) = (20 log10 2) log2(x)
    fxch st1
    fyl2x
    fadd qword [dbfloor]
    fldz
    fcomip st0, st1
    jb .pos
    fstp st0
    fldz
.pos:
    fstp qword [mag + ecx * 8]
    inc ecx
    cmp ecx, FFT_N / 2
    jb .m
    ; bars: the loudest bin of each group, in pixels (90 dB = PLOT_H)
    xor ebx, ebx
.bar:
    fldz
    mov ecx, ebx
    imul ecx, BIN_PER_BAR
    mov edx, BIN_PER_BAR
.bb:
    fld qword [mag + ecx * 8]
    fcomi st0, st1
    jbe .smaller
    fxch st1
.smaller:
    fstp st0
    inc ecx
    dec edx
    jnz .bb
    fmul qword [px_per_db]
    fistp dword [bars + ebx * 4]
    cmp dword [bars + ebx * 4], PLOT_H
    jle .bok
    mov dword [bars + ebx * 4], PLOT_H
.bok:
    inc ebx
    cmp ebx, NBARS
    jb .bar
    ; the peak bin, from 2 up (0 and 1 hold the DC part)
    mov ebx, 2
    mov ecx, 3
.pk:
    fld qword [mag + ecx * 8]
    fld qword [mag + ebx * 8]
    fcomip st0, st1
    fstp st0
    jae .pn
    mov ebx, ecx
.pn:
    inc ecx
    cmp ecx, FFT_N / 2 - 1
    jb .pk
    mov [peakbin], ebx
    mov eax, ebx
    shr eax, 3                      ; / BIN_PER_BAR
    mov [peakbar], eax
    fld qword [mag + ebx * 8]
    fistp dword [peakdb]
    ; a parabola through bins k-1, k, k+1 (in dB):
    ; delta = (a - c) / (2 (a - 2b + c)), f = (k + delta) * rate / N
    fld qword [mag + ebx * 8 - 8]   ; a
    fld qword [mag + ebx * 8 + 8]   ; c a
    fld st1                         ; a c a
    fsub st0, st1                   ; a-c, c, a
    fld qword [mag + ebx * 8]       ; b, a-c, c, a
    fadd st0, st0                   ; 2b
    fsubr st0, st3                  ; a - 2b
    faddp st2, st0                  ; a-c, a-2b+c, a
    fxch st1                        ; a-2b+c, a-c, a
    fadd st0, st0                   ; 2(a-2b+c)
    ftst
    fnstsw ax
    sahf
    jne .div
    fstp st0
    fstp st0
    fldz
    jmp .delta
.div:
    fdivp st1, st0                  ; delta, a
.delta:
    fstp st1                        ; delta
    mov [tmp], ebx
    fiadd dword [tmp]
    fimul dword [rate]
    mov dword [tmp], FFT_N
    fidiv dword [tmp]
    fistp dword [peakhz]
    popad
    ret

; In-place radix-2 FFT of re/im (FFT_N points), decimation in time
fft:
    pushad
    ; bit-reversed order
    xor ebx, ebx                    ; j
    xor ecx, ecx                    ; i
.br:
    cmp ecx, ebx
    jae .nos
    fld qword [re + ecx * 8]
    fld qword [re + ebx * 8]
    fstp qword [re + ecx * 8]
    fstp qword [re + ebx * 8]
    fld qword [im + ecx * 8]
    fld qword [im + ebx * 8]
    fstp qword [im + ecx * 8]
    fstp qword [im + ebx * 8]
.nos:
    mov edx, FFT_N / 2
.bit:
    test ebx, edx
    jz .set
    xor ebx, edx
    shr edx, 1
    jnz .bit
.set:
    or ebx, edx
    inc ecx
    cmp ecx, FFT_N
    jb .br
    ; butterflies: len = 2, 4, ... N; half = len / 2
    mov dword [half_len], 1
.stage:
    mov eax, [half_len]
    cmp eax, FFT_N
    jae .done
    ; step angle = -pi / half
    fldpi
    fchs
    fidiv dword [half_len]
    fstp qword [ang]
    xor esi, esi                    ; k: the twiddle index
.k:
    mov [tmp], esi
    fild dword [tmp]
    fmul qword [ang]
    fsincos                         ; cos, sin
    fstp qword [wr]
    fstp qword [wi]
    mov edi, esi                    ; i = k, k + len, ...
.i:
    mov edx, edi
    add edx, [half_len]             ; the partner
    ; t = w * x[partner]
    fld qword [re + edx * 8]
    fmul qword [wr]
    fld qword [im + edx * 8]
    fmul qword [wi]
    fsubp st1, st0                  ; tr
    fld qword [re + edx * 8]
    fmul qword [wi]
    fld qword [im + edx * 8]
    fmul qword [wr]
    faddp st1, st0                  ; ti, tr
    ; x[partner] = x[i] - t, x[i] = x[i] + t
    fld qword [re + edi * 8]        ; ur, ti, tr
    fld st0
    fsub st0, st3
    fstp qword [re + edx * 8]
    faddp st2, st0                  ; ti, ur+tr
    fld qword [im + edi * 8]        ; ui, ti, ur+tr
    fld st0
    fsub st0, st2
    fstp qword [im + edx * 8]
    faddp st1, st0                  ; ui+ti, ur+tr
    fstp qword [im + edi * 8]
    fstp qword [re + edi * 8]
    mov eax, [half_len]
    shl eax, 1
    add edi, eax
    cmp edi, FFT_N
    jb .i
    inc esi
    cmp esi, [half_len]
    jb .k
    shl dword [half_len], 1
    jmp .stage
.done:
    popad
    ret

draw:
    pushad
    mov al, C_CYAN
    call gui_clear
    mov eax, WIN_X
    mov ebx, WIN_Y
    mov ecx, WIN_W
    mov edx, WIN_H
    mov esi, t_title
    cmp byte [live_on], 0
    je .t
    mov esi, t_live
.t:
    call gui_window
    ; the plot: black, with the bars in green
    mov eax, PLOT_X
    mov ebx, PLOT_Y
    mov ecx, NBARS * BAR_W
    mov edx, PLOT_H
    mov byte [gui_ink], C_BLACK
    call gui_fill
    xor ebp, ebp
.bar:
    mov edx, [bars + ebp * 4]
    test edx, edx
    jle .nb
    mov eax, ebp
    imul eax, BAR_W
    add eax, PLOT_X
    mov ebx, PLOT_Y + PLOT_H
    sub ebx, edx
    mov ecx, BAR_W - 1
    mov byte [gui_ink], C_LGREEN
    cmp ebp, [peakbar]
    jne .f
    mov byte [gui_ink], C_YELLOW
.f:
    call gui_fill
.nb:
    inc ebp
    cmp ebp, NBARS
    jb .bar
    ; scale: 0 Hz and rate/2 under the plot, dB at the side
    mov byte [gui_ink], C_BLACK
    mov byte [gui_bg], C_LGREY
    mov eax, PLOT_X
    mov ebx, PLOT_Y + PLOT_H + 3
    mov esi, m_0
    call gui_text
    mov edi, line
    mov eax, [rate]
    shr eax, 1
    call utoa
    mov esi, m_hz
    call cat
    mov esi, line
    call gui_textw
    neg eax
    add eax, PLOT_X + NBARS * BAR_W
    mov ebx, PLOT_Y + PLOT_H + 3
    call gui_text
    mov eax, WIN_X + 4
    mov ebx, PLOT_Y
    mov esi, m_90
    call gui_text
    mov ebx, PLOT_Y + PLOT_H - CELL_H
    mov esi, m_0
    call gui_text
    ; Peak 1000 Hz
    mov edi, line
    mov esi, m_peak
    call cat
    mov eax, [peakhz]
    call utoa
    mov esi, m_hz
    call cat
    mov eax, PLOT_X
    mov ebx, PLOT_Y + PLOT_H + 3 + CELL_H + 4
    mov esi, line
    call gui_text
    call gui_flip
    popad
    ret

; ---------- small helpers ----------

word_is:
    push esi
.l:
    mov al, [edi]
    test al, al
    jz .end
    cmp al, [esi]
    jne .no
    inc esi
    inc edi
    jmp .l
.end:
    mov al, [esi]
    cmp al, ' '
    ja .no
    call skipsp
    add esp, 4
    xor eax, eax
    ret
.no:
    pop esi
    or eax, 1
    ret

skipsp:
    cmp byte [esi], ' '
    jne .r
    inc esi
    jmp skipsp
.r:
    ret

cat:
    lodsb
    test al, al
    jz .r
    stosb
    jmp cat
.r:
    mov byte [edi], 0
    ret

utoa:
    push eax
    push ebx
    push ecx
    push edx
    mov ebx, 10
    xor ecx, ecx
.d:
    xor edx, edx
    div ebx
    push edx
    inc ecx
    test eax, eax
    jnz .d
.o:
    pop eax
    add al, '0'
    stosb
    loop .o
    mov byte [edi], 0
    pop edx
    pop ecx
    pop ebx
    pop eax
    ret

align 8
half        dq 0.5
inv32k      dq 3.0517578125e-05     ; 1 / 32768
inv128      dq 0.0078125            ; 1 / 128
twopi_n1    dq 6.141921540915112e-03 ; 2 pi / (FFT_N - 1)
magscale    dq 3.90625e-03          ; 2 / (FFT_N / 2): a full-scale sine -> 1 (Hann halves it)
tiny        dq 1.0e-12
db20log2    dq 6.020599913279624    ; 20 log10 2
dbfloor     dq 90.0
px_per_db   dq 1.1111111111111112   ; PLOT_H / 90
t_title     db 'Spectrum Analyser', 0
t_live      db 'Spectrum Analyser - input', 0
w_live      db 'live', 0
w_test      db 'test', 0
m_0         db '0', 0
m_90        db '90', 0
m_hz        db ' Hz', 0
m_peak      db 'Peak ', 0
m_tpeak     db 'spectrum: peak ', 0
m_thz       db ' Hz, ', 0
m_tdb       db ' dB', 10, 0
m_usage     db 'Usage: run spectrum <file.wav> [test] | run spectrum live', 10, 0
m_noopen    db 'spectrum: cannot open the file', 10, 0
m_notwav    db 'spectrum: not an 8- or 16-bit PCM WAV file', 10, 0
m_short     db 'spectrum: the file is shorter than one block', 10, 0
m_nodev     db 'spectrum: no sound device', 10, 0
m_nogfx     db 'spectrum: no graphics', 10, 0

SQX_BSS
name        resd 1
fd          resd 1
fsize       resd 1
blkbytes    resd 1
left        resd 1
rate        resd 1
tmp         resd 1
half_len    resd 1
peakbin     resd 1
peakbar     resd 1
peakhz      resd 1
peakdb      resd 1
testmode    resb 1
playing     resb 1
live_on     resb 1
line        resb 64
WAV_BSS
alignb 8
ang         resq 1
wr          resq 1
wi          resq 1
re          resq FFT_N
im          resq FFT_N
mag         resq FFT_N / 2
bars        resd NBARS
buf         resb FFT_N * 4
GUI_BSS
SQX_END
