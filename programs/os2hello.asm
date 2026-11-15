; os2hello — an OS/2 32-bit LX program, written by hand (P.9). Original
; code. Exercises os2run: the LX headers, one object, internal and import
; fixups, DOSCALLS by ordinal, the TIB through FS and the PIB, files,
; memory and DosQuerySysInfo.
;   run os2hello            ->  Hello from OS/2 land! ... os2hello: PASS
;   run os2hello stub       ->  calls DOSCALLS.1, which os2run does not offer
; Build: nasm -f bin os2hello.asm -o os2hello
BITS 32

; ---------- fixup bookkeeping ----------
; IREF value: a 32-bit internal reference, the last four bytes just
; assembled; DOSCALL ord: call a DOSCALLS function (self-relative fixup).
%assign NFIX 0
%macro IREF 1-2 0                  ; target, bytes after the address
fixs_%[NFIX] equ $ - 4 - %2 - code
fixk_%[NFIX] equ 0
fixt_%[NFIX] equ %1
%assign NFIX NFIX+1
%endmacro
%macro DOSCALL 1
    call $+5                        ; the target comes from the fixup
fixs_%[NFIX] equ $ - 4 - code
fixk_%[NFIX] equ 1
fixt_%[NFIX] equ %1
%assign NFIX NFIX+1
%endmacro
%macro PUSHA_ 1                     ; push the address of a label
    push dword %1 - code
    IREF %1 - code
%endmacro
%macro LEAX 2                       ; mov reg, address of a label
    mov %1, %2 - code
    IREF %2 - code
%endmacro
%macro STEP 1
    mov byte [step - code], %1
    IREF step - code, 1
%endmacro

DosError         equ 212
DosExit          equ 234
DosSetFilePtr    equ 256
DosClose         equ 257
DosDelete        equ 259
DosOpen          equ 273
DosRead          equ 281
DosWrite         equ 282
DosAllocMem      equ 299
DosGetInfoBlocks equ 312
DosQuerySysInfo  equ 348

; ---------- MZ stub and LX header ----------
mz:
    dw 'MZ'
    times 0x3A db 0
    dd lx - mz
lx:
    db 'LX', 0, 0                   ; little-endian bytes and words
    dd 0                            ; format level
    dw 2, 1                         ; 80386, OS/2
    dd 0                            ; module version
    dd 0x00000200                   ; flags: a program, windowable VIO
    dd 1                            ; pages
    dd 1, start - code              ; EIP object and offset
    dd 1, OBJ_SIZE                  ; ESP object and offset (the top)
    dd 0x1000, 0                    ; page size, page offset shift
    dd fixups_end - fpt, 0          ; fixup section size, checksum
    dd loader_end - objtab, 0       ; loader section size, checksum
    dd objtab - lx, 1               ; object table, objects
    dd opt - lx, 0                  ; object page table, iterated pages
    dd 0, 0                         ; resources
    dd resnames - lx                ; resident names
    dd entries - lx                 ; entry table
    dd 0, 0                         ; module directives
    dd fpt - lx                     ; fixup page table
    dd frec - lx                    ; fixup records
    dd imods - lx, 1                ; import modules
    dd iprocs - lx                  ; import procedure names
    dd 0                            ; per-page checksums
    dd code - mz                    ; data pages, from the start of the file
    dd 0                            ; preload pages
    dd 0, 0, 0                      ; non-resident names, length, checksum
    dd 0                            ; automatic data object
    dd 0, 0                         ; debug information
    dd 0, 0                         ; instance pages
    dd 0, 0x2000                    ; heap and stack sizes
    times 0xC4 - ($ - lx) db 0
objtab:
    dd OBJ_SIZE, 0x10000            ; virtual size, preferred base
    dd 0x2007                       ; read, write, execute, 32-bit
    dd 1, 1, 0                      ; first page, pages, reserved
opt:
    dd 0                            ; page 1: at the data pages' start
    dw code_end - code, 0           ; bytes, a legal page
resnames:
    db 8, 'OS2HELLO'
    dw 0
    db 0
entries:
    db 0
loader_end:
    times 0x200 - ($ - mz) db 0

; ---------- object 1, page 1 ----------
OBJ_SIZE equ 0x4000
code:
start:
    STEP 'a'                        ; DosWrite to the console
    PUSHA_ written
    push hello_len
    PUSHA_ hello
    push 1
    DOSCALL DosWrite
    add esp, 16
    test eax, eax
    jnz fail
    cmp dword [written - code], hello_len
    IREF written - code, 1
    jne fail
    STEP 'b'                        ; the PIB's command line, the TIB in FS
    PUSHA_ ppib
    PUSHA_ ptib
    DOSCALL DosGetInfoBlocks
    add esp, 8
    test eax, eax
    jnz fail
    mov eax, [ptib - code]
    IREF ptib - code
    cmp dword [fs:0], -1
    jne fail
    mov ecx, [fs:12]                ; tib_ptib2
    test ecx, ecx
    jz fail
    cmp dword [ecx], 1              ; thread 1
    jne fail
    mov eax, [ppib - code]
    IREF ppib - code
    mov esi, [eax+12]               ; pib_pchcmd: name NUL arguments NUL
    cmp dword [esi], 'os2h'
    jne fail
    ; the entry arguments: [esp+16] is the same command line
    cmp esi, [esp+16]
    jne fail
