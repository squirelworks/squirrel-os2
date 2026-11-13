; Squirrel-OS/2 — SYS_AUDIO numbers and WAV helpers for programs (3.0)
; Original code. Include after SQX_HEADER (it holds code):
;
;     %include "sqx.inc"
;     SQX_HEADER main
;     %include "audio.inc"
;
; See documentation/kernel/audio.md (SYS_AUDIO) and documentation/apps/audio.md.

SYS_AUDIO   equ 46
AU_INFO     equ 0               ; ecx = 16-byte block -> 0, or -1 (no device)
AU_OPEN     equ 1               ; ecx = rate, edx = channels | bits << 8 -> 0, -1, -2 busy
AU_WRITE    equ 2               ; ecx = bytes, edx = count -> count, or -1
AU_DRAIN    equ 3
AU_CLOSE    equ 4
AU_GETVOL   equ 5               ; ecx = control -> left | right << 8 | mute << 16, or -1
AU_SETVOL   equ 6               ; ecx = control, edx = value -> 0, or -1
AU_RECORD   equ 7               ; ecx = buffer, edx = bytes -> bytes (16-bit stereo), or -1
AU_POS      equ 8
AU_MASTER   equ 0               ; volume controls
AU_PCM      equ 1
AU_REC      equ 2

; WAV file (RIFF) reading: after wav_read_header, the file's position is
; at the first sample.
; ebx = open file -> CF clear and wav_rate, wav_ch, wav_bits, wav_bytes
; (the data chunk's size) set; CF set if it is not 8- or 16-bit PCM.
wav_read_header:
    pushad
    mov [wav_fd], ebx
    mov ecx, wav_hdr
    mov edx, 12
    call wav_read
    jc .bad
    cmp dword [wav_hdr], 'RIFF'
    jne .bad
    cmp dword [wav_hdr + 8], 'WAVE'
    jne .bad
    mov byte [wav_gotfmt], 0
.chunk:
    mov ecx, wav_hdr
    mov edx, 8
    call wav_read
    jc .bad
    mov eax, [wav_hdr + 4]          ; the chunk's size
    cmp dword [wav_hdr], 'data'
    je .data
    cmp dword [wav_hdr], 'fmt '
    jne .skip
    cmp eax, 16
    jb .bad
    push eax
    mov ecx, wav_hdr + 8
    mov edx, 16
    call wav_read
    pop eax
    jc .bad
    cmp word [wav_hdr + 8], 1       ; PCM
    jne .bad
    movzx ecx, word [wav_hdr + 10]
    mov [wav_ch], ecx
    mov ecx, [wav_hdr + 12]
    mov [wav_rate], ecx
    movzx ecx, word [wav_hdr + 22]
    mov [wav_bits], ecx
    mov byte [wav_gotfmt], 1
    sub eax, 16
.skip:                              ; jump over the rest of the chunk (padded to even)
    inc eax
    and eax, ~1
    test eax, eax
    jz .chunk
    mov ecx, eax
    mov eax, SYS_SEEK
    mov ebx, [wav_fd]
    mov edx, 1
    int 0x80
    cmp eax, -1
    je .bad
    jmp .chunk
.data:
    cmp byte [wav_gotfmt], 0
    je .bad
    mov [wav_bytes], eax
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; ecx = buffer, edx = bytes: exactly that many from wav_fd, or CF
wav_read:
    push edx
    mov eax, SYS_READ
    mov ebx, [wav_fd]
    int 0x80
    pop edx
    cmp eax, edx
    jne .bad
    clc
    ret
.bad:
    stc
    ret

; edi = 44 bytes: a WAV header for wav_rate, wav_ch, wav_bits, wav_bytes
wav_make_header:
    pushad
    mov dword [edi], 'RIFF'
    mov eax, [wav_bytes]
    add eax, 36
    mov [edi + 4], eax
    mov dword [edi + 8], 'WAVE'
    mov dword [edi + 12], 'fmt '
    mov dword [edi + 16], 16
    mov word [edi + 20], 1
    mov eax, [wav_ch]
    mov [edi + 22], ax
    mov eax, [wav_rate]
    mov [edi + 24], eax
    mov eax, [wav_ch]
    imul eax, [wav_bits]
    shr eax, 3                      ; bytes a frame
    mov [edi + 32], ax
    imul eax, [wav_rate]
    mov [edi + 28], eax
    mov eax, [wav_bits]
    mov [edi + 34], ax
    mov dword [edi + 36], 'data'
    mov eax, [wav_bytes]
    mov [edi + 40], eax
    popad
    ret

; The WAV helpers' data: put WAV_BSS after SQX_BSS.
%macro WAV_BSS 0
alignb 4
wav_fd      resd 1
wav_rate    resd 1
wav_ch      resd 1
wav_bits    resd 1
wav_bytes   resd 1
wav_gotfmt  resb 1
alignb 4
wav_hdr     resb 32
%endmacro
