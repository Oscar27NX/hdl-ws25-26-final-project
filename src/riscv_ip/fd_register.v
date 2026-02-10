// Register that holds signals between the F and D stages
module FD_register (
    input wire clk,
    input wire rst_n,      
    input wire stall,      // also Stall only for this stage since F stage PC is handled separately
    input wire flush,      // Flush D stage on branch

    // Inputs from the F stage
    input wire [31:0] F_pc4,
    input wire [31:0] F_pc, 
    input wire [31:0] F_instr, // fetched instruction
    
    // Outputs to ID Stage
    output reg [31:0] D_pc4,
    output reg [31:0] D_pc,
    output reg [31:0] D_instr
);

    always @(posedge clk) begin
        if (!rst_n) begin
            // Reset state
            D_pc <= 32'b0;
            D_instr <= 32'h00000013;
            D_pc4 <= 32'b0;
        end
        else if (flush) begin
            // Flush pipeline
            D_pc <= 32'b0;
            D_instr <= 32'h00000013; 
            D_pc4 <= 32'b0;
        end
        else if (!stall) begin
            // Stall handles the PC separately, so just pass values
            D_pc <= F_pc;
            D_instr <= F_instr;
            D_pc4 <= F_pc4;
        end
        else begin
            // Hold current state 
            D_pc <= D_pc;
            D_instr <= D_instr;
            D_pc4 <= D_pc4;
        end
    end

endmodule