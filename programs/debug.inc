; Squirrel-OS/2 — SYS_DEBUG for programs (A.4). Original code.
; The numbers match kernel/debug.asm; see documentation/kernel/debug.md.
;
;   mov eax, SYS_DEBUG / mov ebx, DBG_* / mov ecx, pid / mov edx, argument
;   int 0x80

DBG_ATTACH      equ 0           ; ecx = pid -> 0, or -1
DBG_DETACH      equ 1           ; ecx = pid -> 0, or -1
DBG_EXEC        equ 2           ; ecx = file, edx = argument or 0 -> pid (stopped at its entry), or < 0
DBG_WAIT        equ 3           ; ecx = pid, edx = 0 wait / 1 poll -> reason, DBG_ENDED, DBG_RUNNING
DBG_STOP        equ 4           ; ecx = pid -> 0
DBG_GETREGS     equ 5           ; ecx = pid, edx = DBG_REGS_SIZE bytes -> 0, or -1
DBG_SETREGS     equ 6           ; ecx = pid, edx = DBG_REGS_SIZE bytes -> 0, or -1
DBG_READ        equ 7           ; ecx = pid, edx = {address, buffer, length} -> bytes
DBG_WRITE       equ 8           ; ecx = pid, edx = {address, buffer, length} -> bytes
DBG_CONT        equ 9           ; ecx = pid, edx = 0 run / 1 one instruction -> 0, or -1
DBG_KILL        equ 10          ; ecx = pid -> 0

DBG_R_STEP      equ 1           ; stop reasons: a CPU exception number, or
DBG_R_BREAK     equ 3
DBG_R_ENTRY     equ 0x100
DBG_R_STOP      equ 0x101
DBG_ENDED       equ -2
DBG_RUNNING     equ -3

DR_EAX          equ 0
DR_EBX          equ 4
DR_ECX          equ 8
DR_EDX          equ 12
DR_ESI          equ 16
DR_EDI          equ 20
DR_EBP          equ 24
DR_ESP          equ 28
DR_EIP          equ 32
DR_EFLAGS       equ 36
DR_REASON       equ 40
DR_ERR          equ 44
DR_CR2          equ 48
DBG_REGS_SIZE   equ 52
