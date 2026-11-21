#include <stdint.h>
#include "check.h"

#define N 64

static uint8_t src[N];
static uint8_t dst[N];

static void fill(uint8_t *p, int n, uint8_t seed) {
  for (int i = 0; i < n; i++) p[i] = (uint8_t)(seed + i * 7);
}

static void copy_bytes(uint8_t *d, const uint8_t *s, int n) {
  while (n--) *d++ = *s++;
}

static void copy_words(uint32_t *d, const uint32_t *s, int n) {
  while (n--) *d++ = *s++;
}

static void set_bytes(uint8_t *d, uint8_t v, int n) {
  while (n--) *d++ = v;
}

static int equal(const uint8_t *a, const uint8_t *b, int n) {
  for (int i = 0; i < n; i++) {
    if (a[i] != b[i]) return 0;
  }
  return 1;
}

int main(void) {
  fill(src, N, 1);

  set_bytes(dst, 0, N);
  copy_bytes(dst, src, N);
  CHECK(equal(dst, src, N));

  set_bytes(dst, 0, N);
  copy_words((uint32_t *)dst, (const uint32_t *)src, N / 4);
  CHECK(equal(dst, src, N));

  set_bytes(dst, 0xEE, N);
  copy_words((uint32_t *)dst, (const uint32_t *)src, 3);
  copy_bytes(dst + 12, src + 12, 5);
  CHECK(equal(dst, src, 17));
  CHECK(dst[17] == 0xEE);

  set_bytes(dst, 0x11, N);
  copy_bytes(dst, src, 0);
  CHECK(dst[0] == 0x11);

  set_bytes(dst, 0xA5, N);
  CHECK(dst[0] == 0xA5 && dst[N / 2] == 0xA5 && dst[N - 1] == 0xA5);
  set_bytes(dst, 0, N);
  CHECK(dst[0] == 0 && dst[N - 1] == 0);

  fill(dst, N, 1);
  copy_bytes(dst, dst + 8, N - 8);
  CHECK(dst[0] == src[8]);
  CHECK(dst[1] == src[9]);
  CHECK(dst[N - 9] == src[N - 1]);

  set_bytes(dst, 0, N);
  dst[N - 1] = 0x7E;
  CHECK(dst[N - 1] == 0x7E);
  CHECK(dst[N - 2] == 0);

  return 0;
}
