module systolic_array #(parameter WIDTH = 8, SQUAREDIMENSION = 2)  ( 
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
    parameter WIDTH_COUNTER = $clog2(SQUAREDIMENSION);
    parameter MAX_MAC = SQUAREDIMENSION * SQUAREDIMENSION;

    reg signed [WIDTH - 1:0] an [0 : SQUAREDIMENSION - 1][0 : SQUAREDIMENSION - 1];
    reg signed [WIDTH - 1:0] bn [0 : SQUAREDIMENSION - 1][0 : SQUAREDIMENSION - 1];
    reg [SQUAREDIMENSION - 1 : 0] counter;
    reg [SQUAREDIMENSION : 0] counter_out;

    wire signed [WIDTH -1 : 0] acc [0 : SQUAREDIMENSION - 1][0 : SQUAREDIMENSION - 1];
   /*  reg signed [WIDTH -1 : 0] am [0 : SQUAREDIMENSION - 1][0 : SQUAREDIMENSION - 1];
    reg signed [WIDTH -1 : 0] bm [0 : SQUAREDIMENSION - 1][0 : SQUAREDIMENSION - 1];
 */

    

    genvar mac_line,mac_col;

    generate

    for (mac_line= 0; mac_line < SQUAREDIMENSION; mac_line = mac_line + 1) begin : macs_line
        for (mac_col= 0; mac_col < SQUAREDIMENSION; mac_col = mac_col + 1) begin : macs_col
                mac # (
                    .WIDTH(WIDTH)
                )
                mac_inst (
                    .acc(acc[mac_line][mac_col]),
                    .a(an[mac_line][mac_col]),
                    .b(bn[mac_line][mac_col]),
                    .rst(rst),
                    .clk(clk)
                );
         end
    end

    endgenerate



    genvar generate_line,generate_colum;

    generate

    for (generate_colum = 0; generate_colum < SQUAREDIMENSION; generate_colum = generate_colum + 1) begin : coluna
         for (generate_line = 0; generate_line < SQUAREDIMENSION; generate_line = generate_line + 1) begin : line
            
            if(generate_colum !=0)
            begin
                always @(posedge clk, negedge rst) begin
                    if(!rst)
                        begin
                            am[generate_line][generate_colum] <= 0;
                            an[generate_line][generate_colum] <= 0;
                            // am[generate_line] <= 0;
                            // an[generate_line] <= 0;
                            //  bm[/* generate_colum + */ generate_line /* * (SQUAREDIMENSION - 1) */] <= 0;
                            //  bn[/* generate_colum + */ generate_line /* * (SQUAREDIMENSION - 1) */] [generate_colum]<= 0;
                        end
                    else
                        begin
                            am[generate_line][generate_colum] <= an[generate_line ][generate_colum ];
                            an[generate_line][generate_colum] <= an[generate_line ][generate_colum -1];
                            //am[generate_line] <= an[generate_line];
                            //an[generate_line] <= an[generate_line -1];
                            //bm[generate_colum + generate_line * (SQUAREDIMENSION - 1)] <= bn[generate_colum + generate_line * (SQUAREDIMENSION - 1)];
                            //bm[generate_colum + generate_line * (SQUAREDIMENSION - 1)] <=  bn[/* generate_colum + */ generate_line /* * (SQUAREDIMENSION - 1) */] [generate_colum];
                            //bn[/* generate_colum + */ generate_line /* * (SQUAREDIMENSION - 1) */] [generate_colum]<= bn[/* generate_colum + */ generate_line /* * (SQUAREDIMENSION - 1) */ -1][generate_colum];
                        end
                end
            end  

            if(generate_line !=0)
            begin
                always @(posedge clk, negedge rst) begin
                    if(!rst)
                        begin
                            bm[generate_line][generate_colum] <= 0;
                            bn[generate_line][generate_colum] <= 0;
                            // am[generate_line] <= 0;
                            // an[generate_line] <= 0;
                            //  bm[/* generate_colum + */ generate_line /* * (SQUAREDIMENSION - 1) */] <= 0;
                            //  bn[/* generate_colum + */ generate_line /* * (SQUAREDIMENSION - 1) */] [generate_colum]<= 0;
                        end
                    else
                        begin
                            bm[generate_line][generate_colum] <= bn[generate_line ][generate_colum ];
                            bn[generate_line][generate_colum] <= bn[generate_line -1][generate_colum ];
                            //am[generate_line] <= an[generate_line];
                            //an[generate_line] <= an[generate_line -1];
                            //bm[generate_colum + generate_line * (SQUAREDIMENSION - 1)] <= bn[generate_colum + generate_line * (SQUAREDIMENSION - 1)];
                            //bm[generate_colum + generate_line * (SQUAREDIMENSION - 1)] <=  bn[/* generate_colum + */ generate_line /* * (SQUAREDIMENSION - 1) */] [generate_colum];
                            //bn[/* generate_colum + */ generate_line /* * (SQUAREDIMENSION - 1) */] [generate_colum]<= bn[/* generate_colum + */ generate_line /* * (SQUAREDIMENSION - 1) */ -1][generate_colum];
                        end
                end
            end  


        end
    end

    endgenerate

    
    generate
        for (generate_line = 0; generate_line < SQUAREDIMENSION; generate_line = generate_line + 1) begin : linha_entrada
            always @(posedge clk, negedge rst)
            begin
                if(!rst)
                    begin
                        am[generate_line][0] <= 0;
                        an[generate_line][0] <= 0;
                    end
                else
                    begin
                        am[generate_line][0] <= an[generate_line][0];
                        an[generate_line][0] <= a;
                end
            end
        end
    endgenerate


    generate

        for (generate_colum = 0; generate_colum < SQUAREDIMENSION; generate_colum = generate_colum + 1) begin : line
            always @(posedge clk, negedge rst)
            begin
                if(!rst)
                    begin
                        bm[0][generate_colum] <= 0;
                        bn[0][generate_colum] <= 0;
                    end
                else
                    begin
                        bm[0][generate_colum] <= bn[0][generate_colum];
                        bn[0][generate_colum] <= b;
                end
            end
            end
    endgenerate
    
endmodule