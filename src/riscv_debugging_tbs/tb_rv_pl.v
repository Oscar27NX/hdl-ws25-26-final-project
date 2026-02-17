// Testbench for pipelined RISC-V with SYNCHRONOUS BRAM models
// Models real FPGA BRAM behavior: we have 1-cycle read latency!
`timescale 1ns/1ps

module tb_rv_pl;
    // Manually drive clock and reset
    reg clk, resetn;
    
    // Instruction BRAM interface
    wire [31:0] i_addr;
    reg  [31:0] i_instr;
    
    // Data BRAM interface
    wire [31:0] d_addr;
    wire [31:0] d_wdata;
    wire [3:0]  d_we;
    reg  [31:0] d_rdata;
    
    // Instantiate the DUT
    rv_pl DUT (
        .clk     (clk),
        .resetn  (resetn),
        .i_addr  (i_addr),
        .i_instr (i_instr),
        .d_addr  (d_addr),
        .d_wdata (d_wdata),
        .d_we    (d_we),
        .d_rdata (d_rdata)
    );
    
    // Clock: 10ns period
    initial clk = 0;
    always #5 clk = ~clk;
    
    // =========================================================
    // SYNCHRONOUS INSTRUCTION BRAM (1-cycle read latency)
    // Address latched on posedge, data available after
    // =========================================================
    reg [31:0] IRAM [0:4095];
    reg [31:0] i_addr_reg;
    
    always @(posedge clk) begin
        i_addr_reg <= i_addr;
    end
    assign i_instr_sync = IRAM[i_addr_reg[13:2]];
    
    // Use a synchronous model
    always @(*) begin
        i_instr = IRAM[i_addr_reg[13:2]];
    end
    
    // =========================================================
    // SYNCHRONOUS DATA BRAM (1-cycle read latency & sync write)
    // =========================================================
    reg [31:0] DRAM [0:4095];
    reg [31:0] d_addr_reg;
    
    always @(posedge clk) begin
        d_addr_reg <= d_addr;
        if (d_we == 4'b1111) begin
            DRAM[d_addr[13:2]] <= d_wdata;
        end
    end
    
    always @(*) begin
        d_rdata = DRAM[d_addr_reg[13:2]];
    end
    
    // =========================================================
    // TEST INFRASTRUCTURE
    // =========================================================
    integer i, errors, test_num;
    integer cycle_count;
    reg [31:0] expected;
    
    task reset_cpu;
        begin
            resetn = 0;
            @(posedge clk);
            @(posedge clk);
            resetn = 1;
        end
    endtask
    
    task clear_mem;
        begin
            for (i = 0; i < 4096; i = i + 1) begin
                IRAM[i] = 32'h00000013; // NOP
                DRAM[i] = 32'h00000000;
            end
        end
    endtask
    
    task run_and_wait;
        input integer max_cycles;
        input [31:0] done_addr;
        input [31:0] done_value;
        begin
            cycle_count = 0;
            while (cycle_count < max_cycles) begin
                @(posedge clk);
                cycle_count = cycle_count + 1;
                if (DRAM[done_addr[13:2]] == done_value) begin
                    // Wait a few more cycles for pipeline to drain
                    repeat(5) @(posedge clk);
                    cycle_count = cycle_count + 5;
                    disable run_and_wait;
                end
            end
        end
    endtask
    
    // =========================================================
    // TESTS
    // =========================================================
    initial begin
        $dumpfile("tb_rv_pl.vcd");
        $dumpvars(0, tb_rv_pl);
        
        test_num = 0;
        
        // =======================================================
        // TEST 1: Basic store (no loads needed)
        // addi x1, x0, 42   -> x1 = 42
        // sw   x1, 0(x0)    -> DRAM[0] = 42
        // addi x2, x0, 7    -> x2 = 7
        // sw   x2, 4(x0)    -> DRAM[1] = 7
        // beq  x0, x0, 0    -> loop
        // =======================================================
        test_num = 1;
        $display("\n=== TEST %0d: Basic stores ===", test_num);
        clear_mem;
        IRAM[0] = 32'h02A00093; // addi x1, x0, 42
        IRAM[1] = 32'h00102023; // sw   x1, 0(x0)
        IRAM[2] = 32'h00700113; // addi x2, x0, 7
        IRAM[3] = 32'h00202223; // sw   x2, 4(x0)
        IRAM[4] = 32'h00000063; // beq  x0, x0, 0
        
        reset_cpu;
        repeat(30) @(posedge clk);
        
        errors = 0;
        if (DRAM[0] !== 32'd42) begin $display("FAIL: DRAM[0]=%0d expected 42", DRAM[0]); errors = errors+1; end
        if (DRAM[1] !== 32'd7)  begin $display("FAIL: DRAM[1]=%0d expected 7", DRAM[1]); errors = errors+1; end
        if (errors == 0) $display("PASS"); else $display("FAILED with %0d errors", errors);
        
        // =======================================================
        // TEST 2: Store then Load (THE critical BRAM test)
        // addi x1, x0, 99   -> x1 = 99
        // sw   x1, 0(x0)    -> DRAM[0] = 99
        // nop (x5)
        // nop
        // nop
        // nop
        // nop
        // lw   x2, 0(x0)    -> x2 should be 99
        // nop (x5)
        // nop
        // nop
        // nop
        // nop
        // sw   x2, 4(x0)    -> DRAM[1] = x2 (should be 99)
        // beq  x0, x0, 0
        // =======================================================
        test_num = 2;
        $display("\n=== TEST %0d: Store then Load (with NOPs) ===", test_num);
        clear_mem;
        IRAM[0]  = 32'h06300093; // addi x1, x0, 99
        IRAM[1]  = 32'h00102023; // sw   x1, 0(x0)
        IRAM[2]  = 32'h00000013; // nop
        IRAM[3]  = 32'h00000013; // nop
        IRAM[4]  = 32'h00000013; // nop
        IRAM[5]  = 32'h00000013; // nop
        IRAM[6]  = 32'h00000013; // nop
        IRAM[7]  = 32'h00002103; // lw   x2, 0(x0)
        IRAM[8]  = 32'h00000013; // nop
        IRAM[9]  = 32'h00000013; // nop
        IRAM[10] = 32'h00000013; // nop
        IRAM[11] = 32'h00000013; // nop
        IRAM[12] = 32'h00000013; // nop
        IRAM[13] = 32'h00202223; // sw   x2, 4(x0)
        IRAM[14] = 32'h00000063; // beq  x0, x0, 0
        
        reset_cpu;
        repeat(50) @(posedge clk);
        
        errors = 0;
        if (DRAM[0] !== 32'd99) begin $display("FAIL: DRAM[0]=%0d expected 99", DRAM[0]); errors = errors+1; end
        if (DRAM[1] !== 32'd99) begin $display("FAIL: DRAM[1]=%0d expected 99 (loaded value)", DRAM[1]); errors = errors+1; end
        if (errors == 0) $display("PASS"); else $display("FAILED with %0d errors", errors);
        
        // =======================================================
        // TEST 3: Load immediately used (load-use + BRAM stall)
        // addi x1, x0, 55   -> x1 = 55
        // sw   x1, 0(x0)    -> DRAM[0] = 55
        // nop x5
        // nop
        // nop
        // nop
        // nop
        // lw   x2, 0(x0)    -> x2 = 55
        // addi x3, x2, 10   -> x3 = 65 (load-use hazard!)
        // nop x5
        // nop
        // nop
        // nop
        // sw   x3, 4(x0)    -> DRAM[1] = 65
        // beq  x0, x0, 0
        // =======================================================
        test_num = 3;
        $display("\n=== TEST %0d: Load-use hazard ===", test_num);
        clear_mem;
        IRAM[0]  = 32'h03700093; // addi x1, x0, 55
        IRAM[1]  = 32'h00102023; // sw   x1, 0(x0)
        IRAM[2]  = 32'h00000013; // nop
        IRAM[3]  = 32'h00000013; // nop
        IRAM[4]  = 32'h00000013; // nop
        IRAM[5]  = 32'h00000013; // nop
        IRAM[6]  = 32'h00000013; // nop
        IRAM[7]  = 32'h00002103; // lw   x2, 0(x0)
        IRAM[8]  = 32'h00A10193; // addi x3, x2, 10  (load-use!)
        IRAM[9]  = 32'h00000013; // nop
        IRAM[10] = 32'h00000013; // nop
        IRAM[11] = 32'h00000013; // nop
        IRAM[12] = 32'h00000013; // nop
        IRAM[13] = 32'h00302223; // sw   x3, 4(x0)
        IRAM[14] = 32'h00000063; // beq  x0, x0, 0
        
        reset_cpu;
        repeat(50) @(posedge clk);
        
        errors = 0;
        if (DRAM[0] !== 32'd55) begin $display("FAIL: DRAM[0]=%0d expected 55", DRAM[0]); errors = errors+1; end
        if (DRAM[1] !== 32'd65) begin $display("FAIL: DRAM[1]=%0d expected 65", DRAM[1]); errors = errors+1; end
        if (errors == 0) $display("PASS"); else $display("FAILED with %0d errors", errors);
        
        // =======================================================
        // TEST 4: Two consecutive loads
        // addi x1, x0, 10   -> x1 = 10
        // addi x2, x0, 20   -> x2 = 20
        // sw   x1, 0(x0)    -> DRAM[0] = 10
        // sw   x2, 4(x0)    -> DRAM[1] = 20
        // nop x5
        // nop
        // nop
        // nop
        // nop
        // lw   x3, 0(x0)    -> x3 = 10
        // lw   x4, 4(x0)    -> x4 = 20
        // add  x5, x3, x4   -> x5 = 30
        // nop x5
        // nop
        // nop
        // nop
        // sw   x5, 8(x0)    -> DRAM[2] = 30
        // beq  x0, x0, 0
        // =======================================================
        test_num = 4;
        $display("\n=== TEST %0d: Two consecutive loads + add ===", test_num);
        clear_mem;
        IRAM[0]  = 32'h00A00093; // addi x1, x0, 10
        IRAM[1]  = 32'h01400113; // addi x2, x0, 20
        IRAM[2]  = 32'h00102023; // sw   x1, 0(x0)
        IRAM[3]  = 32'h00202223; // sw   x2, 4(x0)
        IRAM[4]  = 32'h00000013; // nop
        IRAM[5]  = 32'h00000013; // nop
        IRAM[6]  = 32'h00000013; // nop
        IRAM[7]  = 32'h00000013; // nop
        IRAM[8]  = 32'h00000013; // nop
        IRAM[9]  = 32'h00002183; // lw   x3, 0(x0)
        IRAM[10] = 32'h00402203; // lw   x4, 4(x0)
        IRAM[11] = 32'h004182B3; // add  x5, x3, x4
        IRAM[12] = 32'h00000013; // nop
        IRAM[13] = 32'h00000013; // nop
        IRAM[14] = 32'h00000013; // nop
        IRAM[15] = 32'h00000013; // nop
        IRAM[16] = 32'h00502423; // sw   x5, 8(x0)
        IRAM[17] = 32'h00000063; // beq  x0, x0, 0
        
        reset_cpu;
        repeat(60) @(posedge clk);
        
        errors = 0;
        if (DRAM[0] !== 32'd10) begin $display("FAIL: DRAM[0]=%0d expected 10", DRAM[0]); errors = errors+1; end
        if (DRAM[1] !== 32'd20) begin $display("FAIL: DRAM[1]=%0d expected 20", DRAM[1]); errors = errors+1; end
        if (DRAM[2] !== 32'd30) begin $display("FAIL: DRAM[2]=%0d expected 30", DRAM[2]); errors = errors+1; end
        if (errors == 0) $display("PASS"); else $display("FAILED with %0d errors", errors);
        
        // =======================================================
        // TEST 5: Branch test
        // addi x1, x0, 5
        // addi x2, x0, 5
        // beq  x1, x2, +8   -> should branch (skip next instr)
        // addi x3, x0, 111  -> SKIPPED
        // addi x3, x0, 222  -> x3 = 222
        // nop x4
        // nop
        // nop
        // nop
        // sw   x3, 0(x0)    -> DRAM[0] = 222
        // beq  x0, x0, 0
        // =======================================================
        test_num = 5;
        $display("\n=== TEST %0d: Branch taken ===", test_num);
        clear_mem;
        IRAM[0]  = 32'h00500093; // addi x1, x0, 5
        IRAM[1]  = 32'h00500113; // addi x2, x0, 5
        IRAM[2]  = 32'h00208463; // beq  x1, x2, +8
        IRAM[3]  = 32'h06F00193; // addi x3, x0, 111  (should be skipped)
        IRAM[4]  = 32'h0DE00193; // addi x3, x0, 222
        IRAM[5]  = 32'h00000013; // nop
        IRAM[6]  = 32'h00000013; // nop
        IRAM[7]  = 32'h00000013; // nop
        IRAM[8]  = 32'h00000013; // nop
        IRAM[9]  = 32'h00302023; // sw   x3, 0(x0)
        IRAM[10] = 32'h00000063; // beq  x0, x0, 0
        
        reset_cpu;
        repeat(40) @(posedge clk);
        
        errors = 0;
        if (DRAM[0] !== 32'd222) begin $display("FAIL: DRAM[0]=%0d expected 222", DRAM[0]); errors = errors+1; end
        if (errors == 0) $display("PASS"); else $display("FAILED with %0d errors", errors);
        
        // =======================================================
        // TEST 6: Mini bubble sort (4 elements)
        // Sort [4, 1, 3, 2] -> [1, 2, 3, 4]
        // Uses same algorithm as the full 32-element sort
        // =======================================================
        test_num = 6;
        $display("\n=== TEST %0d: Mini bubble sort (4 elements) ===", test_num);
        clear_mem;
        // Pre-load data into DRAM
        DRAM[0] = 32'd4;
        DRAM[1] = 32'd1;
        DRAM[2] = 32'd3;
        DRAM[3] = 32'd2;
        // Status flag at word 64 (byte 0x100)
        DRAM[64] = 32'h00000000;
        
        // Load the sort program from hex file
        $readmemh("sort_mini.hex", IRAM);
        
        reset_cpu;
        run_and_wait(2000, 32'h100, 32'hDEADBEAF);
        
        errors = 0;
        if (DRAM[0] !== 32'd1) begin $display("FAIL: DRAM[0]=%0d expected 1", DRAM[0]); errors = errors+1; end
        if (DRAM[1] !== 32'd2) begin $display("FAIL: DRAM[1]=%0d expected 2", DRAM[1]); errors = errors+1; end
        if (DRAM[2] !== 32'd3) begin $display("FAIL: DRAM[2]=%0d expected 3", DRAM[2]); errors = errors+1; end
        if (DRAM[3] !== 32'd4) begin $display("FAIL: DRAM[3]=%0d expected 4", DRAM[3]); errors = errors+1; end
        if (DRAM[64] !== 32'hDEADBEAF) begin $display("FAIL: status=%08X expected DEADBEAF", DRAM[64]); errors = errors+1; end
        if (errors == 0) $display("PASS (sorted in %0d cycles)", cycle_count); 
        else $display("FAILED with %0d errors", errors);
        
        // =======================================================
        // TEST 7: Full 32-element bubble sort
        // =======================================================
        test_num = 7;
        $display("\n=== TEST %0d: Full 32-element bubble sort ===", test_num);
        clear_mem;
        // Load test data (same as Python notebook)
        DRAM[0]  = 32'h0000002D; // 45
        DRAM[1]  = 32'hFFFFFFF4; // -12
        DRAM[2]  = 32'h0000004E; // 78
        DRAM[3]  = 32'h00000003; // 3
        DRAM[4]  = 32'hFFFFFFC8; // -56
        DRAM[5]  = 32'h00000059; // 89
        DRAM[6]  = 32'h00000017; // 23
        DRAM[7]  = 32'hFFFFFFF9; // -7
        DRAM[8]  = 32'h00000043; // 67
        DRAM[9]  = 32'h0000000C; // 12
        DRAM[10] = 32'hFFFFFFDE; // -34
        DRAM[11] = 32'h0000005A; // 90
        DRAM[12] = 32'h00000005; // 5
        DRAM[13] = 32'hFFFFFFB2; // -78
        DRAM[14] = 32'h00000022; // 34
        DRAM[15] = 32'h00000038; // 56
        DRAM[16] = 32'hFFFFFFE9; // -23
        DRAM[17] = 32'h00000043; // 67
        DRAM[18] = 32'h0000000B; // 11
        DRAM[19] = 32'hFFFFFFD3; // -45
        DRAM[20] = 32'h00000058; // 88
        DRAM[21] = 32'h00000016; // 22
        DRAM[22] = 32'hFFFFFFBD; // -67
        DRAM[23] = 32'h0000002C; // 44
        DRAM[24] = 32'h00000021; // 33
        DRAM[25] = 32'hFFFFFFF5; // -11
        DRAM[26] = 32'h00000063; // 99
        DRAM[27] = 32'h00000006; // 6
        DRAM[28] = 32'hFFFFFFA8; // -88
        DRAM[29] = 32'h0000004D; // 77
        DRAM[30] = 32'h00000002; // 2
        DRAM[31] = 32'hFFFFFF9D; // -99
        DRAM[64] = 32'h00000000; // status flag
        
        $readmemh("sort_32_bubble.hex", IRAM);
        
        reset_cpu;
        run_and_wait(100000, 32'h100, 32'hDEADBEAF);
        
        $display("Completed in %0d cycles. Status=0x%08X", cycle_count, DRAM[64]);
        
        // Expected sorted: -99 -88 -78 -67 -56 -45 -34 -23 -12 -11 -7 2 3 5 6 11
        //                    12  22  23  33  34  44  45  56  67  67 77 78 88 89 90 99
        errors = 0;
        // Check first few and last few
        if (DRAM[0]  !== 32'hFFFFFF9D) begin $display("FAIL: [0]=%08X expected FFFFFF9D (-99)", DRAM[0]); errors=errors+1; end
        if (DRAM[1]  !== 32'hFFFFFFA8) begin $display("FAIL: [1]=%08X expected FFFFFFA8 (-88)", DRAM[1]); errors=errors+1; end
        if (DRAM[31] !== 32'h00000063) begin $display("FAIL: [31]=%08X expected 00000063 (99)", DRAM[31]); errors=errors+1; end
        if (DRAM[64] !== 32'hDEADBEAF) begin $display("FAIL: status=%08X expected DEADBEAF", DRAM[64]); errors=errors+1; end
        
        // Full check
        begin : full_check
            reg signed [31:0] prev, curr;
            integer j;
            prev = DRAM[0];
            if (prev[31]) prev = prev | 32'hFFFFFFFF << 32; // sign extend not needed for 32b
            for (j = 1; j < 32; j = j + 1) begin
                curr = DRAM[j];
                if ($signed(curr) < $signed(prev)) begin
                    $display("FAIL: [%0d]=%0d < [%0d]=%0d (not sorted)", j, $signed(curr), j-1, $signed(prev));
                    errors = errors + 1;
                end
                prev = curr;
            end
        end
        
        if (errors == 0) $display("PASS (sorted in %0d cycles)", cycle_count);
        else $display("FAILED with %0d errors", errors);
        
        // Print sorted array
        $display("Sorted output:");
        for (i = 0; i < 32; i = i + 1) begin
            $display("  [%2d] = %0d", i, $signed(DRAM[i]));
        end
        
        $display("\n=== ALL TESTS COMPLETE ===");
        $finish;
    end
    
    // Timeout
    initial begin
        #2000000;
        $display("TIMEOUT!");
        $finish;
    end
    
endmodule
