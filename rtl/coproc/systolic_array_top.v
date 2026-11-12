module systolic_array_top #(parameter WIDTH = 8, SQUAREDIMENSION = 2)  ( 
    output [WIDTH -1 : 0],
    output [WIDTH -1 : 0],
    output [WIDTH -1 : 0],
    output [WIDTH -1 : 0],
    output [WIDTH -1 : 0],
    output [WIDTH -1 : 0],
    output [WIDTH -1 : 0],
    input [WIDTH -1 : 0],
    input [WIDTH -1 : 0],
    input [WIDTH -1 : 0],
    input [WIDTH -1 : 0],
    input [WIDTH -1 : 0],
    input [WIDTH -1 : 0],
    input [WIDTH -1 : 0]
    );
parameter WIDTH_COUNTER = $clog2(WIDTH);



    reg busy;
    reg redy_out;
    reg signed [WIDTH -1 : 0] a;
    reg signed [WIDTH -1 : 0] b;
    reg rst;
    reg clk;
    reg start;
    reg exec;

    systolic_arrayB # (
        .WIDTH(WIDTH),
        .SQUAREDIMENSION(SQUAREDIMENSION)
    )
    systolic_arrayB_inst (
        .busy(busy),
        .redy_out(redy_out),
        .a(a),
        .b(b),
        .rst(rst),
        .clk(clk),
        .start(start),
        .exec(exec),
        .addrA(addrA),
        .addrB(addrB)
    );

    // ============================================================
    // PARAMETROS DOS ESTADOS
    // ============================================================
    localparam       IDLE        = 4'b0000,
                     START       = 4'b0001,
                     READLINE      = 4'b0010,
                     READCOL    = 4'b0011,
                     EXECUTE       = 4'b0100,
                     ENVIA       = 4'b0101,
                     FINALIZA    = 4'b0110,
                     ERRO        = 4'b0111,
                     ESTADO_8    = 4'b1000,
                     ESTADO_9    = 4'b1001,
                     ESTADO_10   = 4'b1010,
                     ESTADO_11   = 4'b1011,
                     ESTADO_12   = 4'b1100,
                     ESTADO_13   = 4'b1101,
                     ESTADO_14   = 4'b1110,
                     ESTADO_15   = 4'b1111;
    
    // ============================================================
    // REGISTRADORES DA MAQUINA DE ESTADOS
    // ============================================================
    reg [3:0] estado_atual,proximo_estado;
    
    // ============================================================
    // MAQUINA DE ESTADOS - REGISTRO DE ESTADO
    // RESET ATIVO EM NIVEL BAIXO
    // ============================================================
    always @(posedge clk or negedge reset) begin
        if (!reset) begin
            estado_atual <= IDLE;
        end
        else begin
            estado_atual <= proximo_estado;
        end
    end
    
    // ============================================================
    // LOGICA DE PROXIMO ESTADO
    // ============================================================
    always @(*) begin
    
    
        case (estado_atual)
    
            IDLE: begin
                    proximo_estado = START;
            end
    
            START: begin
                proximo_estado = READLINE;
            end
    
            READLINE: begin
                    proximo_estado = READCOL;
            end
    
            READCOL: begin
                proximo_estado = EXECUTE;
            end
    
            EXECUTE: begin
                proximo_estado = ENVIA;
            end
    
            ENVIA: begin
                    proximo_estado = FINALIZA;
            end
    
            FINALIZA: begin
                proximo_estado = IDLE;
            end
    
            ERRO: begin
                proximo_estado = IDLE;
            end
    
            ESTADO_8: begin
                proximo_estado = IDLE;
            end
    
            ESTADO_9: begin
                proximo_estado = IDLE;
            end
    
            ESTADO_10: begin
                proximo_estado = IDLE;
            end
    
            ESTADO_11: begin
                proximo_estado = IDLE;
            end
    
            ESTADO_12: begin
                proximo_estado = IDLE;
            end
    
            ESTADO_13: begin
                proximo_estado = IDLE;
            end
    
            ESTADO_14: begin
                proximo_estado = IDLE;
            end
    
            ESTADO_15: begin
                proximo_estado = IDLE;
            end
    
            default: begin
                proximo_estado = IDLE;
            end
    
        endcase
    end
    
    // ============================================================
    // LOGICA DE SAIDAS E REGISTRADORES
    // ============================================================
    always @(estado_atual) begin
    
        // Valores padrao
    
        case (estado_atual)
    
            IDLE: begin
                // Saidas do estado IDLE
            end
    
            START: begin
                // Saidas do estado START
            end
    
            READLINE: begin
                // Saidas do estado READLINE
            end
    
            READCOL: begin
                // Saidas do estado READCOL
            end
    
            EXECUTE: begin
                // Saidas do estado EXECUTE
            end
    
            ENVIA: begin
                // Saidas do estado ENVIA
            end
    
            FINALIZA: begin
                // Saidas do estado FINALIZA
            end
    
            ERRO: begin
                // Saidas do estado ERRO
            end
    
            ESTADO_8: begin
                // Saidas do estado ESTADO_8
            end
    
            ESTADO_9: begin
                // Saidas do estado ESTADO_9
            end
    
            ESTADO_10: begin
                // Saidas do estado ESTADO_10
            end
    
            ESTADO_11: begin
                // Saidas do estado ESTADO_11
            end
    
            ESTADO_12: begin
                // Saidas do estado ESTADO_12
            end
    
            ESTADO_13: begin
                // Saidas do estado ESTADO_13
            end
    
            ESTADO_14: begin
                // Saidas do estado ESTADO_14
            end
    
            ESTADO_15: begin
                // Saidas do estado ESTADO_15
            end
    
            default: begin
                // Estado invalido
            end
    
        endcase
    end
    
    

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
        end
endmodule