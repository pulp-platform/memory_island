// Copyright 2023 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

`include "idma/typedef.svh"
`include "obi/typedef.svh"

module memory_island_dma #(
  /// Register types for DMA configuration
  parameter type                reg_req_t       = logic,
  parameter type                reg_rsp_t       = logic,

  /// Address Width
  parameter int unsigned AddrWidth            = 0,
  /// Data Width for the Narrow Ports
  parameter int unsigned NarrowDataWidth      = 0,
  /// Data Width for the Wide Ports
  parameter int unsigned WideDataWidth        = 0,
  // Derived, DO NOT OVERRIDE
  parameter int unsigned NarrowStrbWidth      = NarrowDataWidth/8,
  parameter int unsigned WideStrbWidth        = WideDataWidth/8
) (
  input  logic                          clk_i,
  input  logic                          rst_ni,
  input  logic                          test_mode_i,

  /// Register configuration ports
  input  reg_req_t                      reg_req_i,
  output reg_rsp_t                      reg_rsp_o,

  output logic [1:0]                    wide_req_o,
  input  logic [1:0]                    wide_gnt_i,
  output logic [1:0][AddrWidth-1:0]     wide_addr_o,
  output logic [1:0]                    wide_we_o,
  output logic [1:0][WideDataWidth-1:0] wide_wdata_o,
  output logic [1:0][WideStrbWidth-1:0] wide_strb_o,
  input  logic [1:0]                    wide_rvalid_i,
  input  logic [1:0][WideDataWidth-1:0] wide_rdata_i
);
  localparam int unsigned TFLenWidth = 24;
  localparam int unsigned NumDim = 3;

  `OBI_TYPEDEF_A_CHAN_T(obi_a_chan_t,
                        AddrWidth,
                        WideDataWidth,
                        1,
                        logic)
  `OBI_TYPEDEF_R_CHAN_T(obi_r_chan_t,
                        WideDataWidth,
                        1,
                        logic)

  `IDMA_TYPEDEF_FULL_REQ_T(idma_req_t,
                           logic,
                           logic[AddrWidth-1:0],
                           logic[TFLenWidth-1:0])
  `IDMA_TYPEDEF_FULL_RSP_T(idma_rsp_t, logic[AddrWidth-1:0])

  `IDMA_TYPEDEF_FULL_ND_REQ_T(idma_nd_req_t, idma_req_t, logic[31:0], logic[31:0])

  typedef struct packed {
    obi_a_chan_t a_chan;
    logic        padding;
  } obi_read_a_chan_padded_t;

  typedef union packed {
    obi_read_a_chan_padded_t obi;
  } read_meta_channel_t;

  typedef struct packed {
    obi_a_chan_t a_chan;
    logic        padding;
  } obi_write_a_chan_padded_t;

  typedef union packed {
    obi_write_a_chan_padded_t obi;
  } write_meta_channel_t;

  `OBI_TYPEDEF_REQ_T(internal_obi_req_t, obi_a_chan_t)
  `OBI_TYPEDEF_RSP_T(internal_obi_rsp_t, obi_r_chan_t)

  idma_nd_req_t midend_req;
  idma_rsp_t    midend_rsp;
  logic         midend_req_valid,
                midend_req_ready,
                midend_rsp_valid,
                midend_rsp_ready;
  idma_req_t    backend_req;
  idma_rsp_t    backend_rsp;
  logic         backend_req_valid,
                backend_req_ready,
                backend_rsp_valid,
                backend_rsp_ready;

  idma_pkg::idma_busy_t midend_busy;
  idma_pkg::idma_busy_t backend_busy;

  logic [31:0] next_id, completed_id;

  internal_obi_req_t [1:0] internal_obi_req;
  internal_obi_rsp_t [1:0] internal_obi_rsp;

  obi_a_chan_t [1:0] filtered_obi_a;
  obi_r_chan_t [1:0] filtered_obi_r;

  idma_reg32_3d #(
    .NumRegs       (32'd1),
    .NumStreams    (32'd1),
    .IdCounterWidth(32),
    .reg_req_t     ( reg_req_t ),
    .reg_rsp_t     ( reg_rsp_t ),
    .dma_req_t     ( idma_nd_req_t )
  ) i_frontend (
    .clk_i,
    .rst_ni,
    .dma_ctrl_req_i( reg_req_i        ),
    .dma_ctrl_rsp_o( reg_rsp_o        ),
    .dma_req_o     ( midend_req       ),
    .req_valid_o   ( midend_req_valid ),
    .req_ready_i   ( midend_req_ready ),
    .next_id_i     ( next_id          ),
    .stream_idx_o  (),
    .done_id_i     ( completed_id     ),
    .busy_i        ( backend_busy     ),
    .midend_busy_i ( midend_busy      )
  );

  idma_transfer_id_gen #(
    .IdWidth ( 32 )
  ) i_transfer_id_gen (
    .clk_i,
    .rst_ni,

    .issue_i    ( midend_req_valid & midend_req_ready ),
    .retire_i   ( midend_rsp_valid ),
    .next_o     ( next_id ),
    .completed_o( completed_id )
  );

  assign midend_rsp_ready = 1'b1;

  idma_nd_midend #(
    .NumDim       ( 3                    ),
    .addr_t       ( logic[AddrWidth-1:0] ),
    .idma_req_t   ( idma_req_t           ),
    .idma_rsp_t   ( idma_rsp_t           ),
    .idma_nd_req_t( idma_nd_req_t        ),
    .RepWidths    ( {3{32'd32}}          )
  ) i_nd_midend (
    .clk_i,
    .rst_ni,

    .nd_req_i         ( midend_req        ),
    .nd_req_valid_i   ( midend_req_valid  ),
    .nd_req_ready_o   ( midend_req_ready  ),

    .nd_rsp_o         ( midend_rsp        ),
    .nd_rsp_valid_o   ( midend_rsp_valid  ),
    .nd_rsp_ready_i   ( midend_rsp_ready  ),

    .burst_req_o      ( backend_req       ),
    .burst_req_valid_o( backend_req_valid ),
    .burst_req_ready_i( backend_req_ready ),

    .burst_rsp_i      ( backend_rsp       ),
    .burst_rsp_valid_i( backend_rsp_valid ),
    .burst_rsp_ready_o( backend_rsp_ready ),

    .busy_o           ( backend_busy      )
  );

  // Backend
  idma_backend_rw_obi #(
    .DataWidth           ( WideDataWidth ),
    .AddrWidth           ( AddrWidth ),
    .UserWidth           ( 1 ), // unused internally, needs >0
    .AxiIdWidth          ( 1 ),
    .NumAxInFlight       ( 3 ),
    .BufferDepth         ( 3 ),
    .TFLenWidth          ( TFLenWidth ),
    .MemSysDepth         ( 3 ),
    .CombinedShifter     ( 1'b0 ),
    .RAWCouplingAvail    ( 1'b1 ),
    .MaskInvalidData     ( 1'b1 ),
    .HardwareLegalizer   ( 1'b1 ),
    .RejectZeroTransfers ( 1'b1 ),
    .ErrorCap            ( idma_pkg::NO_ERROR_HANDLING ),
    .PrintFifoInfo       ( 1'b0 ),
    .idma_req_t          ( idma_req_t ),
    .idma_rsp_t          ( idma_rsp_t ),
    .idma_eh_req_t       ( idma_pkg::idma_eh_req_t ),
    .idma_busy_t         ( idma_pkg::idma_busy_t ),
    .obi_req_t           ( internal_obi_req_t ),
    .obi_rsp_t           ( internal_obi_rsp_t ),
    .read_meta_channel_t ( read_meta_channel_t ),
    .write_meta_channel_t( write_meta_channel_t )
  ) i_backend (
    .clk_i,
    .rst_ni,
    .testmode_i     ( test_mode_i ),

    .idma_req_i     ( backend_req ),
    .req_valid_i    ( backend_req_valid ),
    .req_ready_o    ( backend_req_ready ),

    .idma_rsp_o     ( backend_rsp ),
    .rsp_valid_o    ( backend_rsp_valid ),
    .rsp_ready_i    ( backend_rsp_ready ),

    .idma_eh_req_i  ( '0 ),
    .eh_req_valid_i ( '0 ),
    .eh_req_ready_o (),

    .obi_read_req_o ( internal_obi_req[0] ),
    .obi_read_rsp_i ( internal_obi_rsp[0] ),

    .obi_write_req_o( internal_obi_req[1] ),
    .obi_write_rsp_i( internal_obi_rsp[1] ),

    .busy_o         ( backend_busy )
  );

  for (genvar i = 0; i < 2; i++) begin : gen_rready_convert
    obi_rready_converter #(
      .obi_a_chan_t( obi_a_chan_t ),
      .obi_r_chan_t( obi_r_chan_t ),
      .Depth       ( 2            ),
      .CombRspReq  ( 1'b1         )
    ) i_obi_rready_converter (
      .clk_i,
      .rst_ni,
      .test_mode_i,

      .sbr_a_chan_i( internal_obi_req[i].a      ),
      .req_i       ( internal_obi_req[i].req    ),
      .gnt_o       ( internal_obi_rsp[i].gnt    ),
      .sbr_r_chan_o( internal_obi_rsp[i].r      ),
      .rvalid_o    ( internal_obi_rsp[i].rvalid ),
      .rready_i    ( internal_obi_req[i].rready ),

      .mgr_a_chan_o( filtered_obi_a  [i]        ),
      .req_o       ( wide_req_o      [i]        ),
      .gnt_i       ( wide_gnt_i      [i]        ),
      .mgr_r_chan_i( filtered_obi_r  [i]        ),
      .rvalid_i    ( wide_rvalid_i   [i]        )
    );
    assign wide_addr_o [i] = filtered_obi_a[i].addr;
    assign wide_we_o   [i] = filtered_obi_a[i].we;
    assign wide_wdata_o[i] = filtered_obi_a[i].wdata;
    assign wide_strb_o [i] = filtered_obi_a[i].be;

    assign filtered_obi_r[i] = '{
      rdata: wide_rdata_i[i],
      rid: '0,
      err: '0,
      r_optional: '0
    };
  end
endmodule