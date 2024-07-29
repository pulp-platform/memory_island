// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module mem_rsp_multicut #(
  /// Data Width
  parameter int unsigned DataWidth = 0,
  /// Number of cuts
  parameter int unsigned NumCuts   = 0
) (
  input  logic clk_i,
  input  logic rst_ni,

  // mem interface inputs
  input  logic                 rvalid_i,
  output logic                 rready_o,
  input  logic [DataWidth-1:0] rdata_i,

  // mem interface outputs
  output logic                 rvalid_o,
  input  logic                 rready_i,
  output logic [DataWidth-1:0] rdata_o
);

  if (NumCuts == 0) begin : gen_passthrough
    assign rvalid_o = rvalid_i;
    assign rready_o = rready_i;
    assign rdata_o  = rdata_i;
  end else begin : gen_cuts
    logic [NumCuts:0][DataWidth-1:0]  data_agg;
    logic [NumCuts:0] rvalid, rready;

    assign data_agg    [0] = rdata_i;
    assign rvalid      [0] = rvalid_i;
    assign rready_o        = rready[0];
    assign rready[NumCuts] = rready_i;
    assign rvalid_o        = rvalid   [NumCuts];
    assign rdata_o         = data_agg [NumCuts];

    for (genvar i = 0; i < NumCuts; i++) begin : gen_cut
      spill_register #(
        .T     (logic[DataWidth-1:0]),
        .Bypass(1'b0)
      ) i_cut (
        .clk_i,
        .rst_ni,
        .valid_i ( rvalid  [i  ] ),
        .ready_o ( rready  [i  ] ),
        .data_i  ( data_agg[i  ] ),
        .valid_o ( rvalid  [i+1] ),
        .ready_i ( rready  [i+1] ),
        .data_o  ( data_agg[i+1] )
      );
    end
  end

endmodule
