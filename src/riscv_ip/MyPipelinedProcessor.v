// Pipelined RISC-V processor for FPGA BRAM deployment
// Fixes:
//   1. IRAM 1-cycle latency: F_pc_r aligns PC with BRAM instruction output
//   2. DRAM 1-cycle latency: bramStall in HazardUnit holds pipeline for loads
//   3. 2-cycle branch flush: accounts for BRAM fetch delay after PC redirect
module rv_pl(
    input wire clk,
    input wire resetn,

    // Instruction Memory Interface (BRAM Port B - read only)
    output wire [31:0] i_addr,
    input wire [31:0]  i_instr,

    // Data Memory Interface (BRAM Port B - read/write)
    output wire [31:0] d_addr,
    output wire [31:0] d_wdata,
    output wire [3:0] d_we,
    input wire [31:0]  d_rdata
);

    // ============================================
    // WIRE DECLARATIONS
    // ============================================

    // Fetch
    wire [31:0] F_pc, F_pc_p4, F_pc_next;
    wire        F_stall;

    // Fetch-aligned PC (delayed 1 cycle to match BRAM output)
    reg  [31:0] F_pc_r;
    wire [31:0] F_pc_r_p4;

    // Decode
    wire [31:0] D_pc, D_pc_p4, D_instr, D_imm_ext;
    wire [31:0] D_rf_rd1, D_rf_rd2;
    wire [4:0]  D_rf_a3;
    wire        D_jump, D_branch, D_we_dm, D_sel_alu_src_b, D_we_rf;
    wire [1:0]  D_sel_result;
    wire [3:0]  D_alu_control;
    wire        D_stall, D_flush;

    // Execute
    wire [31:0] E_pc, E_pc_p4, E_rf_rd1, E_rf_rd2, E_ext;
    wire [31:0] E_alu_src_b, E_alu_o, E_target_pc;
    wire [31:0] E_src_a_forwarded, E_src_b_forwarded;
    wire [4:0]  E_rf_a3, E_rs1, E_rs2;
    wire        E_jump, E_branch, E_we_dm, E_sel_alu_src_b, E_we_rf;
    wire [1:0]  E_sel_result;
    wire [3:0]  E_alu_control;
    wire        E_zero, E_flush;

    // Memory
    wire [31:0] M_pc_p4, M_alu_o, M_dm_wd, M_dm_rd;
    wire [4:0]  M_rf_a3;
    wire        M_we_dm, M_we_rf;
    wire [1:0]  M_sel_result;

    // Writeback
    wire [31:0] W_pc_p4, W_alu_o, W_dm_rd, W_result;
    wire [4:0]  W_rf_a3;
    wire        W_we_rf;
    wire [1:0]  W_sel_result;

    // Hazard signals
    wire [1:0]  ForwardAE, ForwardBE;
    wire        PC_Src;
    wire        StallE, StallM;
    wire        MemReadM;

    assign MemReadM = (M_sel_result == 2'b01);

    // ============================================
    // IRAM LATENCY FIX: F_pc_r
    // ============================================
    // BRAM latches i_addr at posedge and outputs data AFTER the edge.
    // F_pc_r is a registered copy of F_pc, so it's aligned with i_instr.
    // FD register receives (F_pc_r, fd_instr_in) = correctly paired.
    always @(posedge clk) begin
        if (!resetn)
            F_pc_r <= 32'b0;
        else if (!F_stall)
            F_pc_r <= F_pc;
    end

    // ============================================
    // INSTRUCTION BUFFER (fixes BRAM corruption during stalls)
    // ============================================
    // Problem: During stalls, BRAM address register (external) keeps
    // latching F_pc, overwriting the correct instruction. When stall
    // releases, BRAM outputs wrong instruction.
    // Fix: On first cycle of stall, i_instr is still valid (BRAM hasn't
    // re-latched yet due to NBA semantics). Save it in a buffer.
    // Use buffer when stall releases.
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

    assign i_addr = F_pc;

    // ============================================
    // PIPE: F -> D
    // ============================================
    // Uses F_pc_r (aligned with BRAM output) instead of F_pc

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

    ThreeMux MuxA (
        .in0 (E_rf_rd1), .in1 (W_result), .in2 (M_alu_o),
        .sel (ForwardAE), .out (E_src_a_forwarded)
    );

    ThreeMux MuxB (
        .in0 (E_rf_rd2), .in1 (W_result), .in2 (M_alu_o),
        .sel (ForwardBE), .out (E_src_b_forwarded)
    );

    Adder Branch_Adder (
        .a   (E_pc),
        .b   (E_ext),
        .sum (E_target_pc)
    );

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

    assign W_result = (W_sel_result == 2'b00) ? W_alu_o :
                      (W_sel_result == 2'b01) ? W_dm_rd :
                      (W_sel_result == 2'b10) ? W_pc_p4 : 32'b0;

endmodule
