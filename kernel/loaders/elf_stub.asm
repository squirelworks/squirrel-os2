; Squirrel-OS/2 — Minimal ELF loader stub (Linux personality)
; Original code. Maps a static ELF and prepares a Linux-ABI entry.
; Status: stub. Does not yet create a full process or translate syscalls.
; Intended for later inclusion once the native process model exists.
;
; Calling convention (future):
;   esi = pointer to ELF image in memory
;   eax = image length
; Returns: eax = 0 on success (entry point in ebx), non-zero on failure
;
; First supported subset (Linux personality):
;   - ELFCLASS32 or ELFCLASS64 (documented; 32-bit path shown)
;   - ET_EXEC or ET_DYN
;   - Program headers of type PT_LOAD only
;   - No dynamic linking yet
;   - Syscalls to translate later: read(0), write(1), exit(60), exit_group(231)

BITS 32

; ---------- ELF constants ----------
ELFMAG equ 0x464C457F          ; 0x7F 'E' 'L' 'F'
ELFCLASS32 equ 1
ELFCLASS64 equ 2
ET_EXEC equ 2
ET_DYN equ 3
PT_LOAD equ 1

; ---------- Public entry ----------
global elf_load_stub
elf_load_stub:
    push ebp
    mov ebp, esp
    push ebx
    push ecx
    push edx
    push edi

    ; esi = image, eax = length
    cmp eax, 52                ; minimum ELF32 header size
    jb .bad_size

    ; Magic
    cmp dword [esi], ELFMAG
    jne .bad_magic

    ; Class
    mov al, [esi+4]
    cmp al, ELFCLASS32
    je .is32
    cmp al, ELFCLASS64
    je .is64_stub
    jmp .bad_class

.is32:
    ; e_type
    mov ax, [esi+16]
    cmp ax, ET_EXEC
    je .ok_type
    cmp ax, ET_DYN
    je .ok_type
    jmp .bad_type
.ok_type:

    ; e_machine (expect EM_386 = 3 for now)
    mov ax, [esi+18]
    cmp ax, 3
    jne .bad_machine

    ; e_entry
    mov ebx, [esi+24]          ; entry point (absolute for ET_EXEC)

    ; e_phoff / e_phentsize / e_phnum
    mov edi, [esi+28]          ; e_phoff
    movzx ecx, word [esi+42]   ; e_phentsize
    movzx edx, word [esi+44]   ; e_phnum

    ; Simple PT_LOAD walk (stub — just counts and validates)
    add edi, esi               ; absolute
    xor eax, eax               ; load count
.ph_loop:
    test edx, edx
    jz .ph_done
    cmp dword [edi], PT_LOAD
    jne .ph_next
    inc eax
.ph_next:
    add edi, ecx
    dec edx
    jmp .ph_loop
.ph_done:
    test eax, eax
    jz .no_loads

    ; Success path (stub)
    ; In a real loader we would:
    ;   - allocate address space
    ;   - copy PT_LOAD segments
    ;   - set up stack with argc/argv/envp in Linux convention
    ;   - install Linux syscall trampoline
    ;   - jump to entry
    mov eax, 0                 ; success
    jmp .out

.is64_stub:
    ; ELF64 path is scaffolded only (header layout differs)
    mov eax, 2                 ; "64-bit not yet implemented"
    jmp .out

.bad_size:
    mov eax, 10
    jmp .out
.bad_magic:
    mov eax, 11
    jmp .out
.bad_class:
    mov eax, 12
    jmp .out
.bad_type:
    mov eax, 13
    jmp .out
.bad_machine:
    mov eax, 14
    jmp .out
.no_loads:
    mov eax, 15

.out:
    pop edi
    pop edx
    pop ecx
    pop ebx
    pop ebp
    ret

; ---------- Linux personality syscall trampoline (stub) ----------
; Future int 0x80 or syscall instruction lands here.
; eax = Linux syscall number
; Translates a tiny subset onto native Squirrel services.
global linux_syscall_stub
linux_syscall_stub:
    cmp eax, 1                 ; write (i386)
    je .write
    cmp eax, 4                 ; write (some ABIs)
    je .write
    cmp eax, 60                ; exit (x86_64)
    je .exit
    cmp eax, 1                 ; exit (i386)
    je .exit
    ; unknown
    mov eax, -38               ; -ENOSYS
    ret
.write:
    ; Stub: ignore and return length (would call native console/FS)
    mov eax, edx               ; pretend we wrote edx bytes
    ret
.exit:
    ; Stub: would call native process_exit
    xor eax, eax
    ret

; ---------- Diagnostic strings (for later console integration) ----------
elf_msg_ok db 'ELF stub: header valid, PT_LOAD segments found', 10, 0
elf_msg_fail db 'ELF stub: rejected', 10, 0
