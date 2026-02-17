// 3-way mux for hazard forwarding.
module ThreeMux (
    input wire [1:0] sel, // 00: No hazard, take from RF stage
                      // 01: Forward from EX stage
                      // 10: Forward from MEM stage
    input wire [31:0] in0,  // RF stage read data
    input wire [31:0] in1,  // EX ALU Result (Prev Instr)
    input wire [31:0] in2,  // MEM ALU Result (Prev-Prev Instr)
    output reg [31:0] out
);
    always @(*) begin
        case (sel)
            2'b00: out = in0; 
            2'b01: out = in1;
            2'b10: out = in2; 
            default: out = in0; 
        endcase
    end
endmodule