#!/usr/bin/env python3
"""Measure issue 211018 and controls with existing, explicitly supplied llc builds."""

import argparse
import hashlib
import itertools
import json
from pathlib import Path
import random
import subprocess
import time


def module(width, kind):
    vector = f"<{width} x float>"
    lines = [
        'target datalayout = "e-p:64:64-i64:64-i128:128-v16:16-v32:32-n16:32:64-S32"',
        'target triple = "nvptx64-nvidia-cuda"',
        f"declare float @llvm.vector.reduce.fadd.v{width}f32(float, {vector})",
        "define void @kernel(ptr addrspace(1) %out, ptr addrspace(1) %in) {",
        "entry:",
    ]
    if kind == "scalar-chain":
        accumulator = "0.000000e+00"
        for index in range(width):
            lines.extend([
                f"  %p{index} = getelementptr float, ptr addrspace(1) %in, i64 {index}",
                f"  %v{index} = load float, ptr addrspace(1) %p{index}, align 4",
                f"  %m{index} = fmul float %v{index}, %v{index}",
                f"  %s{index} = fadd float {accumulator}, %m{index}",
            ])
            accumulator = f"%s{index}"
        lines.append(f"  store float {accumulator}, ptr addrspace(1) %out, align 4")
    else:
        lines.append(f"  %val = load {vector}, ptr addrspace(1) %in, align 32")
        value = "%val"
        if kind != "load-reduce":
            lines.append(f"  %mul = fmul {vector} %val, %val")
            value = "%mul"
        if kind == "no-reduce":
            lines.append(f"  store {vector} {value}, ptr addrspace(1) %out, align 32")
        else:
            flags = "reassoc " if kind == "reassoc" else ""
            lines.extend([
                f"  %res = call {flags}float @llvm.vector.reduce.fadd.v{width}f32(float 0.000000e+00, {vector} {value})",
                "  store float %res, ptr addrspace(1) %out, align 4",
            ])
    return "\n".join(lines + ["  ret void", "}", ""])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", nargs=2, action="append", metavar=("LABEL", "LLC"))
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--widths", type=int, nargs="+", default=[1024, 4096, 16384, 65536])
    kinds = ["ordered", "reassoc", "no-reduce", "load-reduce", "scalar-chain"]
    parser.add_argument("--kinds", nargs="+", choices=kinds, default=kinds)
    parser.add_argument("--repetitions", type=int, default=3)
    parser.add_argument("--timeout", type=int, default=180)
    parser.add_argument("--llc-arg", action="append", default=[])
    parser.add_argument("--generate-only", action="store_true")
    args = parser.parse_args()
    if any(width < 1 for width in args.widths) or args.repetitions < 1 or args.timeout < 1:
        parser.error("widths, repetitions and timeout must be positive")
    if not args.generate_only and not args.compiler:
        parser.error("supply --compiler or --generate-only")
    args.output.mkdir(parents=True, exist_ok=True)
    inputs = args.output / "inputs"
    inputs.mkdir(exist_ok=True)
    cases = list(itertools.product(args.widths, args.kinds))
    for width, kind in cases:
        (inputs / f"{kind}-{width}.ll").write_text(module(width, kind))
    if args.generate_only:
        return
    compilers = {label: str(Path(path).resolve()) for label, path in args.compiler}
    if len(compilers) != len(args.compiler):
        parser.error("compiler labels must be unique")
    for label, executable in compilers.items():
        if not label.replace("-", "").isalnum():
            parser.error("compiler labels must be alphanumeric with optional hyphens")
        (args.output / f"{label}-version.txt").write_text(
            subprocess.check_output([executable, "--version"], text=True)
        )
    rng = random.Random(211018)
    failed = False
    failed_cases = set()
    with (args.output / "measurements.jsonl").open("w") as records:
        # Trial zero warms filesystem and executable pages and is excluded from timing comparisons.
        for trial in range(args.repetitions + 1):
            order = list(itertools.product(compilers, cases))
            rng.shuffle(order)
            for label, (width, kind) in order:
                if (label, width, kind) in failed_cases:
                    continue
                name = f"{label}-{kind}-{width}-{trial}"
                source = inputs / f"{kind}-{width}.ll"
                assembly = args.output / f"{label}-{kind}-{width}.s"
                usage = args.output / f"{name}.usage"
                command = [
                    "timeout", "--kill-after=5s", f"{args.timeout}s",
                    "/usr/bin/time", "-f", "%U %S %M", "-o", str(usage),
                    compilers[label], str(source), *args.llc_arg, "-o", str(assembly),
                ]
                start = time.monotonic()
                with (args.output / f"{name}.stderr").open("w") as stderr:
                    result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=stderr)
                record = {
                    "compiler": label, "width": width, "kind": kind, "trial": trial,
                    "warmup": trial == 0, "command": command, "returncode": result.returncode,
                    "wall_seconds": time.monotonic() - start,
                    "usage": usage.read_text() if usage.exists() else None,
                    "assembly_sha256": hashlib.sha256(assembly.read_bytes()).hexdigest()
                    if result.returncode == 0 else None,
                }
                records.write(json.dumps(record) + "\n")
                records.flush()
                print(json.dumps(record), flush=True)
                failed |= result.returncode != 0
                if result.returncode != 0:
                    failed_cases.add((label, width, kind))
    # Separate region timers from uninstrumented timing measurements.
    with (args.output / "diagnostics.jsonl").open("w") as diagnostics:
        for label, executable in compilers.items():
            for kind in args.kinds:
                successful_widths = [
                    width for width in args.widths
                    if (label, width, kind) not in failed_cases
                ]
                if not successful_widths:
                    continue
                width = max(successful_widths)
                source = inputs / f"{kind}-{width}.ll"
                log = args.output / f"{label}-{kind}-{width}-time-passes.txt"
                command = [
                    "timeout", "--kill-after=5s", f"{args.timeout}s", executable,
                    str(source), *args.llc_arg, "-o", "/dev/null", "-time-passes", "-stats",
                ]
                with log.open("w") as stderr:
                    result = subprocess.run(command, stdout=subprocess.DEVNULL, stderr=stderr)
                diagnostics.write(json.dumps({
                    "compiler": label, "kind": kind, "width": width,
                    "command": command, "returncode": result.returncode, "log": str(log),
                }) + "\n")
                diagnostics.flush()
                failed |= result.returncode != 0
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
