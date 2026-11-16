// Q15 fixed-point arithmetic: a multiply-accumulate loop with rounding and saturation, which is
// the shape of the work the coprocessor does, written for the scalar core.
//
// Every multiply is __mulsi3 and every product needs a shift and a saturating clamp, so this
// mixes the multiply routine with shifts, compares and conditional moves done as branches.
#include <stdint.h>
#include "check.h"

#define Q 15
#define ONE   (1 << Q)                  // 1.0
#define HALF  (ONE / 2)                 // 0.5
#define QMAX  32767
#define QMIN  (-32768)

static int32_t sat16(int32_t v) {
  if (v > QMAX) return QMAX;
  if (v < QMIN) return QMIN;
  return v;
}

// Q15 x Q15 -> Q15, rounded to nearest and saturated
static int32_t qmul(int32_t a, int32_t b) {
  int32_t product = a * b;                      // __mulsi3
  return sat16((product + (1 << (Q - 1))) >> Q);
}

static int32_t qmac(const int32_t *x, const int32_t *w, int n) {
  int32_t acc = 0;
  for (int i = 0; i < n; i++) acc = sat16(acc + qmul(x[i], w[i]));
  return acc;
}

int main(void) {
  volatile int32_t one = ONE, half = HALF, quarter = ONE / 4;
  volatile int32_t neg_half = -HALF, qmax = QMAX, qmin = QMIN;

  // 1.0 is not representable in Q15, so 1.0 * 1.0 saturates to QMAX
  CHECK(qmul(one, one) == QMAX);
  CHECK(qmul(half, half) == ONE / 4);
  CHECK(qmul(half, quarter) == ONE / 8);
  CHECK(qmul(half, 0) == 0);
  CHECK(qmul(neg_half, half) == -(ONE / 4));
  CHECK(qmul(neg_half, neg_half) == ONE / 4);

  // Rounding to nearest, not truncation: 1/32768 * 1/2 rounds up to 1/32768
  CHECK(qmul(1, half) == 1);
  CHECK(qmul(1, quarter) == 0);

  // Saturation at both ends
  CHECK(sat16(QMAX + 1) == QMAX);
  CHECK(sat16(QMIN - 1) == QMIN);
  CHECK(sat16(qmax) == QMAX);
  CHECK(sat16(qmin) == QMIN);
  CHECK(sat16(100000) == QMAX);
  CHECK(sat16(-100000) == QMIN);

  // A dot product that stays in range
  static const int32_t x[8] = { HALF, HALF, HALF, HALF, HALF, HALF, HALF, HALF };
  static const int32_t w[8] = { ONE / 8, ONE / 8, ONE / 8, ONE / 8,
                                ONE / 8, ONE / 8, ONE / 8, ONE / 8 };
  CHECK(qmac(x, w, 8) == 8 * (ONE / 16));

  // A dot product that saturates on the way
  static const int32_t big[8] = { QMAX, QMAX, QMAX, QMAX, QMAX, QMAX, QMAX, QMAX };
  CHECK(qmac(big, big, 8) == QMAX);

  // Alternating signs cancel out
  static const int32_t alt[4] = { HALF, -HALF, HALF, -HALF };
  static const int32_t ones[4] = { ONE / 2, ONE / 2, ONE / 2, ONE / 2 };
  CHECK(qmac(alt, ones, 4) == 0);

  // A longer accumulation, the inner loop of a filter
  static int32_t taps[32];
  static int32_t sig[32];
  for (int i = 0; i < 32; i++) {
    taps[i] = ONE / 64;
    sig[i] = (i & 1) ? HALF : quarter;
  }
  int32_t acc = qmac(sig, taps, 32);
  CHECK(acc > 0 && acc < QMAX);
  CHECK(acc == 16 * qmul(HALF, ONE / 64) + 16 * qmul(ONE / 4, ONE / 64));

  return 0;
}
