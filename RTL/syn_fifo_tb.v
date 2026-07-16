`timescale 1ns/1ps
// =============================================================
// Synchronous FIFO Testbench — FINAL (all corner cases)
// Covers: fill-to-full/overflow, drain-to-empty/underflow,
//         second pointer wraparound lap, simultaneous read+write
//         at the near-full boundary, mid-operation reset,
//         post-reset write/read sanity check.
// =============================================================
module syn_fifo_tb;
    reg         rst;
    reg         clk;
    reg         wr_en;
    reg         rd_en;
    reg  [7:0]  data_in;
    wire        full;
    wire        empty;
    wire        overflow;
    wire        underflow;
    wire [7:0]  data_out;

    syn_fifo dut (
        .rst(rst), .clk(clk), .wr_en(wr_en), .rd_en(rd_en),
        .data_in(data_in), .full(full), .empty(empty),
        .overflow(overflow), .underflow(underflow), .data_out(data_out)
    );

    integer i, fail;
    reg [7:0] expected [15:0];
    reg [3:0] wp;
    reg [3:0] rp;

    always #5 clk <= ~clk;

    initial begin
        $dumpfile("dump.vcd");
        $dumpvars(0, syn_fifo_tb);

        wp = 0; rp = 0; fail = 0;
        rd_en = 0; clk = 0; wr_en = 0; rst = 1;
        #10;
        rst = 0;

        // ---- Fill to full with 8 distinct values ----
        for (i = 0; i < 8; i = i + 1) begin
            @(posedge clk);
            #1;
            wr_en   = 1;
            data_in = i;
        end

        // Let the loop's final write reach its own capturing edge before
        // touching data_in again.
        @(posedge clk);
        #1;

        // ---- Attempt a 9th write — should be blocked, overflow pulses ----
        wr_en   = 1;
        data_in = 8'b10000000;
        #10;
        $display("Overflow flag value: %d", overflow);
        wr_en = 0;
        #10;

        // ---- Drain to empty ----
        rd_en = 1;
        #90;
        $display("Underflow flag value: %d", underflow);
        rd_en = 0;

        // ---- Refill 7 words — exercises the second wraparound lap and
        //      sets up a near-full (1 free slot) boundary state ----
        @(posedge clk);
        for (i = 0; i < 7; i = i + 1) begin
            @(posedge clk);
            #1;
            wr_en   = 1;
            data_in = i;
        end

        // ---- Simultaneous read+write at the near-full boundary ----
        // Let the loop's final pending write (i=6) reach its own
        // capturing edge first...
        @(posedge clk);
        #1;
        // ...THEN set up the simultaneous op for the *next* edge. Skipping
        // this #1 causes a race: the assignment below could leak into the
        // edge that was only supposed to capture i=6's write.
        wr_en = 1;
        data_in = 7;
        rd_en = 1;
        @(posedge clk);
        #1;
        $display("Full Flag during simultaneous rd+wr at boundary: %d (expect 0)", full);
        wr_en = 0;
        rd_en = 0;

        // ---- Drain down to 1 item remaining (near-empty boundary) ----
        @(posedge clk);
        #1;
        rd_en = 1;
        for (i = 0; i < 6; i = i + 1) begin
            @(posedge clk);
        end
        #1;
        rd_en = 0;

        // ---- Simultaneous read+write at the near-empty boundary ----
        wr_en   = 1;
        data_in = 8'hEE;
        rd_en   = 1;
        @(posedge clk);
        #1;
        $display("Empty Flag during simultaneous rd+wr at near-empty boundary: %d (expect 0)", empty);
        wr_en = 0;
        rd_en = 0;

        // ---- Reset mid-operation, confirm clean recovery ----
        rst = 1;
        #10;
        rst = 0;
        $display("Empty Flag after mid-op reset: %d (expect 1)", empty);

        // ---- Post-reset sanity: one write, one read ----
        wr_en   = 1;
        data_in = 8'b10101010;
        #10;
        wr_en = 0;
        rd_en = 1;
        #10;

        $display("failed cases: %d", fail);
        $finish;
    end

    reg rd_valid;
    always @(posedge clk) begin
        if (rst) begin
            wp = 0;
            rp = 0;
        end
        if (wr_en & ~overflow) begin
            expected[wp] = data_in;
            wp = wp + 1;
        end
        // Capture the read-valid decision AT the edge — the same rd_en/
        // underflow values the DUT itself sampled — before the settling
        // delay below, so a later stimulus change can't be misread as
        // having applied to this edge.
        rd_valid = rd_en & ~underflow;
        #2;   // let the DUT's nonblocking data_out update settle
        if (rd_valid) begin
            if (data_out !== expected[rp]) begin
                fail = fail + 1;
                $display("ERROR at time %0t: Expected %d, Got %d", $time, expected[rp], data_out);
            end
            rp = rp + 1;
        end
    end

endmodule
