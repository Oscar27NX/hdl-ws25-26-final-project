// 32-bit MUX from register file to ALU (2-to-1)
module Multiplexer #(parameter WIDTH = 32)(
    input wire sel,                   
    input wire [WIDTH-1:0] b,      
    input wire [WIDTH-1:0] a,       
    output wire [WIDTH-1:0] y       
);
    assign y = (sel) ? a : b;
endmodule  