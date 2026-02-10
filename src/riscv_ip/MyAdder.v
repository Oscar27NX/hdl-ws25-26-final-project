// Simple adder. Uses 32-bit inputs and outputs their sum. Combinational logic to support carry over.

module Adder #(parameter WIDTH = 32)(
    input [WIDTH-1:0] a,
    input [WIDTH-1:0] b,
    output [WIDTH-1:0] sum
);
    assign sum = a + b;
endmodule