#!/usr/bin/env python3
"""Check the operand-count boundary found in the original comparison."""
import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--baseline', required=True)
p.add_argument('--candidate', required=True)
p.add_argument('--output', required=True, type=Path)
args = p.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location('wide', Path(__file__).with_name('wide-vector-reduction.py'))
wide = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wide)
failed = False
with (args.output / 'boundary.jsonl').open('w') as records:
    for width in [32767, 32768, 32769]:
        source = args.output / f'ordered-{width}.ll'
        source.write_text(wide.module(width, 'ordered'))
        results = []
        for label, exe in [('baseline', args.baseline), ('candidate', args.candidate)]:
            stem = args.output / f'{label}-{width}'
            assembly = stem.with_suffix('.s')
            stderr = stem.with_suffix('.stderr')
            command = ['timeout', '--kill-after=5s', '180s', exe, str(source), '-mcpu=sm_80', '-mattr=+ptx70', '-verify-machineinstrs', '-o', str(assembly)]
            start = time.monotonic()
            with stderr.open('w') as err:
                result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=err)
            diagnostic = stderr.read_text(errors='replace')
            digest = hashlib.sha256(assembly.read_bytes()).hexdigest() if result.returncode == 0 else None
            expected = result.returncode == 0 if width <= 32768 else result.returncode == -6 and 'too many operands to fit into SDNode' in diagnostic
            row = {'compiler': label, 'width': width, 'command': command, 'returncode': result.returncode, 'wall_seconds': time.monotonic() - start, 'sha256': digest, 'expected': expected, 'diagnostic_first_line': diagnostic.splitlines()[:1]}
            records.write(json.dumps(row) + '\n')
            records.flush()
            print(json.dumps(row), flush=True)
            failed |= not expected
            results.append((result.returncode, digest))
        failed |= results[0] != results[1]
(args.output / 'ordered-65535.ll').write_text(wide.module(65535, 'ordered'))
raise SystemExit(bool(failed))
