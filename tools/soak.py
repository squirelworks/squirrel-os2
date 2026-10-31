#!/usr/bin/env python3
"""Long stress session for Squirrel-OS/2 in one QEMU boot. Original code.

Usage: tools/soak.py [--rounds N] [--gfx N] [--keep DIR]
Needs nasm, qemu-system-i386 and python3, like tools/regress.sh.

It builds the kernel and a data disk with the sample programs (stress
among them), boots once, and then, without rebooting:

  1. runs `run stress` N times (default 5): threads filling the process
     table under preemption, a message ring, a message flood, preempted
     FPU work, the whole 4 MB heap, thread churn and parallel exec
     (programs/stress.asm);
  2. starts a thread that keeps printing, and meanwhile runs gfxtest,
     gfxprim and gfxtext N times each (default 10);
  3. fills edit to its 16 KB limit, saves and checks the size with wc;
  4. checks `ps` shows only the shell, `mem` reports as much free memory
     as at the start, and `systest` still passes.

Prints one line per step and `soak: PASS` or `soak: FAIL`; exits 0 or 1.
"""
import argparse, os, re, shutil, socket, subprocess, sys, tempfile, time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
from qemu_screen import KEYMAP  # noqa: E402

# A program that prints a dot every so often from a thread, after its own
# main has returned (so the shell is back while it runs)
BG_PROGRAM = r'''%include "sqx.inc"
SQX_HEADER main
main:
    mov eax, SYS_SPAWN
    mov ebx, kid
    int 0x80
    xor eax, eax
    ret
kid:
    mov esi, 40
.l: mov eax, SYS_PUTS
    mov ebx, m
    int 0x80
    mov ecx, 40000000
.d: dec ecx
    jnz .d
    dec esi
    jnz .l
    xor eax, eax
    ret
m db '.', 0
SQX_BSS
SQX_END
'''


class Session:
    """One QEMU boot driven through its monitor."""

    def __init__(self, image, disk, tmp):
        self.tmp = tmp
        mon = os.path.join(tmp, 'mon')
        self.q = subprocess.Popen(
            ['qemu-system-i386', '-display', 'none',
             '-drive', f'format=raw,file={image},index=0,media=disk',
             '-drive', f'format=raw,file={disk},index=1,media=disk',
             '-monitor', f'unix:{mon},server,nowait'])
        for _ in range(100):
            if os.path.exists(mon):
                break
            time.sleep(0.05)
        self.s = socket.socket(socket.AF_UNIX)
        self.s.connect(mon)
        self.n = 0
        self.wait_for('> ', 20)

    def monitor(self, cmd, wait=0.03):
        self.s.sendall((cmd + '\n').encode())
        time.sleep(wait)
        self.s.setblocking(False)
        try:
            while self.s.recv(65536):
                pass
        except BlockingIOError:
            pass
        self.s.setblocking(True)

    def key(self, k):
        self.monitor('sendkey ' + k)

    def type(self, text):
        for ch in text:
            k = KEYMAP.get(ch, ch)
            if ch.isupper():
                k = 'shift-' + ch.lower()
            self.key(k)

    def line(self, text):
        self.type(text)
        self.key('ret')

    def screen(self):
        self.n += 1
        dump = os.path.join(self.tmp, f'vga{self.n}.bin')
        self.monitor(f'pmemsave 0xb8000 4000 "{dump}"')
        for _ in range(200):
            if os.path.exists(dump) and os.path.getsize(dump) == 4000:
                break
            time.sleep(0.02)
        data = open(dump, 'rb').read()
        os.unlink(dump)
        return [data[r * 160:(r + 1) * 160:2].decode('cp437').rstrip()
                for r in range(25)]

    def alive(self):
        if self.q.poll() is not None:
            raise RuntimeError('QEMU exited')

    def wait_for(self, text, timeout):
        end = time.time() + timeout
        while time.time() < end:
            rows = self.screen()
            if any(text in r for r in rows):
                return rows
            self.alive()
            time.sleep(0.2)
        raise TimeoutError(f'no {text!r} within {timeout}s')

    def wait_after(self, marker, text, timeout):
        """Waits for a line containing text below the line that starts
        with marker; returns that line."""
        end = time.time() + timeout
        while time.time() < end:
            rows = self.screen()
            at = [i for i, r in enumerate(rows) if r.startswith(marker)]
            if at:
                for r in rows[at[-1] + 1:]:
                    if text in r:
                        return r
            self.alive()
            time.sleep(0.2)
        raise TimeoutError(f'no {text!r} after {marker!r} within {timeout}s')

    def run(self, command, timeout=120):
        """Types a shell command, waits for the prompt to come back on the
        last line, returns the lines printed after the command line."""
        self.line(command)
        time.sleep(0.3)
        end = time.time() + timeout
        while time.time() < end:
            rows = self.screen()
            while rows and not rows[-1]:
                rows.pop()
            if rows and rows[-1] == '>':
                out = []
                for r in reversed(rows[:-1]):
                    if r in ('> ' + command, '>' + command):
                        break
                    out.append(r)
                return out[::-1]
            self.alive()
            time.sleep(0.3)
        raise TimeoutError(f'{command!r} still running after {timeout}s')

    def close(self):
        try:
            self.monitor('quit')
            self.q.wait(5)
        except (OSError, subprocess.TimeoutExpired):
            self.q.kill()


