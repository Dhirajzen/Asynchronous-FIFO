module sync_w2r
    #(parameter DEPTH = 16)
    (input logic r_clk, rst_n,
     input logic [$clog2(DEPTH):0] wptr,
     output logic [$clog2(DEPTH):0] rsync_ptr2);

    logic [$clog2(DEPTH):0] rsync_ptr1;

    always @(posedge r_clk or negedge rst_n) begin
        if (~rst_n) begin
            rsync_ptr2 <= '0;
            rsync_ptr1 <= '0;
        end
        else begin
            rsync_ptr1 <= wptr;
            rsync_ptr2 <= rsync_ptr1;
        end
    end

endmodule




