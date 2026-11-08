module systolic_arrayB #(parameter WIDTH = 8, SQUAREDIMENSION = 2)  ( 
    output               busy,
    output               redy_out,
   /* output [WIDTH -1 : 0],
    output [WIDTH -1 : 0],
    output [WIDTH -1 : 0],
    output [WIDTH -1 : 0],
    output [WIDTH -1 : 0],*/
    input signed [WIDTH -1 : 0]a,
    input signed [WIDTH -1 : 0]b,
    input               rst,
    input               clk,
    input               start/*,
    input [WIDTH -1 : 0],
    input [WIDTH -1 : 0]*/
    );
    parameter WIDTH_COUNTER = $clog2(WIDTH);
    parameter DEPTH = SQUAREDIMENSION;
    parameter WIDTH_SEL = $clog2(DEPTH); 

    wire signed [WIDTH -1 : 0] acc [0 : SQUAREDIMENSION - 1][0 : SQUAREDIMENSION - 1];
    wire signed [WIDTH -1 : 0] ao  [0 : SQUAREDIMENSION - 1][0 : SQUAREDIMENSION - 1];
    wire signed [WIDTH -1 : 0] bo  [0 : SQUAREDIMENSION - 1][0 : SQUAREDIMENSION - 1];

    wire [(DEPTH*WIDTH) -1 : 0] outA;
    wire [(DEPTH*WIDTH) -1 : 0] outB;
    wire [WIDTH_SEL -1 : 0] selA;
    wire [WIDTH_SEL -1 : 0] selB;



    DEMUX_systolic # (
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
     )
        DEMUX_A (
        .out(outA),
        .sel(selA),
        .in(a)
    );

    DEMUX_systolic # (
        .WIDTH(WIDTH),
        .DEPTH(DEPTH)
    )
    DEMUX_B (
        .out(outB),
        .sel(selB),
        .in(b)
    );

   
    MACB # (
                .WIDTH(WIDTH)
            )
                MACB_inst1 (
                .acc(acc[0][0]),
                .ao(ao[0][0]),
                .bo(bo[0][0]),
                .a(outA[WIDTH-1:0]),
                .b(outB[WIDTH-1:0]),
                .clk(clk),
                .rst(rst)
            );


    genvar line,colum;

    generate

    for (line= 0; line < SQUAREDIMENSION; line = line + 1) begin : mac_line
        for (colum= 0; colum < SQUAREDIMENSION; colum = colum + 1) begin : mac_colum
            if (line != 0 && colum != 0) begin
                MACB # (
                    .WIDTH(WIDTH)
                )
                    MACB_inst (
                    .acc(acc[line][colum]),
                    .ao(ao[line][colum]),
                    .bo(bo[line][colum]),
                    .a(ao[line][colum -1]),
                    .b(bo[line - 1][colum]),
                    .clk(clk),
                    .rst(rst)
                );
            end else begin
                if (line == 0 && colum !=0) begin
                    MACB # (
                    .WIDTH(WIDTH)
                     )
                    MACB_inst (
                    .acc(acc[line][colum]),
                    .ao(ao[line][colum]),
                    .bo(bo[line][colum]),
                    .a(ao[line][colum -1]),
                    .b(outB[(WIDTH * (colum + 1)) - 1: (WIDTH * colum)]),
                    .clk(clk),
                    .rst(rst)
                     );
                end else begin
                    if (line != 0 && colum ==0) begin
                        MACB # (
                    .WIDTH(WIDTH)
                    )
                    MACB_inst (
                    .acc(acc[line][colum]),
                    .ao(ao[line][colum]),
                    .bo(bo[line][colum]),
                    .a(outA[(WIDTH * (line + 1)) - 1: (WIDTH * line)]),
                    .b(bo[line - 1][colum]),
                    .clk(clk),
                    .rst(rst)
                    );
                    end
                end
            end

        end
    end

    endgenerate
/* 
    always @(*)
        begin
            
        end

    always @(posedge)
        begin
            
        end

    always @(posedge clk)
        begin
            
        end

    always @(posedge clk, negedge rst)
        begin
            if(!rst)
            begin
                
            end
            else
            begin
                
            end
        end

    always @(posedge clk)
        begin
            ir(!rst)
            begin
                
            end
            else
            begin
                
            end
        end */
endmodule