; Squirrel-OS/2 — program loader (0.3.0)
; Included from pm.asm. Original code.
;
; Loads a program file from SQFS into the program area and starts it as
; a process. Two formats are accepted:
;   SQX  flat binary with a 16-byte header (see programs/sqx.inc)
;   ELF  32-bit, little-endian, ET_EXEC, i386, PT_LOAD segments only
; Both must be linked to run inside the program area. One program is
; resident at a time. See documentation/kernel/loader.md.

PROG_BASE    equ 0x30000            ; program area: 0x30000-0x3FFFF
PROG_MAX     equ 0x10000
LD_STAGE     equ 0x40000            ; file is read here first (64 KB)
LD_ARGMAX    equ 64

SQX_MAGIC    equ 0x31585153         ; 'SQX1'
SQX_ENTRY    equ 4
SQX_MEMSIZE  equ 8
SQX_HDRSIZE  equ 16

ELF_MAGIC    equ 0x464C457F         ; 0x7F 'ELF'

; error results (negative); -1 doubles as "not found"
LD_ENOENT    equ -1
LD_EFORMAT   equ -2
LD_EBIG      equ -3
LD_EBUSY     equ -4
LD_EPROC     equ -5

; esi = file name, edi = argument string (or 0)
; -> eax = pid of the started program, or LD_E* (< 0)
prog_exec:
    push ebx
    push ecx
    push edx
    push esi
    push edi
    push ebp
    mov ebp, edi                ; keep the argument
    ; only one resident program: is the last one still alive?
    mov ebx, [prog_pid]
    test ebx, ebx
    jz .free
    push edi
    call proc_find
    mov eax, edi
    pop edi
    test eax, eax
    jz .free
    cmp dword [eax+PCB_STATE], P_ZOMBIE
    je .free
    mov eax, LD_EBUSY
    jmp .out
.free:
    mov eax, LD_ENOENT
    cmp byte [fs_mounted], 0
    je .out
    xor ecx, ecx
    call fs_open
    cmp eax, -1
    je .out
    mov ebx, eax
    mov edi, LD_STAGE
    mov ecx, PROG_MAX
    call fs_read
    mov edx, eax                ; file length
    mov edi, ld_probe
    mov ecx, 1
    call fs_read                ; anything past 64 KB?
    push eax
    call fs_close
    pop eax
    cmp edx, -1
    je .enoent
    test eax, eax
    jnz .big
    ; edx = length of the image at LD_STAGE
    cmp edx, 4
    jb .badfmt
    cmp dword [LD_STAGE], SQX_MAGIC
    je .sqx
    cmp dword [LD_STAGE], ELF_MAGIC
    je .elf
.badfmt:
    mov eax, LD_EFORMAT
    jmp .out
.big:
    mov eax, LD_EBIG
    jmp .out
.enoent:
    mov eax, LD_ENOENT
    jmp .out
.sqx:
    call ld_sqx
    jmp .loaded
.elf:
    call ld_elf
.loaded:
    test eax, eax
    js .out
    ; eax = entry point; copy the argument and start the process
    mov ebx, eax
    mov edi, prog_arg
    mov byte [edi], 0
    test ebp, ebp
    jz .spawn
    mov esi, ebp
    mov ecx, LD_ARGMAX-1
.arg:
    lodsb
    test al, al
    jz .argz
    stosb
    loop .arg
.argz:
    mov byte [edi], 0
.spawn:
    mov ecx, prog_arg
    call proc_spawn
    cmp eax, -1
    jne .started
    mov eax, LD_EPROC
    jmp .out
.started:
    mov [prog_pid], eax
.out:
    pop ebp
    pop edi
    pop esi
    pop edx
    pop ecx
    pop ebx
    ret

; SQX flat image at LD_STAGE, edx = length -> eax = entry or LD_EFORMAT/LD_EBIG
ld_sqx:
    cmp edx, SQX_HDRSIZE
    jb .bad
    mov ecx, [LD_STAGE+SQX_MEMSIZE]
    cmp ecx, edx
    jb .bad                     ; memory size must cover the file
    cmp ecx, PROG_MAX
    ja .big
    mov eax, [LD_STAGE+SQX_ENTRY]
    sub eax, PROG_BASE+SQX_HDRSIZE
    jb .bad
    lea ebx, [edx-SQX_HDRSIZE]
    cmp eax, ebx
    jae .bad                    ; entry must lie in the loaded code
    ; copy the file, then zero the rest of its memory (bss)
    push ecx
    mov esi, LD_STAGE
    mov edi, PROG_BASE
    mov ecx, edx
    rep movsb
    pop ecx
    sub ecx, edx
    xor eax, eax
    rep stosb
    mov eax, [LD_STAGE+SQX_ENTRY]
    ret
