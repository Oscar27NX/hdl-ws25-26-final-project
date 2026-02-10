// The instruction decoder module; extracts fields and sign-extends immediates
module InstructionDecoder (
    input wire [31:0] instr,
    output wire [6:0] opcode,
    output wire [2:0] funct3,
    output wire [6:0] funct7,
    output reg [31:0] imm_ext 
);

    // Field Extraction according to RISC-V manual
    assign opcode = instr[6:0];
    assign funct3 = instr[14:12];
    assign funct7 = instr[31:25];

    // Combinational Sign Extension with PC Correction
    always @(*) begin
        case (opcode)
            // I-Type (LW, ADDI, JALR)
            7'b0000011, 7'b0010011, 7'b1100111: begin 
                imm_ext = {{20{instr[31]}}, instr[31:20]};
            end

            // S-Type (SW)
            7'b0100011: begin
                imm_ext = {{20{instr[31]}}, instr[31:25], instr[11:7]};
            end

            // B-Type (BEQ, BNE, BLT...)
            7'b1100011: begin
                imm_ext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0}; 
            end

            // J-Type (JAL)
            7'b1101111: begin
                imm_ext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0};
            end

            // U-Type (LUI)
            7'b0110111, 7'b0010111: begin
                imm_ext = {instr[31:12], 12'b0};
            end

            default: 
                imm_ext = 32'b0;
        endcase
    end
endmodule