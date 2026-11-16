#include <stdint.h>
#include "check.h"

#define POLY 0xEDB88320u

static uint32_t table[256];
static const char text[] = "The quick brown fox jumps over the lazy dog";
static uint8_t data[64];

static uint32_t crc_bitwise(const uint8_t *p, int n) {
  uint32_t crc = 0xFFFFFFFFu;
  for (int i = 0; i < n; i++) {
    crc ^= p[i];
    for (int bit = 0; bit < 8; bit++) {
      crc = (crc >> 1) ^ (POLY & (uint32_t)(-(int32_t)(crc & 1u)));
    }
  }
  return ~crc;
}

static void build_table(void) {
  for (uint32_t i = 0; i < 256; i++) {
    uint32_t crc = i;
    for (int bit = 0; bit < 8; bit++) {
      crc = (crc & 1u) ? (crc >> 1) ^ POLY : (crc >> 1);
    }
    table[i] = crc;
  }
}

static uint32_t crc_table(const uint8_t *p, int n) {
  uint32_t crc = 0xFFFFFFFFu;
  for (int i = 0; i < n; i++) {
    crc = table[(crc ^ p[i]) & 0xFFu] ^ (crc >> 8);
  }
  return ~crc;
}

int main(void) {
  build_table();

  CHECK(table[0] == 0x00000000u);
  CHECK(table[1] == 0x77073096u);
  CHECK(table[255] == 0x2D02EF8Du);

  static const uint8_t digits[9] = { '1', '2', '3', '4', '5', '6', '7', '8', '9' };
  CHECK(crc_bitwise(digits, 9) == 0xCBF43926u);
  CHECK(crc_table(digits, 9) == 0xCBF43926u);

  CHECK(crc_bitwise(digits, 0) == 0u);
  CHECK(crc_table(digits, 0) == 0u);

  CHECK(crc_bitwise((const uint8_t *)"a", 1) == crc_table((const uint8_t *)"a", 1));

  int len = 0;
  while (text[len]) len++;
  CHECK(len == 43);
  uint32_t c1 = crc_bitwise((const uint8_t *)text, len);
  uint32_t c2 = crc_table((const uint8_t *)text, len);
  CHECK(c1 == c2);
  CHECK(c1 == 0x414FA339u);

  for (int i = 0; i < len; i++) data[i] = (uint8_t)text[i];
  data[7] ^= 0x01u;
  CHECK(crc_table(data, len) != c1);
  data[7] ^= 0x01u;
  CHECK(crc_table(data, len) == c1);

  return 0;
}
