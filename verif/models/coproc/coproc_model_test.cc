// Self-test of the coprocessor golden model: the streaming path on L2 layouts against a plain
// row-major product, and the register semantics. Prints a final PASS or FAIL line.
//
// Build and run from the repository root (output in build/):
//   g++ -std=c++11 -O2 -o build/coproc_model_test verif/models/coproc/coproc_model*.cc
//   build/coproc_model_test
#include <cstdio>
#include <random>
#include <vector>

#include "coproc_model.h"

static int errors = 0, checks = 0;

static void expect(bool cond, const char *what) {
  checks++;
  if (!cond && errors++ < 10) std::printf("FAIL: %s\n", what);
}

// Random job on L2 buffers through the streams, compared with the row-major product.
static void matmul_job(std::mt19937 &rng, uint32_t m, uint32_t n, uint32_t k, bool extremes) {
  const uint32_t      dim = 8;
  std::vector<int8_t> a(m * k), b(k * n), a_l2(m * k), b_l2(k * n);
  std::vector<int32_t> c(m * n), c_l2(m * n), c_ref(m * n);
  std::uniform_int_distribution<int> val(-128, 127), pick(0, 3);
  auto gen = [&]() -> int8_t {
    if (extremes) return pick(rng) < 2 ? -128 : (pick(rng) == 2 ? 127 : -128);
    return static_cast<int8_t>(val(rng));
  };
  for (auto &x : a) x = gen();
  for (auto &x : b) x = gen();

  coproc_pack_a(dim, m, k, a.data(), a_l2.data());
  coproc_pack_b(dim, k, n, b.data(), b_l2.data());
  expect(coproc_run_l2(dim, m, n, k, a_l2.data(), b_l2.data(), c_l2.data()) == 0, "run_l2");
  coproc_unpack_c(dim, m, n, c_l2.data(), c.data());
  coproc_matmul(m, n, k, a.data(), b.data(), c_ref.data());
  for (uint32_t i = 0; i < m * n; i++) {
    expect(c[i] == c_ref[i], "C element");
  }
}

static void registers() {
  coproc_model_t *m = coproc_model_new(8, 16);
  uint32_t        d = 0;

  expect(coproc_model_reg_read(m, COPROC_REG_STATUS, &d) == COPROC_RESP_OKAY && d == 0, "reset");
  expect(coproc_model_reg_read(m, 0x14, &d) == COPROC_RESP_SLVERR && d == 0, "read outside map");
  expect(coproc_model_reg_write(m, 0x100, 1, 0xF) == COPROC_RESP_SLVERR, "write outside map");

  // DIM_* keep 16 bits and honour WSTRB byte by byte.
  coproc_model_reg_write(m, COPROC_REG_DIM_M, 0xABCD1234, 0xF);
  coproc_model_reg_read(m, COPROC_REG_DIM_M, &d);
  expect(d == 0x1234, "DIM_M width");
  coproc_model_reg_write(m, COPROC_REG_DIM_M, 0x00005600, 0x2);
  coproc_model_reg_read(m, COPROC_REG_DIM_M, &d);
  expect(d == 0x5634, "DIM_M WSTRB");

  // A one-tile job: START sets BUSY, CTRL reads 0, DIM_* and START are ignored while busy.
  coproc_model_reg_write(m, COPROC_REG_DIM_M, 8, 0xF);
  coproc_model_reg_write(m, COPROC_REG_DIM_N, 8, 0xF);
  coproc_model_reg_write(m, COPROC_REG_DIM_K, 2, 0xF);
  coproc_model_reg_write(m, COPROC_REG_CTRL, COPROC_CTRL_START, 0x1);
  coproc_model_reg_read(m, COPROC_REG_STATUS, &d);
  expect(d == COPROC_STATUS_BUSY, "BUSY after START");
  coproc_model_reg_read(m, COPROC_REG_CTRL, &d);
  expect(d == 0, "CTRL reads 0");
  coproc_model_reg_write(m, COPROC_REG_DIM_K, 5, 0xF);
  coproc_model_reg_read(m, COPROC_REG_DIM_K, &d);
  expect(d == 2, "DIM_K ignored while busy");

  uint32_t w;
  expect(!coproc_model_pop_c(m, &w), "no C before the inputs");
  for (int s = 0; s < 2; s++) {
    coproc_model_push_a(m, 0x0102030405060708ull);
    coproc_model_push_b(m, 0xFFFFFFFFFFFFFFFFull);  // all -1
  }
  int words = 0;
  while (coproc_model_pop_c(m, &w)) {
    // C[r][c] = 2 * A lane r * (-1); lane r of A is 8 - r.
    expect(static_cast<int32_t>(w) == -2 * (8 - words / 8), "tile value");
    words++;
  }
  expect(words == 64, "64 words per tile");
  coproc_model_reg_read(m, COPROC_REG_STATUS, &d);
  expect(d == COPROC_STATUS_DONE, "DONE after the last word");
  coproc_model_reg_write(m, COPROC_REG_STATUS, COPROC_STATUS_DONE, 0x1);
  coproc_model_reg_read(m, COPROC_REG_STATUS, &d);
  expect(d == 0, "DONE is W1C");
  expect(coproc_model_jobs(m) == 1, "job count");
  coproc_model_free(m);
}

int main() {
  std::mt19937 rng(1);
  registers();
  std::uniform_int_distribution<int> tiles(1, 6), kk(1, 70);
  for (int i = 0; i < 300; i++) {
    matmul_job(rng, 8 * tiles(rng), 8 * tiles(rng), kk(rng), i % 10 == 0);
  }
  matmul_job(rng, 8, 8, 4096, true);  // long accumulation of extremes: wraps around
  std::printf("%s: %d checks, %d errors\n", errors ? "FAIL" : "PASS", checks, errors);
  return errors != 0;
}
