; RUN: mlir-translate -import-llvm %s | mlir-translate -mlir-to-llvmir | FileCheck %s

; CHECK-LABEL: define void @synthetic()
; CHECK-SAME: !prof ![[SYNTH_PROF_ID:[0-9]*]]
define void @synthetic() !prof !0 {
  ret void
}

; CHECK-LABEL: define void @with_import_guid()
; CHECK-SAME: !prof ![[IMPORTS_PROF_ID:[0-9]*]]
define void @with_import_guid() !prof !1 {
  ret void
}

!0 = !{!"synthetic_function_entry_count", i64 7}
!1 = !{!"function_entry_count", i64 7, i64 9, i64 4, i64 9}

; CHECK-DAG: ![[SYNTH_PROF_ID]] = !{!"synthetic_function_entry_count", i64 7}
; CHECK-DAG: ![[IMPORTS_PROF_ID]] = !{!"function_entry_count", i64 7, i64 4, i64 9}
