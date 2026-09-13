#!/usr/bin/env python3
"""Add diagnostic counters to the actual helper; never use this build for timing."""
from pathlib import Path
p = Path('llvm/lib/CodeGen/SelectionDAG/ScheduleDAGRRList.cpp')
s = p.read_text()
start = s.index('static unsigned closestSucc(const SUnit *SU) {')
end = s.index('\n/// calcMaxScratches', start)
body = s[start:end]
body = body.replace('  unsigned MaxHeight = 0;', '''  struct Counts {
    uint64_t Calls[18]{}, Edges[18]{}, Data[18]{}, Copies[18]{};
    uint64_t DataCalls[3]{}, DataEdges[3]{};
    ~Counts() {
      for (unsigned I = 0; I != 18; ++I)
        if (Calls[I])
          errs() << "closest-bucket," << I << ',' << Calls[I] << ','
                 << Edges[I] << ',' << Data[I] << ',' << Copies[I] << '\\n';
      for (unsigned I = 0; I != 3; ++I)
        errs() << "closest-data-count," << I << ',' << DataCalls[I] << ','
               << DataEdges[I] << '\\n';
    }
  };
  static Counts C;
  unsigned Bucket = 0;
  for (size_t N = SU->Succs.size(); N > 1 && Bucket < 17; N >>= 1)
    ++Bucket;
  unsigned DataBucket = std::min(SU->NumSuccs, 2u);
  ++C.Calls[Bucket];
  ++C.DataCalls[DataBucket];
  unsigned MaxHeight = 0;''', 1)
body = body.replace('    if (Succ.isCtrl()) continue;', '''    ++C.Edges[Bucket];
    ++C.DataEdges[DataBucket];
    if (Succ.isCtrl()) continue;''')
body = body.replace('    unsigned Height = Succ.getSUnit()->getHeight();', '    ++C.Data[Bucket];\n    unsigned Height = Succ.getSUnit()->getHeight();')
body = body.replace('      Height = closestSucc(Succ.getSUnit())+1;', '      { ++C.Copies[Bucket]; Height = closestSucc(Succ.getSUnit())+1; }')
p.write_text(s[:start] + body + s[end:])
