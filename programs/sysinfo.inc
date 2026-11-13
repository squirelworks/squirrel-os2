; Squirrel-OS/2 — GUI_SYSINFO for programs (A.5). Original code.
; The layouts match kernel/sysinfo.asm; see documentation/kernel/syscalls.md.
;
;   mov eax, SYS_GUI / mov ebx, GUI_SYSINFO / mov edx, part / mov ecx, buffer
;   int 0x80

GUI_SYSINFO     equ 12

SI_PART_SYS     equ 0           ; ecx = SI_SYS_SIZE-byte buffer -> 0
SI_PART_PROCS   equ 1           ; ecx = SI_SLOTS_MAX * SI_ROW bytes -> 0
SI_PART_LOG     equ 2           ; ecx = KLOG_SIZE bytes -> bytes copied
SI_PART_PRIO    equ 3           ; ecx = pid | priority << 16 -> 0, or -1

SI_TICKS        equ 0
SI_IDLE         equ 4
SI_PAGES        equ 8
SI_FREE         equ 12
SI_PROCS        equ 16
SI_SLOTS        equ 20
SI_SWITCHES     equ 24
SI_LOGLEN       equ 28
SI_SYS_SIZE     equ 32

SI_PID          equ 0
SI_STATE        equ 4
SI_PRIO         equ 8
SI_PARENT       equ 12
SI_KB           equ 16          ; -1: runs in the kernel's memory
SI_CPU          equ 20
SI_NAME         equ 24
SI_ROW          equ 40
SI_SLOTS_MAX    equ 8

PS_FREE         equ 0           ; process states
PS_READY        equ 1
PS_RUNNING      equ 2
PS_WAITING      equ 3
PS_ZOMBIE       equ 4
PS_STOPPED      equ 5           ; stopped for its debugger (A.4)

KLOG_SIZE       equ 4096
