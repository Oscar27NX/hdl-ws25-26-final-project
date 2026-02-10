// This unit receives the opcode to breakdwown control signals for the ALU and other units
module Main_Decoder (
    input  wire [6:0] opcode,
    output reg       reg_write,
    output reg       mem_write,
    output reg       alu_src,    
    output reg [1:0] result_src, 
    output reg       branch,
    output reg       jump,       
    output reg [1:0] alu_op    
);

    always @(*) begin
        // Defaults to prevent latches
        reg_write = 0; mem_write = 0; alu_src = 0; 
        result_src = 0; branch = 0; jump = 0; alu_op = 0;

        case (opcode)
            // R-Type (ADD, SUB, OR, etc.)
            7'b0110011: begin 
                reg_write = 1; 
                alu_op = 2'b10; 
            end

            // I-Type Arithmetic (ADDI, etc.)
            7'b0010011: begin 
                reg_write = 1; 
                alu_src = 1;    
                alu_op = 2'b10; 
            end

            // LW (Load Word)
            7'b0000011: begin 
                reg_write = 1; 
                alu_src = 1; 
                result_src = 2'b01; 
                alu_op = 2'b00;    
            end

            // SW (Store Word)
            7'b0100011: begin 
                mem_write = 1; 
                alu_src = 1; 
                alu_op = 2'b00;     
            end

            // BEQ (Branch)
            7'b1100011: begin 
                branch = 1; 
                alu_op = 2'b01;     
            end

            // JAL (Jump)
            7'b1101111: begin 
                reg_write = 1;
                jump = 1; 
                result_src = 2'b10; // Store PC+4
            end

               // JALR (Jump Register)
            7'b1100111: begin
                reg_write = 1;
                jump = 1;       
                alu_src = 1;    // ALU uses Immediate
                result_src = 2'b10; // Store PC+4 in rd
                alu_op = 2'b00; // immediate addition for address calculation
            end

            // U-Type (LUI)
            7'b0110111: begin
                reg_write = 1;
                alu_src   = 1;     // Use Immediate
                alu_op    = 2'b11; // Special "LUI" O
            end

            default:
                ; 
        endcase
    end
endmodule