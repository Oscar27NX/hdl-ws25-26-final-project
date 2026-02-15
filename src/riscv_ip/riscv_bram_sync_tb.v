`timescale 1ns / 1ps

module tb_sort_32_sync;
    // Clock and reset
    reg clk, resetn;
    
    // Processor interface
    wire [31:0] i_addr, i_instr;
    wire [31:0] d_addr, d_wdata, d_rdata;
    wire [3:0] d_we;
    
    // Internal memories
    reg [31:0] imem [0:20479];  // Large enough for 17K+ instructions
    reg [31:0] dmem [0:2047];
    
    // Registers for Synchronous Memory Output
    reg [31:0] i_instr_reg;
    reg [31:0] d_rdata_reg; // registered data output from DMEM
    
    // Debug/temp variables (must be declared at module scope for Verilog)
    integer dbg_idx;
    reg [31:0] dbg_addr_word;
    integer trace_count;
    integer i, cycle, errors;
    reg signed [31:0] expected [0:31];
    reg signed [31:0] input_data [0:31];

    // Instantiate processor
    rv_pl dut (
        .clk(clk),
        .resetn(resetn),
        .i_addr(i_addr),
        .i_instr(i_instr),
        .d_addr(d_addr),
        .d_wdata(d_wdata),
        .d_we(d_we),
        .d_rdata(d_rdata)
    );
    
    // Clock generation: 100 MHz
    initial begin 
        clk = 0; 
        forever #5 clk = ~clk; 
    end

    // Reset/trace init
    initial begin
        resetn = 0;
        trace_count = 0;
        #100;
    end
    
        // Put this in tb_sort_32_sync (testbench file), after instantiation of 'dut'
    always @(posedge clk) begin
        if (resetn) begin
            // Print only when a store is requested or for first N cycles to limit noise
            if (dut.M_we_dm || ($time/10 < 200)) begin
                $display("TB-DBG: cycle=%0t E_rf_rd2=%08h E_src_b_forwarded=%08h ForwardBE=%b M_alu_o=%08h W_result=%08h M_we_dm=%b",
                         $time/10,
                         dut.E_rf_rd2,
                         dut.E_src_b_forwarded,
                         dut.ForwardBE,
                         dut.M_alu_o,
                         dut.W_result,
                         dut.M_we_dm);
                $display("TB-DBG-IDS: RdM=%0d RegWriteM=%b RdW=%0d RegWriteW=%b Rs2E=%0d Rs2D=%0d RdE=%0d",
                         dut.M_rf_a3, dut.M_we_rf, dut.W_rf_a3, dut.W_we_rf,
                         dut.E_rs2, dut.D_instr[24:20], dut.E_rf_a3);
            end
        end
    end
    
    // ========================================================================
    // MEMORY MODELS (MATCHING PYNQ HARDWARE LATENCY)
    // ========================================================================

    // 1. Instruction Memory (Synchronous Read - 1 Cycle Latency)
    always @(posedge clk)
        i_instr_reg <= resetn ? imem[i_addr[31:2]] : 32'h00000013;
    assign i_instr = i_instr_reg;
    
    // small instruction fetch/trace helper for early sanity-check
    always @(posedge clk) begin
        if (resetn && (trace_count < 64)) begin
            $display("TRACE IFETCH: cycle %0d i_addr=0x%08h instr=0x%08h",
                      $time/10, i_addr, i_instr);
            trace_count = trace_count + 1;
        end
    end

    // --------------------------------------------------------------------
    // 2. Data Memory (Synchronous Read - 1 Cycle Latency) -- DEBUG VERSION
    // --------------------------------------------------------------------
    // Behavior: emulate WRITE-FIRST BRAM semantics used on many Xilinx parts:
    //   - on posedge: perform writes (blocking) then register read
    //   - subsequent cycle d_rdata will present the selected word
    //
    // Additional: print every store + print d_rdata each cycle for debugging.
    // --------------------------------------------------------------------
    always @(posedge clk) begin
        if (!resetn) begin
            d_rdata_reg <= 32'b0;
        end else begin
            // capture address/index in temporaries (stable for prints)
            dbg_idx = d_addr[31:2];
            dbg_addr_word = d_addr;

            // ---- Writes FIRST (blocking assignments give write-first semantics)
            if (d_we[0]) dmem[dbg_idx][7:0]   = d_wdata[7:0];
            if (d_we[1]) dmem[dbg_idx][15:8]  = d_wdata[15:8];
            if (d_we[2]) dmem[dbg_idx][23:16] = d_wdata[23:16];
            if (d_we[3]) dmem[dbg_idx][31:24] = d_wdata[31:24];

            // ---- Log any store (show full word when any byte lane enabled)
            if (d_we !== 4'b0000) begin
                $display("SIM: STORE at cycle %0d: addr=0x%08h index=%0d we=%b data=0x%08h (%0d)",
                         $time/10, dbg_addr_word, dbg_idx, d_we, d_wdata, $signed(d_wdata));
                $display("      MEM[%0d] after store = 0x%08h (%0d)", dbg_idx, dmem[dbg_idx], $signed(dmem[dbg_idx]));
            end
            
            $display("DBG: dut.M_alu_o=%08h dut.M_dm_wd=%08h dut.M_we_dm=%b dut.W_result=%08h",
            dut.M_alu_o, dut.M_dm_wd, dut.M_we_dm, dut.W_result);


            // Optional tiny scheduling delay if needed (uncomment to mimic your #1 hack)
            // #1;

            // ---- Then registered read (value available to dut on next cycle)
            d_rdata_reg <= dmem[d_addr[31:2]];

            // ---- Print the read value that will be fed back to CPU next cycle
            $display("SIM: READ  at cycle %0d: addr=0x%08h index=%0d returning=0x%08h (%0d)",
                     $time/10, d_addr, d_addr[31:2], dmem[d_addr[31:2]], $signed(dmem[d_addr[31:2]]));
        end
    end

    assign d_rdata = d_rdata_reg;
    
    // ========================================================================
    // TEST VECTOR SETUP & RUN
    // ========================================================================
    initial begin
        $display("================================================================");
        $display("  RISC-V SYNC MEMORY TEST (Replicates PYNQ Hardware)");
        $display("================================================================");
        
        // Initialize all memory
        for (i = 0; i < 2048; i = i + 1) 
            dmem[i] = 0;
        
        // Generate test data
        input_data[0]  = 32'sd45;   input_data[1]  = -32'sd12;
        input_data[2]  = 32'sd78;   input_data[3]  = 32'sd3;
        input_data[4]  = -32'sd56;  input_data[5]  = 32'sd89;
        input_data[6]  = 32'sd23;   input_data[7]  = -32'sd7;
        input_data[8]  = 32'sd67;   input_data[9]  = 32'sd12;
        input_data[10] = -32'sd34;  input_data[11] = 32'sd90;
        input_data[12] = 32'sd5;    input_data[13] = -32'sd78;
        input_data[14] = 32'sd34;   input_data[15] = 32'sd56;
        input_data[16] = -32'sd23;  input_data[17] = 32'sd67;
        input_data[18] = 32'sd11;   input_data[19] = -32'sd45;
        input_data[20] = 32'sd88;   input_data[21] = 32'sd22;
        input_data[22] = -32'sd67;  input_data[23] = 32'sd44;
        input_data[24] = 32'sd33;   input_data[25] = -32'sd11;
        input_data[26] = 32'sd99;   input_data[27] = 32'sd6;
        input_data[28] = -32'sd88;  input_data[29] = 32'sd77;
        input_data[30] = 32'sd2;    input_data[31] = -32'sd99;
        
        // Load input data
        for (i = 0; i < 32; i = i + 1)
            dmem[i] = input_data[i];
        
        // Expected output (Sorted)
        expected[0]  = -32'sd99; expected[1]  = -32'sd88;
        expected[2]  = -32'sd78; expected[3]  = -32'sd67;
        expected[4]  = -32'sd56; expected[5]  = -32'sd45;
        expected[6]  = -32'sd34; expected[7]  = -32'sd23;
        expected[8]  = -32'sd12; expected[9]  = -32'sd11;
        expected[10] = -32'sd7;  expected[11] = 32'sd2;
        expected[12] = 32'sd3;   expected[13] = 32'sd5;
        expected[14] = 32'sd6;   expected[15] = 32'sd11;
        expected[16] = 32'sd12;  expected[17] = 32'sd22;
        expected[18] = 32'sd23;  expected[19] = 32'sd33;
        expected[20] = 32'sd34;  expected[21] = 32'sd44;
        expected[22] = 32'sd45;  expected[23] = 32'sd56;
        expected[24] = 32'sd67;  expected[25] = 32'sd67;
        expected[26] = 32'sd77;  expected[27] = 32'sd78;
        expected[28] = 32'sd88;  expected[29] = 32'sd89;
        expected[30] = 32'sd90;  expected[31] = 32'sd99;
        
        // Load program (Update path as needed)
        $display("\nLoading program...");
        resetn = 0;
        // UPDATE THIS PATH TO YOUR FILE
        $readmemh("C:/Users/oscar/vivado_tutorial/riscv_pynq_final/sort_32_bubble.hex", imem);
        
        #100;
        resetn = 1;
        cycle = 0;
        
        // Wait for completion
        while (dmem[64] !== 32'hDEADBEAF && cycle < 200000) begin
            @(posedge clk);
            cycle = cycle + 1;
            if (cycle % 50000 == 0) $display("... %0d cycles", cycle);
        end
        
        repeat(10) @(posedge clk);
        
        // Results
        $display("\nResult Check:");
        if (dmem[64] == 32'hDEADBEAF) $display("SUCCESS: Completion Flag Set");
        else $display("FAILURE: Timed out (Flag not set)");
        
        errors = 0;
        for (i = 0; i < 32; i = i + 1) begin
            if (dmem[i] !== expected[i]) begin
                $display("ERROR [%0d]: Expected %d, Got %d", i, expected[i], $signed(dmem[i]));
                errors = errors + 1;
            end
        end
        
        if (errors == 0 && dmem[64] == 32'hDEADBEAF)
            $display("\n*** ALL TESTS PASSED WITH SYNC MEMORY ***");
        else
            $display("\n*** TEST FAILED ***");
        
        // -------------------------
        // FINAL MEMORY DUMP (addresses written by the core)
        // -------------------------
        $display("\nFinal Memory Dump (first 32 words):");
        $display("Index  Addr(hex)   Value(signed)   Value(hex)");
        for (i = 0; i < 32; i = i + 1) begin
            $display("%2d     0x%08h   %12d     0x%08h", i, i*4, $signed(dmem[i]), dmem[i]);
        end

        // show completion flag address 0x100 (index 64)
        $display("\nCompletion flag at 0x100 (index 64): 0x%08h (%0d)", dmem[64], dmem[64]);
        
        $finish;
    end
endmodule
