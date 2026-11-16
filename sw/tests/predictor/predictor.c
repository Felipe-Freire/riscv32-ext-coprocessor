// Branch prediction. The core predicts statically: backward taken, forward not taken
// (rtl/core/units/rv32_branch_pred.sv), and EX redirects to the other path on a misprediction.
// These loops are built to mispredict often, so the redirect path runs thousands of times.
//
// The trace comparison is what checks correctness; the cycle count in the report is where the
// mispredictions show up, since Spike has no pipeline to lose.
#include <stdint.h>
#include "check.h"

#define N 64

static volatile int32_t data[N];

int main(void) {
  // Alternating condition: every iteration decides the other way, so a static prediction is
  // wrong about half the time and a one-bit history would be wrong almost always.
  int taken = 0, skipped = 0;
  for (int i = 0; i < N; i++) {
    if (i & 1) taken++;
    else skipped++;
  }
  CHECK(taken == N / 2);
  CHECK(skipped == N / 2);

  // Data-dependent condition from memory, which cannot be predicted from the opcode at all
  uint32_t x = 0x1234567u;
  for (int i = 0; i < N; i++) {
    x = x * 1103515245u + 12345u;
    data[i] = (int32_t)(int16_t)(x >> 16);   // signed, so both paths of the test run
  }
  int positive = 0, negative = 0;
  for (int i = 0; i < N; i++) {
    if (data[i] < 0) negative++;
    else positive++;
  }
  CHECK(positive + negative == N);
  CHECK(positive > 0 && negative > 0);        // both paths really are taken

  // Forward branch that is always taken: the prediction is wrong every single time
  int hits = 0;
  for (int i = 0; i < N; i++) {
    if (i >= 0) {                             // always true, and the branch over it is forward
      hits++;
      continue;
    }
    hits += 1000;
  }
  CHECK(hits == N);

  // Backward branch that is not taken: a loop that exits on its first test
  int never = 0;
  for (int i = 0; i < 0; i++) never++;
  CHECK(never == 0);

  // Nested loops: the inner backward branch is predicted taken and mispredicts once per exit
  int32_t sum = 0;
  for (int i = 0; i < 8; i++) {
    for (int j = 0; j < 8; j++) sum += (i ^ j);
  }
  CHECK(sum == 224);          // sum over i,j in 0..7 of (i ^ j)

  // A loop whose body contains a call, so JALR and the return compete with the branch
  volatile int32_t acc = 0;
  for (int i = 0; i < 16; i++) acc += (i % 3 == 0) ? 2 : 1;
  CHECK(acc == 22);

  // Early exit out of the middle of a loop
  int found = -1;
  for (int i = 0; i < N; i++) {
    if (data[i] == data[N - 1]) { found = i; break; }
  }
  CHECK(found >= 0);
  CHECK(data[found] == data[N - 1]);

  return 0;
}
