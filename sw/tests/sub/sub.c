#include <stdint.h>
#include "check.h"

int main(void) {
  volatile int32_t  a = 123450987, b = 35;
  volatile int32_t  neg = -3, zero = 0;
  volatile uint32_t ua = 0x10u, ub = 0x20u;

  CHECK(a - b == 123450952);
  CHECK(b - a == -123450952);
  CHECK(a - zero == 123450987);
  CHECK(a - a == 0);
  CHECK(zero - b == -35);

  CHECK(a - neg == 123450990);
  CHECK(neg - neg == 0);
  CHECK(neg - 1 == -4);

  CHECK(a - 1 == 123450986);
  CHECK(a - 2048 == 123448939);

  CHECK(ua - ub == 0xFFFFFFF0u);
  CHECK(0u - 1u == 0xFFFFFFFFu);

  volatile int32_t min = (int32_t)0x80000000;
  CHECK((uint32_t)min - 1u == 0x7FFFFFFFu);

  return 0;
}
