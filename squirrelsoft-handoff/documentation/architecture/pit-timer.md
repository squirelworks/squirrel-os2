# PIT Timer Design

## Purpose

Replace firmware tick services (`int 0x1A`) with a native Programmable Interval Timer (PIT) interrupt handler. This gives Squirrel-OS/2 direct control of periodic timing for beeps, delays, and future scheduling.

## Hardware

- PIT (Intel 8253/8254 compatible) at ports `0x40–0x43`
- IRQ0 is wired to the PIT channel 0 output
- PC speaker can still be driven via channel 2 + port `0x61`

## Design

1. **Initialization**
   - Program PIT channel 0 for a chosen frequency (e.g. 100 Hz or 1000 Hz).
   - Install an interrupt handler for IRQ0.
   - Unmask IRQ0 on the PIC.

2. **Handler**
   - Increment a tick counter.
   - Acknowledge the interrupt (EOI to PIC).
   - Optionally set a flag or wake a simple sleeper.

3. **Beep scheduling**
   - Main loop or a secondary counter watches the tick count.
   - Every ~15 seconds (± jitter derived from a free-running counter or simple LCG) trigger a short speaker pulse.
   - Speaker pulse itself uses PIT channel 2 for frequency and port `0x61` for gate.

4. **Jitter**
   - Keep a small seed updated by the handler or by reading the PIT counter.
   - Add or subtract a few ticks so the interval is not perfectly periodic.

## Interfaces (planned)

```text
timer_init()          ; program PIT + install handler
timer_ticks()         ; return current tick count
timer_sleep(ticks)    ; busy-wait or simple halt-wait
speaker_beep(ms)      ; short tone
```

## Migration from 0.0.1

- Current boot sector uses BIOS `int 0x1A`.
- Next revision keeps the same external behavior (`UwU` + ~15 s beeps) but drives timing from IRQ0.
- Boot-sector size limit may require moving the handler into a second-stage loader; that is acceptable.

## Status

Design only. Implementation follows in the next kernel revision.
