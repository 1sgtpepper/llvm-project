// Private validation harness: include the owner to exercise its static function
// without copying the algorithm or adding a production testing API.
#include "../llvm/lib/CodeGen/SelectionDAG/ScheduleDAGRRList.cpp"

#include <chrono>
#include <iostream>
#include <string>

static std::vector<SUnit> makeNodes(unsigned Count) {
  std::vector<SUnit> Nodes;
  Nodes.reserve(Count);
  for (unsigned I = 0; I < Count; ++I)
    Nodes.emplace_back(static_cast<SDNode *>(nullptr), I);
  return Nodes;
}

static void dataEdge(std::vector<SUnit> &Nodes, unsigned From, unsigned To) {
  Nodes[To].addPred(SDep(&Nodes[From], SDep::Data, 0));
}

static void check(bool Condition, const char *Message) {
  if (!Condition) {
    std::cerr << Message << '\n';
    std::exit(1);
  }
}

static void exhaustive() {
  uint64_t Calls = 0;
  for (unsigned Count = 1; Count <= 6; ++Count) {
    std::vector<std::pair<unsigned, unsigned>> Edges;
    for (unsigned To = 1; To < Count; ++To)
      for (unsigned From = 0; From < To; ++From)
        Edges.emplace_back(From, To);
    for (unsigned Mask = 0; Mask < (1u << Edges.size()); ++Mask) {
      // The independent oracle evaluates nodes in a known topological order.
      // A non-leaf's number is max(preds) + multiplicity(max(preds)) - 1.
      std::vector<unsigned> Expected(Count, 1);
      for (unsigned To = 1; To < Count; ++To) {
        unsigned Maximum = 0, Multiplicity = 0;
        for (unsigned E = 0; E < Edges.size(); ++E) {
          if (!(Mask & (1u << E)) || Edges[E].second != To)
            continue;
          unsigned Value = Expected[Edges[E].first];
          if (Value > Maximum) {
            Maximum = Value;
            Multiplicity = 1;
          } else if (Value == Maximum) {
            ++Multiplicity;
          }
        }
        if (Maximum)
          Expected[To] = Maximum + Multiplicity - 1;
      }
      for (unsigned Reverse = 0; Reverse != 2; ++Reverse) {
        auto Nodes = makeNodes(Count);
        for (unsigned I = 0; I < Edges.size(); ++I) {
          unsigned E = Reverse ? Edges.size() - I - 1 : I;
          if (Mask & (1u << E))
            dataEdge(Nodes, Edges[E].first, Edges[E].second);
        }
        for (unsigned Cached = 0; Cached < (1u << Count); ++Cached) {
          for (unsigned Root = 0; Root < Count; ++Root) {
            std::vector<unsigned> Numbers(Count, 0);
            for (unsigned I = 0; I < Count; ++I)
              if (Cached & (1u << I))
                Numbers[I] = Expected[I];
            check(CalcNodeSethiUllmanNumber(&Nodes[Root], Numbers) ==
                      Expected[Root],
                  "Incorrect priority or cached-root behavior");
            ++Calls;
          }
        }
      }
    }
    std::cout << "exhaustive nodes=" << Count << " calls=" << Calls << std::endl;
  }

  // Cover every non-data dependency kind, which this calculation must ignore.
  auto Nodes = makeNodes(3);
  dataEdge(Nodes, 0, 1);
  dataEdge(Nodes, 1, 2);
  for (SDep Dep : {SDep(&Nodes[2], SDep::Anti, 1),
                   SDep(&Nodes[2], SDep::Output, 1),
                   SDep(&Nodes[2], SDep::Barrier),
                   SDep(&Nodes[2], SDep::MayAliasMem),
                   SDep(&Nodes[2], SDep::MustAliasMem),
                   SDep(&Nodes[2], SDep::Artificial),
                   SDep(&Nodes[2], SDep::Weak),
                   SDep(&Nodes[2], SDep::Cluster)}) {
    Nodes[0].addPred(Dep);
    // The whole graph has a cycle, but its data-edge subgraph is acyclic.
    for (unsigned Spare : {0u, 1u, 32u}) {
      std::vector<unsigned> Numbers(Nodes.size() + Spare, 0);
      check(CalcNodeSethiUllmanNumber(&Nodes[2], Numbers) == 1,
            "Non-data dependency changed the priority");
    }
    Nodes[0].removePred(Dep);
  }

  // The cache index is node identity, not topological position.
  Nodes = makeNodes(8);
  for (unsigned I = 1; I < Nodes.size(); ++I)
    dataEdge(Nodes, I, I - 1);
  std::vector<unsigned> Numbers(16, 0);
  check(CalcNodeSethiUllmanNumber(&Nodes[0], Numbers) == 1,
        "Reverse numbering or spare priority slots changed the result");
  Numbers[3] = 0;
  check(CalcNodeSethiUllmanNumber(&Nodes[3], Numbers) == 1,
        "Recomputation after clearing a priority failed");

  Nodes = makeNodes(9);
  for (unsigned I = 1; I < Nodes.size(); ++I)
    dataEdge(Nodes, I - 1, I);
  Numbers.assign(8, 0);
  check(CalcNodeSethiUllmanNumber(&Nodes[7], Numbers) == 1,
        "Initial priority calculation failed");
  Numbers.resize(16, 0);
  check(CalcNodeSethiUllmanNumber(&Nodes[8], Numbers) == 1,
        "Priority calculation after vector growth failed");
}

