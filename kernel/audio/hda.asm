; Squirrel-OS/2 — Intel High Definition Audio driver (3.0)
; Included from pm.asm. Original code, from the Intel HD Audio 1.0a
; specification.
;
; The controller is a PCI device of class 04, subclass 03 (QEMU -device
; intel-hda or ich9-intel-hda with -device hda-duplex or hda-output). Its
; registers are memory at BAR0, mapped with vm_map_range. Codec verbs go
; out through the CORB and answers come back in the RIRB, both rings in
; one page. The driver walks the first codec's function group for an
; output converter, an output pin, and (for recording) an input converter,
; and drives one output stream and one input stream. A stream plays its
; buffer list round and round; the generic layer in audio.asm keeps track
; of which buffer the link position (LPIB) is in.
; See documentation/kernel/audio.md.

HD_GCAP     equ 0x00
HD_GCTL     equ 0x08
HD_STATESTS equ 0x0E
HD_INTCTL   equ 0x20
HD_CORBLBASE equ 0x40
HD_CORBUBASE equ 0x44
HD_CORBWP   equ 0x48
HD_CORBRP   equ 0x4A
HD_CORBCTL  equ 0x4C
HD_CORBSIZE equ 0x4E
HD_RIRBLBASE equ 0x50
HD_RIRBUBASE equ 0x54
HD_RIRBWP   equ 0x58
HD_RINTCNT  equ 0x5A
HD_RIRBCTL  equ 0x5C
HD_RIRBSTS  equ 0x5D
HD_RIRBSIZE equ 0x5E
HD_SD0      equ 0x80                ; stream descriptors, 0x20 apart
HD_SDCTL    equ 0x00                ; within one (3 bytes; the stream tag in bits 20-23)
HD_SDSTS    equ 0x03
HD_SDLPIB   equ 0x04
HD_SDCBL    equ 0x08
HD_SDLVI    equ 0x0C
HD_SDFMT    equ 0x12
HD_SDBDPL   equ 0x18
HD_SDBDPU   equ 0x1C
HD_OUTTAG   equ 1                   ; stream tags we use
HD_INTAG    equ 2
HD_WAIT     equ 50                  ; ticks for a verb's answer

; verbs (12-bit ones with an 8-bit payload, 4-bit ones with 16 bits)
V_GETPARAM  equ 0xF00
V_SETSTREAM equ 0x706
V_SETPIN    equ 0x707
V_SETPOWER  equ 0x705
V_SETEAPD   equ 0x70C
V_SETFMT    equ 0x2                 ; 4-bit
V_SETAMP    equ 0x3                 ; 4-bit
V_GETAMP    equ 0xB                 ; 4-bit
P_NODES     equ 0x04                ; parameters
P_FGTYPE    equ 0x05
P_WCAPS     equ 0x09
P_PINCAPS   equ 0x0C
P_INAMP     equ 0x0D
P_OUTAMP    equ 0x12

hda_ops:
    dd hda_name, hda_open, hda_submit, hda_done, hda_stop
    dd hda_setvol, hda_getvol, hda_recstart, hda_recdone, hda_recstop
hda_name    db 'hda', 0

; -> CF clear when a controller with a codec that can play is there
hda_probe:
    pushad
    mov ax, 0x0403
    call apci_find_class
    jc .no
    call apci_enable
    mov ecx, APCI_BAR0
    call apci_read
    test al, 1
    jnz .no                         ; must be memory
    and eax, 0xFFFFFFF0
    jz .no
    mov [hd_base], eax
    mov ecx, 0x4000
    mov edx, cr3                    ; vm_map_range loads the kernel's
    call vm_map_range               ; directory; a program calling us
    mov cr3, edx                    ; needs its own back
    call hda_mapcheck
    mov ebx, [hd_base]
    ; reset the controller, then take it out of reset
    and dword [ebx + HD_GCTL], ~1
    call hda_wait_crst0
    or dword [ebx + HD_GCTL], 1
    call hda_wait_crst1
    jc .no
    mov edx, [ticks]                ; codecs say hello within a few ms
    add edx, 5
