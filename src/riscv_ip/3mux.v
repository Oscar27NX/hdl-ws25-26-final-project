// Auxiliary 3-way mux for hazard forwarding.
module ThreeMux (
    input wire [1:0] sel,
    input wire [31:0] in0,  // RF stage read data
    input wire [31:0] in1,  // EX ALU Result (Prev Instr)
    input wire [31:0] in2,  // MEM ALU Result (Prev-Prev Instr)
    output reg [31:0] out
);
    always @(*) begin
        case (sel)
            2'b00: out = in0; // No hazard, take from RF stage
            2'b01: out = in1; // Forward from EX stage
            2'b10: out = in2; // Forward from MEM stage
            default: out = in0; // Default to RF stage
        endcase
    end
endmodule