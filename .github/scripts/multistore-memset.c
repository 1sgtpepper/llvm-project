#include <stddef.h>
#include <stdlib.h>
#include <string.h>

__attribute__((noinline, optnone))
static void reference_forward(unsigned char *a, unsigned char *b,
                              unsigned char *c, size_t n) {
  for (size_t i = 0; i != n; ++i) {
    a[i] = 0;
    b[i] = 0;
    c[i] = 0;
  }
}

__attribute__((noinline))
static void optimized_forward(unsigned char *a, unsigned char *b,
                              unsigned char *c, size_t n) {
  for (size_t i = 0; i != n; ++i) {
    a[i] = 0;
    b[i] = 0;
    c[i] = 0;
  }
}

__attribute__((noinline, optnone))
static void reference_reverse(unsigned char *a, unsigned char *b,
                              unsigned char *c, size_t n) {
  for (size_t i = n; i != 0; --i) {
    a[i] = 0;
    b[i] = 0;
    c[i] = 0;
  }
}

__attribute__((noinline))
static void optimized_reverse(unsigned char *a, unsigned char *b,
                              unsigned char *c, size_t n) {
  for (size_t i = n; i != 0; --i) {
    a[i] = 0;
    b[i] = 0;
    c[i] = 0;
  }
}

static void initialize(unsigned char *buffer, unsigned salt) {
  for (size_t i = 0; i != 256; ++i)
    buffer[i] = (unsigned char)(i * 37u + salt);
}

int main(void) {
  unsigned char reference[256];
  unsigned char optimized[256];

  for (size_t n = 0; n <= 64; ++n) {
    for (size_t a = 0; a <= 32; a += 4) {
      for (size_t b = 0; b <= 32; b += 4) {
        for (size_t c = 0; c <= 32; c += 4) {
          initialize(reference, (unsigned)(n + a + b + c));
          memcpy(optimized, reference, sizeof(reference));
          reference_forward(reference + a, reference + b, reference + c, n);
          optimized_forward(optimized + a, optimized + b, optimized + c, n);
          if (memcmp(reference, optimized, sizeof(reference)) != 0)
            abort();

          initialize(reference, (unsigned)(n + a + b + c + 1));
          memcpy(optimized, reference, sizeof(reference));
          reference_reverse(reference + a, reference + b, reference + c, n);
          optimized_reverse(optimized + a, optimized + b, optimized + c, n);
          if (memcmp(reference, optimized, sizeof(reference)) != 0)
            abort();
        }
      }
    }
  }
  return 0;
}
