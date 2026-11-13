; Squirrel-OS/2 — per-process TLS segment for foreign personalities
; Included from pm.asm. Original code.
;
; Win32 code finds its thread block (TEB) through FS, and i386 Linux
; code finds its thread-local storage through GS. Both need a segment
; whose base is a per-process address. One GDT descriptor (TLS_SEL,
; flat 4 GB, DPL 3) is rewritten on every process switch with the
; incoming process's base (0 for everybody that never asked, which
; makes it an ordinary flat data segment), and FS and GS are reloaded
; with it. The kernel itself never uses FS or GS.
;
; SYS_SETTLS (35): ebx = base -> eax = the selector to load (TLS_SEL);
; also loads it into FS and GS at once. Linux set_thread_area (243) uses
; the same slot (linux.asm). See
; documentation/architecture/foreign-compatibility.md.

TLS_SEL     equ gdt_tls - gdt + 3   ; 0x3B, RPL 3

; edi = PCB of the process about to run (proc_switch): load its segment.
; Clobbers eax.
tls_switch:
    mov eax, edi
    sub eax, proc_table
    shr eax, 4                  ; slot * 4 (PCB_SIZE is 64)
    mov eax, [tls_base+eax]
    ; fall through
; eax = base: writes it into the descriptor and reloads FS and GS
tls_load:
    mov [gdt_tls+2], ax
    shr eax, 16
    mov [gdt_tls+4], al
    mov [gdt_tls+7], ah
    mov ax, TLS_SEL
    mov fs, ax
    mov gs, ax
    ret

; edi = PCB of a new process (proc_spawn): it starts with base 0
tls_clear:
    push eax
    mov eax, edi
    sub eax, proc_table
    shr eax, 4
    mov dword [tls_base+eax], 0
    pop eax
    ret

sys_settls:
    mov eax, [proc_cur]
    sub eax, proc_table
    shr eax, 4
    mov [tls_base+eax], ebx
    mov eax, ebx
    call tls_load
    mov eax, TLS_SEL
    ret

tls_base times PROC_MAX dd 0
