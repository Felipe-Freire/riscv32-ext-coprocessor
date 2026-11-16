// Bit manipulation written out of shifts and masks, since the core has no B extension: popcount,
// leading and trailing zeros, bit reversal, byte swap, rotations and field insert. Shift and mask
// patterns that none of the other tests produce.
#include <stdint.h>
#include "check.h"

static uint32_t popcount(uint32_t x) {
  x = x - ((x >> 1) & 0x55555555u);
  x = (x & 0x33333333u) + ((x >> 2) & 0x33333333u);
  x = (x + (x >> 4)) & 0x0F0F0F0Fu;
  return (x * 0x01010101u) >> 24;        // through __mulsi3
}

static uint32_t clz(uint32_t x) {
  if (x == 0) return 32;
  uint32_t n = 0;
  if (!(x & 0xFFFF0000u)) { n += 16; x <<= 16; }
  if (!(x & 0xFF000000u)) { n += 8;  x <<= 8;  }
  if (!(x & 0xF0000000u)) { n += 4;  x <<= 4;  }
  if (!(x & 0xC0000000u)) { n += 2;  x <<= 2;  }
  if (!(x & 0x80000000u)) { n += 1; }
  return n;
}

static uint32_t ctz(uint32_t x) {
  return (x == 0) ? 32 : 31 - clz(x & (~x + 1u));
}

static uint32_t bitrev(uint32_t x) {
  x = ((x & 0x55555555u) << 1) | ((x >> 1) & 0x55555555u);
  x = ((x & 0x33333333u) << 2) | ((x >> 2) & 0x33333333u);
  x = ((x & 0x0F0F0F0Fu) << 4) | ((x >> 4) & 0x0F0F0F0Fu);
  x = ((x & 0x00FF00FFu) << 8) | ((x >> 8) & 0x00FF00FFu);
  return (x << 16) | (x >> 16);
}

static uint32_t bswap(uint32_t x) {
  return ((x & 0x000000FFu) << 24) | ((x & 0x0000FF00u) << 8)
       | ((x & 0x00FF0000u) >> 8)  | ((x & 0xFF000000u) >> 24);
}

static uint32_t rotl(uint32_t x, unsigned n) {
  return (n == 0) ? x : ((x << n) | (x >> (32 - n)));
}

int main(void) {
  volatile uint32_t zero = 0u, ones = 0xFFFFFFFFu, pat = 0xDEADBEEFu, one = 1u;

  CHECK(popcount(zero) == 0);
  CHECK(popcount(ones) == 32);
  CHECK(popcount(one) == 1);
  CHECK(popcount(pat) == 24);
  CHECK(popcount(0x80000000u) == 1);

  CHECK(clz(zero) == 32);
  CHECK(clz(one) == 31);
  CHECK(clz(0x80000000u) == 0);
  CHECK(clz(0x00FF0000u) == 8);
  CHECK(clz(ones) == 0);

  CHECK(ctz(zero) == 32);
  CHECK(ctz(one) == 0);
  CHECK(ctz(0x80000000u) == 31);
  CHECK(ctz(0x00000100u) == 8);

  CHECK(bitrev(one) == 0x80000000u);
  CHECK(bitrev(0x80000000u) == 1u);
  CHECK(bitrev(zero) == 0u);
  CHECK(bitrev(ones) == 0xFFFFFFFFu);
  CHECK(bitrev(bitrev(pat)) == 0xDEADBEEFu);

  CHECK(bswap(0x12345678u) == 0x78563412u);
  CHECK(bswap(bswap(pat)) == 0xDEADBEEFu);
  CHECK(bswap(zero) == 0u);

  CHECK(rotl(0x80000001u, 1) == 0x00000003u);
  CHECK(rotl(pat, 4) == 0xEADBEEFDu);
  CHECK(rotl(pat, 0) == 0xDEADBEEFu);
  CHECK(rotl(rotl(pat, 8), 24) == 0xDEADBEEFu);

  // Field insert: put 0xA into bits 11:8 of a word, leaving the rest alone
  volatile uint32_t word = 0x12345678u;
  uint32_t inserted = (word & ~0x00000F00u) | (0xAu << 8);
  CHECK(inserted == 0x12345A78u);

  // Sign extension of a 12-bit field by shifting up and back down
  volatile int32_t field = 0x00000FFF;
  CHECK((int32_t)(field << 20) >> 20 == -1);
  field = 0x000007FF;
  CHECK((int32_t)(field << 20) >> 20 == 2047);

  return 0;
}
