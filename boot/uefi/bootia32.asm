; Squirrel-OS/2 UEFI loader for 32-bit firmware: \EFI\BOOT\BOOTIA32.EFI (H.1)
; Original code, written from the UEFI 2.10 and PE/COFF specifications.
;
; The PE32 twin of bootx64.asm, for PCs with 32-bit UEFI (some tablets
; and early UEFI machines). Same steps: GOP, memory map, check and if
; needed move itself out of the kernel's areas, ExitBootServices, paging
; off, then handoff32.inc. EFI calls use the IA32 convention (cdecl,
; arguments on the stack). All data is reached through ebx = the
; image's run-time base, since UEFI may load it anywhere and there is
; no relocation table.
; Build: nasm -f bin -DOS_IMG='"build/os.img"' bootia32.asm -o BOOTIA32.EFI

BITS 32
ORG 0

SECT_ALIGN  equ 0x1000
MAP_BUF     equ 0x8000
MOVE_STACK  equ 0x10000

%define V(x) ebx + (x)                  ; a loader variable, through the base

mz:
    db 'MZ'
    times 0x3C-($-mz) db 0
    dd pe
pe:
    db 'PE', 0, 0
    dw 0x014C                           ; i386
    dw 1
    dd 0, 0, 0
    dw opt_end - opt
    dw 0x0102                           ; executable, 32-bit
opt:
    dw 0x010B                           ; PE32
    db 0, 0
    dd image_end - text
    dd 0, 0
    dd entry
    dd text                             ; base of code
    dd text                             ; base of data
    dd 0x00400000                       ; preferred base: the code does not need it
    dd SECT_ALIGN, SECT_ALIGN
    dw 0, 0, 0, 0, 0, 0
    dd 0
    dd image_end
    dd text
    dd 0
    dw 10                               ; EFI application
    dw 0
    dd 0x10000, 0x1000, 0, 0
    dd 0
    dd 16
    times 16 dq 0
opt_end:
    db '.text', 0, 0, 0
    dd image_end - text
    dd text
    dd image_end - text
    dd text
    dd 0, 0
    dw 0, 0
    dd 0xE0000060
    times SECT_ALIGN-($-$$) db 0

text:
entry:
    push ebp
    mov ebp, esp
    push ebx
    push esi
    push edi
    call .b
.b:
    pop ebx
    sub ebx, .b                         ; ebx = run-time base
    mov eax, [ebp+8]
    mov [V(image_handle)], eax
    mov eax, [ebp+12]
    mov [V(systab)], eax
    mov eax, [eax+60]
    mov [V(bootsvc)], eax
    lea eax, [V(m_hello)]
    call print
    ; the loader and its stack must not be where the kernel goes
    lea eax, [V(mz)]
    lea edx, [V(image_end)]
    call clash
    jc .move
    lea eax, [esp-0x10000]
    lea edx, [esp+0x100]
    call clash
    jc .move
.placed:
    ; GOP
    lea eax, [V(gop)]
    push eax
    push 0
    lea eax, [V(gop_guid)]
    push eax
    mov eax, [V(bootsvc)]
    call [eax+172]                      ; LocateProtocol
    add esp, 12
    test eax, eax
    jnz .nogop
    mov ecx, [V(gop)]
    mov eax, [ecx+12]                   ; Mode
    push dword [eax+4]                  ; Mode->Mode
    push ecx
    call [ecx+4]                        ; SetMode (see bootx64.asm)
    add esp, 8
    mov dx, 0x3DA
    in al, dx
    mov dx, 0x3C0
    mov al, 0x20
    out dx, al
    mov eax, [V(gop)]
    mov eax, [eax+12]                   ; Mode
    cmp dword [eax+20], 0               ; FrameBufferBase, high half
    jne .nogop
    mov ecx, [eax+16]
    mov [V(gop_fb)], ecx
    mov ecx, [eax+8]                    ; Info
    mov eax, [ecx+12]
    cmp eax, 1
    ja .nogop
    mov [V(gop_fmt)], eax
    mov eax, [ecx+4]
    mov [V(gop_w)], eax
    mov eax, [ecx+8]
    mov [V(gop_h)], eax
    mov eax, [ecx+32]
    shl eax, 2
    mov [V(gop_pitch)], eax
    mov dword [V(gop_ok)], 1
    jmp .map
.nogop:
    lea eax, [V(m_nogop)]
    call print
.map:
    mov dword [V(tries)], 3
.again:
    mov dword [V(map_size)], MAP_BUF
    lea eax, [V(desc_ver)]
    push eax
    lea eax, [V(desc_size)]
    push eax
    lea eax, [V(map_key)]
    push eax
    lea eax, [V(map_buf)]
    push eax
    lea eax, [V(map_size)]
    push eax
    mov eax, [V(bootsvc)]
    call [eax+40]                       ; GetMemoryMap
    add esp, 20
    test eax, eax
    jnz .maperr
    call check_map
    jc .used
    push dword [V(map_key)]
    push dword [V(image_handle)]
    mov eax, [V(bootsvc)]
    call [eax+128]                      ; ExitBootServices
    add esp, 8
    test eax, eax
    jz .exited
    dec dword [V(tries)]
    jnz .again