.wc:
    cmp [ticks], edx
    jb .wc
    movzx eax, word [ebx + HD_STATESTS]
    test eax, eax
    jz .no
    bsf eax, eax
    mov [hd_codec], eax
    mov dword [ebx + HD_INTCTL], 0  ; polled
    movzx eax, word [ebx + HD_GCAP]
    mov ecx, eax
    shr ecx, 8
    and ecx, 15                     ; input streams; the outputs follow them
    mov [hd_nin], ecx
    call hda_rings
    jc .no
    call hda_walk
    jc .no
    call pg_alloc                   ; the two buffer lists (128-byte aligned)
    test eax, eax
    jz .no
    mov [hd_bdl_out], eax
    add eax, 2048
    mov [hd_bdl_in], eax
    popad
    clc
    ret
.no:
    popad
    stc
    ret

; The MMIO page directory entry may be missing in a program's page
; directory made before the probe: copy it there from the kernel's.
hda_mapcheck:
    push eax
    push ebx
    push ecx
    mov eax, [hd_base]
    shr eax, 22
    mov ebx, cr3
    mov ecx, [kernel_pd]
    cmp ebx, ecx
    je .r
    mov ecx, [ecx + eax * 4]
    cmp [ebx + eax * 4], ecx
    je .r
    mov [ebx + eax * 4], ecx
    mov ebx, cr3
    mov cr3, ebx
.r:
    pop ecx
    pop ebx
    pop eax
    ret

hda_wait_crst0:
    mov ecx, 1000000
.w:
    test dword [ebx + HD_GCTL], 1
    jz .r
    loop .w
.r:
    ret

; -> CF if the controller does not leave reset
hda_wait_crst1:
    mov edx, [ticks]
    add edx, 20
.w:
    test dword [ebx + HD_GCTL], 1
    jnz .ok
    cmp [ticks], edx
    jb .w
    stc
    ret
.ok:
    clc
    ret

; CORB (256 entries) and RIRB (256 entries) in one page -> CF if no page
hda_rings:
    call pg_alloc
    test eax, eax
    jz .no
    mov [hd_corb], eax
    add eax, 1024
    mov [hd_rirb], eax
    mov ebx, [hd_base]
    mov byte [ebx + HD_CORBCTL], 0
    mov byte [ebx + HD_RIRBCTL], 0
    mov eax, [hd_corb]
    mov [ebx + HD_CORBLBASE], eax
    mov dword [ebx + HD_CORBUBASE], 0
    mov byte [ebx + HD_CORBSIZE], 2 ; 256 entries
    mov word [ebx + HD_CORBRP], 0x8000 ; reset the read pointer
    mov ecx, 100000
.r1:
    test word [ebx + HD_CORBRP], 0x8000
    jnz .r1d
    loop .r1
.r1d:
    mov word [ebx + HD_CORBRP], 0
    mov word [ebx + HD_CORBWP], 0
    mov eax, [hd_rirb]
    mov [ebx + HD_RIRBLBASE], eax
    mov dword [ebx + HD_RIRBUBASE], 0
    mov byte [ebx + HD_RIRBSIZE], 2
    mov word [ebx + HD_RIRBWP], 0x8000 ; reset the write pointer
    mov word [ebx + HD_RINTCNT], 255
    mov byte [ebx + HD_RIRBSTS], 5  ; clear
    mov byte [ebx + HD_CORBCTL], 2  ; run
    mov byte [ebx + HD_RIRBCTL], 2
    mov dword [hd_rirb_rp], 0
    clc
    ret
.no:
    stc
    ret

; eax = node << 20 | verb << 8 | payload (12-bit verb), or node << 20 |
; verb << 16 | payload (4-bit verb). -> eax = the answer, CF on a timeout.
; Keeps the other registers.
hda_verb:
    push ebx
    push ecx
    push edx
    mov ecx, [hd_codec]
    shl ecx, 28
    or eax, ecx
    mov ebx, [hd_base]
    movzx ecx, word [ebx + HD_CORBWP]
    inc ecx
    and ecx, 255
    mov edx, [hd_corb]
    mov [edx + ecx * 4], eax
    mov [ebx + HD_CORBWP], cx
    mov edx, [ticks]
    add edx, HD_WAIT
