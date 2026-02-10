// ALU Module. It uses the register with the given control signals to perform operations.
module ALU(
    input wire [3:0] alu_control,
    input wire [31:0] operand_a,
    input wire [31:0] operand_b,
    output reg [31:0] alu_result,
    output zero
);
    assign zero = (alu_result == 32'b0);

    always @(*) begin
        case (alu_control)
            // ADD / ADDI / LW / SW: Funct3=000, Funct7[5]=0
            4'b0000: alu_result = operand_a + operand_b;  
            
            // SUB (alternative code): Funct3=000, Funct7[5]=1
            4'b0001: alu_result = operand_a - operand_b;
            
            // SLL / SLLI: Funct3=001, Funct7[5]=0
            4'b0010: alu_result = operand_a << operand_b[4:0]; 
            
            // SLT: Funct3=010, Funct7[5]=0
            4'b0100: alu_result = ($signed(operand_a) < $signed(operand_b)) ? 32'b1 : 32'b0;
            
            // SLTU: Funct3=011, Funct7[5]=0
            4'b0110: alu_result = (operand_a < operand_b) ? 32'b1 : 32'b0;
            
            // XOR: Funct3=100, Funct7[5]=0
            4'b1000: alu_result = operand_a ^ operand_b; 

            // SRL / SRLI: Funct3=101, Funct7[5]=0
            4'b1010: alu_result = operand_a >> operand_b[4:0];

            // SRA / SRAI: Funct3=101, Funct7[5]=1
            4'b1011: alu_result = $signed(operand_a) >>> operand_b[4:0];

            // OR: Funct3=110, Funct7[5]=0
            4'b1100: alu_result = operand_a | operand_b; 

            // AND: Funct3=111, Funct7[5]=0
            4'b1110: alu_result = operand_a & operand_b; 

            // LUI: Load Upper Immediate
            4'b1111: alu_result = operand_b;
            
            // No operation
            default: alu_result = 32'b0;
        endcase
    end
endmodule