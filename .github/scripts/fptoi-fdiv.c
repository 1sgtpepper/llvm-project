#include <stdint.h>
#include <stdlib.h>

#define REF __attribute__((noinline, optnone))
#define OPT __attribute__((noinline))

REF static int32_t ref_s3(int32_t x) { return (int32_t)((double)x / 3.0); }
OPT static int32_t opt_s3(int32_t x) { return (int32_t)((double)x / 3.0); }
REF static int32_t ref_sn3(int32_t x) { return (int32_t)((double)x / -3.0); }
OPT static int32_t opt_sn3(int32_t x) { return (int32_t)((double)x / -3.0); }
REF static int32_t ref_s7(int32_t x) { return (int32_t)((double)x / 7.0); }
OPT static int32_t opt_s7(int32_t x) { return (int32_t)((double)x / 7.0); }

REF static uint32_t ref_u3(uint32_t x) { return (uint32_t)((double)x / 3.0); }
OPT static uint32_t opt_u3(uint32_t x) { return (uint32_t)((double)x / 3.0); }
REF static uint32_t ref_u7(uint32_t x) { return (uint32_t)((double)x / 7.0); }
OPT static uint32_t opt_u7(uint32_t x) { return (uint32_t)((double)x / 7.0); }

static void check(uint32_t bits) {
  int32_t signed_value = (int32_t)bits;
  if (ref_s3(signed_value) != opt_s3(signed_value) ||
      ref_sn3(signed_value) != opt_sn3(signed_value) ||
      ref_s7(signed_value) != opt_s7(signed_value) ||
      ref_u3(bits) != opt_u3(bits) || ref_u7(bits) != opt_u7(bits))
    abort();
}

int main(void) {
  static const uint32_t boundaries[] = {
      0,          1,          2,          3,          6,
      7,          8,          0x7ffffffe, 0x7fffffff, 0x80000000,
      0x80000001, 0xfffffffd, 0xfffffffe, 0xffffffff,
  };
  for (unsigned i = 0; i != sizeof(boundaries) / sizeof(boundaries[0]); ++i)
    check(boundaries[i]);

  uint32_t state = 0x9e3779b9u;
  for (unsigned i = 0; i != 1000000; ++i) {
    state ^= state << 13;
    state ^= state >> 17;
    state ^= state << 5;
    check(state);
  }
  return 0;
}
