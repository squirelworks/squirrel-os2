; Squirrel-OS/2 — SQX program header and syscall numbers (0.3.0)
; Original code. Include at the top of a flat program:
;
;     %include "sqx.inc"
;     SQX_HEADER main
;     main: ...            ; called as main(arg), arg = argument string
;     ...                  ; return the exit code in eax, or SYS_EXIT
;     SQX_BSS              ; data that starts zeroed (resb/resd) after this
;     SQX_END
;
; Build: nasm -f bin prog.asm -o prog   (then tools/sqfs.py DISK put prog)

BITS 32

PROG_BASE   equ 0x30000

SYS_PUTC    equ 0
SYS_PUTS    equ 1
SYS_GETC    equ 2
SYS_YIELD   equ 3
SYS_SPAWN   equ 4
SYS_EXIT    equ 5
SYS_WAIT    equ 6
SYS_GETPID  equ 7
SYS_OPEN    equ 10
SYS_READ    equ 11
SYS_WRITE   equ 12
SYS_CLOSE   equ 13
SYS_CREATE  equ 14
SYS_DELETE  equ 15
SYS_RENAME  equ 16
SYS_EXEC    equ 17
SYS_READDIR equ 18
SYS_PALLOC  equ 19
SYS_PFREE   equ 20
SYS_SBRK    equ 21
SYS_DEVFIND equ 22
SYS_DEVREAD equ 23
SYS_DEVWRITE equ 24
SYS_SEEK    equ 25
SYS_FSERROR equ 26
SYS_SEND    equ 27
SYS_RECV    equ 28
SYS_KEYEVENTS equ 29
SYS_NETSENDTO equ 30
SYS_NETRECVFROM equ 31
SYS_SETPRIO equ 32
SYS_DEVREG  equ 33
SYS_DEVUNREG equ 34
SYS_SETTLS  equ 36
SYS_WINOPEN  equ 37         ; windows for programs (2.2-progwin, windows.md)
SYS_WINCLOSE equ 38
SYS_WINMOVE  equ 39
SYS_WINTITLE equ 40
SYS_WINDRAW  equ 41
SYS_WINFLUSH equ 42
SYS_WINEVENT equ 43
SYS_WININFO  equ 44
WE_KEY      equ 1
WE_DOWN     equ 2
WE_CLOSE    equ 6
WE_PAINT    equ 8
WD_FILL     equ 0
WD_LINE     equ 1
WD_TEXT     equ 2
WD_PTEXT    equ 3
WD_BLIT     equ 4
WD_BEVEL    equ 5
WD_PIXEL    equ 7
MSG_KEY     equ 0x4B000000

O_CREATE    equ 1
O_TRUNC     equ 2
O_APPEND    equ 4

; 16-byte header: magic, entry address, memory size (file + bss), reserved
%macro SQX_HEADER 1
    org PROG_BASE
    db 'SQX1'
    dd %1
    dd sqx_mem_end - PROG_BASE
    dd 0
%endmacro

; SQX_BSS ends the file image; uninitialised data (resb/resd) may follow
; and is zeroed by the loader. SQX_END closes the program's memory.
%macro SQX_BSS 0
sqx_file_end:
absolute sqx_file_end
%endmacro

%macro SQX_END 0
sqx_mem_end:
%endmacro
