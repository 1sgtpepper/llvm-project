#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#define REF __attribute__((noinline, optnone))
#define OPT __attribute__((noinline))

#define DEFINE_UNSIGNED(name, attr)                                          \
  attr static uint8_t name(const uint8_t *a, uint8_t k) {                    \
    uint8_t iv = 0;                                                           \
    for (;;) {                                                                \
      if (a[iv] == 0 || !(iv < k))                                            \
        return iv;                                                            \
      ++iv;                                                                   \
    }                                                                         \
  }

#define DEFINE_SIGNED(name, attr)                                            \
  attr static int8_t name(const uint8_t *a, int8_t k) {                      \
    int8_t iv = INT8_MIN;                                                     \
    for (;;) {                                                                \
      if (a[(uint8_t)iv] == 0 || !(iv < k))                                  \
        return iv;                                                            \
      ++iv;                                                                   \
    }                                                                         \
  }

DEFINE_UNSIGNED(ref_unsigned_scan, REF)
DEFINE_UNSIGNED(opt_unsigned_scan, OPT)
DEFINE_SIGNED(ref_signed_scan, REF)
DEFINE_SIGNED(opt_signed_scan, OPT)

int main(void) {
  uint8_t a[256];

  for (unsigned stop = 0; stop <= 256; ++stop) {
    memset(a, 1, sizeof(a));
    if (stop < 256)
      a[stop] = 0;

    for (unsigned k = 0; k <= UINT8_MAX; ++k)
      if (ref_unsigned_scan(a, (uint8_t)k) !=
          opt_unsigned_scan(a, (uint8_t)k))
        abort();

    for (int k = INT8_MIN; k <= INT8_MAX; ++k)
      if (ref_signed_scan(a, (int8_t)k) != opt_signed_scan(a, (int8_t)k))
        abort();
  }

  return 0;
}