.w:
    movzx eax, word [ebx + HD_RIRBWP]
    and eax, 255
    cmp eax, [hd_rirb_rp]
    jne .got
    cmp [ticks], edx
    jb .w
    stc
    jmp .r
.got:
    mov ecx, [hd_rirb_rp]
    inc ecx
    and ecx, 255
    mov [hd_rirb_rp], ecx
    mov edx, [hd_rirb]
    mov eax, [edx + ecx * 8]        ; the answer; the next dword says whose
    mov byte [ebx + HD_RIRBSTS], 5  ; and the answer count starts again
    clc
.r:
    pop edx
    pop ecx
    pop ebx
    ret

; ecx = node, edx = parameter -> eax
hda_param:
    mov eax, ecx
    shl eax, 20
    or eax, V_GETPARAM << 8
    or eax, edx
    jmp hda_verb

; Finds the audio function group and in it an output converter, an output
; pin and an input converter (hd_dac, hd_pin, hd_adc; 0 when missing).
; -> CF if there is no output converter.
hda_walk:
    xor eax, eax
    mov [hd_dac], eax
    mov [hd_pin], eax
    mov [hd_adc], eax
    mov [hd_inpin], eax
    xor ecx, ecx                    ; the root node
    mov edx, P_NODES
    call hda_param
    jc .no
    mov esi, eax
    shr esi, 16
    and esi, 0xFF                   ; first function group
    movzx edi, al                   ; how many
.fg:
    test edi, edi
    jz .no
    mov ecx, esi
    mov edx, P_FGTYPE
    call hda_param
    jc .no
    and al, 0x7F
    cmp al, 1                       ; audio
    je .afg
    inc esi
    dec edi
    jmp .fg
.afg:
    mov [hd_afg], esi
    mov eax, esi                    ; power it up
    shl eax, 20
    or eax, V_SETPOWER << 8
    call hda_verb
    mov ecx, esi
    mov edx, P_NODES
    call hda_param
    jc .no
    mov esi, eax
    shr esi, 16
    and esi, 0xFF
    movzx edi, al
.w:
    test edi, edi
    jz .done
    mov ecx, esi
    mov edx, P_WCAPS
    call hda_param
    jc .no
    shr eax, 20
    and eax, 15                     ; widget type
    jnz .notout
    cmp dword [hd_dac], 0
    jne .next
    mov [hd_dac], esi
    jmp .next
.notout:
    cmp eax, 1
    jne .notin
    cmp dword [hd_adc], 0
    jne .next
    mov [hd_adc], esi
    jmp .next
.notin:
    cmp eax, 4
    jne .next
    mov ecx, esi
    mov edx, P_PINCAPS
    call hda_param
    jc .next
    test eax, 1 << 4                ; can drive an output
    jz .pin_in
    cmp dword [hd_pin], 0
    jne .next
    mov [hd_pin], esi
    jmp .next
.pin_in:
    test eax, 1 << 5
    jz .next
    cmp dword [hd_inpin], 0
    jne .next
    mov [hd_inpin], esi
.next:
    inc esi
    dec edi
    jmp .w
.done:
    cmp dword [hd_dac], 0
    je .no
    ; the output amplifier's steps (on the converter, else the function group)
    mov ecx, [hd_dac]
    mov edx, P_OUTAMP
    call hda_param
    test eax, eax
    jnz .amp
    mov ecx, [hd_afg]
    call hda_param
.amp:
    mov [hd_outamp], eax
    mov ecx, [hd_adc]
    mov edx, P_INAMP
    call hda_param
    test eax, eax
    jnz .iamp
    mov ecx, [hd_afg]
    call hda_param
