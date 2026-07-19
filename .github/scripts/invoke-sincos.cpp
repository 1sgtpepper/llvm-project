extern double may_throw();

double reproduce_source() {
  try {
    double x = may_throw();
    return __builtin_elementwise_sin(x) + __builtin_elementwise_cos(x);
  } catch (...) {
    return 0.0;
  }
}
