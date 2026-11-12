// Coprocessor package: the datapath types and the array geometry shared by the coproc_ modules.
package coproc_pkg;

  parameter int unsigned DATA_W    = 8;   // element of A and B, signed
  parameter int unsigned ACC_W     = 32;  // accumulator and element of C, signed
  parameter int unsigned ARRAY_DIM = 8;   // processing elements per side of the square array

  // Both are signed: the products and the accumulation are signed arithmetic, and the result
  // wraps around on overflow (no saturation).
  typedef logic signed [DATA_W-1:0] data_t;
  typedef logic signed [ACC_W-1:0]  acc_t;

endpackage
