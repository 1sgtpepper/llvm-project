#!/usr/bin/env python3
"""Measure whether successor-query caching penalizes many small scheduling DAGs."""
import argparse
import hashlib
import importlib.util
import itertools
import json
from pathlib import Path
import random
import subprocess
import time

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--baseline', required=True)
p.add_argument('--candidate', required=True)
p.add_argument('--output', type=Path, required=True)
p.add_argument('--functions', type=int, default=1000)
args = p.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
spec = importlib.util.spec_from_file_location('wide', Path(__file__).with_name('wide-vector-reduction.py'))
wide = importlib.util.module_from_spec(spec)
spec.loader.exec_module(wide)
cases = list(itertools.product([2, 8, 32], ['ordered', 'no-reduce'], ['nvptx64-nvidia-cuda', 'x86_64-unknown-linux-gnu']))
for width, kind, triple in cases:
    module = wide.module(width, kind).replace('nvptx64-nvidia-cuda', triple)
    prefix, function = module.split('define void @kernel', 1)
    body = '\n'.join(f'define void @kernel{i}{function}' for i in range(args.functions))
    (args.output / f'{kind}-{width}-{triple}.ll').write_text(prefix + body)
labels = {'baseline': args.baseline, 'candidate': args.candidate}
rng = random.Random(211018)
failed = False
with (args.output / 'measurements.jsonl').open('w') as records:
    for trial in range(4):
        order = list(itertools.product(labels, cases))
        rng.shuffle(order)
        for label, (width, kind, triple) in order:
            name = f'{label}-{kind}-{width}-{triple}-{trial}'
            source = args.output / f'{kind}-{width}-{triple}.ll'
            assembly = args.output / f'{label}-{kind}-{width}-{triple}.s'
            usage = args.output / f'{name}.usage'
            command = ['timeout', '--kill-after=5s', '180s', '/usr/bin/time', '-f', '%U %S %M', '-o', str(usage), labels[label], str(source), '-o', str(assembly)]
            start = time.monotonic()
            with (args.output / f'{name}.stderr').open('w') as err:
                result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=err)
            record = {'compiler': label, 'width': width, 'kind': f'{kind}-{triple}', 'functions': args.functions, 'trial': trial, 'warmup': trial == 0, 'command': command, 'returncode': result.returncode, 'wall_seconds': time.monotonic() - start, 'usage': usage.read_text() if usage.exists() else None, 'assembly_sha256': hashlib.sha256(assembly.read_bytes()).hexdigest() if result.returncode == 0 else None}
            records.write(json.dumps(record) + '\n')
            records.flush()
            print(json.dumps(record), flush=True)
            failed |= result.returncode != 0
raise SystemExit(bool(failed))
