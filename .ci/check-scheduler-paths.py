#!/usr/bin/env python3
"""Check finite graph families and reject data cycles using actual owner binaries."""
import subprocess
import sys
from pathlib import Path
out = Path(sys.argv[1])
out.mkdir(parents=True, exist_ok=True)
for label in ['baseline', 'candidate']:
    executable = str((out / f'paths-{label}').resolve())
    with (out / f'{label}-paths.txt').open('w') as log:
        subprocess.run(['timeout', '--kill-after=5s', '180s', executable, 'exhaustive'], stdout=log, stderr=subprocess.STDOUT, check=True)
        for count, slots in [(1, 1), (2, 2), (3, 64), (32, 128)]:
            result = subprocess.run([executable, 'cycle', str(count), str(slots)], stdout=log, stderr=subprocess.STDOUT, timeout=10)
            if result.returncode != -6:
                raise SystemExit(f'{label}: cycle {count}/{slots}: expected SIGABRT, got {result.returncode}')
        log.write('All cycle cases terminated with SIGABRT.\n')
    with (out / f'{label}-paths.csv').open('w') as log:
        for shape in ['chain', 'star', 'diamonds']:
            for count in [1024, 4096, 16384, 65536]:
                subprocess.run(['timeout', '--kill-after=5s', '180s', executable, 'benchmark', shape, str(count)], stdout=log, stderr=subprocess.STDOUT, check=True)
