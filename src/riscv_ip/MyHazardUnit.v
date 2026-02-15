// Hazard Unit for Pipelined RISC-V with BRAM latency support
// Handles: RAW forwarding, load-use stalls, BRAM 1-cycle read stalls, control hazards
module HazardUnit (
    input wire clk,
    input wire rst_n,

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

    // BRAM stall input (from M stage)
    input wire       MemReadM, // 1 if instruction in M is a Load

    // Control Hazard Input
    input wire       PCSrcE,

    // Outputs
    output reg [1:0] ForwardAE,
    output reg [1:0] ForwardBE,
    output wire      StallF,
    output wire      StallD,
    output wire      StallE,   // Freeze DE register during BRAM stall
    output wire      StallM,   // Freeze EM+MW registers during BRAM stall
    output wire      FlushE,
    output wire      FlushD
);

    // =========================================================
    // RAW FORWARDING LOGIC (unchanged from original)
    // =========================================================
    always @(*) begin
        if ((RegWriteM == 1) && (RdM != 0) && (RdM == Rs1E))
            ForwardAE = 2'b10;
        else if ((RegWriteW == 1) && (RdW != 0) && (RdW == Rs1E))
            ForwardAE = 2'b01;
        else
            ForwardAE = 2'b00;

        if ((RegWriteM == 1) && (RdM != 0) && (RdM == Rs2E))
            ForwardBE = 2'b10;
        else if ((RegWriteW == 1) && (RdW != 0) && (RdW == Rs2E))
            ForwardBE = 2'b01;
        else
            ForwardBE = 2'b00;
    end

    // =========================================================
    // LOAD-USE STALL (standard pipeline hazard)
    // =========================================================
    wire lwStall;
    assign lwStall = (ResultSrcE0 == 1) && (RdE != 0) &&
                     ((RdE == Rs1D) || (RdE == Rs2D));

    // =========================================================
    // BRAM LATENCY STALL (1-cycle stall when load reaches M)
    // =========================================================
    // BRAM synchronous read: address latched at posedge, data valid
    // after clk-to-q. Must hold pipeline 1 extra cycle so MW register
    // captures valid data on the NEXT posedge.
    reg bram_stall_done;
    wire bramStall;
    assign bramStall = MemReadM && !bram_stall_done;

    always @(posedge clk) begin
        if (!rst_n)
            bram_stall_done <= 1'b0;
        else
            bram_stall_done <= bramStall;
    end

    // =========================================================
    // STALL & FLUSH OUTPUTS
    // =========================================================
    assign StallF = lwStall || bramStall;
    assign StallD = lwStall || bramStall;
    assign StallE = bramStall;
    assign StallM = bramStall;

    // Flushes suppressed during bramStall (everything frozen)
    assign FlushE = !bramStall && (lwStall || PCSrcE);
    assign FlushD = !bramStall && PCSrcE;

endmodule
