`timescale 1ns/1ps
module tb_mac;


//**********************************************************************************
//****************   ESPAÇO PARA INSTANCIAÇÃO DOS MÓDULOS   **************************
//**********************************************************************************


    parameter WIDTH = 8;
    wire [WIDTH -1 : 0] acc;
    reg [WIDTH -1 : 0] a;
    reg [WIDTH -1 : 0] b;
    reg rst;
    reg clk;

mac # (
    .WIDTH(WIDTH)
  )
  mac_inst (
    .acc(acc),
    .a(a),
    .b(b),
    .rst(rst),
    .clk(clk)
  );





//**********************************************************************************
//bloco responsavel por resetar, com resete negado, os modulos
    initial begin
           rst = 0;
           #5 rst = 1;
    end

//bloco responsavel por gerar o sinal de clock
    initial begin
           clk = 0;
           @(posedge rst);
        forever #(5,20) clk = ~ clk;
    end

//bloco responsavel por encerrar a simulação
    initial begin
           #200 $finish;
    end

integer result;
//inicial para a simulação
    initial
        begin
            result = 0;
            a = 3;
            b = 4;
            result = result + a*b;
            @(negedge clk);
            a = 1;
            b = 3;
            result = result + a*b;
            @(negedge clk);
            a = 2;
            b = 5;
            result = result + a*b;
            @(negedge clk);
            a = 6;
            b = 2;
            result = result + a*b;
            @(negedge clk);
            a = 1;
            b = 7;
            result = result + a*b;
            @(negedge clk);
            a = 2;
            b = 2;
            result = result + a*b;
            @(negedge clk);
            if(result == acc)
                begin
                    $display("Valor do resultado correto. acc = %d result=%d",acc,result);
                end
            else
                begin
                    $display("Valor do resultado incorreto. acc = %d result=%d",acc,result);
                end
        end
endmodule