// Simulation models of the Genus tutorial library cells (tutorial.lib), for gate-level simulation
// of a netlist synthesized without the PDK (`make gls` with LIBS empty).
//
// The functions follow the Liberty file: R and S are active-low clear and preset (clear wins), the
// latches are transparent while ENA is high, and ivt1 drives Y only while E is high. The specify
// blocks hold the library's timing arcs with zero delay, with the edges Genus writes in its SDF
// (SETUPHOLD per data edge, RECREM), so that SDF fills them in (SDF=1); without SDF, `make gls`
// ignores them and the netlist runs with zero delay.
`timescale 1ns / 1ps

`celldefine
module nand2 (input A, input B, output Y);
  assign Y = ~(A & B);
  specify
    (A => Y) = 0;
    (B => Y) = 0;
  endspecify
endmodule
`endcelldefine

`celldefine
module nor2 (input A, input B, output Y);
  assign Y = ~(A | B);
  specify
    (A => Y) = 0;
    (B => Y) = 0;
  endspecify
endmodule
`endcelldefine

`celldefine
module xor2 (input A, input B, output Y);
  assign Y = A ^ B;
  specify
    (A => Y) = 0;
    (B => Y) = 0;
  endspecify
endmodule
`endcelldefine

`celldefine
module inv1 (input A, output Y);
  assign Y = ~A;
  specify
    (A => Y) = 0;
  endspecify
endmodule
`endcelldefine

`celldefine
module buf1 (input A, output Y);
  assign Y = A;
  specify
    (A => Y) = 0;
  endspecify
endmodule
`endcelldefine

`celldefine
module ivt1 (input A, input E, output Y);
  assign Y = E ? ~A : 1'bz;
  specify
    (A => Y) = 0;
    (E => Y) = 0;
  endspecify
endmodule
`endcelldefine

// Flip-flops: a timing violation (notifier) makes Q unknown.

`celldefine
module fflopd (input D, input CK, output reg Q);
  reg notifier;
  always @(posedge CK) Q <= D;
  always @(notifier) Q <= 1'bx;
  specify
    (posedge CK => (Q +: D)) = 0;
    $setuphold(posedge CK, posedge D, 0, 0, notifier);
    $setuphold(posedge CK, negedge D, 0, 0, notifier);
  endspecify
endmodule
`endcelldefine

`celldefine
module fflopd_ckn (input D, input CKN, output reg Q);
  reg notifier;
  always @(negedge CKN) Q <= D;
  always @(notifier) Q <= 1'bx;
  specify
    (negedge CKN => (Q +: D)) = 0;
    $setuphold(negedge CKN, posedge D, 0, 0, notifier);
    $setuphold(negedge CKN, negedge D, 0, 0, notifier);
  endspecify
endmodule
`endcelldefine

`celldefine
module flopdrs (input D, input CK, input R, input S, output reg Q);
  reg notifier;
  always @(posedge CK or negedge R or negedge S) begin
    if (!R)      Q <= 1'b0;
    else if (!S) Q <= 1'b1;
    else         Q <= D;
  end
  always @(notifier) Q <= 1'bx;
  specify
    (posedge CK => (Q +: D)) = 0;
    (R => Q) = 0;
    (S => Q) = 0;
    $setuphold(posedge CK, posedge D, 0, 0, notifier);
    $setuphold(posedge CK, negedge D, 0, 0, notifier);
    $recrem(posedge R, posedge CK, 0, 0, notifier);
    $recrem(posedge S, posedge CK, 0, 0, notifier);
  endspecify
endmodule
`endcelldefine

`celldefine
module flopdrs_ckn (input D, input CKN, input R, input S, output reg Q);
  reg notifier;
  always @(negedge CKN or negedge R or negedge S) begin
    if (!R)      Q <= 1'b0;
    else if (!S) Q <= 1'b1;
    else         Q <= D;
  end
  always @(notifier) Q <= 1'bx;
  specify
    (negedge CKN => (Q +: D)) = 0;
    (R => Q) = 0;
    (S => Q) = 0;
    $setuphold(negedge CKN, posedge D, 0, 0, notifier);
    $setuphold(negedge CKN, negedge D, 0, 0, notifier);
    $recrem(posedge R, negedge CKN, 0, 0, notifier);
    $recrem(posedge S, negedge CKN, 0, 0, notifier);
  endspecify
endmodule
`endcelldefine

// Latches: transparent while ENA is high.

`celldefine
module latchd (input D, input ENA, output reg Q);
  reg notifier;
  always @(D or ENA) if (ENA) Q <= D;
  always @(notifier) Q <= 1'bx;
  specify
    (D => Q) = 0;
    (posedge ENA => (Q +: D)) = 0;
    $setuphold(negedge ENA, posedge D, 0, 0, notifier);
    $setuphold(negedge ENA, negedge D, 0, 0, notifier);
  endspecify
endmodule
`endcelldefine

`celldefine
module latchdrs (input D, input ENA, input R, input S, output reg Q);
  reg notifier;
  always @(D or ENA or R or S) begin
    if (!R)      Q <= 1'b0;
    else if (!S) Q <= 1'b1;
    else if (ENA) Q <= D;
  end
  always @(notifier) Q <= 1'bx;
  specify
    (D => Q) = 0;
    (posedge ENA => (Q +: D)) = 0;
    (R => Q) = 0;
    (S => Q) = 0;
    $setuphold(negedge ENA, posedge D, 0, 0, notifier);
    $setuphold(negedge ENA, negedge D, 0, 0, notifier);
    $recrem(posedge R, negedge ENA, 0, 0, notifier);
    $recrem(posedge S, negedge ENA, 0, 0, notifier);
  endspecify
endmodule
`endcelldefine
