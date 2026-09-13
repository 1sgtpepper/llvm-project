#!/usr/bin/env python3
"""Compare compiler results at fixed-vector, FP, target and scheduler boundaries."""
import argparse
import hashlib
import itertools
import json
from pathlib import Path
import subprocess


def ir(width, ty, op, flags, start):
    suffix = {'half': 'f16', 'bfloat': 'bf16', 'float': 'f32', 'double': 'f64'}[ty]
    vec = f'<{width} x {ty}>'
    fn = f'llvm.vector.reduce.{op}.v{width}{suffix}'
    if ty in ('half', 'bfloat') and start != '%start':
        prefix = '0xH' if ty == 'half' else '0xR'
        start = prefix + ('8000' if start.startswith('-') else '0000')
    return f'''target triple = "nvptx64-nvidia-cuda"
declare {ty} @{fn}({ty}, {vec})
define {ty} @reduce({ty} %start, {vec} %input) {{
  %square = fmul {vec} %input, %input
  %r = call {flags}{ty} @{fn}({ty} {start}, {vec} %square)
  ret {ty} %r
}}
'''


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--baseline', required=True)
    p.add_argument('--candidate', required=True)
    p.add_argument('--output', type=Path, required=True)
    p.add_argument('--wide-widths', type=int, nargs='*', default=[65535, 65536, 65537])
    args = p.parse_args()
    out = args.output
    out.mkdir(parents=True, exist_ok=True)
    records = (out / 'boundaries.jsonl').open('w')
    checked = 0
    failed = []

    def compare(name, source, flags):
        nonlocal checked
        path = out / f'{name}.ll'
        path.write_text(source)
        values = []
        for label, exe in [('baseline', args.baseline), ('candidate', args.candidate)]:
            output = out / f'{name}-{label}.s'
            stderr = out / f'{name}-{label}.stderr'
            command = ['timeout', '--kill-after=5s', '180s', exe, str(path), '-o', str(output), '-verify-machineinstrs', *flags]
            with stderr.open('w') as err:
                result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=err)
            digest = hashlib.sha256(output.read_bytes()).hexdigest() if result.returncode == 0 else None
            values.append((result.returncode, digest))
            records.write(json.dumps({'name': name, 'compiler': label, 'command': command, 'returncode': result.returncode, 'sha256': digest}) + '\n')
            records.flush()
        if values[0] != values[1] or values[0][0] != 0:
            failed.append((name, values))
        checked += 1
        if checked % 100 == 0:
            print(f'Compared {checked} cases; {len(failed)} failures', flush=True)

    # Each flag is independent. In particular contract does not imply reassoc.
    settings = [
        ('sm80', ['-mcpu=sm_80', '-mattr=+ptx70']),
        ('sm100', ['-mcpu=sm_100', '-mattr=+ptx88']),
        ('sm100-unpacked', ['-mcpu=sm_100', '-mattr=+ptx88', '-nvptx-no-f32x2']),
    ]
    count = 0
    for width, ty, op, fmf, start in itertools.product(
            [1, 2, 3, 7, 8, 9, 63, 64, 65],
            ['half', 'bfloat', 'float', 'double'], ['fadd', 'fmul'],
            ['', 'reassoc ', 'contract ', 'nsz ', 'nnan ', 'fast '],
            ['%start', '0.000000e+00', '-0.000000e+00']):
        # Rotate targets over the full matrix, then exercise every target for the
        # compact packing/odd-width boundary slice below. This is not a full
        # Cartesian product of every target and every flag combination.
        target, flags = settings[count % len(settings)]
        compare(f'fp-{count}-{target}', ir(width, ty, op, fmf, start), flags)
        count += 1
    for width, ty, op, (target, flags), opt in itertools.product(
            [1, 2, 3, 7, 8, 9], ['half', 'bfloat', 'float', 'double'],
            ['fadd', 'fmul'], settings, ['-O0', '-O2']):
        compare(f'packing-{width}-{ty}-{op}-{target}-{opt[1:]}',
                ir(width, ty, op, '', '%start'), [*flags, opt])

    for width, bits, op in itertools.product(
            [1, 3, 8, 65], [1, 8, 32, 64],
            ['add', 'mul', 'and', 'or', 'xor', 'smin', 'smax', 'umin', 'umax']):
        ty, vec = f'i{bits}', f'<{width} x i{bits}>'
        fn = f'llvm.vector.reduce.{op}.v{width}i{bits}'
        source = f'target triple = "nvptx64-nvidia-cuda"\ndeclare {ty} @{fn}({vec})\ndefine {ty} @reduce({vec} %x) {{\n %r = call {ty} @{fn}({vec} %x)\n ret {ty} %r\n}}\n'
        compare(f'int-{width}-{bits}-{op}', source, settings[count % 3][1])
        count += 1
    for width, ty, op in itertools.product(
            [1, 3, 8, 65], ['half', 'bfloat', 'float', 'double'],
            ['fmin', 'fmax', 'fminimum', 'fmaximum']):
        suffix = {'half': 'f16', 'bfloat': 'bf16', 'float': 'f32', 'double': 'f64'}[ty]
        vec, fn = f'<{width} x {ty}>', f'llvm.vector.reduce.{op}.v{width}{suffix}'
        source = f'target triple = "nvptx64-nvidia-cuda"\ndeclare {ty} @{fn}({vec})\ndefine {ty} @reduce({vec} %x) {{\n %r = call {ty} @{fn}({vec} %x)\n ret {ty} %r\n}}\n'
        compare(f'minmax-{width}-{ty}-{op}', source, settings[count % 3][1])
        count += 1

    for width, mode, stress in itertools.product(
            [1, 3, 8, 65, 1024], ['source', 'list-burr', 'list-hybrid', 'list-ilp'], [False, True]):
        flags = ['-mtriple=x86_64-unknown-linux-gnu', f'-pre-RA-sched={mode}']
        if stress:
            flags.append('-stress-sched')
        compare(f'x86-{width}-{mode}-{stress}', ir(width, 'float', 'fadd', '', '%start'), flags)

    # Powers of two and their immediate neighbors use the exact memory form in
    # the report. Keep this large slice separate from the small Cartesian matrix.
    import importlib.util
    spec = importlib.util.spec_from_file_location('wide', Path(__file__).with_name('wide-vector-reduction.py'))
    wide = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(wide)
    for width, kind, (target, flags) in itertools.product(
            args.wide_widths, ['ordered', 'reassoc'], settings):
        compare(f'wide-{width}-{kind}-{target}', wide.module(width, kind), flags)

    records.close()
    print(f'Compared {checked} cases; {len(failed)} failures', flush=True)
    for name, values in failed:
        print(name, values)
    raise SystemExit(bool(failed))


if __name__ == '__main__':
    main()
