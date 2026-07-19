#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>

#if defined(__clang__)
#define NOINLINE __attribute__((noinline))
#elif defined(__GNUC__)
#define NOINLINE __attribute__((noinline))
#else
#define NOINLINE
#endif

static volatile uint64_t branch_sink;

typedef __int128 int128_t;
typedef unsigned __int128 uint128_t;

static uint64_t mix(uint64_t state, uint64_t value) {
  return state ^ (value + UINT64_C(0x9e3779b97f4a7c15) + (state << 6) +
                  (state >> 2));
}

NOINLINE uint32_t neg_sign_mask32(uint32_t x, int32_t y) {
  uint32_t mask = 0u - (uint32_t)(y < 0);
  return 0u - (x & mask);
}

NOINLINE uint32_t neg_not_sign_mask32(uint32_t x, int32_t y) {
  uint32_t mask = ~(0u - (uint32_t)(y < 0));
  return 0u - (x & mask);
}

NOINLINE uint64_t neg_sign_mask64(uint64_t x, int64_t y) {
  uint64_t mask = UINT64_C(0) - (uint64_t)(y < 0);
  return UINT64_C(0) - (x & mask);
}

NOINLINE uint64_t neg_not_sign_mask64(uint64_t x, int64_t y) {
  uint64_t mask = ~(UINT64_C(0) - (uint64_t)(y < 0));
  return UINT64_C(0) - (x & mask);
}

#define DEFINE_SIGNED_BRANCH(NAME, OP, TRUE_VALUE, FALSE_VALUE)                \
  NOINLINE uint64_t NAME(int64_t a, int64_t b) {                              \
    unsigned condition = (unsigned)(a OP b);                                  \
    if ((condition & 1u) != 0u) {                                             \
      branch_sink += UINT64_C(3);                                              \
      return UINT64_C(TRUE_VALUE);                                             \
    }                                                                          \
    branch_sink += UINT64_C(5);                                                \
    return UINT64_C(FALSE_VALUE);                                              \
  }

#define DEFINE_UNSIGNED_BRANCH(NAME, OP, TRUE_VALUE, FALSE_VALUE)              \
  NOINLINE uint64_t NAME(uint64_t a, uint64_t b) {                             \
    unsigned condition = (unsigned)(a OP b);                                   \
    if ((condition & 1u) == 0u) {                                              \
      branch_sink += UINT64_C(7);                                              \
      return UINT64_C(FALSE_VALUE);                                            \
    }                                                                          \
    branch_sink += UINT64_C(11);                                               \
    return UINT64_C(TRUE_VALUE);                                               \
  }

#define DEFINE_FLOAT_BRANCH(NAME, OP, TRUE_VALUE, FALSE_VALUE)                 \
  NOINLINE uint64_t NAME(double a, double b) {                                 \
    unsigned condition = (unsigned)(a OP b);                                   \
    if ((condition & 1u) != 0u) {                                             \
      branch_sink += UINT64_C(13);                                             \
      return UINT64_C(TRUE_VALUE);                                             \
    }                                                                          \
    branch_sink += UINT64_C(17);                                               \
    return UINT64_C(FALSE_VALUE);                                              \
  }

DEFINE_SIGNED_BRANCH(branch_signed_eq, ==, 101, 102)
DEFINE_SIGNED_BRANCH(branch_signed_ne, !=, 103, 104)
DEFINE_SIGNED_BRANCH(branch_signed_lt, <, 105, 106)
DEFINE_SIGNED_BRANCH(branch_signed_le, <=, 107, 108)
DEFINE_SIGNED_BRANCH(branch_signed_gt, >, 109, 110)
DEFINE_SIGNED_BRANCH(branch_signed_ge, >=, 111, 112)

