# Sound programs (3.0, A.6)

Programs on the data disk that use the sound device through `SYS_AUDIO` (`../kernel/audio.md`). The regression run puts them on a disk of their own (`snd.img`) with two test tones: `tone1k.wav` (1 kHz, 22050 Hz, 16-bit mono, 0.5 s) and `tone8.wav` (440 Hz, 11025 Hz, 8-bit stereo, 0.5 s).

## WAV player (`run wavplay <file.wav>`)

Plays 8- or 16-bit PCM, mono or stereo, at any of the eight rates the device takes. It reads the RIFF chunks (`fmt `, then `data`, stepping over any others), prints the format and length, writes the samples 4 KB at a time, and drains:

    wavplay: 22050 Hz, 16-bit, mono, 0.50 s
    wavplay: played 11025 frames

Without a device it prints `wavplay: no sound device, or that format is not played`. Checks: `wavplay-nodev`, `wavplay-ac97`, `wavplay-ac97-8`, `wavplay-hda`, `wavout-*`.

## Sound recorder (`run sndrec <file.wav> [seconds]`)

Records 1 to 10 seconds (2 by default) at 22050 Hz, 16-bit stereo, from the device's input, into memory from `SYS_SBRK`, and saves a WAV file:

    sndrec: 1.00 s, 88200 bytes, peak 0 -> rec.wav

`peak` is the loudest sample (0 to 32768); QEMU's `none` backend records silence, so it is 0 there. Checks: `sndrec-ac97` (and playing the result back), `sndrec-hda`.

## Mixer (`run mixer`)

A window with three sliders: Master, PCM and Record. Each shows its level, green, or red when muted, with the percentage and `on`/`muted` under it. The levels are what the codec reads back, so they come back rounded to its steps. On HDA, Master and PCM are the same amplifier.

| Key | Action |
|-----|--------|
| Left, Right, Tab | pick a slider (its name turns white on blue) |
| Up, Down | 5 % up or down |
| PgUp, PgDn | 25 % |
| M | mute or unmute |
| left click on a slider | sets it to that height |
| Esc | closes |

From the shell: `run mixer show` prints `master  100%  100%  on` and the other two; `run mixer <master|pcm|record> <0-100>` sets both sides; `run mixer <control> mute` / `unmute`. Each prints the three controls afterwards. Checks: `mixer-ac97`, `mixer-gui-ac97`, `mixer-quit`, `mixer-hda`, `mixer-hda-mute`.

## Spectrum analyser (`run spectrum <file.wav>`, `run spectrum live`)

Plays a WAV file and shows the spectrum of each block of 1024 frames as it goes: 64 green bars from 0 Hz to half the rate, 0 to 90 dB, the loudest in yellow, and `Peak 1000 Hz` under them. Without a device it shows the blocks without sound, a twentieth of a second each. `run spectrum live` shows the device's input instead, 1024 frames at a time. Esc stops.

Each block is mixed to mono, given a Hann window, and run through a 1024-point radix-2 FFT (decimation in time, x87 doubles, twiddles from `fsincos`). A bar is the loudest bin of its eight, as 20 log10 of the magnitude (full scale = 90 dB). The peak frequency is the loudest bin from 2 up, moved by a parabola through it and its two neighbours (in dB), which finds a 1 kHz tone at 22050 Hz as 1000 Hz although the bins are 21.5 Hz apart.

`run spectrum <file.wav> test` prints the first block's peak without a window or sound: `spectrum: peak 1000 Hz, 80 dB`. Checks: `spectrum-test`, `spectrum-8bit`, `spectrum-gui`.
