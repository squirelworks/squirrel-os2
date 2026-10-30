; Minimal in-memory file system and program stubs for Squirrel-OS/2
; This is a scaffold toward 0.2.x / 0.3.x milestones.
; Original code.

section .data
fs_magic db 'SQFS', 0

; Simple flat file table (name, data pointer, length)
file_count dd 3

file0_name db 'calc', 0
file0_data db 'CALC: 2+2=4', 10, 0
file0_len  equ $ - file0_data

file1_name db 'edit', 0
file1_data db 'EDIT: hello from Squirrel-OS/2', 10, 0
file1_len  equ $ - file1_data

file2_name db 'draw', 0
file2_data db 'DRAW: *', 10, 0
file2_len  equ $ - file2_data

section .text
; fs_list — prints file names (expects puts)
global fs_list
fs_list:
    ; placeholder — real integration comes with console linkage
    ret

; fs_open — eax = name pointer, returns data pointer or 0
global fs_open
fs_open:
    ; stub
    xor eax, eax
    ret
