#!/usr/bin/env python3
"""Apply the isolated cache-key experiment to the exact pointer-key source."""
from pathlib import Path
import sys

owner = Path(sys.argv[1])
source = owner.read_text()
replacements = {
    "DenseMap<const SUnit *, unsigned> ClosestSuccs;":
        ("DenseMap<unsigned, unsigned> ClosestSuccs;", 1),
    "ClosestSuccs.erase(SU);": ("ClosestSuccs.erase(SU->NodeNum);", 2),
    "ClosestSuccs.erase(V);": ("ClosestSuccs.erase(V->NodeNum);", 1),
    "ClosestSuccs.find(SU);": ("ClosestSuccs.find(SU->NodeNum);", 1),
    "ClosestSuccs.try_emplace(SU, closestSucc(SU))":
        ("ClosestSuccs.try_emplace(SU->NodeNum, closestSucc(SU))", 1),
}
for old, (new, expected) in replacements.items():
    if source.count(old) != expected:
        raise SystemExit(f"Expected {expected} copies of {old!r}")
    source = source.replace(old, new)
owner.write_text(source)
