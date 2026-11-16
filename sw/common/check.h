// Self-checking helper for the bare-metal tests.
//
// CHECK numbers the checks as it goes and returns the index of the first one that fails, so the
// exit code says which check broke: 0 passed everything, 3 means the third CHECK failed. crt0
// turns the return value into the HTIF exit code, which both Spike and the testbench report.
//
// Keep the operands of the operation under test in volatile variables. With constants the
// compiler folds the operation away at compile time and the test checks nothing:
//
//   volatile int32_t a = 1234, b = 5678;
//   CHECK(a + b == 6912);          // the add really runs
//   CHECK(1234 + 5678 == 6912);    // folded, tests nothing
#ifndef CHECK_H
#define CHECK_H

static unsigned check_count __attribute__((unused));   // in .bss, zeroed by crt0

#define CHECK(cond)                        \
  do {                                     \
    ++check_count;                         \
    if (!(cond)) return (int)check_count;  \
  } while (0)

#endif  // CHECK_H
