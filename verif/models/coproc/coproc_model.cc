// Golden model of the matrix coprocessor. Interface and conventions: coproc_model.h.
#include "coproc_model.h"

#include <deque>
#include <vector>

struct coproc_model {
  uint32_t dim;
  uint32_t dim_mask;  // DIM_* register width

  // Registers.
  uint32_t dim_m, dim_n, dim_k;
  bool     busy, done;

  // Job being run: tile counts and steps, sampled with START.
  uint32_t tiles_m, tiles_n, k;
  uint32_t ti, tj;

  // Stream beats received and not used yet.
  std::deque<uint64_t> a_q, b_q;

  // Current tile of C, computed once its 2K beats are in, and the next word to send.
  std::vector<uint32_t> tile;
  bool                  tile_ready;
  uint32_t              word;

  uint32_t jobs;
};

namespace {

int8_t lane(uint64_t beat, uint32_t l) { return static_cast<int8_t>((beat >> (8 * l)) & 0xFF); }

// int32 accumulation with wrap-around, done on unsigned values so the overflow is defined.
uint32_t mac(uint32_t acc, int8_t a, int8_t b) {
  return acc + static_cast<uint32_t>(static_cast<int32_t>(a) * static_cast<int32_t>(b));
}

uint32_t tiles(uint32_t dim_value, uint32_t dim) {
  uint32_t t = dim_value / dim;
  return t == 0 ? 1 : t;
}

uint32_t write_bytes(uint32_t old, uint32_t data, uint32_t strb, uint32_t mask) {
  uint32_t res = old;
  for (uint32_t b = 0; b < 4; b++) {
    if (strb & (1u << b)) {
      uint32_t byte_mask = 0xFFu << (8 * b);
      res = (res & ~byte_mask) | (data & byte_mask);
    }
  }
  return res & mask;
}

void start_job(coproc_model_t *m) {
  m->tiles_m    = tiles(m->dim_m, m->dim);
  m->tiles_n    = tiles(m->dim_n, m->dim);
  m->k          = m->dim_k == 0 ? 1 : m->dim_k;
  m->ti         = 0;
  m->tj         = 0;
  m->tile_ready = false;
  m->word       = 0;
  m->busy       = true;
  m->done       = false;
}

// Computes the current tile from the next K beats of each stream, if they are all in.
bool compute_tile(coproc_model_t *m) {
  if (m->a_q.size() < m->k || m->b_q.size() < m->k) {
    return false;
  }
  const uint32_t d = m->dim;
  m->tile.assign(d * d, 0);
  for (uint32_t s = 0; s < m->k; s++) {
    uint64_t a = m->a_q.front();
    uint64_t b = m->b_q.front();
    m->a_q.pop_front();
    m->b_q.pop_front();
    for (uint32_t r = 0; r < d; r++) {
      for (uint32_t c = 0; c < d; c++) {
        m->tile[r * d + c] = mac(m->tile[r * d + c], lane(a, r), lane(b, c));
      }
    }
  }
  m->tile_ready = true;
  m->word       = 0;
  return true;
}

void next_tile(coproc_model_t *m) {
  m->tile_ready = false;
  if (++m->tj == m->tiles_n) {
    m->tj = 0;
    if (++m->ti == m->tiles_m) {
      m->busy = false;
      m->done = true;
      m->jobs++;
    }
  }
}

}  // namespace