.iamp:
    mov [hd_inamp], eax
    ; power the widgets up, turn the pins on, unmute at full volume
    mov eax, [hd_dac]
    call hda_power
    mov eax, [hd_pin]
    call hda_power
    mov eax, [hd_adc]
    call hda_power
    mov eax, [hd_inpin]
    call hda_power
    mov eax, [hd_pin]
    test eax, eax
    jz .np
    shl eax, 20
    or eax, (V_SETPIN << 8) | 0x40  ; output enabled
    call hda_verb
    mov eax, [hd_pin]
    shl eax, 20
    or eax, (V_SETEAPD << 8) | 2
    call hda_verb
.np:
    mov eax, [hd_inpin]
    test eax, eax
    jz .nip
    shl eax, 20
    or eax, (V_SETPIN << 8) | 0x20  ; input enabled
    call hda_verb
.nip:
    mov ecx, 0
    mov edx, 100 | (100 << 8)
    call hda_setvol
    mov ecx, 2
    call hda_setvol
    clc
    ret
.no:
    stc
    ret

; eax = node (0: nothing): power state D0
hda_power:
    test eax, eax
    jz .r
    shl eax, 20
    or eax, V_SETPOWER << 8
    call hda_verb
.r:
    ret

; eax = sample rate -> eax = the stream format word (16-bit stereo), CF
; if the rate is not one we can make
hda_fmt:
    push esi
    mov esi, hda_rates
.l:
    cmp dword [esi], 0
    je .bad
    cmp [esi], eax
    je .hit
    add esi, 8
    jmp .l
.hit:
    mov eax, [esi + 4]
    pop esi
    clc
    ret
.bad:
    pop esi
    stc
    ret

; eax = stream index (0 = the first input; outputs after hd_nin) ->
; ebx = its descriptor's address. Stops and resets it.
hda_sd_reset:
    push ecx
    push edx
    shl eax, 5
    add eax, HD_SD0
    mov ebx, [hd_base]
    add ebx, eax
    and byte [ebx + HD_SDCTL], ~2   ; stop
    or byte [ebx + HD_SDCTL], 1     ; reset
    mov ecx, 100000
.a:
    test byte [ebx + HD_SDCTL], 1
    jnz .b
    loop .a
.b:
    and byte [ebx + HD_SDCTL], ~1
    mov ecx, 100000
.c:
    test byte [ebx + HD_SDCTL], 1
    jz .d
    loop .c
.d:
    mov byte [ebx + HD_SDSTS], 0x1C ; clear its status
    pop edx
    pop ecx
    ret

; ebx = descriptor, edi = buffer list, esi = AU_NBUF buffer addresses,
; ecx = bytes in each, eax = format, edx = stream tag: set it up, stopped
hda_sd_setup:
    pushad
    push eax
    push edx
    xor edx, edx
.e:
    mov eax, [esi + edx * 4]
    mov [edi], eax
    mov dword [edi + 4], 0
    mov [edi + 8], ecx
    mov dword [edi + 12], 0
    add edi, 16
    inc edx
    cmp edx, AU_NBUF
    jb .e
    pop edx
    shl edx, 20
    mov eax, [ebx + HD_SDCTL]
    and eax, 0x000F00FF
    or eax, edx
    mov [ebx + HD_SDCTL], eax
    pop eax
    mov [ebx + HD_SDFMT], ax
    imul ecx, AU_NBUF
    mov [ebx + HD_SDCBL], ecx
    mov word [ebx + HD_SDLVI], AU_NBUF - 1
    mov eax, [esp + 0]              ; edi as it came in: the list
    mov [ebx + HD_SDBDPL], eax
    mov dword [ebx + HD_SDBDPU], 0
    popad
    ret

; eax = node, ebx = stream tag, ecx = format: the converter's stream,
; channel 0, and format
hda_conv:
    pushad
    mov esi, eax
    shl esi, 20
    mov eax, ebx
    shl eax, 4
    or eax, esi
    or eax, V_SETSTREAM << 8
    call hda_verb
    mov eax, ecx
    and eax, 0xFFFF
    or eax, esi
    or eax, V_SETFMT << 16
    call hda_verb
    popad
    ret

