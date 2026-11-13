# Sound (3.0)

Since 3.0 the kernel drives one sound device: an Intel High Definition Audio controller if there is one, otherwise an AC'97 controller. The code is in `kernel/audio/`: `pci.asm` (configuration space), `ac97.asm`, `hda.asm`, and `audio.asm` (the layer programs see, `SYS_AUDIO`, and the shell commands). It is polled, with no interrupt handler, like the network card. The device is looked for the first time something asks for sound.

Under QEMU:

| Device | QEMU options |
|--------|--------------|
| AC'97 | `-audiodev none,id=snd0 -device AC97,audiodev=snd0` |
| Intel HDA | `-audiodev none,id=snd0 -device intel-hda -device hda-duplex,audiodev=snd0` (or `hda-output`, which cannot record) |

`-audiodev none` takes the sound at the real rate and throws it away, so the hardware's position moves as on a real machine. `-audiodev wav,id=snd0,path=out.wav` writes it to a file instead (44100 Hz stereo); the regression run listens to that file with `tools/wavcheck.py`.

## PCI

`apci_find_class` walks buses 0–255 and devices 0–31 (functions 1–7 only on multi-function devices) for a class and subclass: 04/03 for HD audio, 04/01 for AC'97. `apci_enable` turns on I/O, memory and bus mastering in the command register. The drivers' memory (buffer lists, rings, sound pages) comes from `pg_alloc`; the kernel maps the first 256 MB to itself, so a page's address is what the device is given.

## The layer in `audio.asm`

Playback goes through a ring of `AU_NBUF` (8) pages of 4 KB. A program opens the device with its own format (8- or 16-bit, mono or stereo, at 8000, 11025, 16000, 22050, 24000, 32000, 44100 or 48000 Hz). Each frame it writes becomes 16-bit stereo (8-bit samples are unsigned around 128, as in WAV files) in the page being filled. A full page is handed to the driver. When all eight are queued, the writer waits for the driver to finish one, yielding while it waits. A page the device has played is cleared at once, so if the program falls behind, the device plays silence, not old sound. `au_drain` fills the rest of the last page with silence, hands it over, waits until the driver has played everything (at most three seconds), and stops the device.

Recording uses a second ring of eight pages. `au_record` starts the input stream, copies each page as the device fills it into the caller's buffer, and stops when the buffer is full. The time it allows is the length at the rate, plus two seconds. Recorded sound is 16-bit stereo at the rate the device was opened with.

The driver interface is a table of ten routines (`ac97_ops`, `hda_ops`): name, open (rate), submit (a page), done (pages played so far), stop, set and get volume, and start, done and stop for recording.

## AC'97 (`ac97.asm`)

The mixer registers (NAM) are BAR0 and the bus master registers (NABM) BAR1, both I/O ports. At probe the driver clears the cold reset bit in the global control register, resets the codec's registers, turns on variable rates (extended audio register bit 0), and sets master 0 dB, PCM out 0 dB (`0x0808`), recording from line in at 0 dB gain.

Each direction (PCM in at NABM 0x00, PCM out at 0x10) has a list of 32 buffer descriptors (address, count of 16-bit samples, flags). The controller plays descriptor CIV, moves on, and stops (status bit DCH) after LVI. The driver writes each submitted page into the next descriptor and moves LVI to it, so the controller never runs past what is filled. "Done" is the number of descriptors before CIV, counted on as CIV goes round, or all of them once the controller has stopped. The rate is set in the front DAC rate register (0x2C) for playback and the ADC rate register (0x32) for recording, and read back to see whether the codec took it.

For recording all eight pages are given to descriptors 0–7. Each page that comes back full is given again eight descriptors later, and LVI moves with it.

Volume: master (0x02) and PCM out (0x18) are attenuations of 0 (loudest) to 31 in 1.5 dB steps, left in bits 8–12 and right in bits 0–4, with mute in bit 15. Record gain (0x1C) is 0–15, louder upwards. A level of 0–100 is turned into the nearest step and back, so a level reads back rounded (40 → 39 %).

## Intel HDA (`hda.asm`)

The registers are memory at BAR0, mapped with `vm_map_range` (which loads the kernel's page directory; the probe puts the caller's directory back). A program whose page directory was made before the probe gets the mapping copied in from the kernel's (`hda_mapcheck`), since each program's directory starts as a copy of the kernel's.

