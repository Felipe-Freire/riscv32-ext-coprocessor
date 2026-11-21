#include <stdint.h>
#include "check.h"

static volatile union {
  uint32_t w[4];
  uint16_t h[8];
  uint8_t  b[16];
  int8_t   sb[16];
  int16_t  sh[8];
} m;

int main(void) {
  m.w[0] = 0x12345678u;
  CHECK(m.b[0] == 0x78);
  CHECK(m.b[1] == 0x56);
  CHECK(m.b[2] == 0x34);
  CHECK(m.b[3] == 0x12);

  CHECK(m.h[0] == 0x5678u);
  CHECK(m.h[1] == 0x1234u);

  m.w[1] = 0x80FF7F01u;
  CHECK(m.b[4] == 0x01u);
  CHECK(m.b[5] == 0x7Fu);
  CHECK(m.b[6] == 0xFFu);
  CHECK(m.b[7] == 0x80u);
  CHECK(m.sb[6] == -1);
  CHECK(m.sb[7] == -128);
  CHECK(m.sb[5] == 127);
  CHECK(m.sh[3] == (int16_t)0x80FF);
  CHECK(m.h[3] == 0x80FFu);

  m.w[2] = 0;
  m.b[8]  = 0xAA;
  CHECK(m.w[2] == 0x000000AAu);
  m.b[11] = 0xBB;
  CHECK(m.w[2] == 0xBB0000AAu);
  m.b[9]  = 0xCC;
  CHECK(m.w[2] == 0xBB00CCAAu);
  m.b[10] = 0xDD;
  CHECK(m.w[2] == 0xBBDDCCAAu);

  m.w[3] = 0;
  m.h[6] = 0x1122u;
  CHECK(m.w[3] == 0x00001122u);
  m.h[7] = 0x3344u;
  CHECK(m.w[3] == 0x33441122u);

  volatile uint32_t v = 0;
  v = 0xDEADBEEFu;
  CHECK(v == 0xDEADBEEFu);

  volatile uint8_t *p = &m.b[0];
  CHECK(p[0] == 0x78);
  CHECK(p[3] == 0x12);
  CHECK(*(p + 4) == 0x01);

  return 0;
}
