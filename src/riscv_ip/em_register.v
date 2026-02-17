// Register that holds signals between the E and M stages of the pipeline.
// It also handles flushing (for load hazards) and stalling (for BRAM stalls).
module EM_Register (input wire clk,
    input wire rst_n,
    input wire flush,
    input wire stall,       // Hold values during BRAM stall

    // Signals from control unit in E stage
    input wire [1:0] E_sel_result,
    input wire E_we_dm,
    input wire E_we_rf,

    // More signals from the E stage
    input wire [31:0] E_alu_o,
    input wire [31:0] E_dm_wd,
    input wire [4:0]  E_rf_a3,
    input wire [31:0] E_pc_p4,

    // Output signals to M stage
    output reg [1:0] M_sel_result,
    output reg M_we_dm,
    output reg M_we_rf,
    output reg [31:0] M_alu_o,
    output reg [31:0] M_dm_wd,
    output reg [4:0]  M_rf_a3,
    output reg [31:0] M_pc_p4
);

    always @(posedge clk) begin
        // if core is reset or we need to flush (load hazard), clear all outputs to 0 (NOP)
        if (!rst_n || flush) begin
            M_sel_result <= 2'b0;
            M_we_dm      <= 1'b0;
            M_we_rf      <= 1'b0;
            M_alu_o      <= 32'b0;
            M_dm_wd      <= 32'b0;
            M_rf_a3      <= 5'b0;
            M_pc_p4      <= 32'b0;
        // update sequentally on clock edge if no stall
        end else if (!stall) begin
            M_sel_result <= E_sel_result;
            M_we_dm      <= E_we_dm;
            M_we_rf      <= E_we_rf;
            M_alu_o      <= E_alu_o;
            M_dm_wd      <= E_dm_wd;
            M_rf_a3      <= E_rf_a3;
            M_pc_p4      <= E_pc_p4;
        end
        // else: stall and hold current values
    end
endmodule
