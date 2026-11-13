; Squirrel-OS/2 — sound: the device-neutral layer and SYS_AUDIO (3.0)
; Included from pm.asm. Original code.
;
; One sound device: an Intel HDA controller if there is one, otherwise an
; AC'97 controller (hda.asm, ac97.asm). Both play from the same ring of
; AU_NBUF pages and record into a second ring. Programs open the device
; with their own format (8- or 16-bit, mono or stereo, one of the rates
; in au_rates) and write; this layer turns every frame into 16-bit stereo,
; fills the next page, and hands full pages to the driver, waiting while
; all of them are queued. A page the hardware has played is cleared, so
; if the program falls behind the hardware plays silence. Polled: the
; driver's position is read while writing and draining.
; See documentation/kernel/audio.md.

AU_NBUF     equ 8                   ; pages in each ring (a power of two)
AU_PAGE     equ 4096
AU_PAGE_SHIFT equ 12
AU_FRAME    equ 4                   ; 16-bit stereo on the device

; a driver's operations (ac97_ops, hda_ops)
DRV_NAME    equ 0
DRV_OPEN    equ 4                   ; eax = rate -> CF
DRV_SUBMIT  equ 8                   ; eax = page, ecx = bytes
DRV_DONE    equ 12                  ; -> eax = pages played
DRV_STOP    equ 16
DRV_SETVOL  equ 20                  ; ecx = control, edx = value -> CF
DRV_GETVOL  equ 24                  ; ecx = control -> eax, CF
DRV_RECSTART equ 28                 ; eax = rate, esi = pages, ecx = bytes each -> CF
DRV_RECDONE equ 32                  ; -> eax = pages filled
DRV_RECSTOP equ 36

; SYS_AUDIO (38) operations, in ebx
AU_INFO     equ 0                   ; ecx = 16-byte block -> 0, or -1 (no device)
AU_OPEN     equ 1                   ; ecx = rate, edx = channels | bits << 8 -> 0, -1 bad, -2 busy
AU_WRITE    equ 2                   ; ecx = bytes, edx = count -> count, or -1
AU_DRAIN    equ 3                   ; -> 0 when all is played (the device stops)
AU_CLOSE    equ 4                   ; -> 0
AU_GETVOL   equ 5                   ; ecx = control -> left | right << 8 | mute << 16, or -1
AU_SETVOL   equ 6                   ; ecx = control, edx = as AU_GETVOL -> 0, or -1
AU_RECORD   equ 7                   ; ecx = buffer, edx = bytes -> bytes (16-bit stereo), or -1
AU_POS      equ 8                   ; -> bytes played since AU_OPEN (device format)
AU_OPS      equ 9

AU_CTL_MASTER equ 0
AU_CTL_PCM  equ 1
AU_CTL_REC  equ 2

; -> CF clear when there is a device (found now or before)
au_probe:
    cmp byte [au_state], 1
    je .yes
    cmp byte [au_state], 2
    je .no
    pushad
    mov byte [au_state], 2
    call hda_probe
    jc .ac
    mov dword [au_drv], hda_ops
    jmp .pages
.ac:
    call ac97_probe
    jc .none
    mov dword [au_drv], ac97_ops
.pages:
    xor ebx, ebx
.p:
    call pg_alloc
    test eax, eax
    jz .none
    mov [au_pages + ebx * 4], eax
    inc ebx
    cmp ebx, AU_NBUF * 2 + 1        ; play ring, record ring, a scratch page
    jb .p
    mov byte [au_state], 1
    popad
.yes:
    clc
    ret
.none:
    popad
.no:
    stc
    ret

; edx = byte offset of a driver operation: call it (registers as it says)
au_call:
    push eax
    mov eax, [au_drv]
    mov eax, [eax + edx]
    xchg eax, [esp]
    ret                             ; "returns" into the operation

; ---------- playback ----------

; eax = rate, edx = channels | bits << 8 -> CF if the device or the format
; is refused
au_open:
    pushad
    call au_probe
    jc .bad
    movzx ecx, dl                   ; channels
    cmp ecx, 1
    jb .bad
    cmp ecx, 2
    ja .bad
    movzx ebx, dh                   ; bits
    cmp ebx, 8
    je .bits
    cmp ebx, 16
    jne .bad
.bits:
    mov esi, au_rates
.r:
    cmp dword [esi], 0
    je .bad
    cmp [esi], eax
    je .rate
    add esi, 4
    jmp .r
