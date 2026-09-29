"""Checks that wsconv.exe (Free Pascal) gives the same output as the Python converter.

Usage: python compare.py [--exe PATH] [--corpus-only | --tests-only] [-v]

1. tests: every conversion made by ..\\wsconvert-master\\test_wsconvert.py is run again through the
   exe (same bytes, options, folder with .fi / .df files) and the results compared;
2. corpus: every WordStar document of the project (.WS, .DOC) converted to Markdown, text, RTF and
   RTF with -q by both.
RTF pictures are compared by size (\\picw ... \\pichgoal), not by PNG bytes (Pillow and fcl-image
compress differently)."""
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
PY = os.path.join(HERE, '..', 'wsconvert-master')
sys.path.insert(0, PY)
os.environ.setdefault('PYTHONHASHSEED', '0')

import wsconvert  # noqa: E402
import wsrtf  # noqa: E402

EXE = os.path.join(HERE, 'wsconv.exe')
VERBOSE = '-v' in sys.argv
fails, checked = [], [0]
# conversions the exe cannot repeat exactly: the Python call had no document path (&*& empty) or
# no picture folder (the exe always writes pictures next to its output)
KNOWN = []


def run_exe(args, cwd=None):
    r = subprocess.run([EXE] + args, capture_output=True, stdin=subprocess.DEVNULL, cwd=cwd)
    if r.returncode:
        raise RuntimeError('exe failed %d: %s' % (r.returncode, r.stderr.decode('utf-8', 'replace')))
    return r


def norm_rtf(s):
    return re.sub(r'(\\pichgoal-?\d+)\n[0-9a-f\n]*\}', r'\1 PNG}', s)


def report(name, want, got):
    checked[0] += 1
    if want == got:
        return
    fails.append(name)
    print('DIFF', name)
    if VERBOSE:
        import difflib
        for line in list(difflib.unified_diff(want.splitlines(), got.splitlines(), 'python', 'pascal', lineterm=''))[:40]:
            print('   ', line)


def cp_args(codepage):
    return ['-c', codepage.removeprefix('cp')] if codepage else []


# ---------------------------------------------------------------- 1. the unit tests' conversions

class ShadowConverter(wsconvert.Converter):
    def convert(self, chunk=None, in_note=False):
        result = super().convert(chunk, in_note)
        if chunk is not None or self.depth:
            return result
        want = result.strip('\n')
        name = 'test: ' + want[:50].replace('\n', ' | ')
        if b'\x1d' in self.data and self.image_dir is None and re.search(rb'\x1d..\x10', self.data, re.S):
            KNOWN.append(name + ' (no picture folder)')
            return result
        with tempfile.TemporaryDirectory() as tmp:
            base = self.base_dir if os.path.isdir(self.base_dir) and self.base_dir != '.' else tmp
            src = os.path.join(base, '__fpcin.ws')
            with open(src, 'wb') as f:
                f.write(self.data)
            out = os.path.join(self.image_dir or tmp, '__fpcout.txt')
            args = [src, '-o', out] + (['-t'] if self.textmode else []) + (['-m'] if self.merge else [])
            args += cp_args(self.codepage)
            for k, v in self.preset.items():
                args += ['-s', '%s=%s' % (k, v)]
            try:
                run_exe(args)
                with open(out, encoding='utf-8') as f:
                    got = f.read()
                got = got[:-1] if got.endswith('\n') else got
            except Exception as e:                      # noqa: BLE001
                got = 'EXE ERROR: %s' % e
            finally:
                os.remove(src)
                if os.path.exists(out):
                    os.remove(out)
        if self.merge and re.search(rb'&[*:.\\]&', self.data):
            KNOWN.append(name + ' (document path)')
            return result
        report(name, want, got)
        return result


