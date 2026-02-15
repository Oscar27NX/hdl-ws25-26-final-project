// The top-level module for my pipelined RISC-V processor. 
// Separated into stages for much clearer and readable design.
module rv_pl(
    input wire clk,
    input wire resetn,

    // Instruction Memory Interface (Connects to Instruction BRAM)
    output wire [31:0] i_addr,
    input wire [31:0]  i_instr,    // Data coming FROM BRAM
    
    // Data Memory Interface (Connects to Data BRAM)
    output wire [31:0] d_addr,
    output wire [31:0] d_wdata,
    output wire [3:0] d_we,
    input wire [31:0]  d_rdata     // Data coming FROM BRAM
);
    // Fetch
    wire [31:0] F_pc, F_pc_p4, F_instr, F_pc_next;

    // Decode
    wire [31:0] D_pc, D_pc_p4, D_instr, D_imm_ext;
    wire [31:0] D_rf_rd1, D_rf_rd2;
    wire [4:0]  D_rf_a3; 
    wire        D_jump, D_branch, D_we_dm, D_sel_alu_src_b, D_we_rf;
    wire [1:0]  D_sel_result;
    wire [3:0]  D_alu_control;
    wire        D_flush;

    // Execute
    wire [31:0] E_pc, E_pc_p4, E_rf_rd1, E_rf_rd2, E_ext;
    wire [31:0] E_alu_src_a, E_alu_src_b, E_alu_o, E_target_pc;
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

    // Hazard Control Signals
    // let the HU "peek" at these signals, so we can determine the hazard cases
    wire [1:0]  ForwardAE, ForwardBE;
    wire        PC_Src; 
    wire        hz_StallF, hz_StallD, hz_FlushE;
    reg         m_load_wait;
    wire        MemSyncStall;
    wire        F_stall_all, D_stall_all, E_stall_all;

    // ============================================
    // HAZARD UNIT set-up
    // ============================================
    
    HazardUnit HU (
        .Rs1E        (E_rs1),
        .Rs2E        (E_rs2),
        .RdM         (M_rf_a3),
        .RegWriteM   (M_we_rf),
        .ResultSrcM0 (M_sel_result[0]),
        .RdW         (W_rf_a3),
        .RegWriteW   (W_we_rf),
        
        .Rs1D        (D_instr[19:15]),
        .Rs2D        (D_instr[24:20]),
        .RdE         (E_rf_a3),
        .ResultSrcE0 (E_sel_result[0]), 
        .PCSrcE      (PC_Src),

        .ForwardAE   (ForwardAE),
        .ForwardBE   (ForwardBE),
        .StallF      (hz_StallF),
        .StallD      (hz_StallD),
        .FlushE      (hz_FlushE),
        .FlushD      (D_flush)
    );



    // One-cycle global hold for synchronous data-memory loads.
    // Keeps the load in M for one extra cycle so d_rdata is valid
    // before it is captured into the M/W register.
    always @(posedge clk) begin
        if (!resetn)
            m_load_wait <= 1'b0;
        else if ((M_sel_result === 2'b01) && !m_load_wait)
            m_load_wait <= 1'b1;
        else
            m_load_wait <= 1'b0;
    end

    // Sync-DMEM wait applies only for known loads and must not block
    // a taken branch/jump redirect generated in E this cycle.
    assign MemSyncStall = (M_sel_result === 2'b01) && !m_load_wait && (PC_Src !== 1'b1);
    assign F_stall_all  = hz_StallF || MemSyncStall;
    assign D_stall_all  = hz_StallD || MemSyncStall;
    assign E_stall_all  = MemSyncStall;
    assign E_flush      = hz_FlushE;

    // ============================================
    // FETCH STAGE
    // ============================================

    assign PC_Src = E_jump | (E_branch & E_zero);
    assign F_pc_next = (PC_Src) ? E_target_pc : F_pc_p4;

    ProgramCounter PC (
        .clk    (clk),
        .resetn    (resetn),
        .en     (!F_stall_all),
        .pc_in  (F_pc_next),
        .pc_out (F_pc)
    );

    Adder PC_Adder (
        .a      (F_pc),
        .b      (32'd4),
        .sum    (F_pc_p4)
    );

    assign i_addr = F_pc;
    // assign D_instr = i_instr;

    // ============================================
    // PIPE: F -> D
    // ============================================
    
    FD_register PLR1 (
        .clk     (clk),
        .rst_n   (resetn),
        .stall   (D_stall_all),
        .flush   (D_flush), 
        .F_pc    (F_pc),
        .F_pc4   (F_pc_p4),
        .F_instr (i_instr),
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
        .stall            (E_stall_all),
        .flush            (E_flush),
        
        .D_pc             (D_pc),
        .D_rf_rd1         (D_rf_rd1),
        .D_rf_rd2         (D_rf_rd2),
        .D_ext            (D_imm_ext),
        .D_rf_a3          (D_rf_a3),
        .D_pc_p4          (D_pc_p4),
        .D_rs1           (D_instr[19:15]),
        .D_rs2           (D_instr[24:20]),
        
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
        .E_rs1           (E_rs1),
        .E_rs2           (E_rs2),
        
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

    // 1. FORWARDING MUX A
    ThreeMux MuxA (
        .in0 (E_rf_rd1),
        .in1 (W_result),
        .in2 (M_alu_o),
        .sel  (ForwardAE),
        .out  (E_src_a_forwarded)
    );

    // 2. FORWARDING MUX B
    ThreeMux MuxB (
        .in0 (E_rf_rd2),
        .in1 (W_result),
        .in2 (M_alu_o),
        .sel  (ForwardBE),
        .out  (E_src_b_forwarded)
    );

    Adder Branch_Adder (
        .a      (E_pc), 
        .b      (E_ext),
        .sum    (E_target_pc)
    );

    // 3. ALU SRC B MUX (Immediate vs Forwarded B)
    assign E_alu_src_b = (E_sel_alu_src_b) ? E_ext : E_src_b_forwarded;

    ALU ALU (
        .alu_control (E_alu_control),
        // Operands come from forwarding Muxes
        .operand_a   (E_src_a_forwarded),
        .operand_b   (E_alu_src_b),
        .alu_result  (E_alu_o),
        .zero        (E_zero)
    );

    // ============================================
    // PIPE: E -> M
    // ============================================
    EM_Register PLR3 (
        .clk            (clk),
        .rst_n          (resetn),
        .stall          (E_stall_all),
        .flush          (1'b0),
        
        .E_alu_o        (E_alu_o),
        // Source depends on forwarding logic determined by 3-way Mux
        .E_dm_wd        (E_src_b_forwarded), 
        .E_rf_a3        (E_rf_a3),
        .E_pc_p4        (E_pc_p4),
        
        .E_sel_result   (E_sel_result),
        .E_we_dm        (E_we_dm),
        .E_we_rf        (E_we_rf),

        .M_alu_o        (M_alu_o),
        .M_dm_wd        (M_dm_wd),
        .M_rf_a3        (M_rf_a3),
        .M_pc_p4        (M_pc_p4),
        
        .M_sel_result   (M_sel_result),
        .M_we_dm        (M_we_dm),
        .M_we_rf        (M_we_rf)
    );

    // ============================================
    // MEMORY STAGE
    // ============================================

    assign d_addr = M_alu_o;
    assign d_wdata = M_dm_wd;
    // write the bit en signal for annoying vivado 
    assign d_we = {4{M_we_dm}};

    assign M_dm_rd = d_rdata;
    // W_dm_rd comes from MW pipeline register, NOT directly from BRAM
    // ============================================
    // PIPE: M -> W
    // ============================================
    MW_Register PLR4 (
        .clk            (clk),
        .rst_n          (resetn),
        .stall          (E_stall_all),
        .flush          (1'b0),
        
        .M_dm_rd        (M_dm_rd),
        .M_alu_o        (M_alu_o),
        .M_rf_a3        (M_rf_a3),
        .M_pc_p4        (M_pc_p4),
        
        .M_sel_result   (M_sel_result),
        .M_we_rf        (M_we_rf),

        .W_dm_rd        (W_dm_rd),  
        .W_alu_o        (W_alu_o),
        .W_rf_a3        (W_rf_a3),
        .W_pc_p4        (W_pc_p4),
        
        .W_sel_result   (W_sel_result),
        .W_we_rf        (W_we_rf)
    );

    // ============================================
    // WRITEBACK STAGE
    // ============================================

    assign W_result = (W_sel_result == 2'b00) ? W_alu_o :
                      (W_sel_result == 2'b01) ? W_dm_rd :
                      (W_sel_result == 2'b10) ? W_pc_p4 : 32'b0;

endmodule