.rate:
    mov [au_inch], ecx
    mov [au_inbits], ebx
    imul ecx, ebx
    shr ecx, 3
    mov [au_infs], ecx              ; bytes in one of the program's frames
    mov [au_rate], eax
    call au_stop_play
    mov edi, [au_pages]             ; start from silence
    call au_clear_ring
    xor ecx, ecx
    mov [au_sub], ecx
    mov [au_done], ecx
    mov [au_zdone], ecx
    mov [au_fill], ecx
    mov [au_total], ecx
    mov eax, [au_rate]
    mov edx, DRV_OPEN
    call au_call
    jc .bad
    mov byte [au_isopen], 1
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

; clears the play ring
au_clear_ring:
    pushad
    xor ebx, ebx
.p:
    mov edi, [au_pages + ebx * 4]
    mov ecx, AU_PAGE / 4
    xor eax, eax
    cld
    rep stosd
    inc ebx
    cmp ebx, AU_NBUF
    jb .p
    popad
    ret

; Reads the driver's position into au_done and clears the pages played
; since the last call. Keeps registers.
au_poll:
    pushad
    mov edx, DRV_DONE
    call au_call
    cmp eax, [au_sub]
    jbe .ok
    mov [au_sub], eax               ; it ran past what we gave it (silence)
    mov dword [au_fill], 0
.ok:
    mov [au_done], eax
.z:
    mov ebx, [au_zdone]
    cmp ebx, [au_done]
    jae .r
    and ebx, AU_NBUF - 1
    mov edi, [au_pages + ebx * 4]
    mov ecx, AU_PAGE / 4
    xor eax, eax
    cld
    rep stosd
    inc dword [au_zdone]
    jmp .z
.r:
    popad
    ret

; Waits until a page is free to fill (fewer than AU_NBUF queued), or the
; device stopped moving for two seconds. -> CF on that timeout.
au_wait_room:
    push eax
    push edx
    mov edx, [ticks]
    add edx, 200
.w:
    call au_poll
    mov eax, [au_sub]
    sub eax, [au_done]
    cmp eax, AU_NBUF
    jb .ok
    cmp [ticks], edx
    jae .bad
    pushad
    call proc_idle
    popad
    jmp .w
.ok:
    pop edx
    pop eax
    clc
    ret
.bad:
    pop edx
    pop eax
    stc
    ret

; The current page is full (or the stream ends): give it to the driver.
au_submit:
    pushad
    mov ebx, [au_sub]
    and ebx, AU_NBUF - 1
    mov eax, [au_pages + ebx * 4]
    mov ecx, [au_fill]
    mov edx, DRV_SUBMIT
    call au_call
    inc dword [au_sub]
    mov dword [au_fill], 0
    popad
    ret

; esi = the program's samples, ecx = bytes -> eax = bytes taken (whole
; frames), or -1 when the device stalls
au_write:
    pushad
    cmp byte [au_isopen], 0
    je .bad
    xor eax, eax
    mov edx, ecx
    mov ecx, [au_infs]
    push edx
    mov eax, edx
    xor edx, edx
    div ecx
    pop edx
    mov ebp, eax                    ; whole frames
    imul eax, ecx
    mov [au_took], eax
.frame:
    test ebp, ebp
    jz .done
    cmp dword [au_fill], 0
    jne .room
    call au_wait_room
    jc .bad
.room:
    call au_frame                   ; eax = left | right << 16, esi advanced
    mov ebx, [au_sub]
    and ebx, AU_NBUF - 1
    mov edi, [au_pages + ebx * 4]
    add edi, [au_fill]
    mov [edi], eax
    add dword [au_fill], AU_FRAME
    add dword [au_total], AU_FRAME
    cmp dword [au_fill], AU_PAGE
    jb .nx
    call au_submit
.nx:
    dec ebp
    jmp .frame
.done:
    popad
    mov eax, [au_took]
    ret
.bad:
    popad
    or eax, -1
    ret

; esi = one of the program's frames -> eax = left | right << 16 as
; signed 16-bit samples; esi moves past it
au_frame:
    push ebx
    cmp dword [au_inbits], 8
    je .eight
    movzx eax, word [esi]
    add esi, 2
    mov ebx, eax
    cmp dword [au_inch], 1
    je .pair
    movzx ebx, word [esi]
    add esi, 2
    jmp .pair
.eight:                             ; unsigned 8-bit: 128 is silence
    movzx eax, byte [esi]
    inc esi
    xor al, 0x80
    shl eax, 8
    mov ebx, eax
    cmp dword [au_inch], 1
    je .pair
    movzx ebx, byte [esi]
    inc esi
    xor bl, 0x80
    shl ebx, 8
.pair:
    shl ebx, 16
    or eax, ebx
    pop ebx
    ret