- **Reset**: clear and set `GCTL.CRST`, wait for codecs to show up in `STATESTS`, and use the first.
- **Verbs**: the CORB (256 commands) and RIRB (256 answers) share one page. A verb is written at `CORBWP + 1`; the answer is the RIRB entry after the last one read, once `RIRBWP` moves. `RIRBSTS` is cleared after each so the answer count never stops the ring.
- **Widgets**: from the root node's subordinate nodes, the audio function group (type 1) is powered up and its widgets are walked. The first output converter, the first pin that can drive an output, the first input converter and the first pin that can take input are kept. The output pin gets "out enable" and EAPD, the input pin "in enable". On QEMU's `hda-duplex` that is converter 2, pin 3, converter 4, pin 5 (`audio` prints `audio: hda codec 0, dac 2, pin 3, adc 4`).
- **Streams**: the first output stream (after the input streams, counted from `GCAP`) and the first input stream each get a buffer list of eight 4 KB entries over the ring's pages, a cyclic buffer length of 32 KB, and the stream format. The converter gets the same stream tag (1 for output, 2 for input) and format. The stream format names the rate from a 48 kHz or 44.1 kHz base with a multiplier and divider, which is why the rates are the eight in the table.
- **Position**: a stream plays its list round and round. "Done" is the buffer the link position (`LPIB`) is in, counted on each time it moves past the end; the layer reads it at least every tick while it waits, well inside the 0.18 s a 32 KB ring lasts at 44.1 kHz.
- **Volume**: master and PCM are both the output converter's amplifier (or the function group's when the converter has none); record is the input converter's. The amplifier's step count comes from its capabilities (QEMU: 0–74), and mute is bit 7 of the gain.

## Shell commands

- `audio` prints the device: `audio: ac97`, `audio: hda codec 0, dac 2, pin 3, adc 4`, or `audio: no device`.
- `audiotest` opens 22050 Hz 16-bit stereo, plays six pages (0.28 s) of a 1 kHz square wave, drains, and checks that it took at least 0.2 s and that the driver played all six pages. It then sets the master volume to 50 % and reads it back (45–55 %), mutes it and reads the mute back, puts it back to 100 %, and records one page where the device can record. It prints `audio: PASS ac97` (or `hda`), or `audio: FAIL` and a letter: `o` open, `w` write, `d` drain, `t` too fast, `p` position, `v` volume, `m` mute, `r` record.

Checks: `audio-none`, `audio-ac97`, `audiotest-ac97`, `audio-hda`, `audiotest-hda`, and `wavout-AC97`, `wavout-intel-hda` (what reached QEMU's wav backend is a 1 kHz tone for at least 0.25 s).

## SYS_AUDIO

`SYS_AUDIO` (46) takes the operation in `ebx`, as `SYS_GUI` does; ring-3 pointers are checked per operation (`UA_AUDIO`). `programs/audio.inc` has the numbers and WAV file helpers.

| `ebx` | Name | Arguments | Returns |
|-------|------|-----------|---------|
| 0 | `AU_INFO` | `ecx` = 16-byte block | 0: +0 the driver's name (`ac97`, `hda`), +8 flags (bit 0: can record), +12 the open rate; or −1 with no device |
| 1 | `AU_OPEN` | `ecx` = rate, `edx` = channels (1, 2) \| bits (8, 16) << 8 | 0, −1 no device or a format it does not play, −2 another program has it |
| 2 | `AU_WRITE` | `ecx` = samples, `edx` = bytes | bytes taken (whole frames), or −1 if the device stalled; waits while the ring is full |
| 3 | `AU_DRAIN` | — | 0 when everything is played (the device stops), −1 if it stalled |
| 4 | `AU_CLOSE` | — | 0; stops at once |
| 5 | `AU_GETVOL` | `ecx` = 0 master, 1 PCM, 2 record | left \| right << 8 \| mute << 16, levels 0–100; −1 with no device |
| 6 | `AU_SETVOL` | `ecx` = control, `edx` = as `AU_GETVOL` returns | 0, or −1 |
| 7 | `AU_RECORD` | `ecx` = buffer, `edx` = bytes | bytes recorded (16-bit stereo at the open rate), or −1 |
| 8 | `AU_POS` | — | bytes played since `AU_OPEN`, in the device's format |

The program that opens the device owns it until it closes it or ends; volume calls need no open.
