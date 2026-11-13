; Squirrel-OS/2 UEFI loader for x86-64 firmware: \EFI\BOOT\BOOTX64.EFI (H.1)
; Original code, written from the UEFI 2.10 and PE/COFF specifications.
;
; A PE32+ EFI application assembled by NASM as a flat file: the headers
; are built below, the image is laid out on disk as in memory (one
; section at RVA 0x1000), and all code is position-independent because
; the firmware may load it anywhere. The whole boot disk image (os.img:
; boot sector, low kernel, high kernel) is inside it (`payload`), so the
; ESP needs nothing else.
;
; If the firmware loaded it where the kernel must go (below 640 KB or at
; 1-2 MB, as SquirrelBIOS does), it first copies itself above them.
; It finds the GOP framebuffer, reads the memory map, checks that the
; kernel's fixed areas are free RAM and that the loader itself is not in
; them, calls ExitBootServices, drops from long mode to 32-bit protected
; mode with paging off, and runs handoff32.inc, which copies the kernel
; and enters it as the BIOS path does.
; Build: nasm -f bin -DOS_IMG='"build/os.img"' bootx64.asm -o BOOTX64.EFI

BITS 64
DEFAULT REL
ORG 0

SECT_ALIGN  equ 0x1000
MAP_BUF     equ 0x8000                  ; bytes of memory map buffer
MOVE_STACK  equ 0x10000                 ; stack after the loader moves itself

; ---------- DOS stub and PE32+ headers ----------
mz:
    db 'MZ'
    times 0x3C-($-mz) db 0
    dd pe
pe:
    db 'PE', 0, 0
    dw 0x8664                           ; x86-64
    dw 1                                ; one section
    dd 0, 0, 0
    dw opt_end - opt                    ; optional header size
    dw 0x0022                           ; executable, large-address aware
opt:
    dw 0x020B                           ; PE32+
    db 0, 0
    dd image_end - text                 ; size of code
    dd 0, 0
    dd entry                            ; entry point (RVA)
    dd text                             ; base of code
    dq 0x10000000                       ; preferred base: the code relocates itself
    dd SECT_ALIGN, SECT_ALIGN           ; section and file alignment
    dw 0, 0, 0, 0, 0, 0
    dd 0
    dd image_end                        ; size of image
    dd text                             ; size of headers
    dd 0                                ; checksum
    dw 10                               ; EFI application
    dw 0
    dq 0x10000, 0x1000, 0, 0
    dd 0
    dd 16                               ; data directories, all empty (no relocations needed)
    times 16 dq 0
opt_end:
    db '.text', 0, 0, 0
    dd image_end - text                 ; virtual size
    dd text                             ; RVA
    dd image_end - text                 ; size on disk
    dd text                             ; file offset
    dd 0, 0
    dw 0, 0
    dd 0xE0000060                       ; code, data, read, write, execute
    times SECT_ALIGN-($-$$) db 0

; ---------- loader ----------
text:
entry:
    push rbp
    mov rbp, rsp
    push rbx
    push r12
    and rsp, -16
    sub rsp, 64                         ; shadow space and a fifth argument
    mov [image_handle], rcx
    mov [systab], rdx
    mov rax, [rdx+96]
    mov [bootsvc], rax
    lea rdx, [m_hello]
    call print
    ; the loader and its stack must not be where the kernel goes, and
    ; must be below 4 GB for the 32-bit hand-off; if they are, the loader
    ; moves itself (it is position-independent) and gets a new stack
    lea rax, [mz]
    lea rdx, [image_end]
    call clash
    jc .move
    mov rax, rsp
    sub rax, 0x10000
    lea rdx, [rsp+0x100]
    call clash
    jc .move
