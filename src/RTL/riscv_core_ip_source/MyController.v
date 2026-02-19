// Composed of first level decoder (instruction type) and second level decoder (alu control)
// mostly a wrapper to connect the two decoders and pass the correct signals to the datapath.
module Controller (
    input wire clk,
    input wire [31:0] instr,  
    input wire Zero,

    // Outputs to Datapath 
    output wire d_jump,
    output wire d_branch,
    output wire [1:0] d_sel_result,    
    output wire d_we_dm,
    output wire [3:0] d_alu_control,   
    output wire d_sel_alu_src_b,
    output wire [31:0] imm_ext,
    output wire d_we_rf
);
    // Wires to connect decoders
    wire [6:0] opcode;
    wire [2:0] funct3;
    wire [6:0] funct7;
    wire [1:0] alu_op; 

    // instantiate the instruction decoder which will output the
    // opcode, funct3, funct7, and immediate value (after extension) from the instruction
    InstructionDecoder ID (
        .instr(instr),
        .opcode(opcode),
        .funct3(funct3),
        .funct7(funct7),
        .imm_ext(imm_ext)
    );

    // the main decoder will take the opcode and output the main control signals for the datapath
    // as well as the ALUOp bits for the ALU decoder
    Main_Decoder CU (
        .opcode(opcode),
        .reg_write(d_we_rf),
        .mem_write(d_we_dm),
        .alu_src(d_sel_alu_src_b),
        .result_src(d_sel_result),
        .branch(d_branch),
        .jump(d_jump),
        .alu_op(alu_op)
    );

    // the ALU decoder takes the ALUOp bits from the main decoder and the funct3/funct7 from the instruction
    // to determine the exact ALU control signals to send to the ALU for the correct operation
    ALU_Decoder ALU_Dec (
        .ALUOp(alu_op),
        .funct3(funct3),
        .funct7(funct7),
        .opcode(opcode),
        .ALUControl(d_alu_control)
    );

endmodule