module systolic_array_3x3 #(parameter DATA_WIDTH = 24,parameter ACC_WIDTH  = 48)
(
    output wire signed [ACC_WIDTH-1:0] c00,
    output wire signed [ACC_WIDTH-1:0] c01,
    output wire signed [ACC_WIDTH-1:0] c02,
    output wire signed [ACC_WIDTH-1:0] c10,
    output wire signed [ACC_WIDTH-1:0] c11,
    output wire signed [ACC_WIDTH-1:0] c12,
    output wire signed [ACC_WIDTH-1:0] c20,
    output wire signed [ACC_WIDTH-1:0] c21,
    output wire signed [ACC_WIDTH-1:0] c22,
    input wire signed [DATA_WIDTH-1:0] a0,
    input wire signed [DATA_WIDTH-1:0] a1,
    input wire signed [DATA_WIDTH-1:0] a2,
    input wire signed [DATA_WIDTH-1:0] b0,
    input wire signed [DATA_WIDTH-1:0] b1,
    input wire signed [DATA_WIDTH-1:0] b2,
    input wire valid_b0,
    input wire valid_b1,
    input wire valid_b2,
    input wire valid_a0,
    input wire valid_a1,
    input wire valid_a2,
    input wire clk,
    input wire rst_n
);

    //ESSE SYSTOLIC ARRAY FUNCIONA EM PONTO FIXO Q9.15
    // POR ISSO A LARGURA DOS DADOS ESTÁ EM DATA_WIDTH=24

    wire signed [DATA_WIDTH-1:0] a00_out;
    wire signed [DATA_WIDTH-1:0] a01_out;

    wire signed [DATA_WIDTH-1:0] a10_out;
    wire signed [DATA_WIDTH-1:0] a11_out;

    wire signed [DATA_WIDTH-1:0] a20_out;
    wire signed [DATA_WIDTH-1:0] a21_out;


    wire signed [DATA_WIDTH-1:0] b00_out;
    wire signed [DATA_WIDTH-1:0] b10_out;

    wire signed [DATA_WIDTH-1:0] b01_out;
    wire signed [DATA_WIDTH-1:0] b11_out;

    wire signed [DATA_WIDTH-1:0] b02_out;
    wire signed [DATA_WIDTH-1:0] b12_out;

    // --------------------------------
    // Interconexoes de validacao de A
    // --------------------------------

    wire va00, va01;
    wire va10, va11;
    wire va20, va21;

    // --------------------------------
    // Interconexoes de validacao de B
    // --------------------------------

    wire vb00, vb10;
    wire vb01, vb11;
    wire vb02, vb12;

    // ================================================
    // LINHA 0
    // ================================================

    mac_3x3 #(
        DATA_WIDTH, ACC_WIDTH
    ) PE00 (
        .clk(clk), .rst_n(rst_n), 
        .a_in(a0), .b_in(b0),
        .valid_a_in(valid_a0), .valid_b_in(valid_b0),
        .a_out(a00_out), .b_out(b00_out),
        .valid_a_out(va00), .valid_b_out(vb00),
        .acc(c00)
    );

    mac_3x3 #(
        DATA_WIDTH, ACC_WIDTH
    ) PE01 (
        .clk(clk), .rst_n(rst_n), 
        .a_in(a00_out), .b_in(b1),
        .valid_a_in(va00), .valid_b_in(valid_b1),
        .a_out(a01_out), .b_out(b01_out),
        .valid_a_out(va01), .valid_b_out(vb01),
        .acc(c01)
    );

    mac_3x3 #(
        DATA_WIDTH, ACC_WIDTH
    ) PE02 (
        .clk(clk), .rst_n(rst_n),
        .a_in(a01_out), .b_in(b2),
        .valid_a_in(va01), .valid_b_in(valid_b2),
        .a_out(), .b_out(b02_out),
        .valid_a_out(), .valid_b_out(vb02),
        .acc(c02)
    );

    // ================================================
    // LINHA 1
    // ================================================

    mac_3x3 #(
        DATA_WIDTH, ACC_WIDTH
    ) PE10 (
        .clk(clk), .rst_n(rst_n),
        .a_in(a1), .b_in(b00_out),
        .valid_a_in(valid_a1), .valid_b_in(vb00),
        .a_out(a10_out), .b_out(b10_out),
        .valid_a_out(va10), .valid_b_out(vb10),
        .acc(c10)
    );

    mac_3x3 #(
        DATA_WIDTH, ACC_WIDTH
    ) PE11 (
        .clk(clk), .rst_n(rst_n), 
        .a_in(a10_out), .b_in(b01_out),
        .valid_a_in(va10), .valid_b_in(vb01),
        .a_out(a11_out), .b_out(b11_out),
        .valid_a_out(va11), .valid_b_out(vb11),
        .acc(c11)
    );

    mac_3x3 #(
        DATA_WIDTH, ACC_WIDTH
    ) PE12 (
        .clk(clk), .rst_n(rst_n), 
        .a_in(a11_out), .b_in(b02_out),
        .valid_a_in(va11), .valid_b_in(vb02),
        .a_out(), .b_out(b12_out),
        .valid_a_out(), .valid_b_out(vb12),
        .acc(c12)
    );

    // ================================================
    // LINHA 2
    // ================================================

    mac_3x3 #(
        DATA_WIDTH, ACC_WIDTH
    ) PE20 (
        .clk(clk), .rst_n(rst_n), 
        .a_in(a2), .b_in(b10_out),
        .valid_a_in(valid_a2), .valid_b_in(vb10),
        .a_out(a20_out), .b_out(),
        .valid_a_out(va20), .valid_b_out(),
        .acc(c20)
    );

    mac_3x3 #(
        DATA_WIDTH, ACC_WIDTH
    ) PE21 (
        .clk(clk), .rst_n(rst_n), 
        .a_in(a20_out), .b_in(b11_out),
        .valid_a_in(va20), .valid_b_in(vb11),
        .a_out(a21_out), .b_out(),
        .valid_a_out(va21), .valid_b_out(),
        .acc(c21)
    );

    mac_3x3 #(
        DATA_WIDTH, ACC_WIDTH
    ) PE22 (
        .clk(clk), .rst_n(rst_n), 
        .a_in(a21_out), .b_in(b12_out),
        .valid_a_in(va21), .valid_b_in(vb12),
        .a_out(), .b_out(),
        .valid_a_out(), .valid_b_out(),
        .acc(c22)
    );

endmodule