; eax = rate -> CF if the rate cannot be made
hda_open:
    pushad
    call hda_mapcheck
    call hda_fmt
    jc .bad
    mov [hd_ofmt], eax
    mov eax, [hd_nin]               ; the first output stream
    call hda_sd_reset
    mov [hd_osd], ebx
    mov edi, [hd_bdl_out]
    mov esi, au_pages
    mov ecx, AU_PAGE
    mov eax, [hd_ofmt]
    mov edx, HD_OUTTAG
    call hda_sd_setup
    mov eax, [hd_dac]
    mov ebx, HD_OUTTAG
    mov ecx, [hd_ofmt]
    call hda_conv
    mov dword [hd_done], 0
    mov byte [hd_run], 0
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; eax = buffer (one of au_pages, in order), ecx = bytes: the stream plays
; the whole list round, so only the first one starts it
hda_submit:
    cmp byte [hd_run], 0
    jne .r
    push ebx
    call hda_mapcheck
    mov byte [hd_run], 1
    mov ebx, [hd_osd]
    or byte [ebx + HD_SDCTL], 2     ; run
    pop ebx
.r:
    ret

; -> eax = buffers played since hda_open: the link position's buffer,
; counted on as it goes round
hda_done:
    push ebx
    push ecx
    mov eax, [hd_done]
    cmp byte [hd_run], 0
    je .r
    call hda_mapcheck
    mov ebx, [hd_osd]
    mov eax, [ebx + HD_SDLPIB]
    shr eax, AU_PAGE_SHIFT          ; the buffer it is in
    mov ecx, [hd_done]
    and ecx, AU_NBUF - 1
    sub eax, ecx
    and eax, AU_NBUF - 1
    add [hd_done], eax
    mov eax, [hd_done]
.r:
    pop ecx
    pop ebx
    ret

hda_stop:
    push eax
    push ebx
    call hda_mapcheck
    mov eax, [hd_nin]
    call hda_sd_reset
    mov byte [hd_run], 0
    pop ebx
    pop eax
    ret

