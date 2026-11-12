
`timescale 1ns/1ps

module tb_systolic_array_3x3;


    parameter DATA_WIDTH = 24;
    parameter ACC_WIDTH  = 48;

    reg clk;
    reg rst_n;


    reg signed [23:0] a0;
    reg signed [23:0] a1;
    reg signed [23:0] a2;

    reg signed [23:0] b0;
    reg signed [23:0] b1;
    reg signed [23:0] b2;

    reg valid_a0;
    reg valid_a1;
    reg valid_a2;

    reg valid_b0;
    reg valid_b1;
    reg valid_b2;

    wire signed [47:0] c00;
    wire signed [47:0] c01;
    wire signed [47:0] c02;

    wire signed [47:0] c10;
    wire signed [47:0] c11;
    wire signed [47:0] c12;

    wire signed [47:0] c20;
    wire signed [47:0] c21;
    wire signed [47:0] c22;

    // =========================================
    // VALORES DAS MATRIZES
    // =========================================

    integer A1, A2, A3;
    integer A4, A5, A6;
    integer A7, A8, A9;

    integer B1, B2, B3;
    integer B4, B5, B6;
    integer B7, B8, B9;

    // =========================================
    // RESULTADOS ESPERADOS
    // =========================================

    integer expected00, expected01, expected02;
    integer expected10, expected11, expected12;
    integer expected20, expected21, expected22;

    integer erros;

 

    systolic_array_3x3 #(
        .DATA_WIDTH(DATA_WIDTH),
        .ACC_WIDTH(ACC_WIDTH)
    ) DUT (

        .clk(clk),
        .rst_n(rst_n),
        .a0(a0),
        .a1(a1),
        .a2(a2),
        .valid_a0(valid_a0),
        .valid_a1(valid_a1),
        .valid_a2(valid_a2),
        .b0(b0),
        .b1(b1),
        .b2(b2),
        .valid_b0(valid_b0),
        .valid_b1(valid_b1),
        .valid_b2(valid_b2),
        .c00(c00),
        .c01(c01),
        .c02(c02),
        .c10(c10),
        .c11(c11),
        .c12(c12),
        .c20(c20),
        .c21(c21),
        .c22(c22)

    );


    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end


    initial begin

        erros = 0;

        rst_n = 0;
    

        a0 = 0;
        a1 = 0;
        a2 = 0;

        b0 = 0;
        b1 = 0;
        b2 = 0;

        valid_a0 = 0;
        valid_a1 = 0;
        valid_a2 = 0;

        valid_b0 = 0;
        valid_b1 = 0;
        valid_b2 = 0;

        // =====================================
        // DEFINICAO DOS 18 VALORES
        // =====================================

        A1 =  1;
        A2 = -2;
        A3 =  3;

        A4 =  4;
        A5 = -5;
        A6 =  6;

        A7 = -7;
        A8 =  8;
        A9 =  9;

        B1 = -9;
        B2 =  8;
        B3 =  7;

        B4 =  6;
        B5 = -5;
        B6 =  4;

        B7 =  3;
        B8 =  2;
        B9 = -1;


        expected00 = A1*B1 + A2*B4 + A3*B7;
        expected01 = A1*B2 + A2*B5 + A3*B8;
        expected02 = A1*B3 + A2*B6 + A3*B9;

        expected10 = A4*B1 + A5*B4 + A6*B7;
        expected11 = A4*B2 + A5*B5 + A6*B8;
        expected12 = A4*B3 + A5*B6 + A6*B9;

        expected20 = A7*B1 + A8*B4 + A9*B7;
        expected21 = A7*B2 + A8*B5 + A9*B8;
        expected22 = A7*B3 + A8*B6 + A9*B9;

        // =====================================
        // CONVERSAO PARA Q9.15
        // =====================================

        // Multiplica cada valor por 2^15

        // =====================================
        // RESET
        // =====================================

        #20;

        @(negedge clk);

        rst_n = 1;
      

        @(negedge clk);


        // =====================================
        // CICLO 0
        // =====================================

        a0 = A1 * 32768;
        b0 = B1 * 32768;

        valid_a0 = 1;
        valid_b0 = 1;

        @(negedge clk);

        // =====================================
        // CICLO 1
        // =====================================

        a0 = A2 * 32768;
        a1 = A4 * 32768;

        b0 = B4 * 32768;
        b1 = B2 * 32768;

        valid_a0 = 1;
        valid_a1 = 1;

        valid_b0 = 1;
        valid_b1 = 1;

        @(negedge clk);

        // =====================================
        // CICLO 2
        // =====================================

        a0 = A3 * 32768;
        a1 = A5 * 32768;
        a2 = A7 * 32768;

        b0 = B7 * 32768;
        b1 = B5 * 32768;
        b2 = B3 * 32768;

        valid_a0 = 1;
        valid_a1 = 1;
        valid_a2 = 1;

        valid_b0 = 1;
        valid_b1 = 1;
        valid_b2 = 1;

        @(negedge clk);

        // =====================================
        // CICLO 3
        // =====================================

        a0 = 0;
        a1 = A6 * 32768;
        a2 = A8 * 32768;

        b0 = 0;
        b1 = B8 * 32768;
        b2 = B6 * 32768;

        valid_a0 = 0;
        valid_a1 = 1;
        valid_a2 = 1;

        valid_b0 = 0;
        valid_b1 = 1;
        valid_b2 = 1;

        @(negedge clk);

        // =====================================
        // CICLO 4
        // =====================================

        a0 = 0;
        a1 = 0;
        a2 = A9 * 32768;

        b0 = 0;
        b1 = 0;
        b2 = B9 * 32768;

        valid_a0 = 0;
        valid_a1 = 0;
        valid_a2 = 1;

        valid_b0 = 0;
        valid_b1 = 0;
        valid_b2 = 1;

        @(negedge clk);

        // =====================================
        // CICLO 5
        // =====================================

        a0 = 0;
        a1 = 0;
        a2 = 0;

        b0 = 0;
        b1 = 0;
        b2 = 0;

        valid_a0 = 0;
        valid_a1 = 0;
        valid_a2 = 0;

        valid_b0 = 0;
        valid_b1 = 0;
        valid_b2 = 0;

        @(negedge clk);

        // =====================================
        // CICLO 6 - FINAL DO PIPELINE
        // =====================================

        @(posedge clk);
        #1;

        // =====================================
        // EXIBICAO DOS RESULTADOS
        // =====================================

        $display("");
        $display("========================================");
        $display("         RESULTADO DO SYSTOLIC");
        $display("========================================");

        $display("MATRIZ A:");
        $display("%0d %0d %0d", A1, A2, A3);
        $display("%0d %0d %0d", A4, A5, A6);
        $display("%0d %0d %0d", A7, A8, A9);

        $display("");

        $display("MATRIZ B:");
        $display("%0d %0d %0d", B1, B2, B3);
        $display("%0d %0d %0d", B4, B5, B6);
        $display("%0d %0d %0d", B7, B8, B9);

        $display("");

        $display("RESULTADOS ESPERADOS:");
        $display("%0d %0d %0d",
                 expected00, expected01, expected02);

        $display("%0d %0d %0d",
                 expected10, expected11, expected12);

        $display("%0d %0d %0d",
                 expected20, expected21, expected22);

        $display("");

        // =====================================
        // RESULTADOS DO HARDWARE
        // Q18.30 -> INTEIRO
        // =====================================

        $display("RESULTADOS OBTIDOS:");

        $display("%0d %0d %0d",
                 c00 >>> 30, c01 >>> 30, c02 >>> 30);

        $display("%0d %0d %0d",
                 c10 >>> 30, c11 >>> 30, c12 >>> 30);

        $display("%0d %0d %0d",
                 c20 >>> 30, c21 >>> 30, c22 >>> 30);

        $display("");

        // =====================================
        // COMPARACAO AUTOMATICA
        // =====================================

        if ((c00 >>> 30) !== expected00) begin
            $display("ERRO C00");
            erros = erros + 1;
        end

        if ((c01 >>> 30) !== expected01) begin
            $display("ERRO C01");
            erros = erros + 1;
        end

        if ((c02 >>> 30) !== expected02) begin
            $display("ERRO C02");
            erros = erros + 1;
        end

        if ((c10 >>> 30) !== expected10) begin
            $display("ERRO C10");
            erros = erros + 1;
        end

        if ((c11 >>> 30) !== expected11) begin
            $display("ERRO C11");
            erros = erros + 1;
        end

        if ((c12 >>> 30) !== expected12) begin
            $display("ERRO C12");
            erros = erros + 1;
        end

        if ((c20 >>> 30) !== expected20) begin
            $display("ERRO C20");
            erros = erros + 1;
        end

        if ((c21 >>> 30) !== expected21) begin
            $display("ERRO C21");
            erros = erros + 1;
        end

        if ((c22 >>> 30) !== expected22) begin
            $display("ERRO C22");
            erros = erros + 1;
        end

        // =====================================
        // RESULTADO FINAL
        // =====================================

        $display("");
        $display("========================================");

        if (erros == 0) begin
            $display("TESTE PASSOU!");
            $display("Todos os nove resultados estao corretos.");
        end

        else begin
            $display("TESTE FALHOU!");
            $display("Quantidade de erros: %0d", erros);
        end

        $display("========================================");

        $finish;

    end

endmodule