; Plays what is left, waits for it, and stops the device. -> CF if it
; stalled.
au_drain:
    pushad
    cmp byte [au_isopen], 0
    je .ok
    cmp dword [au_fill], 0
    je .wait
    call au_wait_room               ; (the page being filled is not queued)
    mov ebx, [au_sub]
    and ebx, AU_NBUF - 1
    mov edi, [au_pages + ebx * 4]   ; silence after the end
    add edi, [au_fill]
    mov ecx, AU_PAGE
    sub ecx, [au_fill]
    xor eax, eax
    cld
    rep stosb
    call au_submit
.wait:
    mov edx, [ticks]                ; a full ring at 8 kHz is about a second
    add edx, 300
.w:
    call au_poll
    mov eax, [au_done]
    cmp eax, [au_sub]
    jae .end
    cmp [ticks], edx
    jae .stall
    pushad
    call proc_idle
    popad
    jmp .w
.end:
    call au_stop_play
.ok:
    popad
    clc
    ret
.stall:
    call au_stop_play
    popad
    stc
    ret

au_stop_play:
    push edx
    cmp byte [au_state], 1
    jne .r
    mov edx, DRV_STOP
    call au_call
.r:
    pop edx
    ret

au_close:
    call au_stop_play
    mov byte [au_isopen], 0
    ret

; ---------- recording ----------

; edi = buffer, ecx = bytes -> eax = bytes recorded (16-bit stereo at the
; open rate), or -1 (not open, no input, or nothing came)
au_record:
    pushad
    cmp byte [au_isopen], 0
    je .bad
    and ecx, ~(AU_FRAME - 1)
    jz .bad
    mov [au_rwant], ecx
    mov [au_rbuf], edi
    mov dword [au_rgot], 0
    mov dword [au_rseq], 0
    mov eax, [au_rate]
    mov esi, au_rpages
    mov ecx, AU_PAGE
    mov edx, DRV_RECSTART
    call au_call
    jc .bad
    ; time allowed: the bytes at the rate, and two seconds more
    mov eax, [au_rwant]
    mov ecx, 100
    mul ecx
    mov ecx, [au_rate]
    shl ecx, 2
    div ecx
    add eax, 200
    add eax, [ticks]
    mov [au_rend], eax
.w:
    mov edx, DRV_RECDONE
    call au_call
.copy:
    cmp [au_rseq], eax
    jae .more
    push eax
    mov ebx, [au_rseq]
    and ebx, AU_NBUF - 1
    mov esi, [au_rpages + ebx * 4]
    mov ecx, [au_rwant]
    sub ecx, [au_rgot]
    cmp ecx, AU_PAGE
    jbe .n
    mov ecx, AU_PAGE
.n:
    mov edi, [au_rbuf]
    add edi, [au_rgot]
    add [au_rgot], ecx
    cld
    rep movsb
    inc dword [au_rseq]
    pop eax
    mov ecx, [au_rgot]
    cmp ecx, [au_rwant]
    jae .end
    jmp .copy
.more:
    mov ecx, [ticks]
    cmp ecx, [au_rend]
    jae .end
    pushad
    call proc_idle
    popad
    jmp .w
.end:
    mov edx, DRV_RECSTOP
    call au_call
    mov eax, [au_rgot]
    test eax, eax
    jz .bad
    mov [esp + 28], eax
    popad
    ret
.bad:
    popad
    or eax, -1
    ret

; ---------- SYS_AUDIO ----------

sys_audio:
    cmp ebx, AU_OPS
    jae .bad
    jmp [au_sysops + ebx * 4]
.bad:
    or eax, -1
    ret

au_sysops:
    dd au_op_info, au_op_open, au_op_write, au_op_drain, au_op_close
    dd au_op_getvol, au_op_setvol, au_op_record, au_op_pos

; ebx = operation, ecx/edx = arguments -> CF if a ring-3 pointer is bad
audio_uargs:
    pushad
    cmp ebx, AU_INFO
    je .info
    cmp ebx, AU_WRITE
    je .cd
    cmp ebx, AU_RECORD
    jne .ok
.cd:
    mov esi, ecx
    mov ecx, edx
    jmp .range
.info:
    mov esi, ecx
    mov ecx, 16
.range:
    call ua_range
    jc .bad
.ok:
    popad
    clc
    ret
.bad:
    popad
    stc
    ret

au_pid:
    mov eax, [proc_cur]
    mov eax, [eax + PCB_PID]
    ret

; CF clear when the caller may use the open device (it opened it); a
; device left open by a program that ended is closed here
au_mine:
    cmp byte [au_isopen], 0
    je .no
    push eax
    call au_pid
    cmp eax, [au_owner]
    pop eax
    jne .no
    clc
    ret
