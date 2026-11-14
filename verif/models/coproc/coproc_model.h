// Golden model of the matrix coprocessor (coproc_top): untimed and transaction level.
//
// The model follows rtl/coproc/README.md, not the RTL. It has the same three ports as the block:
//
//   registers   coproc_model_reg_write / _reg_read: the AXI4-Lite map (CTRL, STATUS, DIM_M/N/K)
//   A, B        coproc_model_push_a / _push_b: one stream beat each, in the order the DMA sends
//   C           coproc_model_pop_c: the next expected 32-bit word of the C stream
//
// A job starts on an accepted START and ends when its last C word has been popped. There is no
// time: BUSY and DONE follow the job as the model sees it, and a caller that compares them with
// hardware has to allow for the clock-domain crossing (see the UVM scoreboard). A and B beats are
// queued even while no job runs, as the stream FIFOs of the block do.
//
// Users: the UVM scoreboard of verif/uvm/coproc (through DPI-C), and the SoC-level model, which
// can drive the same API from the DMA's view or use the whole-matrix helpers at the end of this
// file on L2 buffers.
//
// Arithmetic: int8 x int8 products summed in int32 with wrap-around, no saturation.
// Dimensions outside the spec (M or N not a multiple of the array side, K = 0) follow the current
// RTL: M/Dim and N/Dim tiles rounded down, 0 tiles counted as 1, K = 0 run as 1 (verification
// plan, point P1).
#ifndef COPROC_MODEL_H
#define COPROC_MODEL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// AXI responses returned by the register port.
#define COPROC_RESP_OKAY   0u
#define COPROC_RESP_SLVERR 2u

// Register offsets and fields.
#define COPROC_REG_CTRL    0x00u
#define COPROC_REG_STATUS  0x04u
#define COPROC_REG_DIM_M   0x08u
#define COPROC_REG_DIM_N   0x0Cu
#define COPROC_REG_DIM_K   0x10u
#define COPROC_CTRL_START  (1u << 0)
#define COPROC_STATUS_BUSY (1u << 0)
#define COPROC_STATUS_DONE (1u << 1)

typedef struct coproc_model coproc_model_t;

// dim: array side (8); dim_bits: width of the DIM_* registers (16). dim * 8 must fit in 64 bits.
coproc_model_t *coproc_model_new(uint32_t dim, uint32_t dim_bits);
void            coproc_model_free(coproc_model_t *m);
// Reset: registers to 0, no job, stream queues empty.
void            coproc_model_reset(coproc_model_t *m);

// Register port. offset is the byte offset in the block's window; the two low bits are ignored.
// Returns COPROC_RESP_OKAY or COPROC_RESP_SLVERR (offset outside the map).
uint32_t coproc_model_reg_write(coproc_model_t *m, uint32_t offset, uint32_t data, uint32_t strb);
uint32_t coproc_model_reg_read(coproc_model_t *m, uint32_t offset, uint32_t *data);

// Streams. Lane l of an A beat (bits 8l+7:8l) is A[Dim*ti+l][k]; lane l of a B beat is
// B[k][Dim*tj+l].
void coproc_model_push_a(coproc_model_t *m, uint64_t beat);
void coproc_model_push_b(coproc_model_t *m, uint64_t beat);

// Next expected word of the C stream: returns 1 and the word, or 0 when the model has none (no
// job, or the A and B beats of the current tile have not all arrived). The words come in stream
// order: tiles in row-major tile order, each tile row-major, lowest column first.
int  coproc_model_pop_c(coproc_model_t *m, uint32_t *word);
// Position in C of the word the next coproc_model_pop_c returns: tile row and column, row and
// column inside the tile. For error messages.
void coproc_model_c_pos(const coproc_model_t *m, uint32_t *ti, uint32_t *tj, uint32_t *row,
                        uint32_t *col);

// State.
int      coproc_model_busy(const coproc_model_t *m);       // a job is running
uint32_t coproc_model_pending_a(const coproc_model_t *m);  // A beats queued, not yet used
uint32_t coproc_model_pending_b(const coproc_model_t *m);
uint32_t coproc_model_jobs(const coproc_model_t *m);       // jobs completed since reset

// ---- Whole matrices ---------------------------------------------------------------------------
// Row-major matrices <-> the L2 buffer layouts of rtl/coproc/README.md (dim = array side).
void coproc_pack_a(uint32_t dim, uint32_t m, uint32_t k, const int8_t *a, int8_t *a_l2);
void coproc_pack_b(uint32_t dim, uint32_t k, uint32_t n, const int8_t *b, int8_t *b_l2);
void coproc_unpack_c(uint32_t dim, uint32_t m, uint32_t n, const int32_t *c_l2, int32_t *c);

// C = A·B on row-major matrices, int32 with wrap-around.
void coproc_matmul(uint32_t m, uint32_t n, uint32_t k, const int8_t *a, const int8_t *b,
                   int32_t *c);

// One job on L2 buffers, through a fresh model and the same streams the DMA sends (A panels
// repeated per tile column, B repeated per tile row). Returns 0 on success.
int coproc_run_l2(uint32_t dim, uint32_t m, uint32_t n, uint32_t k, const int8_t *a_l2,
                  const int8_t *b_l2, int32_t *c_l2);

#ifdef __cplusplus
}
#endif

#endif  // COPROC_MODEL_H
