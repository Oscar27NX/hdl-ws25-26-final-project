`timescale 1ns / 1ps
/*******************************************************************************
 * RISC-V Pipelined Processor - 32-Element Sorting Testbench
 * 
 * Project: HDL Final Project - Test Your Softcore on PYNQ-Z2
 * Purpose: Comprehensive testbench for verifying 32-element bubble sort
 *
 * This testbench:
 * - Loads 32 signed integers into data memory
 * - Executes bubble sort algorithm using ONLY supported instructions
 *   (ADDI, LW, SW, SLT, BEQ, LUI - NO BLT/BNE/BGE!)
 * - Verifies sorted output against golden reference
 * - Reports execution cycles and status
 *
 * Memory Organization:
 * - Instruction Memory: sort_32_bubble.hex
 * - Data Memory [0-31]: Input/output array (32 signed integers)
 * - Data Memory [64]: Status flag (0xDEADBEAF when complete)
 *******************************************************************************/

module tb_sort_32;
    // Clock and reset
    reg clk, resetn;
    
    // Processor interface
    wire [31:0] i_addr, i_instr;
    wire [31:0] d_addr, d_wdata, d_rdata;
    wire [3:0] d_we;
    
    // Internal memories
    reg [31:0] imem [0:20479];  // Large enough for 17K+ instructions
    reg [31:0] dmem [0:2047];
    reg [31:0] i_instr_reg;
    
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
    
    // Instruction memory (registered read to model BRAM behavior)
    always @(posedge clk)
        i_instr_reg <= resetn ? imem[i_addr[31:2]] : 32'h00000013;
    assign i_instr = i_instr_reg;
    
    // Data memory (COMBINATIONAL read - critical for correct operation!)
    assign d_rdata = dmem[d_addr[31:2]];
    
    // Data memory write (synchronous)
    always @(posedge clk) begin
        if (resetn) begin
            if (d_we[0]) dmem[d_addr[31:2]][7:0]   <= d_wdata[7:0];
            if (d_we[1]) dmem[d_addr[31:2]][15:8]  <= d_wdata[15:8];
            if (d_we[2]) dmem[d_addr[31:2]][23:16] <= d_wdata[23:16];
            if (d_we[3]) dmem[d_addr[31:2]][31:24] <= d_wdata[31:24];
        end
    end
    
    // Test variables
    integer i, cycle, errors;
    reg signed [31:0] expected [0:31];
    reg signed [31:0] input_data [0:31];
    
    // Test execution
    initial begin
        $display("================================================================");
        $display("  RISC-V Pipelined Processor - 32-Element Sort Test");
        $display("================================================================");
        
        // Initialize all memory
        for (i = 0; i < 2048; i = i + 1) 
            dmem[i] = 0;
        
        // Generate test data: Mix of positive and negative signed integers
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
        
        // Load input data into memory
        for (i = 0; i < 32; i = i + 1)
            dmem[i] = input_data[i];
        
        // Calculate expected output (sorted)
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
        
        // Display input array
        $display("\nInput Array (32 signed integers):");
        $display("----------------------------------------------------------------");
        for (i = 0; i < 32; i = i + 4)
            $display("  [%2d-%2d]: %4d %4d %4d %4d", i, i+3,
                $signed(input_data[i]), $signed(input_data[i+1]),
                $signed(input_data[i+2]), $signed(input_data[i+3]));
        
        // Load program
        $display("\nLoading bubble sort program...");
        resetn = 0;

        $readmemh("C:/Users/oscar/vivado_tutorial/riscv_pynq_final/sort_32_bubble.hex", imem);
        $display("Program loaded: sort_32_bubble.hex");
        
        // Start execution
        #100;
        resetn = 1;
        cycle = 0;
        $display("\nStarting execution...");
        
        // Wait for completion flag at word 64 (offset 0x100)
        while (dmem[64] !== 32'hDEADBEAF && cycle < 100000) begin
            @(posedge clk);
            cycle = cycle + 1;
            
            // Progress indicator every 10000 cycles
            if (cycle % 10000 == 0)
                $display("  ... %0d cycles elapsed", cycle);
        end
        
        repeat(10) @(posedge clk);
        
        // Display results
        $display("\n================================================================");
        $display("Execution Statistics:");
        $display("----------------------------------------------------------------");
        $display("  Cycles elapsed:    %0d", cycle);
        $display("  Status flag:       0x%08h", dmem[64]);
        
        if (dmem[64] == 32'hDEADBEAF)
            $display("  Completion:        CONFIRMED");
        else
            $display("  Completion:        FLAG NOT SET!");
        
        // Display output array
        $display("\nOutput Array (sorted):");
        $display("----------------------------------------------------------------");
        for (i = 0; i < 32; i = i + 4)
            $display("  [%2d-%2d]: %4d %4d %4d %4d", i, i+3,
                $signed(dmem[i]), $signed(dmem[i+1]),
                $signed(dmem[i+2]), $signed(dmem[i+3]));
        
        // Verify results
        $display("\nVerification:");
        $display("----------------------------------------------------------------");
        errors = 0;
        for (i = 0; i < 32; i = i + 1) begin
            if (dmem[i] !== expected[i]) begin
                $display("  ERROR at index %2d: got %4d, expected %4d",
                    i, $signed(dmem[i]), $signed(expected[i]));
                errors = errors + 1;
            end
        end
        
        if (dmem[64] !== 32'hDEADBEAF) begin
            $display("  ERROR: Status flag not set correctly!");
            errors = errors + 1;
        end
        
        // Final result
        $display("================================================================");
        if (errors == 0) begin
            $display("                  *** ALL TESTS PASSED ***");
            $display("");
            $display("  32-element bubble sort executed successfully!");
            $display("  Processor verified and ready for FPGA deployment.");
        end else begin
            $display("                  *** TEST FAILED ***");
            $display("");
            $display("  Found %0d error(s) in verification.", errors);
        end
        $display("================================================================\n");
        
        $finish;
    end
    
    // Timeout watchdog
    initial begin
        #10000000; // 10ms timeout at 100MHz = 1M cycles
        $display("\nTIMEOUT: Execution exceeded 1,000,000 cycles");
        $display("Processor may be stuck in infinite loop.\n");
        $finish;
    end
    
endmodule
