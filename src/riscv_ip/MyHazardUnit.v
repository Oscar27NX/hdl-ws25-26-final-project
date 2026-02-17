// Hazard Unit for Pipelined RISC-V with BRAM latency support
// responsibel to handle RAW forwarding logic, load-use stalls, BRAM 1-cycle read stalls & control hazards.
module HazardUnit (
    input wire clk,
    input wire rst_n,

    // Forwarding Inputs (from the EX stage, we know these are the source
    // registers for the current instruction in E stage)
    input wire [4:0] Rs1E,
    input wire [4:0] Rs2E,

    // Forwarding Inputs (from the MEM/WB stages, we know these are the result registers for the instructions
    // in M/W stages)
    input wire [4:0] RdM,
    input wire       RegWriteM,
    input wire [4:0] RdW,
    input wire       RegWriteW,

    // Stall Inputs (from the D/E stages, as we remember the load-use hazard is detected in D stage but requires
    // stalling at the E stage)
    input wire [4:0] Rs1D,
    input wire [4:0] Rs2D,
    input wire [4:0] RdE,
    input wire       ResultSrcE0, // 1 if instruction in E is a Load

    // BRAM stall input (from M stage)
    input wire       MemReadM, // 1 if instruction in M is a Load

    // Control Hazard Input (to check if address to be written back is from a branch instruction, which we
    // want to suppress flushes for since we don't want to insert a NOP after a branch, since
    // the instruction after a branch is always valid.
    input wire       PCSrcE,

    // Outputs to control forwarding muxes in E stage
    output reg [1:0] ForwardAE,
    output reg [1:0] ForwardBE,

        // Outputs to control stalling and flushing of pipeline registers
    output wire      StallF,
    output wire      StallD,
    output wire      StallE,   // Freeze DE register during BRAM stall
    output wire      StallM,   // Freeze EM+MW registers during BRAM stall
    output wire      FlushE,
    output wire      FlushD
);

    // =========================================================
    // RAW FORWARDING LOGIC
    // =========================================================
    always @(*) begin
        // if the M stage instruction is writing to a register (RegWriteM) and it's not trivial (RdM != 0)
        //  and the destination register matches the source register in E stage (RdM == Rs1E),
        // then we need to forward instead from M stage (ForwardAE = 2'b10)!!
        // this way we can use the value that is just being computed in M without waiting for it to be written back
        if ((RegWriteM == 1) && (RdM != 0) && (RdM == Rs1E))
            ForwardAE = 2'b10;
        else if ((RegWriteW == 1) && (RdW != 0) && (RdW == Rs1E))
            ForwardAE = 2'b01;
        else
            ForwardAE = 2'b00;

        // same logic for the second source register in E stage (Rs2E)
        // and the destination registers in M/W stages (RdM/RdW)
        if ((RegWriteM == 1) && (RdM != 0) && (RdM == Rs2E))
            ForwardBE = 2'b10;
        else if ((RegWriteW == 1) && (RdW != 0) && (RdW == Rs2E))
            ForwardBE = 2'b01;
        else
            ForwardBE = 2'b00;
    end

    // =========================================================
    // LOAD-USE STALL (pipeline hazard)
    // =========================================================
    // If the instruction in E stage is a Load (ResultSrcE0 == 1)
    // and the destination register (RdE) matches either source register in D stage (Rs1D or Rs2D),
    //  then we have a load-use hazard and need to stall the pipeline
    //  for 1 cycle to allow the load to complete and write back its result before we can use it.
    wire lwStall;
    assign lwStall = (ResultSrcE0 == 1) && (RdE != 0) &&
                     ((RdE == Rs1D) || (RdE == Rs2D));

    // =========================================================
    // BRAM LATENCY STALL
    // =========================================================
    // BRAM synchronous read: address latched at posedge, data valid
    // after clk-to-q. Must hold pipeline 1 extra cycle so MW register
    // captures valid data on the NEXT posedge.
    reg bram_stall_done;
    wire bramStall;
    assign bramStall = MemReadM && !bram_stall_done;

    // We use a register to remember that we have already stalled for the current load instruction in M stage,
    // so we only stall for at most 1 cycle per load.
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