DEFINE_UNSIGNED_BRANCH(branch_unsigned_eq, ==, 201, 202)
DEFINE_UNSIGNED_BRANCH(branch_unsigned_ne, !=, 203, 204)
DEFINE_UNSIGNED_BRANCH(branch_unsigned_lt, <, 205, 206)
DEFINE_UNSIGNED_BRANCH(branch_unsigned_le, <=, 207, 208)
DEFINE_UNSIGNED_BRANCH(branch_unsigned_gt, >, 209, 210)
DEFINE_UNSIGNED_BRANCH(branch_unsigned_ge, >=, 211, 212)

DEFINE_FLOAT_BRANCH(branch_float_eq, ==, 301, 302)
DEFINE_FLOAT_BRANCH(branch_float_ne, !=, 303, 304)
DEFINE_FLOAT_BRANCH(branch_float_lt, <, 305, 306)
DEFINE_FLOAT_BRANCH(branch_float_le, <=, 307, 308)
DEFINE_FLOAT_BRANCH(branch_float_gt, >, 309, 310)
DEFINE_FLOAT_BRANCH(branch_float_ge, >=, 311, 312)

#define DEFINE_I128_IMMEDIATE_BRANCH(NAME, TYPE, OP, CONSTANT, TRUE_VALUE,     \
                                     FALSE_VALUE)                             \
  NOINLINE uint64_t NAME(TYPE value) {                                        \
    unsigned condition = (unsigned)(value OP (CONSTANT));                     \
    if ((condition & 1u) != 0u) {                                             \
      branch_sink += UINT64_C(19);                                            \
      return UINT64_C(TRUE_VALUE);                                            \
    }                                                                          \
    branch_sink += UINT64_C(23);                                              \
    return UINT64_C(FALSE_VALUE);                                             \
  }

DEFINE_I128_IMMEDIATE_BRANCH(branch_i128_eq_neg1, int128_t, ==,
                             (int128_t)-1, 401, 402)
DEFINE_I128_IMMEDIATE_BRANCH(branch_i128_lt_zero, int128_t, <, (int128_t)0,
                             403, 404)
DEFINE_I128_IMMEDIATE_BRANCH(branch_i128_ge_2p64, int128_t, >=,
                             ((int128_t)1 << 64), 405, 406)
DEFINE_I128_IMMEDIATE_BRANCH(branch_i128_lt_neg_2p64, int128_t, <,
                             -((int128_t)1 << 64), 407, 408)
DEFINE_I128_IMMEDIATE_BRANCH(branch_u128_eq_2p64, uint128_t, ==,
                             ((uint128_t)1 << 64), 409, 410)
DEFINE_I128_IMMEDIATE_BRANCH(branch_u128_lt_2p64, uint128_t, <,
                             ((uint128_t)1 << 64), 411, 412)
DEFINE_I128_IMMEDIATE_BRANCH(branch_u128_gt_u64max, uint128_t, >,
                             (uint128_t)UINT64_MAX, 413, 414)
DEFINE_I128_IMMEDIATE_BRANCH(branch_u128_ge_2p127, uint128_t, >=,
                             ((uint128_t)1 << 127), 415, 416)