.skip:
    lodsb
    test al, al
    jnz .skip
    mov [args - code], esi
    IREF args - code
    PUSHA_ cmdmsg
    call print
    push esi
    call print
    PUSHA_ nl
    call print
    STEP 'c'                        ; version and page size
    push 8
    PUSHA_ sysinfo
    push 11
    push 10
    DOSCALL DosQuerySysInfo
    add esp, 16
    test eax, eax
    jnz fail
    cmp dword [sysinfo - code], 4096
    IREF sysinfo - code, 4
    jne fail
    cmp dword [sysinfo - code + 4], 20
    IREF sysinfo - code + 4, 1
    jne fail
    STEP 'd'                        ; memory
    push 0x13                       ; PAG_COMMIT | PAG_READ | PAG_WRITE
    push 9000
    PUSHA_ pmem
    DOSCALL DosAllocMem
    add esp, 12
    test eax, eax
    jnz fail
    mov eax, [pmem - code]
    IREF pmem - code
    test eax, 0xFFF
    jnz fail
    cmp dword [eax+8996], 0
    jne fail
    mov dword [eax+8996], -1
    STEP 'e'                        ; create a file and write it
    push 0
    push 0x41                       ; deny none, write only
    push 0x12                       ; replace if it exists, create if not
    push 0
    push 0
    PUSHA_ action
    PUSHA_ hfile
    PUSHA_ fname
    DOSCALL DosOpen
    add esp, 32
    test eax, eax
    jnz fail
    mov eax, [action - code]
    IREF action - code
    cmp eax, 2                      ; created ...
    je .made
    cmp eax, 3                      ; ... or replaced
    jne fail
.made:
    PUSHA_ written
    push ftext_len
    PUSHA_ ftext
    push dword [hfile - code]
    IREF hfile - code
    DOSCALL DosWrite
    add esp, 16
    test eax, eax
    jnz fail
    push dword [hfile - code]
    IREF hfile - code
    DOSCALL DosClose
    add esp, 4
    test eax, eax
    jnz fail
    STEP 'f'                        ; open it again, seek, read
    push 0
    push 0x40                       ; deny none, read only
    push 0x01                       ; open if it exists, fail if not
    push 0
    push 0
    PUSHA_ action
    PUSHA_ hfile
    PUSHA_ fname
    DOSCALL DosOpen
    add esp, 32
    test eax, eax
    jnz fail
    cmp dword [action - code], 1
    IREF action - code, 1
    jne fail
    PUSHA_ written
    push 0                          ; FILE_BEGIN
    push 5
    push dword [hfile - code]
    IREF hfile - code
    DOSCALL DosSetFilePtr
    add esp, 16
    test eax, eax
    jnz fail
    cmp dword [written - code], 5
    IREF written - code, 1
    jne fail
    PUSHA_ written
    push 64
    PUSHA_ buf
    push dword [hfile - code]
    IREF hfile - code
    DOSCALL DosRead
    add esp, 16
    test eax, eax
    jnz fail
    cmp dword [written - code], ftext_len - 5
    IREF written - code, 1
    jne fail
    cmp dword [buf - code], 'wrot'
    IREF buf - code, 4
    jne fail
    push dword [hfile - code]
    IREF hfile - code
    DOSCALL DosClose
    add esp, 4
    PUSHA_ fname
    DOSCALL DosDelete
    add esp, 4
    test eax, eax
    jnz fail
    STEP 'g'                        ; a missing file: ERROR_OPEN_FAILED
    push 0
    push 0x40
    push 0x01
    push 0
    push 0
    PUSHA_ action
    PUSHA_ hfile
    PUSHA_ missing
    DOSCALL DosOpen
    add esp, 32
    cmp eax, 110
    jne fail
    STEP 'h'                        ; "stub" calls an import with no shim
    mov esi, [args - code]
    IREF args - code
    cmp dword [esi], 'stub'
    jne .pass
    DOSCALL 1
    jmp fail
.pass:
    PUSHA_ pass
    call print
    push 0
    push 1                          ; EXIT_PROCESS
    DOSCALL DosExit
fail:
    PUSHA_ failmsg
    call print
    push 1
    push 1
    DOSCALL DosExit

; print(ASCIIZ) through DosWrite to handle 1; keeps registers
print:
    pushad
    mov esi, [esp+36]
    xor ecx, ecx
.len:
    cmp byte [esi+ecx], 0
    je .go
    inc ecx
    jmp .len
.go:
    push 0
    push ecx
    push esi
    push 1
    DOSCALL DosWrite
    add esp, 16
    popad
    ret 4

hello db 'Hello from OS/2 land!', 13, 10
hello_len equ $ - hello
cmdmsg db 'arguments: ', 0
nl db 13, 10, 0
fname db 'os2.txt', 0
missing db 'nosuchfile', 0
ftext db 'OS/2 wrote this', 13, 10
ftext_len equ $ - ftext
pass db 'os2hello: PASS', 13, 10, 0
failmsg db 'os2hello: FAIL '
step db '?', 13, 10, 0
align 4
written dd 0
ptib dd 0
ppib dd 0
args dd 0
pmem dd 0
hfile dd 0
action dd 0
sysinfo dd 0, 0
buf times 64 db 0
code_end:
%if code_end - code > 0x1000
%error the program outgrew its one page
%endif

; ---------- fixups (behind the page; offsets are relative to the LX header) ----------
fpt:
    dd 0, frec_end - frec           ; page 1's records, and the end
frec:
%assign i 0
%rep NFIX
%if fixk_%[i] == 0
    db 0x07, 0x10                   ; 32-bit offset; internal, 32-bit target
    dw fixs_%[i]
    db 1
    dd fixt_%[i]
%else
    db 0x08, 0x01                   ; 32-bit self-relative; import ordinal
    dw fixs_%[i]
    db 1                            ; module 1
    dw fixt_%[i]
%endif
%assign i i+1
%endrep
frec_end:
imods:
    db 8, 'DOSCALLS'
iprocs:
    db 0
fixups_end:
