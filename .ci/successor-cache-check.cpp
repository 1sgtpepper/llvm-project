// Private validation of the actual queue and helper. No production test API.
#include "../llvm/lib/CodeGen/SelectionDAG/ScheduleDAGRRList.cpp"
#include "llvm/AsmParser/Parser.h"
#include "llvm/CodeGen/MachineModuleInfo.h"
#include "llvm/IR/Module.h"
#include "llvm/MC/TargetRegistry.h"
#include "llvm/Support/SourceMgr.h"
#include "llvm/Support/TargetSelect.h"
#include "llvm/Target/TargetMachine.h"
#include <chrono>
#include <iostream>

static void require(bool V, const char *Message) {
  if (!V) {
    std::cerr << Message << '\n';
    std::exit(1);
  }
}

// Only the opcode and IR order are consumed by the query fixture. These are not
// whole SelectionDAG programs; compiler-level tests cover the real lowering.
struct QueryNode : SDNode {
  explicit QueryNode(unsigned Opcode)
      : SDNode(Opcode, 0, DebugLoc(), getSDVTList(MVT::i32)) {}
};

struct Fixture {
  std::vector<SUnit> Nodes;
  SrcRegReductionPriorityQueue &Queue;
  std::unique_ptr<ScheduleDAGRRList> DAG;
  explicit Fixture(MachineFunction &MF, unsigned Count)
      : Queue(*new SrcRegReductionPriorityQueue(MF, false, true, nullptr,
                                               nullptr, nullptr)),
        DAG(std::make_unique<ScheduleDAGRRList>(MF, false, &Queue,
                                               CodeGenOptLevel::Default)) {
    // ScheduleDAGRRList owns and deletes the queue.
    Queue.setScheduleDAG(DAG.get());
    Nodes.reserve(Count);
    for (unsigned I = 0; I < Count; ++I)
      Nodes.emplace_back(static_cast<SDNode *>(nullptr), I);
  }
  void edge(unsigned From, unsigned To, SDep::Kind Kind = SDep::Data,
            unsigned Latency = 1) {
    SDep Dep(&Nodes[From], Kind, Kind == SDep::Data ? 0 : 1);
    Dep.setLatency(Latency);
    Nodes[To].addPred(Dep);
  }
  void initialize() { Queue.initNodes(Nodes); }
  void push(unsigned I) {
    Nodes[I].isAvailable = true;
    Nodes[I].NumSuccsLeft = 0;
    Queue.push(&Nodes[I]);
  }
  unsigned query(unsigned I) {
#ifdef USE_SUCCESSOR_CACHE
    unsigned Value = Queue.getClosestSucc(&Nodes[I]);
#else
    unsigned Value = closestSucc(&Nodes[I]);
#endif
    require(Value == closestSucc(&Nodes[I]), "A cached successor query is stale");
    return Value;
  }
  void drain() {
    while (!Queue.empty())
      Queue.pop();
  }
  ~Fixture() {
    drain();
    Queue.releaseState();
  }
};

