declare double @may_throw()
declare double @llvm.sin.f64(double)
declare double @llvm.cos.f64(double)
declare i32 @__gxx_personality_v0(...)

define double @reproduce() personality ptr @__gxx_personality_v0 {
entry:
  %x = invoke double @may_throw()
          to label %continue unwind label %catch

continue:
  %sin = call double @llvm.sin.f64(double %x)
  %cos = call double @llvm.cos.f64(double %x)
  %sum = fadd double %sin, %cos
  ret double %sum

catch:
  %landing = landingpad { ptr, i32 }
          catch ptr null
  ret double 0.0
}
