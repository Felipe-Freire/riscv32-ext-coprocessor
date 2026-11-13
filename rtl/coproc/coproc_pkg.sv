// Coprocessor package: the datapath types and the array geometry shared by the coproc_ modules.
package coproc_pkg;

  parameter int unsigned DATA_W    = 8;   // element of A and B, signed
  parameter int unsigned ACC_W     = 32;  // accumulator and element of C, signed
  parameter int unsigned ARRAY_DIM = 8;   // processing elements per side of the square array
  parameter int unsigned DIM_CNT_W = 16;  // width of the M, N and K dimension registers

  // Both are signed: the products and the accumulation are signed arithmetic, and the result
  // wraps around on overflow (no saturation).
  typedef logic signed [DATA_W-1:0] data_t;
  typedef logic signed [ACC_W-1:0]  acc_t;

  // A matrix dimension (M, N or K) as software programs it. Unsigned: a dimension is a count.
  typedef logic [DIM_CNT_W-1:0] dim_t;

endpackage
