#include <stdint.h>
#include "check.h"

int main(void) {
  volatile int32_t a = 1234, b = 5678;
  volatile int32_t neg = -7, zero = 0;
  volatile uint32_t ua = 0x00010001u, ub = 3u;

  CHECK(a * b == 7006652);
  CHECK(b * a == 7006652);
  CHECK(a * zero == 0);
  CHECK(a * neg == -8638);
  CHECK(neg * neg == 49);
  CHECK(ua * ub == 0x00030003u);

  CHECK(a * 8 == 9872);
  CHECK(neg * 4 == -28);

  volatile uint32_t big = 0x00010000u;
  CHECK(big * big == 0u);

  return 0;
}
