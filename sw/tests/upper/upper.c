#include <stdint.h>
#include "check.h"

static volatile uint32_t slot;
static volatile uint32_t other;

static __attribute__((noinline)) uint32_t identity(uint32_t x) { return x; }

int main(void) {
  volatile uint32_t a = 0xDEADBEEFu;
  volatile uint32_t b = 0x7FFFF800u;
  volatile uint32_t c = 0x00000800u;
  volatile uint32_t d = 0xFFFFF7FFu;

  CHECK(a == 0xDEADBEEFu);
  CHECK(b == 0x7FFFF800u);
  CHECK(c == 0x00000800u);
  CHECK(d == 0xFFFFF7FFu);
  CHECK(identity(0x12345000u) == 0x12345000u);
  CHECK(identity(0xFFFFFFFFu) == 0xFFFFFFFFu);

  uint32_t addr = (uint32_t)&slot;
  CHECK(addr >= 0x80000000u);
  CHECK(addr < 0x80010000u);
  CHECK((addr & 3u) == 0u);
  CHECK((uint32_t)&other != addr);

  uint32_t fn = (uint32_t)(void *)identity;
  CHECK(fn >= 0x80000000u);
  CHECK(fn < 0x80010000u);

  slot = a;
  CHECK(slot == 0xDEADBEEFu);
  other = ~a;
  CHECK(other == 0x21524110u);
  CHECK((slot ^ other) == 0xFFFFFFFFu);

  return 0;
}