.no:
    stc
    ret

au_op_info:
    mov edi, ecx
    call au_probe
    jc .none
    mov esi, [au_drv]
    mov esi, [esi + DRV_NAME]
    xor ecx, ecx
.n:
    mov al, [esi + ecx]
    mov [edi + ecx], al
    inc ecx
    test al, al
    jnz .n
    xor eax, eax
    mov ebx, [au_drv]
    cmp ebx, hda_ops
    jne .rec
    cmp dword [hd_adc], 0
    je .flags
.rec:
    or eax, 1                       ; can record
.flags:
    mov [edi + 8], eax
    mov eax, [au_rate]
    mov [edi + 12], eax
    xor eax, eax
    ret
.none:
    or eax, -1
    ret

au_op_open:
    cmp byte [au_isopen], 0
    je .free
    push ebx
    push edi
    mov ebx, [au_owner]
    call proc_find
    test edi, edi
    jz .gone
    cmp dword [edi + PCB_STATE], P_ZOMBIE
    je .gone
    pop edi
    pop ebx
    call au_pid
    cmp eax, [au_owner]
    je .free                        ; reopening our own
    mov eax, -2
    ret
.gone:
    pop edi
    pop ebx
    call au_close
.free:
    mov eax, ecx
    call au_open
    jc .bad
    call au_pid
    mov [au_owner], eax
    xor eax, eax
    ret
.bad:
    or eax, -1
    ret

au_op_write:
    call au_mine
    jc .bad
    mov esi, ecx
    mov ecx, edx
    jmp au_write
.bad:
    or eax, -1
    ret

au_op_drain:
    call au_mine
    jc .bad
    call au_drain
    sbb eax, eax
    ret
.bad:
    or eax, -1
    ret

au_op_close:
    call au_mine
    jc .bad
    call au_close
    xor eax, eax
    ret
.bad:
    or eax, -1
    ret

au_op_getvol:
    call au_probe
    jc .bad
    mov edx, DRV_GETVOL
    call au_call
    jc .bad
    ret
.bad:
    or eax, -1
    ret

au_op_setvol:
    call au_probe
    jc .bad
    call au_setvol_k
    jc .bad
    xor eax, eax
    ret
.bad:
    or eax, -1
    ret

au_op_record:
    call au_mine
    jc .bad
    mov edi, ecx
    mov ecx, edx
    jmp au_record
.bad:
    or eax, -1
    ret

au_op_pos:
    call au_mine
    jc .bad
    call au_poll
    mov eax, [au_done]
    shl eax, AU_PAGE_SHIFT
    cmp eax, [au_total]
    jbe .r
    mov eax, [au_total]
.r:
    ret
.bad:
    or eax, -1
    ret

; ---------- shell ----------

; audio — which device, and what the driver found
cmd_audio_run:
    call au_probe
    jc .none
    mov esi, au_m_dev
    call puts
    mov esi, [au_drv]
    mov esi, [esi + DRV_NAME]
    call puts
    cmp dword [au_drv], hda_ops
    jne .nl
    mov esi, au_m_codec
    call puts
    mov eax, [hd_codec]
    call au_putn
    mov esi, au_m_dac
    call puts
    mov eax, [hd_dac]
    call au_putn
    mov esi, au_m_pin
    call puts
    mov eax, [hd_pin]
    call au_putn
    mov esi, au_m_adc
    call puts
    mov eax, [hd_adc]
    call au_putn
.nl:
    mov al, 10
    jmp putc
.none:
    mov esi, au_m_none
    jmp puts

au_putn:
    call itoa
    mov esi, num_buf
    jmp puts

; audiotest — plays a quarter of a second, checks the device took it at
; the right pace, sets and reads back the volume and mute, records a
; little, and prints audio: PASS <driver> or audio: FAIL <step>
AT_BYTES    equ 6 * AU_PAGE         ; 6144 frames: 0.28 s at 22050 Hz
cmd_audiotest_run:
    call au_probe
    jc cmd_audio_run.none
    mov byte [au_why], 'o'
    mov eax, 22050
    mov edx, 2 | (16 << 8)
    call au_open
    jc .fail
    mov edi, [au_pages + AU_NBUF * 2 * 4] ; the scratch page: a square wave
    xor ecx, ecx
.sq:
    mov eax, ecx
    xor edx, edx
    push ecx
    mov ecx, 22                     ; about 1 kHz
    div ecx
    pop ecx
    mov eax, 0x20002000
    cmp edx, 11
    jb .hi
    mov eax, 0xE000E000
