; sndrec — sound recorder (A.6, 3.0 OS2-NET-AUDIO)
; Original code.  run sndrec <file.wav> [seconds]
; Records from the sound device's input (SYS_AUDIO AU_RECORD) at 22050 Hz,
; 16-bit stereo, for 1 to 10 seconds (2 by default), and saves a WAV
; file. Prints
;   sndrec: 2.00 s, 176400 bytes, peak 0 -> rec.wav
; where peak is the loudest sample (0..32768). See documentation/apps/audio.md.
%include "sqx.inc"
SQX_HEADER main
%include "audio.inc"

RATE        equ 22050
FRAME       equ 4                   ; 16-bit stereo

main:
    mov esi, [esp+4]
    call skipsp
    cmp byte [esi], 0
    je usage
    mov [name], esi
.c:
    cmp byte [esi], ' '
    jbe .cut
    inc esi
    jmp .c
.cut:
    mov dword [secs], 2
    cmp byte [esi], 0
    je .go
    mov byte [esi], 0
    inc esi
    call skipsp
    cmp byte [esi], 0
    je .go
    xor eax, eax
.d:
    movzx edx, byte [esi]
    sub edx, '0'
    cmp edx, 9
    ja .dend
    imul eax, eax, 10
    add eax, edx
    inc esi
    jmp .d
.dend:
    cmp eax, 1
    jb usage
    cmp eax, 10
    ja usage
    mov [secs], eax
.go:
    mov eax, [secs]
    imul eax, RATE * FRAME
    mov [bytes], eax
    mov eax, SYS_SBRK               ; room for it all, and the header
    mov ebx, [bytes]
    add ebx, 44
    int 0x80
    cmp eax, -1
    je .nomem
    mov [mem], eax
    mov eax, SYS_AUDIO
    mov ebx, AU_OPEN
    mov ecx, RATE
    mov edx, 2 | (16 << 8)
    int 0x80
    test eax, eax
    jnz .nodev
    mov eax, SYS_AUDIO
    mov ebx, AU_RECORD
    mov ecx, [mem]
    add ecx, 44
    mov edx, [bytes]
    int 0x80
    push eax
    mov eax, SYS_AUDIO
    mov ebx, AU_CLOSE
    int 0x80
    pop eax
    cmp eax, -1
    je .norec
    mov [got], eax
    ; the loudest sample
    mov esi, [mem]
    add esi, 44
    mov ecx, eax
    shr ecx, 1
    xor edx, edx
.pk:
    movsx eax, word [esi]
    add esi, 2
    test eax, eax
    jns .abs
    neg eax
.abs:
    cmp eax, edx
    jbe .pn
    mov edx, eax
.pn:
    loop .pk
    mov [peak], edx
    ; header and file
    mov dword [wav_rate], RATE
    mov dword [wav_ch], 2
    mov dword [wav_bits], 16
    mov eax, [got]
    mov [wav_bytes], eax
    mov edi, [mem]
    call wav_make_header
    mov eax, SYS_OPEN
    mov ebx, [name]
    mov ecx, O_CREATE | O_TRUNC
    int 0x80
    cmp eax, -1
    je .nofile
    mov [fd], eax
    mov eax, SYS_WRITE
    mov ebx, [fd]
    mov ecx, [mem]
    mov edx, [got]
    add edx, 44
    int 0x80
    push eax
    mov eax, SYS_CLOSE
    mov ebx, [fd]
    int 0x80
    pop eax
    mov edx, [got]
    add edx, 44
    cmp eax, edx
    jne .nofile
    ; sndrec: 2.00 s, 176400 bytes, peak 0 -> name
    mov edi, line
    mov esi, m_head
    call cat
    mov eax, [got]
    mov ecx, 100
    mul ecx
    mov ecx, RATE * FRAME
    div ecx
    xor edx, edx
    mov ecx, 100
    div ecx
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
    mov eax, [got]
    call utoa
    mov esi, m_bytes
    call cat
    mov eax, [peak]
    call utoa
    mov esi, m_arrow
    call cat
    mov esi, [name]
    call cat
    mov word [edi], 10
    mov eax, SYS_PUTS
    mov ebx, line
    int 0x80
    xor eax, eax
    ret
.nomem:
    mov ebx, m_nomem
    jmp fail
.nodev:
    mov ebx, m_nodev
    jmp fail
.norec:
    mov ebx, m_norec
    jmp fail
.nofile:
    mov ebx, m_nofile
    jmp fail
usage:
    mov ebx, m_usage
fail:
    mov eax, SYS_PUTS
    int 0x80
    mov eax, 1
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

m_usage     db 'Usage: run sndrec <file.wav> [seconds 1-10]', 10, 0
m_nomem     db 'sndrec: no memory', 10, 0
m_nodev     db 'sndrec: no sound device', 10, 0
m_norec     db 'sndrec: the device does not record', 10, 0
m_nofile    db 'sndrec: cannot write the file', 10, 0
m_head      db 'sndrec: ', 0
m_s         db ' s, ', 0
m_bytes     db ' bytes, peak ', 0
m_arrow     db ' -> ', 0

SQX_BSS
name        resd 1
secs        resd 1
bytes       resd 1
mem         resd 1
got         resd 1
peak        resd 1
fd          resd 1
line        resb 96
WAV_BSS
SQX_END
