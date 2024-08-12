// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

module varlat_inorder_interco #(
  ///////////////////////////
  // global parameters
  /// number of initiator ports (must be aligned with power of 2 for bfly and clos)
  parameter int unsigned NumIn          = 32,
  /// number of TCDM banks (must be aligned with power of 2 for bfly and clos)
  parameter int unsigned NumOut         = 64,
  /// address width on initiator side
  parameter int unsigned AddrWidth      = 32,
  /// word width of data
  parameter int unsigned DataWidth      = 32,
  /// width of corresponding byte enables
  parameter int unsigned BeWidth        = DataWidth / 8,
  /// number of address bits per TCDM bank
  parameter int unsigned AddrMemWidth   = 12,
  /// defines whether the interconnect returns a write response
  parameter bit          WriteRespOn    = 1,
  /// Number of outstanding requests supported
  parameter int unsigned NumOutstanding = 1,
  /// determines the width of the byte offset in a memory word. normally this can be left at the
  /// default vaule, but sometimes it needs to be overridden (e.g. when meta-data is supplied to
  /// the memory via the wdata signal).
  parameter int unsigned ByteOffWidth   = $clog2(DataWidth - 1) - 3,

  /// topology can be: LIC, BFLY2, BFLY4, CLOS
  parameter tcdm_interconnect_pkg::topo_e Topology   = tcdm_interconnect_pkg::LIC,
  /// number of parallel butterfly's to use, only relevant for BFLY topologies
  parameter int unsigned                  NumPar     = 1,
  /// this detemines which Clos config to use, only relevant for CLOS topologies
  /// 1: m=0.50*n, 2: m=1.00*n, 3: m=2.00*n
  parameter int unsigned                  ClosConfig = 2
  ///////////////////////////
) (
  input  logic                                clk_i,
  input  logic                                rst_ni,
  /// master side
  /// request signal
  input  logic [ NumIn-1:0]                   req_i,
  /// tcdm address
  input  logic [ NumIn-1:0][   AddrWidth-1:0] add_i,
  /// 1: store, 0: load
  input  logic [ NumIn-1:0]                   we_i,
  /// write data
  input  logic [ NumIn-1:0][   DataWidth-1:0] wdata_i,
  /// byte enable
  input  logic [ NumIn-1:0][     BeWidth-1:0] be_i,
  /// grant (combinationally dependent on req_i and add_i
  output logic [ NumIn-1:0]                   gnt_o,
  /// response valid, also asserted if write responses ar
  output logic [ NumIn-1:0]                   vld_o,
  /// data response (for load commands)
  output logic [ NumIn-1:0][   DataWidth-1:0] rdata_o,
  // slave side
  /// request out
  output logic [NumOut-1:0]                   req_o,
  /// grant input
  input  logic [NumOut-1:0]                   gnt_i,
  /// address within bank
  output logic [NumOut-1:0][AddrMemWidth-1:0] add_o,
  /// write enable
  output logic [NumOut-1:0]                   we_o,
  /// write data
  output logic [NumOut-1:0][   DataWidth-1:0] wdata_o,
  /// byte enable
  output logic [NumOut-1:0][     BeWidth-1:0] be_o,
  /// response valid
  input  logic [NumOut-1:0]                   rvalid_i,
  /// response ready
  output logic [NumOut-1:0]                   rready_o,
  /// data response (for load commands)
  input  logic [NumOut-1:0][   DataWidth-1:0] rdata_i
);

  localparam int unsigned NumOutLog2 = $clog2(NumOut);
  localparam int unsigned NumInLog2 = $clog2(NumIn);
  localparam int unsigned AggDataWidth = 1 + BeWidth + AddrMemWidth + DataWidth;
  logic [ NumIn-1:0][AggDataWidth-1:0] data_agg_in;
  logic [NumOut-1:0][AggDataWidth-1:0] data_agg_out;
  logic [NumIn-1:0][NumOutLog2-1:0] bank_sel, bank_sel_rsp;
  logic [NumOut-1:0][NumInLog2-1:0] ini_addr_req, ini_addr_rsp;

  for (genvar j = 0; unsigned'(j) < NumIn; j++) begin : gen_inputs
    // extract bank index
    assign bank_sel[j] = add_i[j][ByteOffWidth+NumOutLog2-1:ByteOffWidth];
    // aggregate data to be routed to slaves
    assign data_agg_in[j] = {
      we_i[j],
      be_i[j],
      add_i[j][ByteOffWidth+NumOutLog2+AddrMemWidth-1:ByteOffWidth+NumOutLog2],
      wdata_i[j]
    };
  end

  // disaggregate data
  for (genvar k = 0; unsigned'(k) < NumOut; k++) begin : gen_outputs
    assign {we_o[k], be_o[k], add_o[k], wdata_o[k]} = data_agg_out[k];
  end


  if (Topology == tcdm_interconnect_pkg::LIC) begin : gen_lic
    logic [NumIn-1:0] xbar_gnt, fifo_gnt, fifo_gnt_n;
    logic [NumOut-1:0] out_fifo_gnt, out_fifo_gnt_n;

    assign fifo_gnt     = ~fifo_gnt_n;
    assign gnt_o        = xbar_gnt & fifo_gnt;

    assign out_fifo_gnt = ~out_fifo_gnt_n;

    // Request path
    simplex_xbar #(
      .NumIn              (NumIn),
      .NumOut             (NumOut),
      .DataWidth          (AggDataWidth),
      .ExtPrio            (1'b0),
      .AxiVldRdy          (1'b1),
      .SpillRegister      (1'b0),
      .FallThroughRegister(1'b0)
    ) req_xbar (
      .clk_i,
      .rst_ni,
      .rr_i      ('0),
      .valid_i   (req_i & fifo_gnt),
      .ready_o   (xbar_gnt),
      .tgt_addr_i(bank_sel),
      .data_i    (data_agg_in),
      .valid_o   (req_o),
      .ini_addr_o(ini_addr_req),
      .ready_i   (gnt_i & out_fifo_gnt),
      .data_o    (data_agg_out)
    );

    // Response path
    for (genvar i = 0; i < NumIn; i++) begin : gen_rsp
      assign vld_o[i] = rvalid_i[bank_sel_rsp[i]] &
                        rready_o[bank_sel_rsp[i]] &
                        (ini_addr_rsp[bank_sel_rsp[i]] == i);
      assign rdata_o[i] = rdata_i[bank_sel_rsp[i]];
    end
    for (genvar i = 0; i < NumOut; i++) begin : gen_rready
      assign rready_o[i] = bank_sel_rsp[ini_addr_rsp[i]] == i;
    end

    for (genvar i = 0; i < NumIn; i++) begin : gen_rsp_port_match
      fifo_v3 #(
        .FALL_THROUGH(1'b0),           // expect at least 1 cycle latency
        .DATA_WIDTH  (NumOutLog2),
        .DEPTH       (NumOutstanding)
      ) i_bank_sel (
        .clk_i,
        .rst_ni,

        .flush_i   ('0),
        .testmode_i('0),

        .full_o (fifo_gnt_n[i]),
        .empty_o(),
        .usage_o(),

        .data_i(bank_sel[i]),
        .push_i(req_i[i] & gnt_o[i]),

        .data_o(bank_sel_rsp[i]),
        .pop_i (vld_o[i])
      );
    end

    for (genvar i = 0; i < NumOut; i++) begin : gen_out_fifo
      fifo_v3 #(
        .FALL_THROUGH(1'b0),           // expect at least 1 cycle latency
        .DATA_WIDTH  (NumInLog2),
        .DEPTH       (NumOutstanding)
      ) i_ini_sel (
        .clk_i,
        .rst_ni,

        .flush_i   ('0),
        .testmode_i('0),

        .full_o (out_fifo_gnt_n[i]),
        .empty_o(),
        .usage_o(),

        .data_i(ini_addr_req[i]),
        .push_i(req_o[i] & gnt_i[i] & out_fifo_gnt[i]),

        .data_o(ini_addr_rsp[i]),
        .pop_i (rvalid_i[i] & rready_o[i])
      );
    end
  end else begin : gen_fail
    $fatal(1, "unimplemented");
  end

endmodule