.placed:
    ; GOP: the framebuffer the console will draw into
    lea rcx, [gop_guid]
    xor edx, edx
    lea r8, [gop]
    mov rax, [bootsvc]
    call [rax+320]                      ; LocateProtocol
    test rax, rax
    jnz .nogop
    ; set the current mode again: some firmware only programs the
    ; display when a mode is set (SquirrelBIOS 2.1.0 does not before)
    mov rcx, [gop]
    mov rax, [rcx+24]
    mov edx, [rax+4]                    ; Mode->Mode
    call [rcx+8]                        ; SetMode
    ; and make sure a VGA-compatible adapter is not blanked: attribute
    ; controller palette address source on (SquirrelBIOS 2.1.0 leaves it
    ; off, and QEMU's standard VGA then shows nothing)
    mov dx, 0x3DA
    in al, dx
    mov dx, 0x3C0
    mov al, 0x20
    out dx, al
    mov rax, [gop]
    mov rax, [rax+24]                   ; Mode
    mov rcx, [rax+24]                   ; FrameBufferBase
    mov rdx, rcx
    shr rdx, 32
    jnz .nogop                          ; above 4 GB: out of a 32-bit kernel's reach
    mov [gop_fb], ecx
    mov rcx, [rax+8]                    ; Info
    mov eax, [rcx+12]                   ; PixelFormat
    cmp eax, 1
    ja .nogop                           ; bit masks or Blt only: not supported
    mov [gop_fmt], eax
    mov eax, [rcx+4]
    mov [gop_w], eax
    mov eax, [rcx+8]
    mov [gop_h], eax
    mov eax, [rcx+32]                   ; PixelsPerScanLine
    shl eax, 2
    mov [gop_pitch], eax
    mov dword [gop_ok], 1
    jmp .map
.nogop:
    lea rdx, [m_nogop]
    call print
.map:
    mov dword [tries], 3
.again:
    mov qword [map_size], MAP_BUF
    lea rcx, [map_size]
    lea rdx, [map_buf]
    lea r8, [map_key]
    lea r9, [desc_size]
    lea rax, [desc_ver]
    mov [rsp+32], rax
    mov rax, [bootsvc]
    call [rax+56]                       ; GetMemoryMap
    test rax, rax
    jnz .maperr
    call check_map
    jc .used
    mov rcx, [image_handle]
    mov rdx, [map_key]
    mov rax, [bootsvc]
    call [rax+232]                      ; ExitBootServices
    test rax, rax
    jz .exited
    dec dword [tries]                   ; the map changed under us: once more
    jnz .again
.maperr:
    lea rdx, [m_maperr]
    jmp .fail
.used:
    lea rdx, [m_used]
    call print
    mov rax, [bad_desc]                 ; which entry: type and start, in hex
    mov eax, [rax]
    call print_hex
    mov rax, [bad_desc]
    mov rax, [rax+8]
    call print_hex
    mov rax, [bad_desc]
    mov rax, [rax+24]
    call print_hex
    lea rdx, [m_nl]
    jmp .fail
.clash:
    lea rdx, [m_clash]
.fail:
    call print
    mov rax, 0x8000000000000001         ; EFI_LOAD_ERROR
    lea rsp, [rbp-16]
    pop r12
    pop rbx
    pop rbp
    ret

.move:
    cmp byte [moved], 0
    jne .clash
    mov dword [tries], 8
.alloc:
    mov eax, 0xFFFFFFFF                 ; AllocateMaxAddress: below 4 GB
    mov [newbase], rax
    mov ecx, 1
    mov edx, 2                          ; EfiLoaderData
    mov r8, (image_end - mz + MOVE_STACK) >> 12
    lea r9, [newbase]
    mov rax, [bootsvc]
    call [rax+40]                       ; AllocatePages
    test rax, rax
    jnz .clash
    mov rax, [newbase]
    lea rdx, [rax + image_end + MOVE_STACK]
    call clash
    jnc .copy
    dec dword [tries]                   ; keep that block (so it is not
    jnz .alloc                          ; handed out again) and try once more
    jmp .clash
.copy:
    mov byte [moved], 1
    lea rsi, [mz]
    mov rdi, [newbase]
    mov rcx, image_end
    cld
    rep movsb
    mov rax, [newbase]
    lea rsp, [rax + image_end + MOVE_STACK - 64]
    add rax, .placed                    ; (an RVA: ORG 0)
    jmp rax

.exited:
    ; long mode -> 32-bit compatibility mode -> protected mode, paging off
    cli
    lea rax, [gdt32]
    mov [gdt32_desc+2], rax
    lgdt [gdt32_desc]
    lea rax, [pm32]
    push qword 0x08
    push rax
    o64 retf

; rdx = UTF-16 string on the console
print:
    sub rsp, 40
    mov rcx, [systab]
    mov rcx, [rcx+64]                   ; ConOut
    call [rcx+8]                        ; OutputString
    add rsp, 40
    ret

; rax -> 16 hex digits and a space on the console
print_hex:
    push rbx
    sub rsp, 48
    lea rdx, [hexbuf]
    mov ecx, 16
.d:
    rol rax, 4
    mov ebx, eax
    and ebx, 15
    add ebx, '0'
    cmp ebx, '9'
    jbe .w
    add ebx, 'A'-'9'-1
.w:
    mov [rdx], bx
    add rdx, 2
    loop .d
    mov dword [rdx], ' '
    lea rdx, [hexbuf]
    call print
    add rsp, 48
    pop rbx
    ret

; [rax, rdx) -> CF if it is above 4 GB or overlaps the kernel's areas
clash:
    mov rcx, rdx
    shr rcx, 32
    jnz .yes
    cmp rax, KMEM_LO_END
    jae .hi
    cmp rdx, KMEM_LO_START
    ja .yes
.hi:
    cmp rax, KMEM_HI_END
    jae .no
    cmp rdx, KMEM_HI_START
    ja .yes
.no:
    clc
    ret
.yes:
    stc
    ret

; CF if any memory-map entry that overlaps the kernel's areas is of a
; type that is not free once boot services have exited
check_map:
    lea rsi, [map_buf]
    mov rcx, [map_size]
.d:
    cmp rcx, [desc_size]
    jb .ok
    mov eax, [rsi]
    cmp eax, 4
    jbe .t                               ; (type 0, reserved, is checked below)
    cmp eax, 7
    je .next
    jmp .chk
.t:
    test eax, eax
    jnz .next
.chk:
    mov rax, [rsi+8]                    ; start
    cmp rax, KMEM_HI_END
    jae .next                           ; above the kernel's areas
    mov rdx, [rsi+24]
    shl rdx, 12
    add rdx, rax                        ; end
    push rcx
    call clash
    pop rcx
    mov [bad_desc], rsi
    jc .bad
.next:
    add rsi, [desc_size]
    sub rcx, [desc_size]
    jmp .d
.ok:
    clc
    ret
.bad:
    stc
    ret

BITS 32
pm32:
    mov ax, 0x10
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov eax, cr0
    and eax, 0x7FFFFFFF                 ; paging off: leaves long mode
    mov cr0, eax
    mov ecx, 0xC0000080                 ; EFER: LME off
    rdmsr
    and eax, ~0x100
    wrmsr
    xor eax, eax
    mov cr4, eax                        ; PAE off: the kernel uses 32-bit paging
    jmp handoff32

%include "handoff32.inc"

align 8
gdt32:
    dq 0
    dq 0x00CF9A000000FFFF               ; 08: 32-bit code, flat
    dq 0x00CF92000000FFFF               ; 10: data, flat
gdt32_desc:
    dw gdt32_desc - gdt32 - 1
    dq 0
gop_guid:
    dd 0x9042A9DE
    dw 0x23DC, 0x4A38
    db 0x96, 0xFB, 0x7A, 0xDE, 0xD0, 0x80, 0x51, 0x6A
align 8
image_handle dq 0
systab dq 0
bootsvc dq 0
gop dq 0
tries dd 0
moved db 0
align 8
newbase dq 0
bad_desc dq 0
hexbuf times 18 dw 0
m_nl dw 13, 10, 0
m_hello dw __utf16__('Squirrel-OS/2 UEFI loader (x86-64): starting the kernel'), 13, 10, 0
m_nogop dw __utf16__('No usable GOP framebuffer: the screen stays blank, the kernel runs.'), 13, 10, 0
m_maperr dw __utf16__('Squirrel-OS/2: cannot read the memory map.'), 13, 10, 0
m_used dw __utf16__('Squirrel-OS/2: memory the kernel needs (below 640 KB, 1-2 MB) is reserved by the firmware.'), 13, 10, 0
m_clash dw __utf16__('Squirrel-OS/2: the firmware loaded this program where the kernel must go.'), 13, 10, 0
align 16
map_buf times MAP_BUF db 0
align 16
payload:
    incbin OS_IMG
payload_end:
    times (SECT_ALIGN - ($-$$) % SECT_ALIGN) % SECT_ALIGN db 0
image_end:
