#!/usr/bin/env python3
"""Instrument the candidate query for a separate CI correctness build."""
from pathlib import Path
import sys

owner = Path(sys.argv[1])
source = owner.read_text()
old = '''unsigned RegReductionPQBase::getClosestSucc(const SUnit *SU) {
  auto It = ClosestSuccs.find(SU->NodeNum);
  if (It != ClosestSuccs.end())
    return It->second;
  return ClosestSuccs.try_emplace(SU->NodeNum, closestSucc(SU)).first->second;
}'''
new = '''STATISTIC(NumSuccessorQueries, "Number of successor queries");
STATISTIC(NumSuccessorCacheHits, "Number of successor cache hits");

unsigned RegReductionPQBase::getClosestSucc(const SUnit *SU) {
  ++NumSuccessorQueries;
  auto It = ClosestSuccs.find(SU->NodeNum);
  if (It != ClosestSuccs.end()) {
    ++NumSuccessorCacheHits;
    assert(It->second == closestSucc(SU) && "Stale successor cache value");
    return It->second;
  }
  return ClosestSuccs.try_emplace(SU->NodeNum, closestSucc(SU)).first->second;
}'''
if source.count(old) != 1:
    raise SystemExit('Expected exactly one candidate query definition')
owner.write_text(source.replace(old, new))
