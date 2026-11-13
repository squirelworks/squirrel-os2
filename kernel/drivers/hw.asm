; Squirrel-OS/2 — modern hardware drivers: start-up and timer hook (OS2-HW)
; Included from pm.asm (high image). Original code.
;
; hw_init runs once at boot, after dev_init: each driver looks for its
; controller on the PCI bus and registers what it finds in the device
; table. Nothing is registered for hardware that is not there, so the
; `devices` list of a machine without it does not change.
; hw_tick runs on every timer interrupt (interrupts off) for drivers
; that poll: the USB keyboard and the GOP text console.
; See documentation/kernel/hardware.md.

hw_init:
    call ahci_init
    call nvme_init
    call xhci_init
    jmp hw_pick_data_disk

hw_tick:
    jmp xhci_poll

; With no ATA data disk (hd1 absent, as on a q35 or other AHCI/NVMe-only
; machine), the first of the new disks whose sector 0 holds an SQFS
; superblock becomes the file system's data disk. Runs before
; fs_mount_boot. A blank disk is never picked, so nothing is formatted
; by surprise.
hw_pick_data_disk:
    pushad
    cmp dword [FS_DEV+DEV_SIZE], 0
    jne .out
    mov esi, hw_disks
.l:
    lodsd
    test eax, eax
    jz .out
    mov ebx, eax
    test dword [ebx+DEV_FLAGS], DEVF_UP
    jz .l
    xor ecx, ecx
    mov edi, FS_SB
    call dev_bread
    jc .l
    cmp dword [FS_SB+SB_MAGIC], FS_MAGIC
    jne .l
    mov [fs_dev], ebx           ; (the screen is cleared after this: no message)
.out:
    popad
    ret

hw_disks dd dev_sd0, dev_sd1, dev_nv0, dev_ud0, 0
