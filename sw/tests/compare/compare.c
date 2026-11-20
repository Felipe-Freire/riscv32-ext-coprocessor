#include <stdint.h>
#include "check.h"

int main(void) {
  volatile int32_t  neg = -1, pos = 1, zero = 0;
  volatile int32_t  min = (int32_t)0x80000000, max = 0x7FFFFFFF;
  volatile uint32_t umin = 0x80000000u, umax = 0xFFFFFFFFu;

  CHECK(neg < pos);
  CHECK(!(pos < neg));
  CHECK(min < max);
  CHECK(min < zero);
  CHECK(max > zero);
  CHECK(!(neg < neg));

  CHECK(umax > 1u);
  CHECK(umin > 0x7FFFFFFFu);
  CHECK((uint32_t)neg == umax);
  CHECK(!((uint32_t)neg < 1u));

  CHECK(min < max);
  CHECK(umin > (uint32_t)max);

  CHECK(neg < 5);
  CHECK((uint32_t)neg >= 5u);
  CHECK(zero < 1);
  CHECK(!(zero < 0));

  return 0;
}
