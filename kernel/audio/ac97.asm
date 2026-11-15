; Squirrel-OS/2 — AC'97 audio driver (3.0)
; Included from pm.asm. Original code, from the AC'97 2.3 register map and
; the ICH bus master interface.
;
; The controller is a PCI audio device (class 04, subclass 01: QEMU
; -device AC97, 8086:2415). BAR0 is the mixer (NAM, I/O ports), BAR1 the
; bus master (NABM, I/O ports). Each direction has a box of registers and
; a list of 32 buffer descriptors; the controller plays descriptor CIV,
; moves on, and halts after LVI, so the driver keeps LVI just behind what
; it has filled. Playback and recording always use 16-bit stereo; the
; sample rate is set through the variable rate registers.
; The generic layer in audio.asm calls these through ac97_ops.
; See documentation/kernel/audio.md.

AC_RESET    equ 0x00                ; NAM registers (words)
AC_MASTER   equ 0x02
AC_PCMOUT   equ 0x18
AC_RECSEL   equ 0x1A
AC_RECGAIN  equ 0x1C
AC_EXTSTAT  equ 0x2A                ; bit 0: variable rate on
AC_FRONTRATE equ 0x2C
AC_ADCRATE  equ 0x32

AC_PI       equ 0x00                ; NABM boxes: PCM in, PCM out
AC_PO       equ 0x10
AC_BDBAR    equ 0x00                ; within a box
AC_CIV      equ 0x04
AC_LVI      equ 0x05
AC_SR       equ 0x06
AC_PICB     equ 0x08
AC_CR       equ 0x0B
AC_GLOB_CNT equ 0x2C

AC_SR_DCH   equ 1                   ; halted
AC_CR_RUN   equ 1
AC_CR_RESET equ 2
AC_NDESC    equ 32

ac97_ops:
    dd ac97_name, ac97_open, ac97_submit, ac97_done, ac97_stop
    dd ac97_setvol, ac97_getvol, ac97_recstart, ac97_recdone, ac97_recstop
ac97_name   db 'ac97', 0

; -> CF clear when an AC'97 controller is there and ready
ac97_probe:
    pushad
    mov ax, 0x0401
    call apci_find_class
    jc .no
    call apci_enable
    mov ecx, APCI_BAR0
    call apci_read
    test al, 1                      ; must be I/O space
    jz .no
    and eax, 0xFFFC
    mov [ac_nam], ax
    mov ecx, APCI_BAR1
    call apci_read
    test al, 1
    jz .no
    and eax, 0xFFFC
    mov [ac_nabm], ax
    mov dx, [ac_nabm]               ; cold reset off: the link runs
    add dx, AC_GLOB_CNT
    mov eax, 2
    out dx, eax
    mov dx, [ac_nam]                ; reset the codec's registers
    add dx, AC_RESET
    xor ax, ax
    out dx, ax
    mov dx, [ac_nam]                ; variable sample rates
    add dx, AC_EXTSTAT
    in ax, dx
    or ax, 1
    out dx, ax
    mov dx, [ac_nam]                ; full volume, not muted
    add dx, AC_MASTER
    xor ax, ax
    out dx, ax
    mov dx, [ac_nam]
    add dx, AC_PCMOUT
    mov ax, 0x0808                  ; 0 dB
    out dx, ax
    mov dx, [ac_nam]                ; record from the line input, 0 dB gain
    add dx, AC_RECSEL
    mov ax, 0x0404
    out dx, ax
    mov dx, [ac_nam]
    add dx, AC_RECGAIN
    xor ax, ax
    out dx, ax
    call pg_alloc                   ; the two descriptor lists, 256 bytes each
    test eax, eax
    jz .no
    mov [ac_bdl_out], eax
    add eax, 256
    mov [ac_bdl_in], eax
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; dx = box (AC_PI / AC_PO): stop it and reset it. Keeps registers.
ac97_reset_box:
    push eax
    push ecx
    push edx
    add dx, [ac_nabm]
    push edx
    add dx, AC_CR
    xor al, al
    out dx, al
    mov al, AC_CR_RESET
    out dx, al
    mov ecx, 100000
.w:
    in al, dx
    test al, AC_CR_RESET
    jz .d
    loop .w
.d:
    pop edx
    pop edx
    pop ecx
    pop eax
    ret