static void cases(MachineFunction &MF) {
  uint64_t Queries = 0;
  // Every directed graph in topological numbering through five nodes, every
  // root and three latency assignments. Compare cold and warm queries.
  for (unsigned Count = 1; Count <= 5; ++Count) {
    std::vector<std::pair<unsigned, unsigned>> Edges;
    for (unsigned To = 1; To < Count; ++To)
      for (unsigned From = 0; From < To; ++From)
        Edges.emplace_back(From, To);
    for (unsigned Mask = 0; Mask < (1u << Edges.size()); ++Mask) {
      for (unsigned Weight : {0u, 1u, 7u}) {
        Fixture F(MF, Count);
        for (unsigned E = 0; E < Edges.size(); ++E)
          if (Mask & (1u << E))
            F.edge(Edges[E].first, Edges[E].second, SDep::Data, Weight);
        F.initialize();
        // Each root is observed in its own valid available interval: all its
        // successors have already received their final heights.
        for (unsigned Root = 0; Root < Count; ++Root) {
          for (unsigned I = 0; I < Count; ++I) {
            F.Nodes[I].isScheduled = I > Root;
            F.Nodes[I].getHeight();
          }
          F.push(Root);
          for (unsigned Repeat = 0; Repeat != 3; ++Repeat) {
            F.query(Root);
            ++Queries;
          }
          F.Queue.remove(&F.Nodes[Root]);
        }
      }
    }
  }

  // Every non-data dependency must be excluded even with a greater height.
  for (unsigned Variant = 0; Variant != 8; ++Variant) {
    Fixture F(MF, 3);
    F.edge(0, 1);
    F.Nodes[1].setHeightToAtLeast(7);
    F.Nodes[2].setHeightToAtLeast(100);
    SDep Dep = Variant < 2
                   ? SDep(&F.Nodes[0], Variant ? SDep::Output : SDep::Anti, 1)
                   : SDep(&F.Nodes[0], static_cast<SDep::OrderKind>(Variant - 2));
    F.Nodes[2].addPred(Dep);
    F.initialize();
    F.push(0);
    require(F.query(0) == 7, "Control dependency affected closest successor");
    require(F.query(0) == 7, "Warm control query changed");
  }

  // CopyToReg heights are intentionally replaced by the recursive position.
  QueryNode Copy(ISD::CopyToReg);
  Fixture F(MF, 6);
  F.Nodes[2].setNode(&Copy);
  F.Nodes[3].setNode(&Copy);
  F.edge(0, 2);
  F.edge(2, 3);
  F.edge(3, 4);
  F.edge(1, 5);
  F.Nodes[2].setHeightToAtLeast(100);
  F.Nodes[3].setHeightToAtLeast(100);
  F.Nodes[4].setHeightToAtLeast(7);
  F.Nodes[5].setHeightToAtLeast(8);
  F.initialize();
  F.push(0);
  F.push(1);
  require(F.query(0) == 9 && F.query(1) == 8, "CopyToReg path was flattened incorrectly");
  F.Queue.remove(&F.Nodes[0]);
  F.Nodes[4].setHeightToAtLeast(11);
  F.push(0);
  require(F.query(0) == 13, "Remove/re-entry retained the old CopyToReg height");
  F.Queue.remove(&F.Nodes[0]);
  F.Nodes[4].setHeightToAtLeast(19);
  F.push(0);
  require(F.query(0) == 21, "Repeated re-entry retained stale state");

  // updateNode is the owner notification for a changed node's graph.
  F.Nodes[5].setHeightToAtLeast(30);
  F.Queue.updateNode(&F.Nodes[1]);
  require(F.query(1) == 30, "Owner update retained the old value");

  require(F.Queue.pop() == &F.Nodes[1], "Incorrect normal queue winner");
  F.Nodes[5].setHeightToAtLeast(37);
  F.push(1);
  require(F.query(1) == 37, "Pop/re-entry retained the old value");
#ifndef NDEBUG
  F.DAG->StressSched = true;
  F.Queue.dump(F.DAG.get());
  require(F.Queue.pop() == &F.Nodes[0], "Stress reversal changed queue semantics");
  F.push(0);
  F.DAG->StressSched = false;
#endif
  F.drain();
  F.Queue.releaseState();
  F.Nodes[5].setHeightToAtLeast(41);
  F.initialize();
  F.push(1);
  require(F.query(1) == 41, "Graph-state reuse retained the old value");

  // Zero and UINT_MAX are valid values, not cache-empty sentinels.
  Fixture Limits(MF, 3);
  Limits.edge(0, 2, SDep::Data, 0);
  Limits.initialize();
  Limits.push(0);
  Limits.push(1);
  require(Limits.query(0) == 0 && Limits.query(1) == 0, "Zero result changed");
  Limits.Queue.remove(&Limits.Nodes[0]);
  Limits.Nodes[2].setHeightToAtLeast(std::numeric_limits<unsigned>::max());
  Limits.push(0);
  require(Limits.query(0) == std::numeric_limits<unsigned>::max(), "Max height was used as an empty sentinel");
  std::cout << "Successor queries checked: " << Queries << "; lifecycle, control and CopyToReg boundaries passed.\n";
}

int main() {
  InitializeNativeTarget();
  InitializeNativeTargetAsmPrinter();
  LLVMContext Context;
  SMDiagnostic Error;
  auto M = parseAssemblyString("define void @f() { ret void }", Error, Context);
  require(bool(M), "Failed to create fixture module");
  Triple TT("x86_64-unknown-linux-gnu");
  std::string Message;
  const Target *T = TargetRegistry::lookupTarget("", TT, Message);
  require(T != nullptr, "X86 target is required");
  auto TM = std::unique_ptr<TargetMachine>(T->createTargetMachine(TT, "generic", "", TargetOptions(), std::nullopt));
  M->setDataLayout(TM->createDataLayout());
  MachineModuleInfo MMI(TM.get());
  auto *Fn = M->getFunction("f");
  MachineFunction MF(*Fn, *TM, *TM->getSubtargetImpl(*Fn), MMI.getContext(), 0);
  cases(MF);
}
