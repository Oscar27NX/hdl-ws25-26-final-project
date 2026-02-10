// Simple HU that handles the three required basic hazards
module HazardUnit (
    // Forwarding Inputs (from EX stage)
    input wire [4:0] Rs1E,
    input wire [4:0] Rs2E,
    
    // Forwarding Inputs (from MEM/WB stages)
    input wire [4:0] RdM,
    input wire       RegWriteM,
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

    wire lwStall;

    // RAW-HANDLING FORWARDING LOGIC
    always @(*) begin
        // Forward A
        if ((RegWriteM == 1) && (RdM != 0) && (RdM == Rs1E))
            ForwardAE = 2'b10; // Forward from Memory Stage
        else if ((RegWriteW == 1) && (RdW != 0) && (RdW == Rs1E))
            ForwardAE = 2'b01; // Forward from Writeback Stage
        else
            ForwardAE = 2'b00; // No forwarding

        // Forward B
        if ((RegWriteM == 1) && (RdM != 0) && (RdM == Rs2E))
            ForwardBE = 2'b10;
        else if ((RegWriteW == 1) && (RdW != 0) && (RdW == Rs2E))
            ForwardBE = 2'b01;
        else
            ForwardBE = 2'b00;
    end

    // STALLING LOGIC
    // If logic in E is a Load, and it writes to a register that D reads, then the control must stall
    assign lwStall = (ResultSrcE0 == 1) && ((RdE == Rs1D) || (RdE == Rs2D));

    // CONTROL SIGNAL LOGIC (branch/jump flushes and load-use stalls)
    always @(*) begin
        StallF = lwStall;
        StallD = lwStall;
        
        // Flush E if we stall or if we take a branch
        FlushE = lwStall || PCSrcE;
        
        // Flush D if we take a branch
        FlushD = PCSrcE;
    end

endmodule