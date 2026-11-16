#include <stdint.h>
#include "check.h"

int main(void) {
  volatile int32_t a = 1000, b = 50, c = -7, d = 2;
  volatile uint32_t ua = 0xFFFFFFFFu, ub = 3u;

  CHECK(a / b == 20);
  CHECK(a % b == 0);
  CHECK(a / 7 == 142);
  CHECK(a % 7 == 6);

  CHECK(c / d == -3);
  CHECK(c % d == -1);
  CHECK(-a / c == 142);
  CHECK(a / -b == -20);

  CHECK(ua / ub == 0x55555555u);
  CHECK(ua % ub == 0u);
  CHECK((int32_t)ua / (int32_t)ub == 0);
  CHECK((int32_t)ua % (int32_t)ub == -1);

  CHECK(a / 8 == 125);
  CHECK(c / 2 == -3);

  return 0;
}
