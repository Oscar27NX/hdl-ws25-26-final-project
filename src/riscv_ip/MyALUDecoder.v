// Second level decoding for the specific alu operations
module ALU_Decoder (
    input wire [1:0] ALUOp,      // From Controller
    input wire [2:0] funct3,      // From Instruction [14:12]
    input wire [6:0] funct7,      // From Instruction [31:25]
    input wire [6:0] opcode,      // From Instruction [6:0]
    output reg [3:0] ALUControl  // To ALU
);

    always @(*) begin
        case (ALUOp)
            // Mode 00: LW / SW / PC+4 (Force ADD)
            2'b00: ALUControl = 4'b0000; 

            // Mode 01: BEQ (Force SUB)
            2'b01: ALUControl = 4'b0001; 
            
            // Mode 10: R-Type and I-Type Arithmetic
            2'b10: begin 
                case (funct3)
                    3'b000: begin 
                        // ADD, ADDI, SUB
                        if (opcode == 7'b0110011 && funct7[5]) 
                            ALUControl = 4'b0001; // SUB
                        else 
                            ALUControl = 4'b0000; // ADD / ADDI
                    end
                    3'b001: ALUControl = 4'b0010; // SLL / SLLI
                    3'b010: ALUControl = 4'b0100; // SLT / SLTI
                    3'b011: ALUControl = 4'b0110; // SLTU / SLTIU
                    3'b100: ALUControl = 4'b1000; // XOR / XORI
                    3'b101: begin // SRL / SRA
                         if (funct7[5]) ALUControl = 4'b1011; // SRA / SRAI
                         else           ALUControl = 4'b1010; // SRL / SRLI
                    end
                    3'b110: ALUControl = 4'b1100; // OR / ORI
                    3'b111: ALUControl = 4'b1110; // AND / ANDI
                    default: ALUControl = 4'b0000;
                endcase
            end

            2'b11: ALUControl = 4'b1111;
            
            default: ALUControl = 4'b0000;
        endcase
    end
endmodule