.maperr:
    lea eax, [V(m_maperr)]
    jmp .fail
.used:
    lea eax, [V(m_used)]
    jmp .fail
.clash:
    lea eax, [V(m_clash)]
.fail:
    call print
    mov eax, 0x80000001                 ; EFI_LOAD_ERROR
    lea esp, [ebp-12]
    pop edi
    pop esi
    pop ebx
    pop ebp
    ret

.move:
    cmp byte [V(moved)], 0
    jne .clash
    mov dword [V(tries)], 8
.alloc:
    mov dword [V(newbase)], 0xFFFFFFFF  ; AllocateMaxAddress: below 4 GB
    mov dword [V(newbase)+4], 0
    lea eax, [V(newbase)]
    push eax
    push (image_end - mz + MOVE_STACK) >> 12
    push 2                              ; EfiLoaderData
    push 1
    mov eax, [V(bootsvc)]
    call [eax+32]                       ; AllocatePages
    add esp, 16
    test eax, eax
    jnz .clash
    mov eax, [V(newbase)]
    lea edx, [eax + image_end + MOVE_STACK]
    call clash
    jnc .copy
    dec dword [V(tries)]
    jnz .alloc
    jmp .clash
.copy:
    mov byte [V(moved)], 1
    lea esi, [V(mz)]
    mov edi, [V(newbase)]
    mov ecx, image_end
    cld
    rep movsb
    mov eax, [V(newbase)]
    lea esp, [eax + image_end + MOVE_STACK - 64]
    add eax, .placed
    mov ebx, [V(newbase)]               ; the new base
    jmp eax

.exited:
    cli
    mov eax, cr0
    and eax, 0x7FFFFFFF                 ; paging off (the firmware maps 1:1)
    mov cr0, eax
    xor eax, eax
    mov cr4, eax
    lea eax, [V(gdt32)]
    mov [V(gdt32_base)], eax
    lgdt [V(gdt32_desc)]                ; flat segments of our own
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    lea eax, [V(handoff32)]
    push dword 0x08
    push eax
    retf

; eax = UTF-16 string on the console (ebx = base)
print:
    push eax
    mov eax, [V(systab)]
    mov eax, [eax+44]                   ; ConOut
    push eax
    call [eax+4]                        ; OutputString
    add esp, 8
    ret

; [eax, edx) -> CF if it overlaps the kernel's areas (or wraps past 4 GB)
clash:
    cmp edx, eax
    jb .yes
    cmp eax, KMEM_LO_END
    jae .hi
    cmp edx, KMEM_LO_START
    ja .yes
.hi:
    cmp eax, KMEM_HI_END
    jae .no
    cmp edx, KMEM_HI_START
    ja .yes
.no:
    clc
    ret
.yes:
    stc
    ret

; CF if a map entry that overlaps the kernel's areas is not free after exit
check_map:
    push esi
    lea esi, [V(map_buf)]
    mov ecx, [V(map_size)]
.d:
    cmp ecx, [V(desc_size)]
    jb .ok
    mov eax, [esi]
    cmp eax, 4
    jbe .t
    cmp eax, 7
    je .next
    jmp .chk
.t:
    test eax, eax
    jnz .next
.chk:
    cmp dword [esi+12], 0
    jne .next                           ; above 4 GB
    mov eax, [esi+8]
    cmp eax, KMEM_HI_END
    jae .next
    mov edx, [esi+24]
    shl edx, 12
    add edx, eax
    push ecx
    call clash
    pop ecx
    jc .bad
.next:
    add esi, [V(desc_size)]
    sub ecx, [V(desc_size)]
    jmp .d
.ok:
    pop esi
    clc
    ret
.bad:
    pop esi
    stc
    ret

%include "handoff32.inc"

align 8
gdt32:
    dq 0
    dq 0x00CF9A000000FFFF
    dq 0x00CF92000000FFFF
gdt32_desc:
    dw gdt32_desc - gdt32 - 1
gdt32_base:
    dd 0                                ; set at run time
gop_guid:
    dd 0x9042A9DE
    dw 0x23DC, 0x4A38
    db 0x96, 0xFB, 0x7A, 0xDE, 0xD0, 0x80, 0x51, 0x6A
align 8
newbase dq 0
image_handle dd 0
systab dd 0
bootsvc dd 0
gop dd 0
tries dd 0
moved db 0
m_hello dw __utf16__('Squirrel-OS/2 UEFI loader (IA32): starting the kernel'), 13, 10, 0
m_nogop dw __utf16__('No usable GOP framebuffer: the screen stays blank, the kernel runs.'), 13, 10, 0
m_maperr dw __utf16__('Squirrel-OS/2: cannot read the memory map.'), 13, 10, 0
m_used dw __utf16__('Squirrel-OS/2: memory the kernel needs (below 640 KB, 1-2 MB) is reserved by the firmware.'), 13, 10, 0
m_clash dw __utf16__('Squirrel-OS/2: no room for this loader outside the kernel areas.'), 13, 10, 0
align 16
map_buf times MAP_BUF db 0
align 16
payload:
    incbin OS_IMG
payload_end:
    times (SECT_ALIGN - ($-$$) % SECT_ALIGN) % SECT_ALIGN db 0
image_end:
