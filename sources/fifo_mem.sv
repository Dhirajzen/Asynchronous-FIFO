module fifo_mem 
#(
  parameter WIDTH = 8,
  parameter DEPTH = 16
)
(
  input logic w_clk,
  input logic wr_rq,
  input logic rd_rq,
  input logic full,
  input logic empty,
  input logic [$clog2(DEPTH)-1:0] waddr,
  input logic [$clog2(DEPTH)-1:0] raddr,
  input logic [WIDTH-1:0] wdata,
  output logic [WIDTH-1:0] rdata
);

  logic [WIDTH-1:0] fifo [DEPTH-1:0];

  // Write into FIFO when not full and write requested
  always_ff @(posedge w_clk) begin
    if (wr_rq && !full) begin
      fifo[waddr] <= wdata;
    end
  end

  // Read from FIFO when not empty and read requested
  always_comb begin
    if (rd_rq && !empty) begin
      rdata = fifo[raddr];
    end else begin
      rdata = '0;
    end
  end

endmodule