extern "C" {

coproc_model_t *coproc_model_new(uint32_t dim, uint32_t dim_bits) {
  if (dim == 0 || dim * 8 > 64 || dim_bits == 0 || dim_bits > 32) {
    return nullptr;
  }
  coproc_model_t *m = new coproc_model;
  m->dim            = dim;
  m->dim_mask       = dim_bits == 32 ? 0xFFFFFFFFu : ((1u << dim_bits) - 1);
  m->jobs           = 0;
  coproc_model_reset(m);
  return m;
}

void coproc_model_free(coproc_model_t *m) { delete m; }

void coproc_model_reset(coproc_model_t *m) {
  m->dim_m = m->dim_n = m->dim_k = 0;
  m->busy = m->done = false;
  m->tiles_m = m->tiles_n = m->k = 1;
  m->ti = m->tj = 0;
  m->a_q.clear();
  m->b_q.clear();
  m->tile.clear();
  m->tile_ready = false;
  m->word       = 0;
  m->jobs       = 0;
}

uint32_t coproc_model_reg_write(coproc_model_t *m, uint32_t offset, uint32_t data, uint32_t strb) {
  switch (offset & ~3u) {
    case COPROC_REG_CTRL:
      if ((strb & 1u) && (data & COPROC_CTRL_START) && !m->busy) {
        start_job(m);
      }
      return COPROC_RESP_OKAY;
    case COPROC_REG_STATUS:
      if ((strb & 1u) && (data & COPROC_STATUS_DONE)) {
        m->done = false;
      }
      return COPROC_RESP_OKAY;
    case COPROC_REG_DIM_M:
      if (!m->busy) m->dim_m = write_bytes(m->dim_m, data, strb, m->dim_mask);
      return COPROC_RESP_OKAY;
    case COPROC_REG_DIM_N:
      if (!m->busy) m->dim_n = write_bytes(m->dim_n, data, strb, m->dim_mask);
      return COPROC_RESP_OKAY;
    case COPROC_REG_DIM_K:
      if (!m->busy) m->dim_k = write_bytes(m->dim_k, data, strb, m->dim_mask);
      return COPROC_RESP_OKAY;
    default:
      return COPROC_RESP_SLVERR;
  }
}

uint32_t coproc_model_reg_read(coproc_model_t *m, uint32_t offset, uint32_t *data) {
  switch (offset & ~3u) {
    case COPROC_REG_CTRL:   *data = 0; return COPROC_RESP_OKAY;  // START reads 0
    case COPROC_REG_STATUS:
      *data = (m->busy ? COPROC_STATUS_BUSY : 0u) | (m->done ? COPROC_STATUS_DONE : 0u);
      return COPROC_RESP_OKAY;
    case COPROC_REG_DIM_M:  *data = m->dim_m; return COPROC_RESP_OKAY;
    case COPROC_REG_DIM_N:  *data = m->dim_n; return COPROC_RESP_OKAY;
    case COPROC_REG_DIM_K:  *data = m->dim_k; return COPROC_RESP_OKAY;
    default:                *data = 0; return COPROC_RESP_SLVERR;
  }
}

void coproc_model_push_a(coproc_model_t *m, uint64_t beat) { m->a_q.push_back(beat); }
void coproc_model_push_b(coproc_model_t *m, uint64_t beat) { m->b_q.push_back(beat); }

int coproc_model_pop_c(coproc_model_t *m, uint32_t *word) {
  if (!m->busy) {
    return 0;
  }
  if (!m->tile_ready && !compute_tile(m)) {
    return 0;
  }
  *word = m->tile[m->word];
  if (++m->word == m->dim * m->dim) {
    next_tile(m);
  }
  return 1;
}

void coproc_model_c_pos(const coproc_model_t *m, uint32_t *ti, uint32_t *tj, uint32_t *row,
                        uint32_t *col) {
  *ti  = m->ti;
  *tj  = m->tj;
  *row = m->tile_ready ? m->word / m->dim : 0;
  *col = m->tile_ready ? m->word % m->dim : 0;
}

int      coproc_model_busy(const coproc_model_t *m) { return m->busy ? 1 : 0; }
uint32_t coproc_model_pending_a(const coproc_model_t *m) { return m->a_q.size(); }
uint32_t coproc_model_pending_b(const coproc_model_t *m) { return m->b_q.size(); }
uint32_t coproc_model_jobs(const coproc_model_t *m) { return m->jobs; }

// ---- Whole matrices -------------------------------------------------------------------------

void coproc_pack_a(uint32_t dim, uint32_t m, uint32_t k, const int8_t *a, int8_t *a_l2) {
  for (uint32_t row = 0; row < m; row++) {
    for (uint32_t kk = 0; kk < k; kk++) {
      uint32_t i = row / dim, r = row % dim;
      a_l2[dim * k * i + dim * kk + r] = a[row * k + kk];
    }
  }
}

void coproc_pack_b(uint32_t dim, uint32_t k, uint32_t n, const int8_t *b, int8_t *b_l2) {
  for (uint32_t kk = 0; kk < k; kk++) {
    for (uint32_t col = 0; col < n; col++) {
      uint32_t j = col / dim, c = col % dim;
      b_l2[dim * k * j + dim * kk + c] = b[kk * n + col];
    }
  }
}

void coproc_unpack_c(uint32_t dim, uint32_t m, uint32_t n, const int32_t *c_l2, int32_t *c) {
  const uint32_t tn = n / dim;
  for (uint32_t row = 0; row < m; row++) {
    for (uint32_t col = 0; col < n; col++) {
      uint32_t i = row / dim, r = row % dim, j = col / dim, cc = col % dim;
      c[row * n + col] = c_l2[dim * dim * (i * tn + j) + dim * r + cc];
    }
  }
}

void coproc_matmul(uint32_t m, uint32_t n, uint32_t k, const int8_t *a, const int8_t *b,
                   int32_t *c) {
  for (uint32_t r = 0; r < m; r++) {
    for (uint32_t col = 0; col < n; col++) {
      uint32_t acc = 0;
      for (uint32_t kk = 0; kk < k; kk++) {
        acc = mac(acc, a[r * k + kk], b[kk * n + col]);
      }
      c[r * n + col] = static_cast<int32_t>(acc);
    }
  }
}

int coproc_run_l2(uint32_t dim, uint32_t m, uint32_t n, uint32_t k, const int8_t *a_l2,
                  const int8_t *b_l2, int32_t *c_l2) {
  coproc_model_t *mdl = coproc_model_new(dim, 16);
  if (mdl == nullptr || m % dim != 0 || n % dim != 0 || k == 0) {
    coproc_model_free(mdl);
    return -1;
  }
  coproc_model_reg_write(mdl, COPROC_REG_DIM_M, m, 0xF);
  coproc_model_reg_write(mdl, COPROC_REG_DIM_N, n, 0xF);
  coproc_model_reg_write(mdl, COPROC_REG_DIM_K, k, 0xF);
  coproc_model_reg_write(mdl, COPROC_REG_CTRL, COPROC_CTRL_START, 0xF);

  // The DMA's view (sw/README.md): A panel i once per tile column, all of B once per tile row.
  auto beat = [dim](const int8_t *p) {
    uint64_t v = 0;
    for (uint32_t l = 0; l < dim; l++) {
      v |= static_cast<uint64_t>(static_cast<uint8_t>(p[l])) << (8 * l);
    }
    return v;
  };
  const uint32_t tm = m / dim, tn = n / dim;
  uint32_t       w  = 0;
  for (uint32_t i = 0; i < tm; i++) {
    for (uint32_t j = 0; j < tn; j++) {
      for (uint32_t kk = 0; kk < k; kk++) {
        coproc_model_push_a(mdl, beat(a_l2 + dim * k * i + dim * kk));
        coproc_model_push_b(mdl, beat(b_l2 + dim * k * j + dim * kk));
      }
      uint32_t word;
      for (uint32_t e = 0; e < dim * dim; e++) {
        if (!coproc_model_pop_c(mdl, &word)) {
          coproc_model_free(mdl);
          return -1;
        }
        c_l2[w++] = static_cast<int32_t>(word);
      }
    }
  }
  int ok = !coproc_model_busy(mdl);
  coproc_model_free(mdl);
  return ok ? 0 : -1;
}

}  // extern "C"