; eax = sample rate -> CF if the codec does not take it
ac97_open:
    push edx
    push eax
    mov dx, AC_PO
    call ac97_reset_box
    mov dx, [ac_nam]
    add dx, AC_FRONTRATE
    out dx, ax
    in ax, dx
    movzx edx, ax
    pop eax
    cmp edx, eax
    jne .bad
    mov dx, [ac_nabm]
    add dx, AC_PO + AC_BDBAR
    mov eax, [ac_bdl_out]
    out dx, eax
    mov dword [ac_sub], 0
    mov dword [ac_done], 0
    mov byte [ac_run], 0
    pop edx
    clc
    ret
.bad:
    pop edx
    stc
    ret

; eax = buffer address, ecx = bytes (even): the next descriptor, and play
; on to it
ac97_submit:
    pushad
    mov edi, [ac_sub]
    and edi, AC_NDESC - 1
    lea esi, [edi * 8]
    add esi, [ac_bdl_out]
    mov [esi], eax
    shr ecx, 1                      ; 16-bit samples
    mov [esi + 4], cx
    mov word [esi + 6], 0
    inc dword [ac_sub]
    mov dx, [ac_nabm]               ; the controller may play up to here
    add dx, AC_PO + AC_LVI
    mov eax, edi
    out dx, al
    cmp byte [ac_run], 0
    jne .r
    mov byte [ac_run], 1
    mov dx, [ac_nabm]
    add dx, AC_PO + AC_CR
    mov al, AC_CR_RUN
    out dx, al
.r:
    popad
    ret

; -> eax = buffers played (counted from ac97_open)
ac97_done:
    push ecx
    push edx
    mov eax, [ac_sub]
    cmp byte [ac_run], 0
    je .r                           ; nothing given yet
    mov dx, [ac_nabm]
    add dx, AC_PO + AC_SR
    in ax, dx
    test al, AC_SR_DCH
    jz .moving
    mov eax, [ac_sub]               ; halted after the last one: all played
    mov [ac_done], eax
    jmp .r
.moving:
    mov dx, [ac_nabm]
    add dx, AC_PO + AC_CIV
    in al, dx
    movzx eax, al
    mov ecx, [ac_done]
    and ecx, AC_NDESC - 1
    sub eax, ecx
    and eax, AC_NDESC - 1
    add [ac_done], eax
    mov eax, [ac_done]
.r:
    pop edx
    pop ecx
    ret

ac97_stop:
    push edx
    mov dx, AC_PO
    call ac97_reset_box
    mov byte [ac_run], 0
    pop edx
    ret

; ecx = control (0 master, 1 PCM, 2 record), edx = left | right << 8 |
; mute << 16 (0..100) -> CF for an unknown control
ac97_setvol:
    pushad
    cmp ecx, 2
    ja .bad
    mov ebx, ecx
    movzx eax, dl
    call ac97_level
    mov esi, eax
    movzx eax, dh
    call ac97_level
    shl esi, 8
    or esi, eax
    test edx, 0x10000
    jz .m
    or esi, 0x8000
.m:
    mov dx, [ac_nam]
    add dx, [ac_volreg + ebx * 2]
    mov eax, esi
    out dx, ax
    popad
    clc
    ret
.bad:
    popad
    stc
    ret
; eax = 0..100, ebx = control -> eax = the register field
ac97_level:
    cmp eax, 100
    jbe .in
    mov eax, 100
.in:
    cmp ebx, 2
    je .gain
    neg eax                         ; attenuation: 0 loudest, 31 quietest
    add eax, 100
    imul eax, 31
    add eax, 50
    push edx
    xor edx, edx
    push ecx
    mov ecx, 100
    div ecx
    pop ecx
    pop edx
    ret
.gain:                              ; record gain: 0..15, 15 loudest
    imul eax, 15
    add eax, 50
    push edx
    push ecx
    xor edx, edx
    mov ecx, 100
    div ecx
    pop ecx
    pop edx
    ret

; ecx = control -> eax = left | right << 8 | mute << 16, or CF
ac97_getvol:
    push ebx
    push ecx
    push edx
    push esi
    cmp ecx, 2
    ja .bad
    mov ebx, ecx
    mov dx, [ac_nam]
    add dx, [ac_volreg + ebx * 2]
    in ax, dx
    movzx esi, ax
    mov eax, esi
    shr eax, 8
    call ac97_pct
    mov ecx, eax
    mov eax, esi
    call ac97_pct
    shl eax, 8
    or ecx, eax
    test esi, 0x8000
    jz .m
    or ecx, 0x10000