class ShadowRtf(wsrtf.RtfWriter):
    def document(self):
        result = super().document()
        if self.depth:
            return result
        with tempfile.TemporaryDirectory() as tmp:
            base = self.base_dir if os.path.isdir(self.base_dir) and self.base_dir != '.' else tmp
            src = os.path.join(base, '__fpcin.ws')
            with open(src, 'wb') as f:
                f.write(self.data)
            out = os.path.join(tmp, '__fpcout.rtf')
            args = [src, '-r', '-o', out] + (['-q'] if self.quotes else [])
            if getattr(self, '_given_cp', None):
                args += cp_args(self._given_cp)
            try:
                run_exe(args)
                with open(out, 'rb') as f:
                    got = f.read().decode('ascii').replace('\r\n', '\n')
            except Exception as e:                      # noqa: BLE001
                got = 'EXE ERROR: %s' % e
            finally:
                os.remove(src)
        report('rtf test: ' + result[-60:].replace('\n', ' | '), norm_rtf(result), norm_rtf(got))
        return result


_rtf_init = wsrtf.RtfWriter.__init__


def rtf_init(self, data, base_dir='.', codepage=None, *a, **kw):
    _rtf_init(self, data, base_dir, codepage, *a, **kw)
    self._given_cp = codepage


def run_tests():
    original = wsconvert.Converter, wsrtf.RtfWriter
    wsconvert.Converter = ShadowConverter
    ShadowRtf.__init__ = rtf_init
    wsrtf.RtfWriter = ShadowRtf
    cwd = os.getcwd()
    os.chdir(PY)
    try:
        import test_wsconvert                      # noqa: F401  (its checks run on import)
    except SystemExit:
        pass
    finally:
        os.chdir(cwd)
        wsconvert.Converter, wsrtf.RtfWriter = original     # the corpus runs the plain classes


# ---------------------------------------------------------------- 2. corpus

def corpus_files():
    root = os.path.normpath(os.path.join(HERE, '..'))
    files = []
    for pat in ('**/*.WS', '**/*.ws', '**/*.DOC', '**/*.doc'):
        files += glob.glob(os.path.join(root, pat), recursive=True)
    skip = ('sandbox', 'wsconvert')
    return sorted({f for f in files if not any(s in f.split(os.sep) for s in skip)})


def run_corpus():
    tmp = tempfile.mkdtemp()
    try:
        for path in corpus_files():
            rel = os.path.relpath(path, os.path.join(HERE, '..'))
            with open(path, 'rb') as f:
                data = f.read()
            base = os.path.dirname(os.path.abspath(path))
            for mode in ('md', 'txt'):
                outdir = os.path.join(tmp, mode + 'py')
                os.makedirs(outdir, exist_ok=True)
                conv = wsconvert.Converter(data, mode == 'txt', base, doc_path=path, image_dir=outdir)
                want = conv.convert().strip('\n')
                exedir = os.path.join(tmp, mode + 'pas')
                os.makedirs(exedir, exist_ok=True)
                out = os.path.join(exedir, 'out.' + mode)
                try:
                    run_exe([path, '-o', out] + (['-t'] if mode == 'txt' else []))
                    with open(out, encoding='utf-8') as f:
                        got = f.read().strip('\n')
                except Exception as e:                  # noqa: BLE001
                    got = 'EXE ERROR: %s' % e
                report('%s %s' % (mode, rel), want, got)
            for quotes in (False, True):
                w = wsrtf.RtfWriter(data, base, doc_path=path, quotes=quotes)
                want = w.document()
                out = os.path.join(tmp, 'out.rtf')
                try:
                    run_exe([path, '-r', '-o', out] + (['-q'] if quotes else []))
                    with open(out, 'rb') as f:
                        got = f.read().decode('ascii').replace('\r\n', '\n')
                except Exception as e:                  # noqa: BLE001
                    got = 'EXE ERROR: %s' % e
                report('rtf%s %s' % (' -q' if quotes else '', rel), norm_rtf(want), norm_rtf(got))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == '__main__':
    if '--exe' in sys.argv:
        EXE = sys.argv[sys.argv.index('--exe') + 1]
    if '--corpus-only' not in sys.argv:
        run_tests()
    if '--tests-only' not in sys.argv:
        run_corpus()
    for k in KNOWN:
        print('skipped', k)
    print('%d compared, %d differ' % (checked[0], len(fails)))
    sys.exit(1 if fails else 0)
