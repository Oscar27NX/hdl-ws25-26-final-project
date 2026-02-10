// Similar to Dmem, but RO (read-only)
module Imem #(parameter MEM_DEPTH = 256) (
    input wire [31:0] addr,
    output wire [31:0] rd
);
    // Name the memory RAM as required
    reg [31:0] RAM [0 : MEM_DEPTH-1];

    // Asynchronous Read
    assign rd = RAM[addr[31:2]];
endmodule