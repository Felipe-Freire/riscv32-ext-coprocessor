module MACB #(parameter WIDTH = 8)  ( 
    output reg signed [WIDTH -1 : 0]acc,
    output reg signed [WIDTH -1 : 0]ao,
    output reg signed [WIDTH -1 : 0]bo,
    input signed [WIDTH -1 : 0]a,
    input signed [WIDTH -1 : 0]b,
    input clk,
    input rst
    );
parameter WIDTH_COUNTER = $clog2(WIDTH);

    always @(posedge clk or negedge rst)
        begin
            if(~rst)
            begin
                acc <= 0;
                ao <= 0;
                bo <= 0;
            end
            else
            begin
                acc <= acc + a * b;
                ao <= a;
                bo <= b;
            end
        end

endmodule