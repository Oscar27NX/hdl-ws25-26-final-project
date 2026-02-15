module HazardUnit (
    // Forwarding Inputs (from EX stage)
    input wire [4:0] Rs1E,
    input wire [4:0] Rs2E,
    
    // Forwarding Inputs (from MEM/WB stages)
    input wire [4:0] RdM,
    input wire       RegWriteM,
    input wire       ResultSrcM0, // 1 if instruction in M is a Load
    input wire [4:0] RdW,
    input wire       RegWriteW,

    // Stall Inputs (from D/E stages)
    input wire [4:0] Rs1D,
    input wire [4:0] Rs2D,
    input wire [4:0] RdE,
    input wire       ResultSrcE0, // 1 if instruction in E is a Load 
    
    // Control Hazard Input
    input wire       PCSrcE, // 1 if branch taken or jump in E stage

    // Outputs
    output reg [1:0] ForwardAE,
    output reg [1:0] ForwardBE,
    output reg       StallF,
    output reg       StallD,
    output reg       FlushE,
    output reg       FlushD
);

    wire matchRs1E_M;
    wire matchRs2E_M;
    wire matchRs1E_W;
    wire matchRs2E_W;
    wire lwStallE;
    wire lwStallM;

    assign matchRs1E_M = (RdM != 5'b0) && (RdM == Rs1E);
    assign matchRs2E_M = (RdM != 5'b0) && (RdM == Rs2E);
    assign matchRs1E_W = (RdW != 5'b0) && (RdW == Rs1E);
    assign matchRs2E_W = (RdW != 5'b0) && (RdW == Rs2E);

    // RAW-HANDLING FORWARDING LOGIC
    always @(*) begin
        // Forward A
        if (RegWriteM && !ResultSrcM0 && matchRs1E_M)
            ForwardAE = 2'b10; // Forward from Memory Stage
        else if (RegWriteW && matchRs1E_W)
            ForwardAE = 2'b01; // Forward from Writeback Stage
        else
            ForwardAE = 2'b00; // No forwarding

        // Forward B
        if (RegWriteM && !ResultSrcM0 && matchRs2E_M)
            ForwardBE = 2'b10;
        else if (RegWriteW && matchRs2E_W)
            ForwardBE = 2'b01;
        else
            ForwardBE = 2'b00;
    end

    // STALLING LOGIC
    // If logic in E is a Load, and it writes to a register that D reads, then the control must stall
    assign lwStallE = ResultSrcE0 && (RdE != 5'b0) && ((RdE == Rs1D) || (RdE == Rs2D));
    // Synchronous data memory: loaded data is only available in WB, so hold
    // the dependent instruction in D for one extra cycle while Load is in M.
    assign lwStallM = ResultSrcM0 && (RdM != 5'b0) && ((RdM == Rs1D) || (RdM == Rs2D));

    // CONTROL SIGNAL LOGIC (branch/jump flushes and load-use stalls)
    always @(*) begin
        StallF = lwStallE || lwStallM;
        StallD = lwStallE || lwStallM;
        
        // Flush E if we stall or if we take a branch
        FlushE = lwStallE || lwStallM || PCSrcE;
        
        // Flush D if we take a branch
        FlushD = PCSrcE;
    end

endmodule