; ecx = control (0 master, 1 PCM: both the output amplifier; 2 record:
; the input converter's amplifier), edx = left | right << 8 | mute << 16
; -> CF for an unknown control
hda_setvol:
    pushad
    cmp ecx, 2
    ja .bad
    mov ebx, [hd_dac]
    mov esi, [hd_outamp]
    mov edi, 0x8000                 ; set the output amplifier
    cmp ecx, 2
    jne .amp
    mov ebx, [hd_adc]
    mov esi, [hd_inamp]
    mov edi, 0x4000                 ; the input one
.amp:
    test ebx, ebx
    jz .ok
    call hda_mapcheck
    mov ecx, esi
    shr ecx, 8
    and ecx, 0x7F                   ; steps - 1
    movzx eax, dl                   ; left
    call .gain
    or eax, 0x2000
    call .send
    movzx eax, dh                   ; right
    call .gain
    or eax, 0x1000
    call .send
.ok:
    popad
    clc
    ret
.bad:
    popad
    stc
    ret
; eax = 0..100, ecx = top step -> eax = the gain, with the mute bit
.gain:
    cmp eax, 100
    jbe .g
    mov eax, 100
.g:
    imul eax, ecx
    add eax, 50
    push edx
    push ecx
    xor edx, edx
    mov ecx, 100
    div ecx
    pop ecx
    pop edx
    test edx, 0x10000
    jz .gr
    or eax, 0x80
.gr:
    ret
; eax = gain bits: to node ebx, direction edi
.send:
    or eax, edi
    push ebx
    shl ebx, 20
    or eax, ebx
    or eax, V_SETAMP << 16
    call hda_verb
    pop ebx
    ret

; ecx = control -> eax = left | right << 8 | mute << 16, or CF
hda_getvol:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    cmp ecx, 2
    ja .bad
    mov ebx, [hd_dac]
    mov esi, [hd_outamp]
    mov edi, 0x8000
    cmp ecx, 2
    jne .amp
    mov ebx, [hd_adc]
    mov esi, [hd_inamp]
    xor edi, edi
.amp:
    xor eax, eax
    test ebx, ebx
    jz .r
    call hda_mapcheck
    shr esi, 8
    and esi, 0x7F
    jz .r                           ; no steps
    mov eax, edi
    or eax, 0x2000                  ; left
    call .get
    push eax                        ; left, mute in bit 16
    mov eax, edi                    ; right
    call .get
    and eax, 0xFF
    shl eax, 8
    pop ecx
    or eax, ecx
.r:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    clc
    ret
.bad:
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    stc
    ret
; eax = payload -> eax = 0..100, with the mute in bit 16
.get:
    push ebx
    shl ebx, 20
    or eax, ebx
    or eax, V_GETAMP << 16
    call hda_verb
    pop ebx
    mov edx, eax
    and eax, 0x7F
    imul eax, 100
    push edx
    mov ecx, esi
    shr ecx, 1
    add eax, ecx
    xor edx, edx
    div esi
    pop edx
    test edx, 0x80
    jz .gx
    or eax, 0x10000
.gx:
    ret

; eax = rate, esi = record buffers, ecx = bytes in each -> CF if the rate
; or the input converter is not there
hda_recstart:
    pushad
    call hda_mapcheck
    cmp dword [hd_adc], 0
    je .bad
    cmp dword [hd_nin], 0
    je .bad
    call hda_fmt
    jc .bad
    mov [hd_ifmt], eax
    xor eax, eax                    ; the first input stream
    call hda_sd_reset
    mov [hd_isd], ebx
    mov edi, [hd_bdl_in]
    mov eax, [hd_ifmt]
    mov edx, HD_INTAG
    call hda_sd_setup               ; esi, ecx as given
    mov eax, [hd_adc]
    mov ebx, HD_INTAG
    mov ecx, [hd_ifmt]
    call hda_conv
    mov dword [hd_rdone], 0
    mov ebx, [hd_isd]
    or byte [ebx + HD_SDCTL], 2
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

hda_recdone:
    push ebx
    push ecx
    call hda_mapcheck
    mov ebx, [hd_isd]
    mov eax, [ebx + HD_SDLPIB]
    shr eax, AU_PAGE_SHIFT
    mov ecx, [hd_rdone]
    and ecx, AU_NBUF - 1
    sub eax, ecx
    and eax, AU_NBUF - 1
    add [hd_rdone], eax
    mov eax, [hd_rdone]
    pop ecx
    pop ebx
    ret

hda_recstop:
    push eax
    push ebx
    call hda_mapcheck
    xor eax, eax
    call hda_sd_reset
    pop ebx
    pop eax
    ret

; rates the stream format can name (16-bit stereo: bits 4-6 = 1, channels 2)
; base 48 kHz (bit 14 = 0) or 44.1 kHz (1), multiply bits 11-13, divide bits 8-10
align 4
hda_rates:
    dd 48000, 0x0011
    dd 44100, 0x4011
    dd 32000, 0x0A11                ; 48k * 2 / 3
    dd 24000, 0x0111                ; 48k / 2
    dd 22050, 0x4111                ; 44.1k / 2
    dd 16000, 0x0211                ; 48k / 3
    dd 11025, 0x4311                ; 44.1k / 4
    dd 8000, 0x0511                 ; 48k / 6
    dd 0, 0

hd_run      db 0
align 4
hd_base     dd 0
hd_codec    dd 0
hd_nin      dd 0
hd_corb     dd 0
hd_rirb     dd 0
hd_rirb_rp  dd 0
hd_afg      dd 0
hd_dac      dd 0
hd_pin      dd 0
hd_adc      dd 0
hd_inpin    dd 0
hd_outamp   dd 0
hd_inamp    dd 0
hd_bdl_out  dd 0
hd_bdl_in   dd 0
hd_osd      dd 0
hd_isd      dd 0
hd_ofmt     dd 0
hd_ifmt     dd 0
hd_done     dd 0
hd_rdone    dd 0
