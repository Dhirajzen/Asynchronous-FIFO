module sync_r2w
#(parameter DEPTH = 16)
(
    input  logic               w_clk,
    input  logic               rst_n,
    input  logic [$clog2(DEPTH):0] rptr,
    output logic [$clog2(DEPTH):0] wsync_ptr2
);

    logic [$clog2(DEPTH):0] wsync_ptr1;

    always_ff @(posedge w_clk or negedge rst_n) begin
        if (~rst_n) begin
            wsync_ptr2 <= '0;
            wsync_ptr1 <= '0;
        end
        else begin
            wsync_ptr1 <= rptr;
            wsync_ptr2 <= wsync_ptr1;
        end
    end

endmodule

