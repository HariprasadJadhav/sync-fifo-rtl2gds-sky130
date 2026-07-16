module syn_fifo #(
    parameter WIDTH     = 8,
    parameter DEPTH     = 8,
    parameter PTR_WIDTH = $clog2(DEPTH) + 1
) (
    input  wire             rst,
    input  wire             clk,
    input  wire             wr_en,
    input  wire             rd_en,
    input  wire [WIDTH-1:0] data_in,
    output                  full,
    output                  empty,
    output                  overflow,
    output                  underflow,
    output reg [WIDTH-1:0]  data_out
);

    reg [PTR_WIDTH-1:0] rd_ptr;
    reg [PTR_WIDTH-1:0] wr_ptr;
    reg [WIDTH-1:0]     mem [DEPTH-1:0];

    // Full/empty via MSB-extended pointer comparison
    assign full  = (rd_ptr[PTR_WIDTH-1] ^ wr_ptr[PTR_WIDTH-1]) &
                   (wr_ptr[PTR_WIDTH-2:0] == rd_ptr[PTR_WIDTH-2:0]);
    assign empty = (wr_ptr[PTR_WIDTH-1:0] == rd_ptr[PTR_WIDTH-1:0]);

    assign underflow = rd_en & empty;
    assign overflow  = wr_en & full;

    // Pointer update — gated so illegal ops never advance a pointer
    always @(posedge clk) begin
        if (rst) begin
            rd_ptr <= 0;
            wr_ptr <= 0;
        end else begin
            rd_ptr <= rd_ptr + (rd_en & ~empty);
            wr_ptr <= wr_ptr + (wr_en & ~full);
        end
    end

    // Memory read/write — gated identically to the pointers
    always @(posedge clk) begin
        if (wr_en & ~full) begin
            mem[wr_ptr[PTR_WIDTH-2:0]] <= data_in;
        end
        if (rd_en & ~empty) begin
            data_out <= mem[rd_ptr[PTR_WIDTH-2:0]];
        end
    end

endmodule
