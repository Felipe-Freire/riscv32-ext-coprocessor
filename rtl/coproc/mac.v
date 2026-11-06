module mac #(parameter WIDTH = 8)  ( 
    output reg signed [2*WIDTH -1 : 0]acc,
    input signed [WIDTH -1 : 0]a,
    input signed [WIDTH -1 : 0]b,
    input               rst ,
    input 		        clk
    );
	
    always @(posedge clk, negedge rst)
        begin
            if(!rst)
            begin
                acc <= 0;
            end
            else
            begin
                acc <= acc + a * b;
            end
     end
endmodule