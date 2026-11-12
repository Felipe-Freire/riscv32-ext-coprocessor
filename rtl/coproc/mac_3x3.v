module mac_3x3 #(parameter DATA_WIDTH = 24,parameter ACC_WIDTH  = 48)
(
    output reg signed [DATA_WIDTH-1:0] a_out,
    output reg signed [DATA_WIDTH-1:0] b_out,
    output reg valid_a_out,
    output reg valid_b_out,
    output reg signed [ACC_WIDTH-1:0] acc,
    input wire clk,
    input wire rst_n,
    input wire signed [DATA_WIDTH-1:0] a_in,
    input wire signed [DATA_WIDTH-1:0] b_in,
    input wire valid_a_in,
    input wire valid_b_in
);

    wire signed [(2*DATA_WIDTH)-1:0] produto;

    assign produto = a_in * b_in;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            a_out       <= 0;
            b_out       <= 0;
            valid_a_out <= 0;
            valid_b_out <= 0;
            acc         <= 0;
        end
        else 
        begin
            a_out <= a_in;
            b_out <= b_in;

            valid_a_out <= valid_a_in;
            valid_b_out <= valid_b_in;

            if (valid_a_in && valid_b_in)
            begin
                acc <= acc + produto;
            end
        end
    end

endmodule
