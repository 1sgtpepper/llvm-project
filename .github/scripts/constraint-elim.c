#include <stdint.h>
#include <stdlib.h>

#define REF __attribute__((noinline, optnone))
#define OPT __attribute__((noinline))

#define PAIR(name, body)                                                      \
  REF static int ref_##name(int8_t a, int8_t b, int8_t c) { body }           \
  OPT static int opt_##name(int8_t a, int8_t b, int8_t c) { body }

PAIR(descending_chain,
     if (a > b && b >= c) return a == c;
     return 2;)

PAIR(ascending_chain,
     if (a <= b && b <= c) return a > c;
     return 2;)

PAIR(and_negative,
     (void)c;
     if ((int8_t)(a & b) < 0) return a < 0 && b < 0;
     return 2;)

PAIR(or_nonnegative,
     (void)c;
     if ((int8_t)(a | b) >= 0) return a >= 0 && b >= 0;
     return 2;)

PAIR(signed_to_unsigned,
     (void)c;
     if (a >= 0 && a <= b) return (uint8_t)a <= (uint8_t)b;
     return 2;)

static void check(int8_t a, int8_t b, int8_t c) {
  if (ref_descending_chain(a, b, c) != opt_descending_chain(a, b, c) ||
      ref_ascending_chain(a, b, c) != opt_ascending_chain(a, b, c) ||
      ref_and_negative(a, b, c) != opt_and_negative(a, b, c) ||
      ref_or_nonnegative(a, b, c) != opt_or_nonnegative(a, b, c) ||
      ref_signed_to_unsigned(a, b, c) != opt_signed_to_unsigned(a, b, c))
    abort();
}

int main(void) {
  for (int a = -128; a <= 127; ++a)
    for (int b = -128; b <= 127; ++b)
      for (int c = -128; c <= 127; ++c)
        check((int8_t)a, (int8_t)b, (int8_t)c);
  return 0;
}
