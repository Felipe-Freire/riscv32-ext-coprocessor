#include <stdint.h>
#include "check.h"

int main(void) {
  volatile int32_t  a = 1234, b = 5678;
  volatile int32_t  neg = -3, zero = 0;
  volatile uint32_t ua = 0xFFFFFFF0u, ub = 0x20u;

  CHECK(a + b == 6912);
  CHECK(b + a == 6912);
  CHECK(a + zero == 1234);
  CHECK(a + neg == 1231);
  CHECK(neg + neg == -6);

  CHECK(a + 1 == 1235);
  CHECK(a + 2047 == 3281);
  CHECK(a + (-2048) == -814);
  CHECK(a + 4096 == 5330);

  CHECK(ua + ub == 0x10u);
  CHECK(ua + 1u == 0xFFFFFFF1u);
  CHECK(0xFFFFFFFFu + (uint32_t)a == 1233u);

  volatile int32_t max = 0x7FFFFFFF;
  CHECK((uint32_t)max + 1u == 0x80000000u);

  return 0;
}
