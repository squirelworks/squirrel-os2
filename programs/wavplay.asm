; wavplay — play a WAV file (A.6, 3.0 OS2-NET-AUDIO)
; Original code.  run wavplay <file.wav>
; Plays 8- or 16-bit PCM, mono or stereo, at 8000, 11025, 16000, 22050,
; 24000, 32000, 44100 or 48000 Hz on the sound device (SYS_AUDIO). Prints
;   wavplay: 22050 Hz, 16-bit, mono, 0.50 s
;   wavplay: played 11025 frames
; See documentation/apps/audio.md.
%include "sqx.inc"
SQX_HEADER main
%include "audio.inc"

BLOCK       equ 4096

main:
    mov esi, [esp+4]
.sp:
    cmp byte [esi], ' '
    jne .n
    inc esi
    jmp .sp
.n:
    cmp byte [esi], 0
    je usage
    mov edi, esi                    ; cut the name at a space
.c:
    cmp byte [edi], ' '
    jbe .cut
    inc edi
    jmp .c
.cut:
    mov byte [edi], 0
    mov eax, SYS_OPEN
    mov ebx, esi
    xor ecx, ecx
    int 0x80
    cmp eax, -1
    je .noopen
    mov [fd], eax
    mov ebx, eax
    call wav_read_header
    jc .notwav
    call describe
    mov eax, [wav_ch]               ; bytes in one frame
    imul eax, [wav_bits]
    shr eax, 3
    test eax, eax
    jz .notwav
    mov [fsize], eax
    mov eax, SYS_AUDIO
    mov ebx, AU_OPEN
    mov ecx, [wav_rate]
    mov edx, [wav_bits]
    shl edx, 8
    or edx, [wav_ch]
    int 0x80
    test eax, eax
    jz .play
    mov ebx, m_nodev
    cmp eax, -2
    jne .fail
    mov ebx, m_busy
    jmp .fail
.play:
    mov eax, [wav_bytes]
    mov [left], eax
.blk:
    mov edx, [left]
    test edx, edx
    jz .drain
    cmp edx, BLOCK
    jbe .rd
    mov edx, BLOCK
.rd:
    mov eax, SYS_READ
    mov ebx, [fd]
    mov ecx, buf
    int 0x80
    test eax, eax
    jle .drain                      ; a short file: play what there was
    sub [left], eax
    mov edx, eax
    mov eax, SYS_AUDIO
    mov ebx, AU_WRITE
    mov ecx, buf
    int 0x80
    cmp eax, -1
    je .stall
    add [played], eax
    jmp .blk
.drain:
    mov eax, SYS_AUDIO
    mov ebx, AU_DRAIN
    int 0x80
    push eax
    mov eax, SYS_AUDIO
    mov ebx, AU_CLOSE
    int 0x80
    pop eax
    test eax, eax
    jnz .stall2
    mov eax, SYS_CLOSE
    mov ebx, [fd]
    int 0x80
    mov edi, line                   ; played N frames
    mov esi, m_played
    call cat
    mov eax, [played]
    xor edx, edx
    div dword [fsize]
    call utoa
    mov esi, m_frames
    call cat
    mov eax, SYS_PUTS
    mov ebx, line
    int 0x80
    xor eax, eax
    ret
.stall:
    mov eax, SYS_AUDIO
    mov ebx, AU_CLOSE
    int 0x80
.stall2:
    mov ebx, m_stall
    jmp .fail
.noopen:
    mov ebx, m_noopen
    jmp .fail
.notwav:
    mov ebx, m_notwav
.fail:
    mov eax, SYS_PUTS
    int 0x80
    mov eax, 1
    ret
usage:
    mov ebx, m_usage
    mov eax, SYS_PUTS
    int 0x80
    mov eax, 1
    ret

; wavplay: 22050 Hz, 16-bit, mono, 0.50 s
describe:
    mov edi, line
    mov esi, m_head
    call cat
    mov eax, [wav_rate]
    call utoa
    mov esi, m_hz
    call cat
    mov eax, [wav_bits]
    call utoa
    mov esi, m_bit
    call cat
    mov esi, m_mono
    cmp dword [wav_ch], 1
    je .ch
    mov esi, m_stereo
.ch:
    call cat
    ; seconds with two decimals: bytes * 100 / (rate * frame bytes)
    mov eax, [wav_ch]
    imul eax, [wav_bits]
    shr eax, 3
    imul eax, [wav_rate]
    mov ecx, eax
    test ecx, ecx
    jz .nl
    mov eax, [wav_bytes]
    mov ebx, 100
    mul ebx
    div ecx
    xor edx, edx
    mov ebx, 100
    div ebx
    push edx
    call utoa
    mov byte [edi], '.'
    inc edi
    pop eax
    cmp eax, 10
    jae .two
    mov byte [edi], '0'
    inc edi
.two:
    call utoa
    mov esi, m_s
    call cat
.nl:
    mov word [edi], 10
    mov eax, SYS_PUTS
    mov ebx, line
    int 0x80
    ret

; esi = ASCIIZ -> copied to edi (edi at its end)
cat:
    lodsb
    test al, al
    jz .r
    stosb
    jmp cat
.r:
    mov byte [edi], 0
    ret

; eax -> decimal at edi (edi at its end)
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

m_usage     db 'Usage: run wavplay <file.wav>', 10, 0
m_noopen    db 'wavplay: cannot open the file', 10, 0
m_notwav    db 'wavplay: not an 8- or 16-bit PCM WAV file', 10, 0
m_nodev     db 'wavplay: no sound device, or that format is not played', 10, 0
m_busy      db 'wavplay: another program has the sound device', 10, 0
m_stall     db 'wavplay: the sound device stopped', 10, 0
m_head      db 'wavplay: ', 0
m_hz        db ' Hz, ', 0
m_bit       db '-bit, ', 0
m_mono      db 'mono, ', 0
m_stereo    db 'stereo, ', 0
m_s         db ' s', 0
m_played    db 'wavplay: played ', 0
m_frames    db ' frames', 10, 0

SQX_BSS
fd          resd 1
fsize       resd 1
left        resd 1
played      resd 1
line        resb 96
WAV_BSS
alignb 4
buf         resb BLOCK
SQX_END
