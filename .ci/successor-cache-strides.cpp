// Compare exact queue queries on valid DAGs with strided available-node IDs.
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

static void measure(MachineFunction &MF, unsigned Roots, unsigned Stride) {
  auto *Queue = new SrcRegReductionPriorityQueue(MF, false, true, nullptr,
                                                nullptr, nullptr);
  auto DAG = std::make_unique<ScheduleDAGRRList>(MF, false, Queue,
                                               CodeGenOptLevel::Default);
  Queue->setScheduleDAG(DAG.get());
  DAG->BB = &MF.front();
  unsigned Count = Roots * Stride + 1;
  std::vector<SUnit> Nodes;
  Nodes.reserve(Count);
  for (unsigned I = 0; I != Count; ++I)
    Nodes.emplace_back(static_cast<SDNode *>(nullptr), I);
  auto edge = [&](unsigned From, unsigned To) {
    SDep D(&Nodes[From], SDep::Data, 0);
    D.setLatency(1);
    Nodes[To].addPred(D);
  };
  // Every node participates: independent chains converge on one scheduled sink.
  // Only their heads are available, with stable, identical successor distances.
  for (unsigned Root = 0; Root != Roots; ++Root) {
    unsigned Head = Root * Stride;
    edge(Head, Count - 1);
    for (unsigned I = 1; I != Stride; ++I)
      edge(Head + I, Head + I - 1);
  }
  Nodes.back().setHeightToAtLeast(42);
  Nodes.back().isScheduled = true;
  Queue->initNodes(Nodes);
  for (unsigned Root = 0; Root != Roots; ++Root) {
    SUnit *SU = &Nodes[Root * Stride];
    SU->isAvailable = true;
    SU->NumSuccsLeft = 0;
    Queue->push(SU);
  }
  for (unsigned Trial = 0; Trial != 4; ++Trial) {
    uint64_t Sum = 0;
    auto Start = std::chrono::steady_clock::now();
    for (unsigned Repeat = 0; Repeat != 4096; ++Repeat)
      for (unsigned Root = 0; Root != Roots; ++Root)
        Sum += Queue->getClosestSucc(&Nodes[Root * Stride]);
    double Seconds = std::chrono::duration<double>(
        std::chrono::steady_clock::now() - Start).count();
    if (Sum != uint64_t(Roots) * 4096 * 42)
      std::abort();
    std::cout << Roots << ',' << Stride << ',' << Trial << ',' << Seconds
              << ',' << Sum << '\n';
  }
  // Construction, cache filling on trial zero, and draining are not measured
  // as successful warm-cache trials.
  while (!Queue->empty())
    Queue->pop();
  Queue->releaseState();
}

int main() {
  InitializeNativeTarget();
  InitializeNativeTargetAsmPrinter();
  LLVMContext Context;
  SMDiagnostic Error;
  auto M = parseAssemblyString("define void @f() { ret void }", Error, Context);
  Triple TT("x86_64-unknown-linux-gnu");
  std::string Message;
  const Target *T = TargetRegistry::lookupTarget("", TT, Message);
  auto TM = std::unique_ptr<TargetMachine>(T->createTargetMachine(
      TT, "generic", "", TargetOptions(), std::nullopt));
  M->setDataLayout(TM->createDataLayout());
  MachineModuleInfo MMI(TM.get());
  MachineFunction MF(*M->getFunction("f"), *TM, *TM->getSubtargetImpl(*M->getFunction("f")),
                     MMI.getContext(), 0);
  MF.push_back(MF.CreateMachineBasicBlock());
  for (unsigned Roots : {64u, 256u})
    for (unsigned Stride : {1u, 64u, 512u, 2048u})
      measure(MF, Roots, Stride);
}