int main(void) {
  static const int32_t signed32_values[] = {
      INT32_MIN, INT32_MIN + 1, -65537, -1, 0, 1, 65535, INT32_MAX - 1,
      INT32_MAX};
  static const int64_t signed_values[] = {
      INT64_MIN, INT64_MIN + 1, -4294967296LL, -2147483649LL, -2147483648LL,
      -65537,    -1,            0,             1,             65535,
      2147483647LL, 2147483648LL, 4294967295LL, INT64_MAX - 1, INT64_MAX};
  static const uint64_t unsigned_values[] = {
      0, 1, 2, 255, 256, 65535, 65536, UINT32_MAX - 1, UINT32_MAX,
      UINT64_C(0x8000000000000000), UINT64_MAX - 1, UINT64_MAX};
  static const double float_values[] = {
      -INFINITY, -1.0, -0.0, 0.0, 1.0, INFINITY, NAN};
  static const int128_t signed128_values[] = {
      -((int128_t)1 << 100), -((int128_t)1 << 64),
      -((int128_t)1 << 64) + 1, (int128_t)INT64_MIN, -1, 0, 1,
      (int128_t)INT64_MAX, ((int128_t)1 << 64) - 1,
      ((int128_t)1 << 64), ((int128_t)1 << 100)};
  static const uint128_t unsigned128_values[] = {
      0, 1, (uint128_t)UINT64_MAX, ((uint128_t)1 << 64),
      ((uint128_t)1 << 64) + 1, ((uint128_t)1 << 100),
      ((uint128_t)1 << 127), ~(uint128_t)0};
  uint64_t state = UINT64_C(0xcbf29ce484222325);

  for (size_t i = 0; i < sizeof(signed32_values) / sizeof(signed32_values[0]);
       ++i) {
    for (size_t j = 0; j < sizeof(signed32_values) / sizeof(signed32_values[0]);
         ++j) {
      int32_t a = signed32_values[i];
      int32_t b = signed32_values[j];
      state = mix(state, neg_sign_mask32((uint32_t)a, b));
      state = mix(state, neg_not_sign_mask32((uint32_t)a, b));
    }
  }

  for (size_t i = 0; i < sizeof(signed_values) / sizeof(signed_values[0]); ++i) {
    for (size_t j = 0; j < sizeof(signed_values) / sizeof(signed_values[0]);
         ++j) {
      int64_t a = signed_values[i];
      int64_t b = signed_values[j];
      state = mix(state, neg_sign_mask64((uint64_t)a, b));
      state = mix(state, neg_not_sign_mask64((uint64_t)a, b));
      state = mix(state, branch_signed_eq(a, b));
      state = mix(state, branch_signed_ne(a, b));
      state = mix(state, branch_signed_lt(a, b));
      state = mix(state, branch_signed_le(a, b));
      state = mix(state, branch_signed_gt(a, b));
      state = mix(state, branch_signed_ge(a, b));
    }
  }

  for (size_t i = 0; i < sizeof(unsigned_values) / sizeof(unsigned_values[0]);
       ++i) {
    for (size_t j = 0; j < sizeof(unsigned_values) / sizeof(unsigned_values[0]);
         ++j) {
      uint64_t a = unsigned_values[i];
      uint64_t b = unsigned_values[j];
      state = mix(state, branch_unsigned_eq(a, b));
      state = mix(state, branch_unsigned_ne(a, b));
      state = mix(state, branch_unsigned_lt(a, b));
      state = mix(state, branch_unsigned_le(a, b));
      state = mix(state, branch_unsigned_gt(a, b));
      state = mix(state, branch_unsigned_ge(a, b));
    }
  }

  for (size_t i = 0; i < sizeof(float_values) / sizeof(float_values[0]); ++i) {
    for (size_t j = 0; j < sizeof(float_values) / sizeof(float_values[0]); ++j) {
      double a = float_values[i];
      double b = float_values[j];
      state = mix(state, branch_float_eq(a, b));
      state = mix(state, branch_float_ne(a, b));
      state = mix(state, branch_float_lt(a, b));
      state = mix(state, branch_float_le(a, b));
      state = mix(state, branch_float_gt(a, b));
      state = mix(state, branch_float_ge(a, b));
    }
  }

  for (size_t i = 0;
       i < sizeof(signed128_values) / sizeof(signed128_values[0]); ++i) {
    int128_t value = signed128_values[i];
    state = mix(state, branch_i128_eq_neg1(value));
    state = mix(state, branch_i128_lt_zero(value));
    state = mix(state, branch_i128_ge_2p64(value));
    state = mix(state, branch_i128_lt_neg_2p64(value));
  }

  for (size_t i = 0;
       i < sizeof(unsigned128_values) / sizeof(unsigned128_values[0]); ++i) {
    uint128_t value = unsigned128_values[i];
    state = mix(state, branch_u128_eq_2p64(value));
    state = mix(state, branch_u128_lt_2p64(value));
    state = mix(state, branch_u128_gt_u64max(value));
    state = mix(state, branch_u128_ge_2p127(value));
  }

  state = mix(state, branch_sink);
  printf("%016" PRIx64 "\n", state);
  return 0;
}