.m:
    mov eax, ecx
    pop esi
    pop edx
    pop ecx
    pop ebx
    clc
    ret
.bad:
    pop esi
    pop edx
    pop ecx
    pop ebx
    stc
    ret
; al = register field, ebx = control -> eax = 0..100
ac97_pct:
    push ecx
    push edx
    cmp ebx, 2
    je .gain
    and eax, 31
    imul eax, 100
    add eax, 15
    xor edx, edx
    mov ecx, 31
    div ecx
    neg eax
    add eax, 100
    jmp .r
.gain:
    and eax, 15
    imul eax, 100
    add eax, 7
    xor edx, edx
    mov ecx, 15
    div ecx
.r:
    pop edx
    pop ecx
    ret

; Recording: eax = rate, esi = the generic layer's record buffers
; (AU_NBUF addresses), ecx = bytes in each -> CF if the rate is refused.
; All of them are handed to the controller at once.
ac97_recstart:
    pushad
    mov dx, AC_PI
    call ac97_reset_box
    mov dx, [ac_nam]
    add dx, AC_ADCRATE
    out dx, ax
    in ax, dx
    movzx edx, ax
    cmp edx, [esp + 28]             ; the eax we were given
    jne .bad
    mov edi, [ac_bdl_in]
    xor ebx, ebx
.d:
    mov eax, [esi + ebx * 4]
    mov [edi], eax
    mov eax, ecx
    shr eax, 1
    mov [edi + 4], ax
    mov word [edi + 6], 0
    add edi, 8
    inc ebx
    cmp ebx, AU_NBUF
    jb .d
    mov dx, [ac_nabm]
    add dx, AC_PI + AC_BDBAR
    mov eax, [ac_bdl_in]
    out dx, eax
    mov dx, [ac_nabm]
    add dx, AC_PI + AC_LVI
    mov al, AU_NBUF - 1
    out dx, al
    mov dword [ac_rdone], 0
    mov dx, [ac_nabm]
    add dx, AC_PI + AC_CR
    mov al, AC_CR_RUN
    out dx, al
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; -> eax = buffers filled since ac97_recstart. Each buffer read is given
; back at once: the caller has copied it before asking again.
ac97_recdone:
    push ecx
    push edx
    mov dx, [ac_nabm]
    add dx, AC_PI + AC_CIV
    in al, dx
    movzx eax, al
    mov ecx, [ac_rdone]
    and ecx, AC_NDESC - 1
    sub eax, ecx
    and eax, AC_NDESC - 1
    jz .same
    mov ecx, eax                    ; give those buffers back: their
.give:                              ; descriptors repeat AU_NBUF later
    push ecx
    mov ecx, [ac_rdone]
    mov edx, ecx
    and ecx, AU_NBUF - 1
    and edx, AC_NDESC - 1
    add edx, AU_NBUF
    and edx, AC_NDESC - 1
    push eax
    push edi
    mov edi, [ac_bdl_in]
    mov eax, [edi + ecx * 8]        ; the same buffer, AU_NBUF descriptors on
    mov [edi + edx * 8], eax
    mov eax, [edi + ecx * 8 + 4]
    mov [edi + edx * 8 + 4], eax
    pop edi
    pop eax
    push eax
    mov al, dl                      ; and let the controller go that far
    mov dx, [ac_nabm]
    add dx, AC_PI + AC_LVI
    out dx, al
    pop eax
    inc dword [ac_rdone]
    pop ecx
    loop .give
.same:
    mov eax, [ac_rdone]
    pop edx
    pop ecx
    ret

ac97_recstop:
    push edx
    mov dx, AC_PI
    call ac97_reset_box
    pop edx
    ret

align 2
ac_nam      dw 0
ac_nabm     dw 0
ac_volreg   dw AC_MASTER, AC_PCMOUT, AC_RECGAIN
ac_run      db 0
align 4
ac_bdl_out  dd 0
ac_bdl_in   dd 0
ac_sub      dd 0
ac_done     dd 0
ac_rdone    dd 0
