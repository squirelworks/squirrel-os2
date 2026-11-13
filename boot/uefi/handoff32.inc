; Squirrel-OS/2 UEFI loader — the 32-bit hand-off shared by BOOTX64.EFI
; and BOOTIA32.EFI (H.1). Original code.
;
; Entered after ExitBootServices with interrupts off, paging off, flat
; 32-bit code and data segments. Uses only the loader's own data (found
; through ebp = the image's run-time base, since UEFI may load the image
; anywhere) and leaves the machine as the BIOS path's stage2 does just
; before it jumps to pm:
;   - the low kernel image at 0x8000, the high image at KHIGH_BASE,
;   - the memory map as E820 entries in E820_BUF and e820_count,
;   - ld_drive = 80h, UEFI_INFO describing the GOP framebuffer,
;   - the kernel's GDT loaded, then a far jump to 08h:pm.
; The kernel's hand-off header (uefi_hdr in kernel/pm.asm) gives the
; addresses; the loader does not hard-code them.

E820_BUF        equ 0x1000
E820_MAX        equ 32
UEFI_INFO       equ 0x1300
UEFI_MAGIC      equ 0x46453253          ; 'S2EF'

BITS 32
handoff32:
    call .base
.base:
    pop ebp
    sub ebp, .base                      ; ebp = run-time address of RVA 0
    ; the kernel's hand-off header, in the low image
    lea esi, [ebp+payload+512]
    lea ecx, [ebp+payload+512+0x18000]
.find:
    cmp esi, ecx
    jae .halt
    cmp dword [esi], 'S2UE'
    jne .fnext
    mov eax, [esi+4]                    ; pm must be in the low image
    cmp eax, 0x8000
    jb .fnext
    cmp eax, 0x20000
    jb .found
.fnext:
    inc esi
    jmp .find
.found:
    mov eax, [esi+4]
    mov [ebp+k_pm], eax
    mov eax, [esi+8]
    mov [ebp+k_gdtdesc], eax
    mov eax, [esi+12]
    mov [ebp+k_drive], eax
    mov eax, [esi+16]
    mov [ebp+k_e820n], eax
    mov eax, [esi+20]
    mov [ebp+k_size], eax
    mov eax, [esi+24]
    mov [ebp+k_high], eax
    ; low image -> 0x8000, high image -> KHIGH_BASE
    lea esi, [ebp+payload+512]
    mov edi, 0x8000
    mov ecx, [ebp+k_size]
    cld
    rep movsb
    mov edi, [ebp+k_high]
    lea ecx, [ebp+payload_end]
    sub ecx, esi
    rep movsb
    ; UEFI memory map -> E820 entries (merging neighbours of one type)
    mov edi, E820_BUF
    xor ebx, ebx                        ; entries written
    lea esi, [ebp+map_buf]
    mov ecx, [ebp+map_size]
.desc:
    cmp ecx, [ebp+desc_size]
    jb .mapped
    push ecx
    mov eax, [esi]                      ; EFI memory type -> E820 type
    mov edx, 1
    cmp eax, 4
    jbe .t                              ; loader/boot-services code and data
    cmp eax, 7                          ; conventional
    je .t
    mov edx, 3
    cmp eax, 9                          ; ACPI reclaim
    je .t
    mov edx, 4
    cmp eax, 10                         ; ACPI NVS
    je .t
    mov edx, 5
    cmp eax, 8                          ; unusable
    je .t
    mov edx, 2                          ; everything else: reserved
.t:
    cmp eax, 0                          ; EfiReservedMemoryType
    jne .t2
    mov edx, 2
.t2:
    ; length = pages << 12, 64-bit
    mov eax, [esi+24]
    mov ecx, [esi+28]
    shld ecx, eax, 12
    shl eax, 12
    ; can it extend the previous entry? same type and base = prev end
    test ebx, ebx
    jz .new
    cmp [edi-24+16], edx
    jne .new
    push eax
    push ecx
    mov eax, [edi-24]
    mov ecx, [edi-24+4]
    add eax, [edi-24+8]
    adc ecx, [edi-24+12]
    cmp eax, [esi+8]
    jne .nomerge
    cmp ecx, [esi+12]
    jne .nomerge
    pop ecx
    pop eax
    add [edi-24+8], eax
    adc [edi-24+12], ecx
    jmp .dnext
.nomerge:
    pop ecx
    pop eax
.new:
    cmp ebx, E820_MAX
    jae .dnext
    push eax
    mov eax, [esi+8]
    mov [edi], eax
    mov eax, [esi+12]
    mov [edi+4], eax
    pop eax
    mov [edi+8], eax
    mov [edi+12], ecx
    mov [edi+16], edx
    mov dword [edi+20], 1
    add edi, 24
    inc ebx
.dnext:
    pop ecx
    add esi, [ebp+desc_size]
    sub ecx, [ebp+desc_size]
    jmp .desc
