"""Checks the DOS build (dos\\wsconv.exe, go32v2) against the Windows build in DOSBox-X.
Usage: python dostest.py   (build first: DOSBox-X with build-dos.conf; Windows: fpc wsconv.pas)
Converts ..\\wsconvert-master\\samples\\*.WS to md, txt and rtf with both and compares the files."""
import glob
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SAMPLES = os.path.join(HERE, '..', 'wsconvert-master', 'samples')
DOSBOX = r'D:\DOSBox-X\dosbox-x.exe'
OUT = os.path.join(HERE, 'dostest')

CONF = r'''[sdl]
output = surface
[dosbox]
memsize = 512
[cpu]
cycles = max
[dos]
ver = 7.1
lfn = true
[autoexec]
mount c "%s"
mount s "%s"
c:
call dostest\run.bat
exit
'''

MODES = (('md', []), ('txt', ['-t']), ('rtf', ['-r']))


def main():
    shutil.rmtree(OUT, ignore_errors=True)
    os.makedirs(os.path.join(OUT, 'dos'))
    os.makedirs(os.path.join(OUT, 'win'))
    names = [os.path.basename(p)[:-3] for p in sorted(glob.glob(os.path.join(SAMPLES, '*.WS')))]
    bat = []
    for n in names:
        for ext, opts in MODES:
            bat.append(r'dos\wsconv S:\%s.WS %s -o C:\dostest\dos\%s.%s >> C:\dostest\log.txt'
                       % (n, ' '.join(opts), n, ext))
            subprocess.run([os.path.join(HERE, 'wsconv.exe'), os.path.join(SAMPLES, n + '.WS')] + opts
                           + ['-o', os.path.join(OUT, 'win', '%s.%s' % (n, ext))], check=True, capture_output=True)
    with open(os.path.join(OUT, 'run.bat'), 'w', newline='\r\n') as f:
        f.write('\n'.join(bat) + '\n')
    conf = os.path.join(OUT, 'test.conf')
    with open(conf, 'w') as f:
        f.write(CONF % (HERE, os.path.abspath(SAMPLES)))
    subprocess.run([DOSBOX, '-conf', conf, '-nopromptfolder'], timeout=600)
    bad = 0
    for n in names:
        for ext, _ in MODES:
            a = os.path.join(OUT, 'win', '%s.%s' % (n, ext))
            b = os.path.join(OUT, 'dos', '%s.%s' % (n, ext))
            same = os.path.exists(b) and open(a, 'rb').read() == open(b, 'rb').read()
            bad += not same
            if not same:
                print('DIFF', n, ext, 'missing' if not os.path.exists(b) else '')
    print('%d files compared, %d differ' % (len(names) * len(MODES), bad))
    sys.exit(1 if bad else 0)


if __name__ == '__main__':
    main()
