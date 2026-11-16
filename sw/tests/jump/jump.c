#include <stdint.h>
#include "check.h"

static __attribute__((noinline)) int leaf(int x) {
  return x + 1;
}

static __attribute__((noinline)) int middle(int x) {
  return leaf(x) * 2;
}

static __attribute__((noinline)) int outer(int x) {
  return middle(x) + leaf(x);
}

static __attribute__((noinline)) int add_op(int a, int b) { return a + b; }
static __attribute__((noinline)) int sub_op(int a, int b) { return a - b; }

static int (*volatile ops[2])(int, int) = { add_op, sub_op };

int main(void) {
  volatile int x = 10;

  CHECK(leaf(x) == 11);
  CHECK(middle(x) == 22);
  CHECK(outer(x) == 33);

  CHECK(outer(outer(x)) == 102);

  CHECK(ops[0](7, 3) == 10);
  CHECK(ops[1](7, 3) == 4);

  volatile int which = 1;
  CHECK(ops[which](20, 5) == 15);

  CHECK(leaf(x) + middle(x) == 33);

  return 0;
}
