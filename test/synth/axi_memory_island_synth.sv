// Copyright 2023 ETH Zurich and University of Bologna.
// Internal use only

// Michael Rogenmoser <michaero@iis.ee.ethz.ch>

`include "axi/typedef.svh"
`include "axi/port.svh"

// Synthesis wrapper used for testing and internal CI
module axi_memory_island_synth #(
  localparam int unsigned AddrWidth       = 32,
  localparam int unsigned NarrowDataWidth = 32,
  localparam int unsigned WideDataWidth   = 512,

  localparam int unsigned AxiIdWidth      = 3,

  localparam int unsigned NumNarrowReq    = 5,
  localparam int unsigned NumWideReq      = 4,
  localparam int unsigned WordsPerBank    = 8192
) (
  input  logic clk_i,
  input  logic rst_ni,

  input  logic             [NumNarrowReq-1:0]                        s_axi_narrow_awvalid,
  input  logic             [NumNarrowReq-1:0][       AxiIdWidth-1:0] s_axi_narrow_awid,
  input  logic             [NumNarrowReq-1:0][        AddrWidth-1:0] s_axi_narrow_awaddr,
  input  axi_pkg::len_t    [NumNarrowReq-1:0]                        s_axi_narrow_awlen,
  input  axi_pkg::size_t   [NumNarrowReq-1:0]                        s_axi_narrow_awsize,
  input  axi_pkg::burst_t  [NumNarrowReq-1:0]                        s_axi_narrow_awburst,
  input  logic             [NumNarrowReq-1:0]                        s_axi_narrow_awlock,
  input  axi_pkg::cache_t  [NumNarrowReq-1:0]                        s_axi_narrow_awcache,
  input  axi_pkg::prot_t   [NumNarrowReq-1:0]                        s_axi_narrow_awprot,
  input  axi_pkg::qos_t    [NumNarrowReq-1:0]                        s_axi_narrow_awqos,
  input  axi_pkg::region_t [NumNarrowReq-1:0]                        s_axi_narrow_awregion,
  input  axi_pkg::atop_t   [NumNarrowReq-1:0]                        s_axi_narrow_awatop,
  input  logic             [NumNarrowReq-1:0]                        s_axi_narrow_awuser,
  input  logic             [NumNarrowReq-1:0]                        s_axi_narrow_wvalid,
  input  logic             [NumNarrowReq-1:0][NarrowDataWidth  -1:0] s_axi_narrow_wdata,
  input  logic             [NumNarrowReq-1:0][NarrowDataWidth/8-1:0] s_axi_narrow_wstrb,
  input  logic             [NumNarrowReq-1:0]                        s_axi_narrow_wlast,
  input  logic             [NumNarrowReq-1:0]                        s_axi_narrow_wuser,
  input  logic             [NumNarrowReq-1:0]                        s_axi_narrow_bready,
  input  logic             [NumNarrowReq-1:0]                        s_axi_narrow_arvalid,
  input  logic             [NumNarrowReq-1:0][       AxiIdWidth-1:0] s_axi_narrow_arid,
  input  logic             [NumNarrowReq-1:0][        AddrWidth-1:0] s_axi_narrow_araddr,
  input  axi_pkg::len_t    [NumNarrowReq-1:0]                        s_axi_narrow_arlen,
  input  axi_pkg::size_t   [NumNarrowReq-1:0]                        s_axi_narrow_arsize,
  input  axi_pkg::burst_t  [NumNarrowReq-1:0]                        s_axi_narrow_arburst,
  input  logic             [NumNarrowReq-1:0]                        s_axi_narrow_arlock,
  input  axi_pkg::cache_t  [NumNarrowReq-1:0]                        s_axi_narrow_arcache,
  input  axi_pkg::prot_t   [NumNarrowReq-1:0]                        s_axi_narrow_arprot,
  input  axi_pkg::qos_t    [NumNarrowReq-1:0]                        s_axi_narrow_arqos,
  input  axi_pkg::region_t [NumNarrowReq-1:0]                        s_axi_narrow_arregion,
  input  logic             [NumNarrowReq-1:0]                        s_axi_narrow_aruser,
  input  logic             [NumNarrowReq-1:0]                        s_axi_narrow_rready,
  output logic             [NumNarrowReq-1:0]                        s_axi_narrow_awready,
  output logic             [NumNarrowReq-1:0]                        s_axi_narrow_arready,
  output logic             [NumNarrowReq-1:0]                        s_axi_narrow_wready,
  output logic             [NumNarrowReq-1:0]                        s_axi_narrow_bvalid,
  output logic             [NumNarrowReq-1:0][       AxiIdWidth-1:0] s_axi_narrow_bid,
  output axi_pkg::resp_t   [NumNarrowReq-1:0]                        s_axi_narrow_bresp,
  output logic             [NumNarrowReq-1:0]                        s_axi_narrow_buser,
  output logic             [NumNarrowReq-1:0]                        s_axi_narrow_rvalid,
  output logic             [NumNarrowReq-1:0][       AxiIdWidth-1:0] s_axi_narrow_rid,
  output logic             [NumNarrowReq-1:0][NarrowDataWidth  -1:0] s_axi_narrow_rdata,
  output axi_pkg::resp_t   [NumNarrowReq-1:0]                        s_axi_narrow_rresp,
  output logic             [NumNarrowReq-1:0]                        s_axi_narrow_rlast,
  output logic             [NumNarrowReq-1:0]                        s_axi_narrow_ruser,

  input  logic             [NumWideReq-1:0]                      s_axi_wide_awvalid,
  input  logic             [NumWideReq-1:0][     AxiIdWidth-1:0] s_axi_wide_awid,
  input  logic             [NumWideReq-1:0][      AddrWidth-1:0] s_axi_wide_awaddr,
  input  axi_pkg::len_t    [NumWideReq-1:0]                      s_axi_wide_awlen,
  input  axi_pkg::size_t   [NumWideReq-1:0]                      s_axi_wide_awsize,
  input  axi_pkg::burst_t  [NumWideReq-1:0]                      s_axi_wide_awburst,
  input  logic             [NumWideReq-1:0]                      s_axi_wide_awlock,
  input  axi_pkg::cache_t  [NumWideReq-1:0]                      s_axi_wide_awcache,
  input  axi_pkg::prot_t   [NumWideReq-1:0]                      s_axi_wide_awprot,
  input  axi_pkg::qos_t    [NumWideReq-1:0]                      s_axi_wide_awqos,
  input  axi_pkg::region_t [NumWideReq-1:0]                      s_axi_wide_awregion,
  input  axi_pkg::atop_t   [NumWideReq-1:0]                      s_axi_wide_awatop,
  input  logic             [NumWideReq-1:0]                      s_axi_wide_awuser,
  input  logic             [NumWideReq-1:0]                      s_axi_wide_wvalid,
  input  logic             [NumWideReq-1:0][WideDataWidth  -1:0] s_axi_wide_wdata,
  input  logic             [NumWideReq-1:0][WideDataWidth/8-1:0] s_axi_wide_wstrb,
  input  logic             [NumWideReq-1:0]                      s_axi_wide_wlast,
  input  logic             [NumWideReq-1:0]                      s_axi_wide_wuser,
  input  logic             [NumWideReq-1:0]                      s_axi_wide_bready,
  input  logic             [NumWideReq-1:0]                      s_axi_wide_arvalid,
  input  logic             [NumWideReq-1:0][     AxiIdWidth-1:0] s_axi_wide_arid,
  input  logic             [NumWideReq-1:0][      AddrWidth-1:0] s_axi_wide_araddr,
  input  axi_pkg::len_t    [NumWideReq-1:0]                      s_axi_wide_arlen,
  input  axi_pkg::size_t   [NumWideReq-1:0]                      s_axi_wide_arsize,
  input  axi_pkg::burst_t  [NumWideReq-1:0]                      s_axi_wide_arburst,
  input  logic             [NumWideReq-1:0]                      s_axi_wide_arlock,
  input  axi_pkg::cache_t  [NumWideReq-1:0]                      s_axi_wide_arcache,
  input  axi_pkg::prot_t   [NumWideReq-1:0]                      s_axi_wide_arprot,
  input  axi_pkg::qos_t    [NumWideReq-1:0]                      s_axi_wide_arqos,
  input  axi_pkg::region_t [NumWideReq-1:0]                      s_axi_wide_arregion,
  input  logic             [NumWideReq-1:0]                      s_axi_wide_aruser,
  input  logic             [NumWideReq-1:0]                      s_axi_wide_rready,
  output logic             [NumWideReq-1:0]                      s_axi_wide_awready,
  output logic             [NumWideReq-1:0]                      s_axi_wide_arready,
  output logic             [NumWideReq-1:0]                      s_axi_wide_wready,
  output logic             [NumWideReq-1:0]                      s_axi_wide_bvalid,
  output logic             [NumWideReq-1:0][     AxiIdWidth-1:0] s_axi_wide_bid,
  output axi_pkg::resp_t   [NumWideReq-1:0]                      s_axi_wide_bresp,
  output logic             [NumWideReq-1:0]                      s_axi_wide_buser,
  output logic             [NumWideReq-1:0]                      s_axi_wide_rvalid,
  output logic             [NumWideReq-1:0][     AxiIdWidth-1:0] s_axi_wide_rid,
  output logic             [NumWideReq-1:0][WideDataWidth  -1:0] s_axi_wide_rdata,
  output axi_pkg::resp_t   [NumWideReq-1:0]                      s_axi_wide_rresp,
  output logic             [NumWideReq-1:0]                      s_axi_wide_rlast,
  output logic             [NumWideReq-1:0]                      s_axi_wide_ruser

);
  `AXI_TYPEDEF_ALL(axi_narrow,
      logic[AddrWidth-1:0],
      logic[AxiIdWidth-1:0],
      logic[NarrowDataWidth-1:0],
      logic[NarrowDataWidth/8-1:0],
      logic)
  `AXI_TYPEDEF_ALL(axi_wide,
      logic[AddrWidth-1:0],
      logic[AxiIdWidth-1:0],
      logic[WideDataWidth-1:0],
      logic[WideDataWidth/8-1:0],
      logic)

  axi_narrow_req_t  [NumNarrowReq-1:0] narrow_req;
  axi_narrow_resp_t [NumNarrowReq-1:0] narrow_rsp;
  axi_wide_req_t    [NumWideReq  -1:0] wide_req;
  axi_wide_resp_t   [NumWideReq  -1:0] wide_rsp;

  axi_narrow_req_t  [NumNarrowReq-1:0] narrow_cut_req;
  axi_narrow_resp_t [NumNarrowReq-1:0] narrow_cut_rsp;
  axi_wide_req_t    [NumWideReq  -1:0] wide_cut_req;
  axi_wide_resp_t   [NumWideReq  -1:0] wide_cut_rsp;

  for (genvar i = 0; i < NumNarrowReq; i++) begin : gen_narrow_assign
    assign narrow_req[i].aw_valid  = s_axi_narrow_awvalid [i];
    assign narrow_req[i].aw.id     = s_axi_narrow_awid    [i];
    assign narrow_req[i].aw.addr   = s_axi_narrow_awaddr  [i];
    assign narrow_req[i].aw.len    = s_axi_narrow_awlen   [i];
    assign narrow_req[i].aw.size   = s_axi_narrow_awsize  [i];
    assign narrow_req[i].aw.burst  = s_axi_narrow_awburst [i];
    assign narrow_req[i].aw.lock   = s_axi_narrow_awlock  [i];
    assign narrow_req[i].aw.cache  = s_axi_narrow_awcache [i];
    assign narrow_req[i].aw.prot   = s_axi_narrow_awprot  [i];
    assign narrow_req[i].aw.qos    = s_axi_narrow_awqos   [i];
    assign narrow_req[i].aw.region = s_axi_narrow_awregion[i];
    assign narrow_req[i].aw.atop   = s_axi_narrow_awatop  [i];
    assign narrow_req[i].aw.user   = s_axi_narrow_awuser  [i];
    assign narrow_req[i].w_valid   = s_axi_narrow_wvalid  [i];
    assign narrow_req[i].w.data    = s_axi_narrow_wdata   [i];
    assign narrow_req[i].w.strb    = s_axi_narrow_wstrb   [i];
    assign narrow_req[i].w.last    = s_axi_narrow_wlast   [i];
    assign narrow_req[i].w.user    = s_axi_narrow_wuser   [i];
    assign narrow_req[i].b_ready   = s_axi_narrow_bready  [i];
    assign narrow_req[i].ar_valid  = s_axi_narrow_arvalid [i];
    assign narrow_req[i].ar.id     = s_axi_narrow_arid    [i];
    assign narrow_req[i].ar.addr   = s_axi_narrow_araddr  [i];
    assign narrow_req[i].ar.len    = s_axi_narrow_arlen   [i];
    assign narrow_req[i].ar.size   = s_axi_narrow_arsize  [i];
    assign narrow_req[i].ar.burst  = s_axi_narrow_arburst [i];
    assign narrow_req[i].ar.lock   = s_axi_narrow_arlock  [i];
    assign narrow_req[i].ar.cache  = s_axi_narrow_arcache [i];
    assign narrow_req[i].ar.prot   = s_axi_narrow_arprot  [i];
    assign narrow_req[i].ar.qos    = s_axi_narrow_arqos   [i];
    assign narrow_req[i].ar.region = s_axi_narrow_arregion[i];
    assign narrow_req[i].ar.user   = s_axi_narrow_aruser  [i];
    assign narrow_req[i].r_ready   = s_axi_narrow_rready  [i];
    assign s_axi_narrow_awready[i] = narrow_rsp[i].aw_ready;
    assign s_axi_narrow_arready[i] = narrow_rsp[i].ar_ready;
    assign s_axi_narrow_wready [i] = narrow_rsp[i].w_ready;
    assign s_axi_narrow_bvalid [i] = narrow_rsp[i].b_valid;
    assign s_axi_narrow_bid    [i] = narrow_rsp[i].b.id;
    assign s_axi_narrow_bresp  [i] = narrow_rsp[i].b.resp;
    assign s_axi_narrow_buser  [i] = narrow_rsp[i].b.user;
    assign s_axi_narrow_rvalid [i] = narrow_rsp[i].r_valid;
    assign s_axi_narrow_rid    [i] = narrow_rsp[i].r.id;
    assign s_axi_narrow_rdata  [i] = narrow_rsp[i].r.data;
    assign s_axi_narrow_rresp  [i] = narrow_rsp[i].r.resp;
    assign s_axi_narrow_rlast  [i] = narrow_rsp[i].r.last;
    assign s_axi_narrow_ruser  [i] = narrow_rsp[i].r.user;

    axi_cut #(
      .aw_chan_t ( axi_narrow_aw_chan_t ),
      .w_chan_t  ( axi_narrow_w_chan_t  ),
      .b_chan_t  ( axi_narrow_b_chan_t  ),
      .ar_chan_t ( axi_narrow_ar_chan_t ),
      .r_chan_t  ( axi_narrow_r_chan_t  ),
      .axi_req_t ( axi_narrow_req_t     ),
      .axi_resp_t( axi_narrow_resp_t    )
    ) i_cut (
      .clk_i,
      .rst_ni,
      .slv_req_i ( narrow_req    [i] ),
      .slv_resp_o( narrow_rsp    [i] ),
      .mst_req_o ( narrow_cut_req[i] ),
      .mst_resp_i( narrow_cut_rsp[i] )
    );
  end

  for (genvar i = 0; i < NumWideReq; i++) begin : gen_wide_assign
    assign wide_req[i].aw_valid  = s_axi_wide_awvalid [i];
    assign wide_req[i].aw.id     = s_axi_wide_awid    [i];
    assign wide_req[i].aw.addr   = s_axi_wide_awaddr  [i];
    assign wide_req[i].aw.len    = s_axi_wide_awlen   [i];
    assign wide_req[i].aw.size   = s_axi_wide_awsize  [i];
    assign wide_req[i].aw.burst  = s_axi_wide_awburst [i];
    assign wide_req[i].aw.lock   = s_axi_wide_awlock  [i];
    assign wide_req[i].aw.cache  = s_axi_wide_awcache [i];
    assign wide_req[i].aw.prot   = s_axi_wide_awprot  [i];
    assign wide_req[i].aw.qos    = s_axi_wide_awqos   [i];
    assign wide_req[i].aw.region = s_axi_wide_awregion[i];
    assign wide_req[i].aw.atop   = s_axi_wide_awatop  [i];
    assign wide_req[i].aw.user   = s_axi_wide_awuser  [i];
    assign wide_req[i].w_valid   = s_axi_wide_wvalid  [i];
    assign wide_req[i].w.data    = s_axi_wide_wdata   [i];
    assign wide_req[i].w.strb    = s_axi_wide_wstrb   [i];
    assign wide_req[i].w.last    = s_axi_wide_wlast   [i];
    assign wide_req[i].w.user    = s_axi_wide_wuser   [i];
    assign wide_req[i].b_ready   = s_axi_wide_bready  [i];
    assign wide_req[i].ar_valid  = s_axi_wide_arvalid [i];
    assign wide_req[i].ar.id     = s_axi_wide_arid    [i];
    assign wide_req[i].ar.addr   = s_axi_wide_araddr  [i];
    assign wide_req[i].ar.len    = s_axi_wide_arlen   [i];
    assign wide_req[i].ar.size   = s_axi_wide_arsize  [i];
    assign wide_req[i].ar.burst  = s_axi_wide_arburst [i];
    assign wide_req[i].ar.lock   = s_axi_wide_arlock  [i];
    assign wide_req[i].ar.cache  = s_axi_wide_arcache [i];
    assign wide_req[i].ar.prot   = s_axi_wide_arprot  [i];
    assign wide_req[i].ar.qos    = s_axi_wide_arqos   [i];
    assign wide_req[i].ar.region = s_axi_wide_arregion[i];
    assign wide_req[i].ar.user   = s_axi_wide_aruser  [i];
    assign wide_req[i].r_ready   = s_axi_wide_rready  [i];
    assign s_axi_wide_awready[i] = wide_rsp[i].aw_ready;
    assign s_axi_wide_arready[i] = wide_rsp[i].ar_ready;
    assign s_axi_wide_wready [i] = wide_rsp[i].w_ready;
    assign s_axi_wide_bvalid [i] = wide_rsp[i].b_valid;
    assign s_axi_wide_bid    [i] = wide_rsp[i].b.id;
    assign s_axi_wide_bresp  [i] = wide_rsp[i].b.resp;
    assign s_axi_wide_buser  [i] = wide_rsp[i].b.user;
    assign s_axi_wide_rvalid [i] = wide_rsp[i].r_valid;
    assign s_axi_wide_rid    [i] = wide_rsp[i].r.id;
    assign s_axi_wide_rdata  [i] = wide_rsp[i].r.data;
    assign s_axi_wide_rresp  [i] = wide_rsp[i].r.resp;
    assign s_axi_wide_rlast  [i] = wide_rsp[i].r.last;
    assign s_axi_wide_ruser  [i] = wide_rsp[i].r.user;

    axi_cut #(
      .aw_chan_t ( axi_wide_aw_chan_t ),
      .w_chan_t  ( axi_wide_w_chan_t  ),
      .b_chan_t  ( axi_wide_b_chan_t  ),
      .ar_chan_t ( axi_wide_ar_chan_t ),
      .r_chan_t  ( axi_wide_r_chan_t  ),
      .axi_req_t ( axi_wide_req_t     ),
      .axi_resp_t( axi_wide_resp_t    )
    ) i_cut (
      .clk_i,
      .rst_ni,
      .slv_req_i ( wide_req    [i] ),
      .slv_resp_o( wide_rsp    [i] ),
      .mst_req_o ( wide_cut_req[i] ),
      .mst_resp_i( wide_cut_rsp[i] )
    );
  end

  axi_memory_island_wrap #(
    .AddrWidth            ( AddrWidth         ),
    .NarrowDataWidth      ( NarrowDataWidth   ),
    .WideDataWidth        ( WideDataWidth     ),
    .AxiNarrowIdWidth     ( AxiIdWidth        ),
    .AxiWideIdWidth       ( AxiIdWidth        ),
    .axi_narrow_req_t     ( axi_narrow_req_t  ),
    .axi_narrow_rsp_t     ( axi_narrow_resp_t ),
    .axi_wide_req_t       ( axi_wide_req_t    ),
    .axi_wide_rsp_t       ( axi_wide_resp_t   ),
    .NumNarrowReq         ( NumNarrowReq      ),
    .NumWideReq           ( NumWideReq        ),
    .WordsPerBank         ( WordsPerBank      ),
    .SpillNarrowReqEntry (0),
    .SpillNarrowRspEntry (0),
    .SpillNarrowReqRouted(0),
    .SpillNarrowRspRouted(0),
    .SpillWideReqEntry   (0),
    .SpillWideRspEntry   (0),
    .SpillWideReqRouted  (0),
    .SpillWideRspRouted  (0),
    .SpillWideReqSplit   (0),
    .SpillWideRspSplit   (0),
    .SpillReqBank        (0),
    .SpillRspBank        (1),
    .WidePriorityWait    (2)
  ) i_mem_island (
    .clk_i,
    .rst_ni,

    .axi_narrow_req_i ( narrow_cut_req ),
    .axi_narrow_rsp_o ( narrow_cut_rsp ),

    .axi_wide_req_i   ( wide_cut_req   ),
    .axi_wide_rsp_o   ( wide_cut_rsp   )
);

endmodule