.mapped:
    mov eax, [ebp+k_e820n]
    mov [eax], bx                       ; e820_count is a word
    mov eax, [ebp+k_drive]
    mov byte [eax], 0x80                ; "the first hard disk"
    ; the framebuffer for the GOP console (drivers/gopcon.asm)
    mov dword [UEFI_INFO], 0
    cmp dword [ebp+gop_ok], 0
    je .nogop
    mov eax, [ebp+gop_fb]
    mov [UEFI_INFO+4], eax
    mov eax, [ebp+gop_w]
    mov [UEFI_INFO+8], eax
    mov eax, [ebp+gop_h]
    mov [UEFI_INFO+12], eax
    mov eax, [ebp+gop_pitch]
    mov [UEFI_INFO+16], eax
    mov eax, [ebp+gop_fmt]
    mov [UEFI_INFO+20], eax
    mov dword [UEFI_INFO], UEFI_MAGIC
.nogop:
    call legacy_irqs
    call legacy_kbc
    ; the kernel's GDT, then pm with its code selector
    mov eax, [ebp+k_gdtdesc]
    lgdt [eax]
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    push dword 0x08
    push dword [ebp+k_pm]
    retf
.halt:
    hlt
    jmp .halt

; The kernel drives the 8259 PIC, as on a BIOS boot. UEFI firmware may
; leave the local APIC with LINT0 masked (then no PIC interrupt reaches
; the CPU: SquirrelBIOS 2.1.0) and I/O APIC routes or the APIC timer on.
; Put back what a BIOS leaves: LINT0 ExtINT (virtual wire), LINT1 NMI,
; APIC timer masked, every I/O APIC redirection entry masked.
legacy_irqs:
    mov eax, 1
    cpuid
    test edx, 1 << 9                    ; a local APIC?
    jz .r
    mov ecx, 0x1B                       ; IA32_APIC_BASE
    rdmsr
    test eax, 1 << 11                   ; enabled?
    jz .ioapic
    and eax, 0xFFFFF000
    mov ebx, eax
    or dword [ebx+0xF0], 0x1FF          ; software enable, spurious vector FFh
    mov dword [ebx+0x320], 0x10000      ; timer: masked
    mov dword [ebx+0x350], 0x700        ; LINT0: ExtINT
    mov dword [ebx+0x360], 0x400        ; LINT1: NMI
    mov dword [ebx+0x370], 0x10000      ; error: masked
    mov dword [ebx+0xB0], 0             ; EOI anything in service
.ioapic:
    mov ebx, 0xFEC00000                 ; the standard I/O APIC address
    mov dword [ebx], 1                  ; version register
    mov eax, [ebx+0x10]
    cmp eax, 0xFFFFFFFF
    je .r                               ; none there
    shr eax, 16
    and eax, 0xFF                       ; highest redirection entry
    mov ecx, eax
.mask:
    lea eax, [0x10+ecx*2]
    mov [ebx], eax
    or dword [ebx+0x10], 0x10000
    dec ecx
    jns .mask
.r:
    ret

; The keyboard controller as a BIOS leaves it: scan-code translation to
; set 1 and the IRQ 1 output on (SquirrelBIOS 2.1.0 turns translation
; off, so the kernel would get set-2 codes). Skipped if there is no 8042.
legacy_kbc:
    in al, 0x64
    cmp al, 0xFF
    je .r
    call .wait_in
    mov al, 0x20                        ; read the command byte
    out 0x64, al
    mov ecx, 100000
.out:
    in al, 0x64
    test al, 1
    jnz .got
    loop .out
    ret
.got:
    in al, 0x60
    or al, 0x41                         ; translation, keyboard interrupt
    and al, ~0x10                       ; keyboard clock enabled
    mov ah, al
    call .wait_in
    mov al, 0x60                        ; write the command byte
    out 0x64, al
    call .wait_in
    mov al, ah
    out 0x60, al
.r:
    ret
.wait_in:
    mov ecx, 100000
.w:
    in al, 0x64
    test al, 2
    jz .ok
    loop .w
.ok:
    ret

; Range check shared by both loaders' native code is in their own width;
; these are the kernel's fixed areas the copy above writes.
KMEM_LO_START   equ 0x1000
KMEM_LO_END     equ 0xA0000
KMEM_HI_START   equ 0x100000
KMEM_HI_END     equ 0x200000

align 4
k_pm        dd 0
k_gdtdesc   dd 0
k_drive     dd 0
k_e820n     dd 0
k_size      dd 0
k_high      dd 0
gop_ok      dd 0
gop_fb      dd 0
gop_w       dd 0
gop_h       dd 0
gop_pitch   dd 0
gop_fmt     dd 0
map_size    dq 0
map_key     dq 0
desc_size   dq 0
desc_ver    dq 0
