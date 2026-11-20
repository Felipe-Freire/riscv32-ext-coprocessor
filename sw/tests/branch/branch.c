#include <stdint.h>
#include "check.h"

int main(void) {
  volatile int32_t  a = 5, b = 5, c = -3;
  volatile uint32_t ua = 0xFFFFFFFFu;
  int taken = 0;

  if (a == b) taken++;
  if (a == c) taken += 100;
  CHECK(taken == 1);

  if (a != c) taken++;
  if (a != b) taken += 100;
  CHECK(taken == 2);

  if (c < a) taken++;
  if (a < c) taken += 100;
  CHECK(taken == 3);

  if (a >= b) taken++;
  if (c >= a) taken += 100;
  CHECK(taken == 4);

  if ((uint32_t)a < ua) taken++;
  if (ua < (uint32_t)a) taken += 100;
  CHECK(taken == 5);
  CHECK((int32_t)ua < a);

  int sum = 0;
  for (volatile int i = 1; i <= 10; i++) sum += i;
  CHECK(sum == 55);

  sum = 0;
  for (volatile int i = 0; i < 10; i++) {
    if (i & 1) continue;
    sum += i;
  }
  CHECK(sum == 20);

  volatile int32_t x = 7;
  int32_t y = x - 7;
  CHECK(y == 0);
  if (y != 0) return 99;

  int n = 0;
  do { n++; } while (n < 3);
  CHECK(n == 3);

  return 0;
}
