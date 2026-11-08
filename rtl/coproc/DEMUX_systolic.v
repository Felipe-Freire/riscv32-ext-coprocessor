module DEMUX_systolic #(parameter WIDTH = 8,DEPTH = 2,WIDTH_SEL = $clog2(DEPTH) )  ( 
    output [(DEPTH*WIDTH) -1 : 0] out,
    input [WIDTH_SEL -1 : 0] sel,
    input [WIDTH -1 : 0] in
    );


    genvar outmux;

    generate

    for (outmux= 0; outmux < DEPTH; outmux = outmux + 1) begin : apelido_bloco
        assign out[(WIDTH * (outmux + 1)) - 1: (WIDTH* outmux)] = sel == outmux? in : 0 ;
    end

    endgenerate
endmodule