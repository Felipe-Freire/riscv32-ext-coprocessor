#include <stdint.h>
#include "check.h"

static __attribute__((noinline)) uint32_t fib(uint32_t n) {
  return (n < 2) ? n : fib(n - 1) + fib(n - 2);
}

static __attribute__((noinline)) uint32_t fact(uint32_t n) {
  return (n == 0) ? 1 : n * fact(n - 1);
}

static __attribute__((noinline)) uint32_t sum_to(uint32_t n) {
  return (n == 0) ? 0 : n + sum_to(n - 1);
}

static int is_odd(uint32_t n);
static __attribute__((noinline)) int is_even(uint32_t n) { return (n == 0) ? 1 : is_odd(n - 1); }
static __attribute__((noinline)) int is_odd(uint32_t n)  { return (n == 0) ? 0 : is_even(n - 1); }

static __attribute__((noinline)) uint32_t depth(uint32_t n, uint32_t acc) {
  volatile uint32_t here = acc ^ n;
  if (n == 0) return acc;
  return depth(n - 1, here) ^ 0u;
}

int main(void) {
  volatile uint32_t n = 12;

  CHECK(fib(0) == 0);
  CHECK(fib(1) == 1);
  CHECK(fib(n) == 144);
  CHECK(fib(n - 1) == 89);

  CHECK(fact(0) == 1);
  CHECK(fact(5) == 120);
  CHECK(fact(10) == 3628800u);

  CHECK(sum_to(10) == 55);
  CHECK(sum_to(32) == 528);

  CHECK(is_even(10));
  CHECK(!is_even(11));
  CHECK(is_odd(7));
  CHECK(!is_odd(8));

  CHECK(depth(16, 0) != 0xFFFFFFFFu);
  CHECK(depth(0, 0x1234u) == 0x1234u);

  volatile uint32_t sentinel = 0xC0FFEEu;
  CHECK(fib(8) == 21);
  CHECK(sentinel == 0xC0FFEEu);

  return 0;
}