.bad:
    mov eax, LD_EFORMAT
    ret
.big:
    mov eax, LD_EBIG
    ret

; ELF32 image at LD_STAGE, edx = length -> eax = entry or LD_EFORMAT/LD_EBIG
ld_elf:
    push ebp
    call .load
    pop ebp
    ret
.load:
    cmp edx, 52                 ; ELF32 header
    jb .bad
    cmp word [LD_STAGE+4], 0x0101   ; ELFCLASS32, ELFDATA2LSB
    jne .bad
    cmp word [LD_STAGE+16], 2       ; ET_EXEC
    jne .bad
    cmp word [LD_STAGE+18], 3       ; EM_386
    jne .bad
    cmp word [LD_STAGE+42], 32      ; e_phentsize
    jne .bad
    movzx ecx, word [LD_STAGE+44]   ; e_phnum
    mov esi, [LD_STAGE+28]          ; e_phoff
    ; the program header table must lie inside the file
    mov eax, ecx
    shl eax, 5
    add eax, esi
    jc .bad
    cmp eax, edx
    ja .bad
    add esi, LD_STAGE
    xor ebp, ebp                ; PT_LOAD count
    ; clear the area so gaps between segments read as zero
    push ecx
    mov edi, PROG_BASE
    mov ecx, PROG_MAX/4
    xor eax, eax
    rep stosd
    pop ecx
    jecxz .done
.ph:
    cmp dword [esi], 1          ; PT_LOAD
    jne .next
    mov eax, [esi+16]           ; p_filesz
    cmp eax, [esi+20]           ; p_memsz
    ja .bad
    mov ebx, [esi+4]            ; p_offset
    add ebx, eax
    jc .bad
    cmp ebx, edx
    ja .bad
    mov ebx, [esi+8]            ; p_vaddr
    sub ebx, PROG_BASE
    jb .big
    cmp ebx, PROG_MAX
    ja .big
    mov eax, PROG_MAX
    sub eax, ebx
    cmp [esi+20], eax
    ja .big                     ; segment must end inside the area
    push ecx
    push esi
    mov edi, [esi+8]
    mov ecx, [esi+16]
    mov esi, [esi+4]
    add esi, LD_STAGE
    rep movsb                   ; the bss part is already zero
    pop esi
    pop ecx
    inc ebp
.next:
    add esi, 32
    loop .ph
.done:
    test ebp, ebp
    jz .bad
    mov eax, [LD_STAGE+24]      ; e_entry
    sub eax, PROG_BASE
    jb .bad
    cmp eax, PROG_MAX
    jae .bad
    mov eax, [LD_STAGE+24]
    ret
.bad:
    mov eax, LD_EFORMAT
    ret
.big:
    mov eax, LD_EBIG
    ret

; eax = LD_E* -> prints the matching message
ld_perror:
    push esi
    neg eax
    dec eax
    cmp eax, 4
    jbe .ok
    mov eax, 1
.ok:
    mov esi, [ld_errs+eax*4]
    call puts
    pop esi
    ret

sys_exec:                       ; ebx = name, ecx = argument (or 0)
    mov esi, ebx
    mov edi, ecx
    jmp prog_exec

prog_pid dd 0
prog_arg times LD_ARGMAX db 0
ld_probe db 0
ld_errs dd ld_m_enoent, ld_m_eformat, ld_m_ebig, ld_m_ebusy, ld_m_eproc
ld_m_enoent db 'Unknown command or program', 10, 0
ld_m_eformat db 'Not a program (bad SQX/ELF header)', 10, 0
ld_m_ebig db 'Program too big for the 64 KB program area', 10, 0
ld_m_ebusy db 'Another program is still running', 10, 0
ld_m_eproc db 'Too many processes', 10, 0
