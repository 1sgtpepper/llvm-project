#!/usr/bin/env python3
"""Instrument the candidate query for a separate CI correctness build."""
from pathlib import Path
import sys

owner = Path(sys.argv[1])
source = owner.read_text()
old = '''unsigned RegReductionPQBase::getClosestSucc(const SUnit *SU) {
  auto [It, Inserted] = ClosestSuccs.try_emplace(SU);
  if (Inserted)
    It->second = closestSucc(SU);
  return It->second;
}'''
new = '''STATISTIC(NumSuccessorQueries, "Number of successor queries");
STATISTIC(NumSuccessorCacheHits, "Number of successor cache hits");

unsigned RegReductionPQBase::getClosestSucc(const SUnit *SU) {
  ++NumSuccessorQueries;
  auto [It, Inserted] = ClosestSuccs.try_emplace(SU);
  if (Inserted) {
    It->second = closestSucc(SU);
  } else {
    ++NumSuccessorCacheHits;
    assert(It->second == closestSucc(SU) && "Stale successor cache value");
  }
  return It->second;
}'''
if source.count(old) != 1:
    raise SystemExit('Expected exactly one candidate query definition')
owner.write_text(source.replace(old, new))
