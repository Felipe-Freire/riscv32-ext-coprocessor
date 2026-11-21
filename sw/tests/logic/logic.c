#include <stdint.h>
#include "check.h"

int main(void) {
  volatile uint32_t a = 0xF0F0F0F0u, b = 0x0FF00FF0u;
  volatile int32_t  neg = -16;
  volatile int      sh = 4;

  CHECK((a & b) == 0x00F000F0u);
  CHECK((a | b) == 0xFFF0FFF0u);
  CHECK((a ^ b) == 0xFF00FF00u);
  CHECK((~a) == 0x0F0F0F0Fu);
  CHECK((a & 0xFFu) == 0xF0u);
  CHECK((a | 0x0Fu) == 0xF0F0F0FFu);
  CHECK((a ^ 0xFFu) == 0xF0F0F00Fu);

  CHECK((a << sh) == 0x0F0F0F00u);
  CHECK((a >> sh) == 0x0F0F0F0Fu);
  CHECK((neg >> sh) == -1);

  CHECK((a << 1) == 0xE1E1E1E0u);
  CHECK((a >> 31) == 1u);
  CHECK((a << 31) == 0u);
  CHECK((a >> 0) == 0xF0F0F0F0u);
  CHECK((neg >> 31) == -1);
  CHECK(((int32_t)0x40000000 >> 30) == 1);

  volatile uint32_t u = 0x80000000u;
  CHECK((u >> 4) == 0x08000000u);
  CHECK(((int32_t)u >> 4) == (int32_t)0xF8000000);

  return 0;
}
