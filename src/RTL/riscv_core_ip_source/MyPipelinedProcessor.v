// Pipelined RISC-V processor for FPGA-BRAM deployment

module rv_pl(
    // EXPOSED INPUT/OUTPUT PORTS
    input wire clk,
    input wire resetn,

    // Instruction Memory Interface (BRAM Port B,read only)
    output wire [31:0] i_addr,
    input wire [31:0]  i_instr,

    // Data Memory Interface (BRAM Port B)
    output wire [31:0] d_addr,
    output wire [31:0] d_wdata,

    // d_we is 4 bits for byte-enable as per vivado default bram generator config;
    // we use 0xF for word stores and 0x0 for no stores at all
    output wire [3:0] d_we,
    input wire [31:0]  d_rdata
);
    // WIRES (internal connections between modules)

    // Fetch stage:

    // we need F_pc_p4 to see the next sequential PC.
    // this is used for branch target calculation and the jump register instructions.
    wire [31:0] F_pc, F_pc_p4, F_pc_next;
    wire        F_stall;

    // Fetch-aligned PC:
    // since BRAM causes a 1-cycle delay due to synchronous reads, we need to use
    //  a registered version of F_pc for the FD register and the next instruction input, so that they are correctly aligned.
    // This is because the BRAM will instead output the instruction corresponding to the LATCHED address from the previous cycle, which is F_pc_r.
    reg  [31:0] F_pc_r;
    wire [31:0] F_pc_r_p4;

    // Decode stage
    wire [31:0] D_pc, D_pc_p4, D_instr, D_imm_ext;
    wire [31:0] D_rf_rd1, D_rf_rd2;
    wire [4:0]  D_rf_a3;
    wire        D_jump, D_branch, D_we_dm, D_sel_alu_src_b, D_we_rf;
    wire [1:0]  D_sel_result;
    wire [3:0]  D_alu_control;
    wire        D_stall, D_flush;

    // Execute stage
    wire [31:0] E_pc, E_pc_p4, E_rf_rd1, E_rf_rd2, E_ext;
    wire [31:0] E_alu_src_b, E_alu_o, E_target_pc;
    wire [31:0] E_src_a_forwarded, E_src_b_forwarded;
    wire [4:0]  E_rf_a3, E_rs1, E_rs2;
    wire        E_jump, E_branch, E_we_dm, E_sel_alu_src_b, E_we_rf;
    wire [1:0]  E_sel_result;
    wire [3:0]  E_alu_control;
    wire        E_zero, E_flush;

    // Memory stage
    wire [31:0] M_pc_p4, M_alu_o, M_dm_wd, M_dm_rd;
    wire [4:0]  M_rf_a3;
    wire        M_we_dm, M_we_rf;
    wire [1:0]  M_sel_result;

    // Writeback stage
    wire [31:0] W_pc_p4, W_alu_o, W_dm_rd, W_result;
    wire [4:0]  W_rf_a3;
    wire        W_we_rf;
    wire [1:0]  W_sel_result;

    // Hazard signals
    // the forwarding signals (ForwardAE and ForwardBE) determine where the ALU sources in the E stage get their data from:
    // 00 = from register file, 01 = from W stage (writeback), 10 = from M stage (memory)
    // AE corresponds to the first ALU operand (rs1) and BE corresponds to the second ALU operand (rs2 or immediate)
    wire [1:0]  ForwardAE, ForwardBE;
    wire        PC_Src;

   // the new stall and flush signals from the Hazard Unit, which are used
   // for control stalling and flushing of the pipeline registers in ALL stages.
    wire        StallE, StallM;
    wire        MemReadM;

   // the value of MemReadM is determined by the instruction in the M stage.
   // If the instruction in M stage is a load (sel_result = 01), then we need to stall the pipeline because of BRAM latency,
   // and we also need to forward the loaded value from M stage instead of W stage.
    assign MemReadM = (M_sel_result == 2'b01);

    // ============================================
    // MANAGE IRAM LATENCY: F_pc_r
    // ============================================
    // BRAM latches the i_addr at posedge and outputs data AFTER the edge!
    // F_pc_r is a registered copy of F_pc, so it's aligned with i_instr by design.
    // We use F_pc_r for the FD register and the next PC calculation, so that they are correctly paired with the instruction coming out of BRAM.
    // FD register receives (F_pc_r, fd_instr_in) = correctly paired.
    always @(posedge clk) begin
        if (!resetn)
            F_pc_r <= 32'b0;
        else if (!F_stall)
            F_pc_r <= F_pc;
    end

    // ============================================
    // INSTRUCTION BUFFER
    // ============================================
    // The main solution to our problem: During stalls, BRAM address register (external) keeps
    // latching the value in F_pc, overwriting the correct instruction that was being executed. When stall then
    // releases, BRAM outputs wrong instruction.
    // So instead: on first cycle of stall we know i_instr is still valid (sequential update)
    // So in the meantime, save it in a buffer.
    // Then read from the buffer when stall releases.
    reg [31:0] instr_buf;
    reg        instr_buf_valid;
    always @(posedge clk) begin
        if (!resetn) begin
            instr_buf_valid <= 1'b0;
            instr_buf <= 32'h00000013;
        end else if (FD_flush_final) begin
            instr_buf_valid <= 1'b0;
        end else if (!F_stall) begin
            instr_buf_valid <= 1'b0;
        end else if (F_stall && !instr_buf_valid) begin
            instr_buf <= i_instr;
            instr_buf_valid <= 1'b1;
        end
    end
    wire [31:0] fd_instr_in = instr_buf_valid ? instr_buf : i_instr;

    Adder PC_R_Adder (
        .a   (F_pc_r),
        .b   (32'd4),
        .sum (F_pc_r_p4)
    );

    // ============================================
    // 2-CYCLE BRANCH FLUSH
    // ============================================
    // After a taken branch, BRAM needs 1 extra cycle to fetch target instr.
    // Cycle 0: PCSrcE=1, PC←target, FD flushed (from HazardUnit FlushD)
    // Cycle 1: BRAM outputs stale instr, need extra flush
    // Cycle 2: BRAM outputs correct target instr
    reg branch_flush_r;
    always @(posedge clk) begin
        if (!resetn)
            branch_flush_r <= 1'b0;
        else
            branch_flush_r <= PC_Src;
    end

    // Combined FD flush: normal hazard flush + extra BRAM cycle
    wire FD_flush_final = D_flush || branch_flush_r;

    // ============================================
    // HAZARD UNIT
    // ============================================

    // instantiate the Hazard Unit and connect all its signals
    HazardUnit HU (
        .clk         (clk),
        .rst_n       (resetn),

        .Rs1E        (E_rs1),
        .Rs2E        (E_rs2),
        .RdM         (M_rf_a3),
        .RegWriteM   (M_we_rf),
        .RdW         (W_rf_a3),
        .RegWriteW   (W_we_rf),

        .Rs1D        (D_instr[19:15]),
        .Rs2D        (D_instr[24:20]),
        .RdE         (E_rf_a3),
        .ResultSrcE0 (E_sel_result[0]),
        .MemReadM    (MemReadM),
        .PCSrcE      (PC_Src),

        .ForwardAE   (ForwardAE),
        .ForwardBE   (ForwardBE),
        .StallF      (F_stall),
        .StallD      (D_stall),
        .StallE      (StallE),
        .StallM      (StallM),
        .FlushE      (E_flush),
        .FlushD      (D_flush)
    );

    // ============================================
    // FETCH STAGE
    // ============================================

    // assign the next value in PC address in case of a jump or taken branch,
    // otherwise PC+4 for next sequential instruction as normal
    assign PC_Src = E_jump | (E_branch & E_zero);
    assign F_pc_next = (PC_Src) ? E_target_pc : F_pc_p4;

    ProgramCounter PC (
        .clk    (clk),
        .resetn (resetn),
        .en     (!F_stall),
        .pc_in  (F_pc_next),
        .pc_out (F_pc)
    );

    Adder PC_Adder (
        .a   (F_pc),
        .b   (32'd4),
        .sum (F_pc_p4)
    );

    // next address to fetch is either from the PC (normal operation)
    // or it is held constant during a stall (F_stall = 1)
    assign i_addr = F_pc;

    // ============================================
    // PIPE: F -> D
    // ============================================
    // Uses F_pc_r (aligned with BRAM output)

    FD_register PLR1 (
        .clk     (clk),
        .rst_n   (resetn),
        .stall   (D_stall),
        .flush   (FD_flush_final),
        .F_pc    (F_pc_r),
        .F_pc4   (F_pc_r_p4),
        .F_instr (fd_instr_in),
        .D_pc    (D_pc),
        .D_pc4   (D_pc_p4),
        .D_instr (D_instr)
    );

    // ============================================
    // DECODE STAGE
    // ============================================

    // this is the destination register address for writing back results to the RF,
    // which is needed in the hazard unit for forwarding and stalling decisions,
    // and also needed in the DE register to pass to later stages.
    assign D_rf_a3 = D_instr[11:7];

    Controller Controller (
        .clk             (clk),
        .instr           (D_instr),
        .Zero            (1'b0),
        .d_jump          (D_jump),
        .d_branch        (D_branch),
        .d_sel_result    (D_sel_result),
        .d_we_dm         (D_we_dm),
        .d_alu_control   (D_alu_control),
        .d_sel_alu_src_b (D_sel_alu_src_b),
        .d_we_rf         (D_we_rf),
        .imm_ext         (D_imm_ext)
    );

    RegisterFile RF (
        .clk        (clk),
        .rs1        (D_instr[19:15]),
        .rs2        (D_instr[24:20]),
        .rd         (W_rf_a3),
        .write_data (W_result),
        .reg_write  (W_we_rf),
        .read_data1 (D_rf_rd1),
        .read_data2 (D_rf_rd2)
    );

    // ============================================
    // PIPE: D -> E
    // ============================================

    // instantiate the DE pipeline register and connect all its signals as the
    // architecture states.
    DE_Register PLR2 (
        .clk              (clk),
        .rst_n            (resetn),
        .flush            (E_flush),
        .stall            (StallE),

        .D_pc             (D_pc),
        .D_rf_rd1         (D_rf_rd1),
        .D_rf_rd2         (D_rf_rd2),
        .D_ext            (D_imm_ext),
        .D_rf_a3          (D_rf_a3),
        .D_pc_p4          (D_pc_p4),
        .D_rs1            (D_instr[19:15]),
        .D_rs2            (D_instr[24:20]),

        .D_jump           (D_jump),
        .D_branch         (D_branch),
        .D_sel_result     (D_sel_result),
        .D_we_dm          (D_we_dm),
        .D_alu_control    (D_alu_control),
        .D_sel_alu_src_b  (D_sel_alu_src_b),
        .D_we_rf          (D_we_rf),

        .E_pc             (E_pc),
        .E_rf_rd1         (E_rf_rd1),
        .E_rf_rd2         (E_rf_rd2),
        .E_ext            (E_ext),
        .E_rf_a3          (E_rf_a3),
        .E_pc_p4          (E_pc_p4),
        .E_rs1            (E_rs1),
        .E_rs2            (E_rs2),

        .E_jump           (E_jump),
        .E_branch         (E_branch),
        .E_sel_result     (E_sel_result),
        .E_we_dm          (E_we_dm),
        .E_alu_control    (E_alu_control),
        .E_sel_alu_src_b  (E_sel_alu_src_b),
        .E_we_rf          (E_we_rf)
    );

    // ============================================
    // EXECUTE STAGE
    // ============================================

    // prepare the muxes for the forwarding logic in the E stage.
    // The Hazard Unit determines the control signals ForwardAE and ForwardBE to decide
    //  where the ALU sources get their data from.
    ThreeMux MuxA (
        .in0 (E_rf_rd1), .in1 (W_result), .in2 (M_alu_o),
        .sel (ForwardAE), .out (E_src_a_forwarded)
    );

    ThreeMux MuxB (
        .in0 (E_rf_rd2), .in1 (W_result), .in2 (M_alu_o),
        .sel (ForwardBE), .out (E_src_b_forwarded)
    );

    // branch adder to calculate the target address for branches and jumps.
    // This is used when PCSrcE = 1 to update the PC to the target address.
    Adder Branch_Adder (
        .a   (E_pc),
        .b   (E_ext),
        .sum (E_target_pc)
    );

    // the second ALU operand is either the forwarded value from the register file (after passing through MuxB) or
    //  the immediate value (after extension), depending on the instruction type!
    assign E_alu_src_b = (E_sel_alu_src_b) ? E_ext : E_src_b_forwarded;

    ALU ALU (
        .alu_control (E_alu_control),
        .operand_a   (E_src_a_forwarded),
        .operand_b   (E_alu_src_b),
        .alu_result  (E_alu_o),
        .zero        (E_zero)
    );

    // ============================================
    // PIPE: E -> M
    // ============================================

    EM_Register PLR3 (
        .clk (clk), .rst_n (resetn), .flush (1'b0), .stall (StallM),
        .E_alu_o (E_alu_o), .E_dm_wd (E_src_b_forwarded),
        .E_rf_a3 (E_rf_a3), .E_pc_p4 (E_pc_p4),
        .E_sel_result (E_sel_result), .E_we_dm (E_we_dm), .E_we_rf (E_we_rf),
        .M_alu_o (M_alu_o), .M_dm_wd (M_dm_wd),
        .M_rf_a3 (M_rf_a3), .M_pc_p4 (M_pc_p4),
        .M_sel_result (M_sel_result), .M_we_dm (M_we_dm), .M_we_rf (M_we_rf)
    );

    // ============================================
    // MEMORY STAGE
    // ============================================

    assign d_addr  = M_alu_o;
    assign d_wdata = M_dm_wd;

    // write M_we_dm to all 4 bits of d_we for word stores, or 0 for no store.
    // this is because the BRAM generator IP in vivado is configured for 32-bit data with 4-bit byte enables,
    // so we need to use the byte enables to control writes.
    assign d_we    = {4{M_we_dm}};
    assign M_dm_rd = d_rdata;

    // ============================================
    // PIPE: M -> W
    // ============================================

    MW_Register PLR4 (
        .clk (clk), .rst_n (resetn), .flush (1'b0), .stall (StallM),
        .M_dm_rd (M_dm_rd), .M_alu_o (M_alu_o),
        .M_rf_a3 (M_rf_a3), .M_pc_p4 (M_pc_p4),
        .M_sel_result (M_sel_result), .M_we_rf (M_we_rf),
        .W_dm_rd (W_dm_rd), .W_alu_o (W_alu_o),
        .W_rf_a3 (W_rf_a3), .W_pc_p4 (W_pc_p4),
        .W_sel_result (W_sel_result), .W_we_rf (W_we_rf)
    );

    // ============================================
    // WRITEBACK STAGE
    // ============================================

    // the value to write back to the RF in the W stage is determined by the control signal W_sel_result:
    // 00 = from ALU (R-type, I-type arithmetic), 01 = from Data Memory (loads),
    //  10 = from PC+4 (JAL, JALR), 00 = default 0 (NOP)
    assign W_result = (W_sel_result == 2'b00) ? W_alu_o :
                      (W_sel_result == 2'b01) ? W_dm_rd :
                      (W_sel_result == 2'b10) ? W_pc_p4 : 32'b0;

endmodule