def build(out):
    subprocess.check_call([sys.executable, os.path.join(ROOT, 'tools', 'mkstrings.py'), '--check'])
    kernel = os.path.join(ROOT, 'kernel')
    subprocess.check_call(['nasm', '-f', 'bin', 'boot.asm', '-o', f'{out}/boot.bin'], cwd=kernel)
    subprocess.check_call(['nasm', '-f', 'bin', 'pm.asm', '-o', f'{out}/pm.bin'], cwd=kernel,
                          stderr=subprocess.DEVNULL)
    with open(f'{out}/os.img', 'wb') as f:
        for part in ('boot.bin', 'pm.bin'):
            f.write(open(f'{out}/{part}', 'rb').read())
    sqfs = [sys.executable, os.path.join(ROOT, 'tools', 'sqfs.py'), f'{out}/data.img']
    subprocess.check_call(sqfs + ['format', '4096'], stdout=subprocess.DEVNULL)
    progs = os.path.join(ROOT, 'programs')
    open(f'{out}/soakbg.asm', 'w').write(BG_PROGRAM)
    sources = [os.path.join(progs, n) for n in sorted(os.listdir(progs)) if n.endswith('.asm')]
    for src in sources + [f'{out}/soakbg.asm']:
        name = os.path.basename(src)[:-4]
        subprocess.check_call(['nasm', '-f', 'bin', '-i', progs + '/', src, '-o', f'{out}/{name}'])
        subprocess.check_call(sqfs + ['put', f'{out}/{name}'], stdout=subprocess.DEVNULL)
    # 16380 bytes: four short of the editor's 16 KB buffer
    open(f'{out}/big', 'w').write(('x' * 79 + '\n') * 204 + 'y' * 60)
    subprocess.check_call(sqfs + ['put', f'{out}/big'], stdout=subprocess.DEVNULL)


def main():
    ap = argparse.ArgumentParser(description='Long stress session for Squirrel-OS/2')
    ap.add_argument('--rounds', type=int, default=5, help='times to run the stress program')
    ap.add_argument('--gfx', type=int, default=10, help='rounds of the three graphics tests')
    ap.add_argument('--keep', help='build into this directory and keep it')
    args = ap.parse_args()
    out = args.keep or tempfile.mkdtemp(prefix='soak-')
    os.makedirs(out, exist_ok=True)
    build(out)
    failed = []

    def step(name, ok, detail=''):
        print(f"{'ok  ' if ok else 'FAIL'} {name}{(' ' + detail) if detail else ''}", flush=True)
        if not ok:
            failed.append(name)

    s = Session(f'{out}/os.img', f'{out}/data.img', out)

    def free_kb():
        s.run('ps')                     # frees zombies nobody can wait for
        rows = s.run('mem')
        m = re.search(r'(\d+) KB free', rows[-1] if rows else '')
        return int(m.group(1)) if m else -1

    try:
        start_free = free_kb()
        step('mem at start', start_free > 0, f'{start_free} KB free')
        for i in range(args.rounds):
            t = time.time()
            rows = s.run('run stress', 600)
            bad = [r for r in rows if 'FAIL' in r or '***' in r]
            ok = bool(rows) and rows[-1] == 'stress: PASS' and not bad
            step(f'stress round {i + 1}', ok, f'{time.time() - t:.1f}s' + (' ' + '; '.join(bad) if bad else ''))
            if not ok:
                break
        s.line('run soakbg')                # its dots keep coming after the prompt
        s.wait_for('> ', 10)
        gfx = {'gfxtest': 0, 'gfxprim': 0, 'gfxtext': 0}
        for i in range(args.gfx):
            for c in gfx:
                mark = f'mark-{c}-{i}'      # the result must come after it
                s.line(f'echo {mark}')
                s.wait_for(mark, 10)
                s.line(c)
                gfx[c] += f'{c}: PASS' in s.wait_after(mark, f'{c}: ', 30)
        step('graphics with a thread printing', all(v == args.gfx for v in gfx.values()),
             ', '.join(f'{k} {v}/{args.gfx}' for k, v in gfx.items()))
        s.line('run edit big')
        s.wait_for('Loaded', 15)
        for _ in range(20):
            s.key('pgdn')
        s.key('end')
        s.type('abcdefgh')
        rows = s.screen()
        full = any('Buffer full' in r for r in rows)
        s.key('ctrl-s')
        s.wait_for('Saved', 10)
        s.key('esc')
        time.sleep(0.5)
        rows = s.run('run wc big')
        step('edit at its 16 KB limit', full and bool(rows) and ' 16384 big' in rows[-1],
             rows[-1] if rows else '')
        end = time.time() + 120             # let the printing thread finish
        while True:
            s.line('')
            rows = s.run('ps')
            if len(rows) <= 2 or time.time() > end:
                break
            time.sleep(2)
        step('only the shell is left', len(rows) == 2 and 'shell' in rows[1], '; '.join(rows[1:]))
        end_free = free_kb()
        step('no memory lost', end_free == start_free, f'{start_free} -> {end_free} KB free')
        rows = s.run('systest')
        step('systest after all that', bool(rows) and rows[-1] == 'systest: PASS')
    except (TimeoutError, RuntimeError) as e:
        step('session', False, str(e))
        print('\n'.join(s.screen()))
    finally:
        s.close()
        if not args.keep:
            shutil.rmtree(out, ignore_errors=True)
    print('soak: FAIL' if failed else 'soak: PASS')
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