.hi:
    mov [edi + ecx * 4], eax
    inc ecx
    cmp ecx, AU_PAGE / 4
    jb .sq
    mov eax, [ticks]
    mov [au_t0], eax
    mov byte [au_why], 'w'
    mov ebx, AT_BYTES / AU_PAGE
.wr:
    mov esi, [au_pages + AU_NBUF * 2 * 4]
    mov ecx, AU_PAGE
    push ebx
    call au_write
    pop ebx
    cmp eax, AU_PAGE
    jne .fail
    dec ebx
    jnz .wr
    mov byte [au_why], 'd'
    call au_drain
    jc .fail
    mov byte [au_why], 't'          ; 0.28 s of sound took at least 0.2 s
    mov eax, [ticks]
    sub eax, [au_t0]
    cmp eax, 20
    jb .fail
    mov byte [au_why], 'p'
    mov eax, [au_done]
    shl eax, AU_PAGE_SHIFT
    cmp eax, AT_BYTES
    jb .fail
    ; volume: 50% both sides, read back within a step; then mute
    mov byte [au_why], 'v'
    mov ecx, AU_CTL_MASTER
    mov edx, 50 | (50 << 8)
    call au_setvol_k
    jc .fail
    mov ecx, AU_CTL_MASTER
    mov edx, DRV_GETVOL
    call au_call
    jc .fail
    mov ebx, eax
    movzx eax, bl
    call .near50
    jc .fail
    movzx eax, bh
    call .near50
    jc .fail
    test ebx, 0x10000
    jnz .fail
    mov byte [au_why], 'm'
    mov ecx, AU_CTL_MASTER
    mov edx, 50 | (50 << 8) | 0x10000
    call au_setvol_k
    mov ecx, AU_CTL_MASTER
    mov edx, DRV_GETVOL
    call au_call
    test eax, 0x10000
    jz .fail
    mov ecx, AU_CTL_MASTER
    mov edx, 100 | (100 << 8)
    call au_setvol_k
    ; recording, where the device has an input
    mov byte [au_why], 'r'
    cmp dword [au_drv], hda_ops
    jne .rec
    cmp dword [hd_adc], 0
    je .pass
.rec:
    mov edi, [au_pages + AU_NBUF * 2 * 4]
    mov ecx, AU_PAGE
    call au_record
    cmp eax, AU_PAGE
    jne .fail
.pass:
    call au_close
    mov esi, au_m_pass
    call puts
    mov esi, [au_drv]
    mov esi, [esi + DRV_NAME]
    call puts
    mov al, 10
    jmp putc
.fail:
    call au_close
    mov esi, au_m_fail
    call puts
    mov al, [au_why]
    call putc
    mov al, 10
    jmp putc
; eax = 0..100 -> CF unless 45..55
.near50:
    cmp eax, 45
    jb .far
    cmp eax, 55
    ja .far
    clc
    ret
.far:
    stc
    ret

; ecx = control, edx = value -> the driver's setvol, CF
au_setvol_k:
    push eax
    push edx
    mov eax, [au_drv]
    call [eax + DRV_SETVOL]
    pop edx
    pop eax
    ret

au_m_dev    db 'audio: ', 0
au_m_none   db 'audio: no device', 10, 0
au_m_codec  db ' codec ', 0
au_m_dac    db ', dac ', 0
au_m_pin    db ', pin ', 0
au_m_adc    db ', adc ', 0
au_m_pass   db 'audio: PASS ', 0
au_m_fail   db 'audio: FAIL ', 0
align 4
au_rates    dd 48000, 44100, 32000, 24000, 22050, 16000, 11025, 8000, 0
au_state    db 0                    ; 0 not probed, 1 a device, 2 none
au_isopen   db 0
au_why      db 0
align 4
au_drv      dd 0
au_owner    dd 0
au_pages    times AU_NBUF dd 0      ; the play ring
au_rpages   times AU_NBUF dd 0      ; the record ring
au_scratch  dd 0                    ; (au_pages + 2 * AU_NBUF)
au_rate     dd 0
au_inch     dd 0
au_inbits   dd 0
au_infs     dd 0
au_sub      dd 0                    ; pages given to the driver
au_done     dd 0                    ; pages it has played
au_zdone    dd 0                    ; pages cleared after playing
au_fill     dd 0                    ; bytes in the page being filled
au_total    dd 0                    ; device bytes written since opening
au_took     dd 0
au_t0       dd 0
au_rwant    dd 0
au_rgot     dd 0
au_rbuf     dd 0
au_rseq     dd 0
au_rend     dd 0