static void benchmark(const std::string &Shape, unsigned Count) {
  check(Count >= 4, "Benchmark needs at least four nodes");
  auto Nodes = makeNodes(Count);
  if (Shape == "chain") {
    for (unsigned I = 1; I < Count; ++I)
      dataEdge(Nodes, I - 1, I);
  } else if (Shape == "star") {
    for (unsigned I = 0; I + 1 < Count; ++I)
      dataEdge(Nodes, I, Count - 1);
  } else if (Shape == "diamonds") {
    for (unsigned I = 1; I < Count; ++I) {
      dataEdge(Nodes, I - 1, I);
      if (I > 1)
        dataEdge(Nodes, I - 2, I);
    }
  } else {
    check(false, "Unknown graph shape");
  }
  std::vector<unsigned> Numbers(Count, 0);
  // Graph construction and cache clearing are outside the timed interval.
  for (unsigned Trial = 0; Trial != 6; ++Trial) {
    std::fill(Numbers.begin(), Numbers.end(), 0);
    auto Start = std::chrono::steady_clock::now();
    unsigned Value = CalcNodeSethiUllmanNumber(&Nodes.back(), Numbers);
    auto End = std::chrono::steady_clock::now();
    std::cout << Shape << ',' << Count << ',' << Trial << ',' << Value << ','
              << std::chrono::duration<double>(End - Start).count() << '\n';
  }
}

int main(int Argc, char **Argv) {
  check(Argc >= 2, "Expected exhaustive, cycle, or benchmark mode");
  std::string Mode = Argv[1];
  if (Mode == "exhaustive") {
    exhaustive();
  } else if (Mode == "cycle") {
    check(Argc == 4, "Expected cycle length and priority-slot count");
    unsigned Count = std::stoul(Argv[2]);
    unsigned Slots = std::stoul(Argv[3]);
    check(Count && Slots >= Count, "Invalid cycle fixture size");
    auto Nodes = makeNodes(Count);
    for (unsigned I = 0; I < Count; ++I)
      dataEdge(Nodes, I, (I + 1) % Count);
    std::vector<unsigned> Numbers(Slots, 0);
    CalcNodeSethiUllmanNumber(&Nodes[0], Numbers);
    check(false, "Uncached data cycle was not rejected");
  } else if (Mode == "benchmark") {
    check(Argc == 4, "Expected benchmark shape and node count");
    benchmark(Argv[2], std::stoul(Argv[3]));
  } else {
    check(false, "Unknown mode");
  }
}
