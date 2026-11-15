# System Monitor (A.5)

`run sysmon` shows what the machine is doing, from a snapshot it takes twice a second through `GUI_SYSINFO` (`../kernel/syscalls.md`). It is a program on the data disk (`programs/sysmon.asm`) built on `SYS_GUI` and `gui.inc` (`gui-programs.md`).

- **CPU**: how busy the CPU was since the last snapshot (the timer ticks it did not find the CPU halted in the idle loop), the time since boot, how many of the 8 process slots are in use, and a graph of the last 64 snapshots.
- **Memory**: the 4 KB pages the kernel manages, used, free and all of them (in KB) with a bar, and how many times the timer has switched processes.
- **Processes**: pid, state, priority, the share of the CPU each had since the last snapshot, the CPU time each has used (seconds), memory (its own address space; `kernel` for the shell and the built-in apps) and name.

## Keys

Up and Down (or a click on a row) pick a process; at first it is the monitor itself. `+` and `-` raise and lower the picked process's priority, from 0 to 3; a higher priority runs first (`../kernel/processes.md`). Esc quits.

## Checks

`run sysmon test` checks the snapshot against what the program knows of itself: its pid, name, state and memory; that spinning for 0.3 s adds to its CPU time and yielding for 0.3 s (nobody else wanting the CPU) adds idle time; that it can set its own priority to 2 and back while priority 9 and pid 9999 are refused; that the kernel log has the boot line and `started sysmon`; that an unknown part is refused; and that a busy stretch shows as more than 50 % CPU, for the system and for the monitor's own row. It prints `sysmon: PASS`. The regress run also reads the window (`sysmon-view`) and raises the shell's priority from it (`sysmon-prio`, seen in `ps`).
