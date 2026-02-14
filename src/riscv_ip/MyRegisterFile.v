// 32-bit register file module
module RegisterFile #(parameter WIDTH = 32)(
    input clk,                  
    input wire [4:0] rs1,    
    input wire [4:0] rs2,    
    input wire [4:0] rd,     
    input wire [WIDTH-1:0] write_data,    
    input wire reg_write,            
    output wire [WIDTH-1:0] read_data1,   
    output wire [WIDTH-1:0] read_data2    
);

    // Declare the register file as an array of 32 registers, each 32 bits wide 
    reg [WIDTH-1:0] registers [0:31];

    // Read operations (combinational with internal forwarding)
    // If reading the same register being written, bypass the write data
    assign read_data1 = (rs1 == 5'b0) ? {WIDTH{1'b0}} : 
                       (reg_write && (rs1 == rd)) ? write_data :
                       registers[rs1];
                       
    assign read_data2 = (rs2 == 5'b0) ? {WIDTH{1'b0}} : 
                       (reg_write && (rs2 == rd)) ? write_data :
                       registers[rs2];
    integer i;

    // Write operation (synchronous => sequential)
    always @(posedge clk) begin
        if (reg_write && (rd != 5'b0)) begin
            registers[rd] <= write_data;
        end
    end
endmodule