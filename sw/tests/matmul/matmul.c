#include <stdint.h>
#include "check.h"

#define M 8
#define K 8
#define N 8

static int32_t A[M][K];
static int32_t B[K][N];
static int32_t C[M][N];
static int32_t D[M][N];
static int32_t I[K][N];

static void matmul_ijk(const int32_t a[M][K], const int32_t b[K][N], int32_t c[M][N]) {
  for (int i = 0; i < M; i++) {
    for (int j = 0; j < N; j++) {
      int32_t acc = 0;
      for (int k = 0; k < K; k++) acc += a[i][k] * b[k][j];
      c[i][j] = acc;
    }
  }
}

static void matmul_kij(const int32_t a[M][K], const int32_t b[K][N], int32_t c[M][N]) {
  for (int i = 0; i < M; i++) {
    for (int j = 0; j < N; j++) c[i][j] = 0;
  }
  for (int k = 0; k < K; k++) {
    for (int i = 0; i < M; i++) {
      int32_t aik = a[i][k];
      for (int j = 0; j < N; j++) c[i][j] += aik * b[k][j];
    }
  }
}

static int equal(const int32_t x[M][N], const int32_t y[M][N]) {
  for (int i = 0; i < M; i++) {
    for (int j = 0; j < N; j++) {
      if (x[i][j] != y[i][j]) return 0;
    }
  }
  return 1;
}

int main(void) {
  for (int i = 0; i < M; i++) {
    for (int k = 0; k < K; k++) A[i][k] = i - k + 1;
  }
  for (int k = 0; k < K; k++) {
    for (int j = 0; j < N; j++) B[k][j] = (k + 1) * (j + 1);
  }
  for (int k = 0; k < K; k++) {
    for (int j = 0; j < N; j++) I[k][j] = (k == j) ? 1 : 0;
  }

  matmul_ijk(A, I, C);
  for (int i = 0; i < M; i++) {
    for (int j = 0; j < N; j++) CHECK(C[i][j] == A[i][j]);
  }

  matmul_ijk(A, B, C);
  matmul_kij(A, B, D);
  CHECK(equal(C, D));

  int32_t c00 = 0;
  for (int k = 0; k < K; k++) c00 += (1 - k) * (k + 1);
  CHECK(C[0][0] == c00);

  for (int i = 0; i < M; i++) {
    for (int j = 0; j < N; j++) CHECK(C[i][j] == C[i][0] * (j + 1));
  }

  int32_t colsum[N];
  for (int j = 0; j < N; j++) {
    colsum[j] = 0;
    for (int k = 0; k < K; k++) colsum[j] += B[k][j];
  }
  for (int i = 0; i < M; i++) {
    for (int j = 0; j < N; j++) CHECK(C[i][j] == C[0][j] + i * colsum[j]);
  }

  for (int k = 0; k < K; k++) {
    for (int j = 0; j < N; j++) I[k][j] = 0;
  }
  matmul_ijk(A, I, C);
  for (int i = 0; i < M; i++) {
    for (int j = 0; j < N; j++) CHECK(C[i][j] == 0);
  }

  return 0;
}
