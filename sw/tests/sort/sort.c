#include <stdint.h>
#include "check.h"

#define N 48

static int32_t a[N];
static int32_t b[N];

static void fill(int32_t *p) {
  uint32_t x = 0x1234567u;
  for (int i = 0; i < N; i++) {
    x = x * 1103515245u + 12345u;
    p[i] = (int32_t)(x >> 16) % 100 - 50;
  }
}

static void insertion_sort(int32_t *p, int n) {
  for (int i = 1; i < n; i++) {
    int32_t key = p[i];
    int j = i - 1;
    while (j >= 0 && p[j] > key) {
      p[j + 1] = p[j];
      j--;
    }
    p[j + 1] = key;
  }
}

static void bubble_sort(int32_t *p, int n) {
  for (int pass = 0; pass < n - 1; pass++) {
    int swapped = 0;
    for (int i = 0; i < n - 1 - pass; i++) {
      if (p[i] > p[i + 1]) {
        int32_t t = p[i];
        p[i] = p[i + 1];
        p[i + 1] = t;
        swapped = 1;
      }
    }
    if (!swapped) break;
  }
}

static int sorted(const int32_t *p, int n) {
  for (int i = 1; i < n; i++) {
    if (p[i - 1] > p[i]) return 0;
  }
  return 1;
}

static int32_t checksum(const int32_t *p, int n) {
  int32_t s = 0;
  for (int i = 0; i < n; i++) s += p[i];
  return s;
}

int main(void) {
  fill(a);
  fill(b);
  CHECK(checksum(a, N) == checksum(b, N));
  int32_t before = checksum(a, N);
  CHECK(!sorted(a, N));

  insertion_sort(a, N);
  CHECK(sorted(a, N));
  CHECK(checksum(a, N) == before);

  bubble_sort(b, N);
  CHECK(sorted(b, N));
  CHECK(checksum(b, N) == before);

  for (int i = 0; i < N; i++) CHECK(a[i] == b[i]);

  insertion_sort(a, N);
  CHECK(sorted(a, N));
  bubble_sort(b, N);
  CHECK(sorted(b, N));
  CHECK(a[0] == b[0] && a[N - 1] == b[N - 1]);
  CHECK(a[0] <= a[N - 1]);

  for (int i = 0; i < N; i++) b[i] = a[N - 1 - i];
  insertion_sort(b, N);
  CHECK(sorted(b, N));
  CHECK(checksum(b, N) == before);

  int32_t one[1] = { 42 };
  insertion_sort(one, 1);
  CHECK(one[0] == 42);
  bubble_sort(one, 0);
  CHECK(one[0] == 42);

  return 0;
}
