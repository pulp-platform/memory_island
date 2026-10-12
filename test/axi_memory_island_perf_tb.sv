// Copyright 2026 ETH Zurich and University of Bologna.
// Solderpad Hardware License, Version 0.51, see LICENSE for details.
// SPDX-License-Identifier: SHL-0.51

// AXI-level performance testbench for event accumulation into the memory island.
//
// Drives the four narrow and one wide AXI ports of `axi_memory_island_wrap`. The sensor port
// (index 3) issues AXI AtomicStore+ADD writes that accumulate int8 event counters in a frame
// buffer; the other ports run background traffic. The adds are executed by a per-lane signed
// saturating adder in each bank's ecc_sram read-modify-write stage, so one AXI write can update a
// whole word of consecutive counters.
//
// Because the number of events one AXI write carries depends on +MERGE, every scenario reports
// both AXI transactions and events.
//
// Parameters set per run with vsim -G:
//   AccumEnabled    memory-side accumulation in the island (1 = on, 0 = baseline)
//   NarrowExtraBF   narrow banking factor multiplier
//
// Plusargs:
//   +SCENARIO=P1|P2|P3|P4  traffic scenario (default P1)
//   +MERGE=0|1             sensor merges a cluster into word-wide writes (default 0)
//   +CYCLES=<n>            measured cycles (default 20000)
//
// Scenarios (sensor traffic / background traffic). With AccumEnabled = 0 the sensor issues plain
// writes instead of ATOP ADD, which gives the reference point without accumulation.
//   P1  sensor ATOP ADD at full rate, event clusters   / none        peak accumulation rate
//   P2  sensor ATOP ADD at full rate, all to one word  / none        worst-case serialization
//   P3  sensor ATOP ADD at 10 M events/s               / full        expected operating point
//   P4  sensor ATOP ADD at full rate                   / full        contention worst case
//
// Background traffic (P3, P4): port 0 host, 20% injection, random single-beat reads and writes
// with 30% of writes sub-word; port 1 DmaR, sequential 16-beat read bursts; port 2 DmaW,
// sequential 16-beat write bursts; wide port, sequential 16-beat bursts alternating read/write.
//
// Seed the traffic with vsim -sv_seed.

`include "axi/typedef.svh"

module axi_memory_island_perf_tb #(
  parameter int unsigned NarrowExtraBF     = 1,
  parameter bit          AccumEnabled      = 1'b1,
  parameter int unsigned NumWideBanks      = 2,
  parameter int unsigned WordsPerBank      = 16384,
  parameter int unsigned BankAccessLatency = 1,
  parameter int unsigned WidePriorityWait  = 3,
  parameter time         CyclTime          = 10ns,
  parameter int unsigned WatchdogCycles    = 5 * 1000 * 1000,
  /// Write transactions the sensor master keeps in flight (AXI credits)
  parameter int unsigned SensorOutstanding = 4
) ();

  localparam int unsigned AddrWidth        = 32;
  localparam int unsigned NarrowDataWidth  = 32;
  localparam int unsigned WideDataWidth    = 256;
  localparam int unsigned AxiNarrowIdWidth = 4;
  localparam int unsigned AxiWideIdWidth   = 5;
  localparam int unsigned AxiUserWidth     = 1;
  localparam int unsigned NumNarrowReq     = 4;
  localparam int unsigned NumWideReq       = 1;

  localparam int unsigned NarrowStrbWidth = NarrowDataWidth / 8;
  localparam int unsigned WideStrbWidth   = WideDataWidth / 8;
  localparam int unsigned NarrowWordBit   = $clog2(NarrowStrbWidth);
  localparam int unsigned WideWordBit     = $clog2(WideStrbWidth);
  localparam int unsigned BurstLen        = 16;


  // Port roles
  localparam int unsigned PortHost   = 0;
  localparam int unsigned PortDmaR   = 1;
  localparam int unsigned PortDmaW   = 2;
  localparam int unsigned PortSensor = 3;

  // Disjoint address regions, so the frame checker only ever sees sensor traffic
  localparam logic [AddrWidth-1:0] HostBase   = 32'h0000_0000;  //  64 KiB
  localparam logic [AddrWidth-1:0] HostSize   = 32'h0001_0000;
  localparam logic [AddrWidth-1:0] DmaSrcBase = 32'h0001_0000;  // 128 KiB
  localparam logic [AddrWidth-1:0] DmaDstBase = 32'h0004_0000;  // 128 KiB
  localparam logic [AddrWidth-1:0] WideBase   = 32'h0008_0000;  // 128 KiB
  localparam logic [AddrWidth-1:0] DmaSize    = 32'h0002_0000;
  localparam logic [AddrWidth-1:0] WideSize   = 32'h0002_0000;
  localparam logic [AddrWidth-1:0] FrameBase  = 32'h000C_0000;
  // Scratch word block for the directed phase, outside the frame
  localparam logic [AddrWidth-1:0] ScratchBase = 32'h000F_0000;

  // Event frame: int8 counters, row major, addr = FrameBase + y*FrameW + x
  localparam int unsigned FrameW = 320;
  localparam int unsigned FrameH = 240;

  // 10 M events/s at 1 GHz is one event per 100 cycles; a cluster averages 15 events
  localparam int unsigned ClusterPeriod = 1500;

  // The ATOP code the island executes as an accumulate
  localparam axi_pkg::atop_t AtopAdd = {axi_pkg::ATOP_ATOMICSTORE, 1'b0, axi_pkg::ATOP_ADD};

  logic clk, rst_n;

  clk_rst_gen #(
    .RstClkCycles(5),
    .ClkPeriod   (CyclTime)
  ) i_clk_gen (
    .clk_o (clk),
    .rst_no(rst_n)
  );

  //////////////////
  // AXI plumbing //
  //////////////////

  `AXI_TYPEDEF_ALL(narrow, logic [AddrWidth-1:0], logic [AxiNarrowIdWidth-1:0],
                   logic [NarrowDataWidth-1:0], logic [NarrowStrbWidth-1:0],
                   logic [AxiUserWidth-1:0])
  `AXI_TYPEDEF_ALL(wide, logic [AddrWidth-1:0], logic [AxiWideIdWidth-1:0],
                   logic [WideDataWidth-1:0], logic [WideStrbWidth-1:0],
                   logic [AxiUserWidth-1:0])

  narrow_req_t  [NumNarrowReq-1:0] narrow_req;
  narrow_resp_t [NumNarrowReq-1:0] narrow_rsp;
  wide_req_t    [  NumWideReq-1:0] wide_req;
  wide_resp_t   [  NumWideReq-1:0] wide_rsp;

  axi_memory_island_wrap #(
    .AddrWidth           (AddrWidth),
    .NarrowDataWidth     (NarrowDataWidth),
    .WideDataWidth       (WideDataWidth),
    .AxiNarrowIdWidth    (AxiNarrowIdWidth),
    .AxiWideIdWidth      (AxiWideIdWidth),
    .axi_narrow_req_t    (narrow_req_t),
    .axi_narrow_rsp_t    (narrow_resp_t),
    .axi_wide_req_t      (wide_req_t),
    .axi_wide_rsp_t      (wide_resp_t),
    .NumNarrowReq        (NumNarrowReq),
    .NumWideReq          (NumWideReq),
    .AccumEnabled        (AccumEnabled),
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
    .SpillRspBank        (0),
    .WidePriorityWait    (WidePriorityWait),
    .NumWideBanks        (NumWideBanks),
    .NarrowExtraBF       (NarrowExtraBF),
    .WordsPerBank        (WordsPerBank),
    .MemorySimInit       ("zeros"),
    .BankAccessLatency   (BankAccessLatency)
  ) i_dut (
    .clk_i           (clk),
    .rst_ni          (rst_n),
    .axi_narrow_req_i(narrow_req),
    .axi_narrow_rsp_o(narrow_rsp),
    .axi_wide_req_i  (wide_req),
    .axi_wide_rsp_o  (wide_rsp)
  );

  //////////////
  // Plusargs //
  //////////////

  string       scenario = "P1";
  int unsigned merge    = 0;
  int unsigned cycles   = 20000;
  logic        background_on, sensor_rate_limited, sensor_one_word;

  initial begin
    void'($value$plusargs("SCENARIO=%s", scenario));
    void'($value$plusargs("MERGE=%d", merge));
    void'($value$plusargs("CYCLES=%d", cycles));

    background_on       = (scenario == "P3") || (scenario == "P4");
    sensor_rate_limited = (scenario == "P3");
    sensor_one_word     = (scenario == "P2");
  end

  ///////////////
  // Add model //
  ///////////////

  // What the per-bank adder does: one independent signed saturating 8-bit adder per lane
  function automatic logic [NarrowDataWidth-1:0] model_accum(
      logic [NarrowDataWidth-1:0] mem, logic [NarrowDataWidth-1:0] addend,
      logic [NarrowStrbWidth-1:0] strb);
    logic [NarrowDataWidth-1:0] res;
    int                         s;
    res = mem;
    for (int b = 0; b < NarrowStrbWidth; b++) begin
      if (strb[b]) begin
        s = $signed(mem[8*b+:8]) + $signed(addend[8*b+:8]);
        if (s > 127) s = 127;
        if (s < -128) s = -128;
        res[8*b+:8] = s[7:0];
      end
    end
    return res;
  endfunction

  /////////////////////
  // Shadow of frame //
  /////////////////////

  // Word-aligned address -> expected content. Only words the sensor touched are tracked.
  logic [NarrowDataWidth-1:0] shadow[logic [AddrWidth-1:0]];

  function automatic void shadow_add(logic [AddrWidth-1:0] word_addr,
                                     logic [NarrowDataWidth-1:0] addend,
                                     logic [NarrowStrbWidth-1:0] strb);
    logic [NarrowDataWidth-1:0] cur;
    cur = shadow.exists(word_addr) ? shadow[word_addr] : '0;
    shadow[word_addr] = model_accum(cur, addend, strb);
  endfunction

  function automatic void shadow_write(logic [AddrWidth-1:0] word_addr,
                                       logic [NarrowDataWidth-1:0] data,
                                       logic [NarrowStrbWidth-1:0] strb);
    logic [NarrowDataWidth-1:0] cur;
    cur = shadow.exists(word_addr) ? shadow[word_addr] : '0;
    for (int b = 0; b < NarrowStrbWidth; b++) if (strb[b]) cur[8*b+:8] = data[8*b+:8];
    shadow[word_addr] = cur;
  endfunction

  ///////////////////////
  // Driven AXI inputs //
  ///////////////////////

  // Unpacked so that each port's agent drives a separate variable
  logic                       aw_valid[NumNarrowReq] = '{default: 1'b0};
  logic                       w_valid [NumNarrowReq] = '{default: 1'b0};
  logic                       w_last  [NumNarrowReq] = '{default: 1'b0};
  logic                       ar_valid[NumNarrowReq] = '{default: 1'b0};
  logic [      AddrWidth-1:0] aw_addr [NumNarrowReq] = '{default: '0};
  logic [      AddrWidth-1:0] ar_addr [NumNarrowReq] = '{default: '0};
  logic [                7:0] aw_len  [NumNarrowReq] = '{default: '0};
  logic [                7:0] ar_len  [NumNarrowReq] = '{default: '0};
  logic [                5:0] aw_atop [NumNarrowReq] = '{default: '0};
  logic [NarrowDataWidth-1:0] w_data  [NumNarrowReq] = '{default: '0};
  logic [NarrowStrbWidth-1:0] w_strb  [NumNarrowReq] = '{default: '0};

  for (genvar p = 0; p < NumNarrowReq; p++) begin : gen_narrow_drive
    always_comb begin
      narrow_req[p]          = '0;
      narrow_req[p].aw.id    = AxiNarrowIdWidth'(p);
      narrow_req[p].aw.addr  = aw_addr[p];
      narrow_req[p].aw.len   = aw_len[p];
      narrow_req[p].aw.size  = 3'd2;
      narrow_req[p].aw.burst = axi_pkg::BURST_INCR;
      narrow_req[p].aw.atop  = aw_atop[p];
      narrow_req[p].aw_valid = aw_valid[p];
      narrow_req[p].w.data   = w_data[p];
      narrow_req[p].w.strb   = w_strb[p];
      narrow_req[p].w.last   = w_last[p];
      narrow_req[p].w_valid  = w_valid[p];
      narrow_req[p].b_ready  = 1'b1;
      narrow_req[p].ar.id    = AxiNarrowIdWidth'(p);
      narrow_req[p].ar.addr  = ar_addr[p];
      narrow_req[p].ar.len   = ar_len[p];
      narrow_req[p].ar.size  = 3'd2;
      narrow_req[p].ar.burst = axi_pkg::BURST_INCR;
      narrow_req[p].ar_valid = ar_valid[p];
      narrow_req[p].r_ready  = 1'b1;
    end
  end

  logic                     wd_aw_valid = 1'b0, wd_w_valid = 1'b0;
  logic                     wd_w_last = 1'b0, wd_ar_valid = 1'b0;
  logic [    AddrWidth-1:0] wd_aw_addr = '0, wd_ar_addr = '0;
  logic [              7:0] wd_aw_len = '0, wd_ar_len = '0;
  logic [WideDataWidth-1:0] wd_w_data = '0;

  always_comb begin
    wide_req[0]          = '0;
    wide_req[0].aw.addr  = wd_aw_addr;
    wide_req[0].aw.len   = wd_aw_len;
    wide_req[0].aw.size  = 3'(WideWordBit);
    wide_req[0].aw.burst = axi_pkg::BURST_INCR;
    wide_req[0].aw_valid = wd_aw_valid;
    wide_req[0].w.data   = wd_w_data;
    wide_req[0].w.strb   = '1;
    wide_req[0].w.last   = wd_w_last;
    wide_req[0].w_valid  = wd_w_valid;
    wide_req[0].b_ready  = 1'b1;
    wide_req[0].ar.addr  = wd_ar_addr;
    wide_req[0].ar.len   = wd_ar_len;
    wide_req[0].ar.size  = 3'(WideWordBit);
    wide_req[0].ar.burst = axi_pkg::BURST_INCR;
    wide_req[0].ar_valid = wd_ar_valid;
    wide_req[0].r_ready  = 1'b1;
  end

  ////////////////
  // Statistics //
  ////////////////

  logic            measure = 1'b0;
  longint unsigned cyc = 0, now_cyc = 0;

  longint unsigned sensor_txn = 0, sensor_events = 0, sensor_lat_sum = 0, sensor_acc_sum = 0;
  longint unsigned sensor_lat_max = 0, sensor_acc_max = 0;
  longint unsigned n_wr_txn [NumNarrowReq] = '{default: 0};
  longint unsigned n_wr_beat[NumNarrowReq] = '{default: 0};
  longint unsigned n_rd_txn [NumNarrowReq] = '{default: 0};
  longint unsigned n_rd_beat[NumNarrowReq] = '{default: 0};
  longint unsigned wide_wr_beat = 0, wide_rd_beat = 0;

  always @(posedge clk) begin
    now_cyc++;
    if (measure) begin
      cyc++;
      for (int p = 0; p < NumNarrowReq; p++) begin
        if (narrow_req[p].w_valid && narrow_rsp[p].w_ready) n_wr_beat[p]++;
        if (narrow_rsp[p].r_valid && narrow_req[p].r_ready) n_rd_beat[p]++;
        if (narrow_req[p].aw_valid && narrow_rsp[p].aw_ready) n_wr_txn[p]++;
        if (narrow_req[p].ar_valid && narrow_rsp[p].ar_ready) n_rd_txn[p]++;
      end
      if (wide_req[0].w_valid && wide_rsp[0].w_ready) wide_wr_beat++;
      if (wide_rsp[0].r_valid && wide_req[0].r_ready) wide_rd_beat++;
    end
  end

  ///////////////////////
  // Sensor port agent //
  ///////////////////////

  typedef struct {
    logic [      AddrWidth-1:0] addr;
    logic [                7:0] len;
    logic [NarrowDataWidth-1:0] data;
    logic [NarrowStrbWidth-1:0] strb;
    logic [                5:0] atop;
    int unsigned                events;
    longint unsigned            issue_cyc;
    logic                       counted;
  } narrow_txn_t;

  narrow_txn_t     sensor_awq[$], sensor_wq[$], sensor_inflight[$];
  longint unsigned sensor_accept_q[$];
  int unsigned     sensor_outstanding = 0;

  // Hand a single-beat request to the sensor master. Blocks only while all AXI write credits are
  // in use, so up to SensorOutstanding adds can be in flight and the banks can pipeline.
  task automatic sensor_send(input narrow_txn_t txn);
    narrow_txn_t rec;
    while (sensor_outstanding >= SensorOutstanding) @(posedge clk);
    rec           = txn;
    rec.issue_cyc = now_cyc;
    rec.counted   = measure;
    sensor_awq.push_back(rec);
    sensor_inflight.push_back(rec);
    sensor_outstanding++;
    if (rec.counted) begin
      sensor_txn++;
      sensor_events += txn.events;
    end
    @(posedge clk);
  endtask

  // AW and W of one request are presented together; the next request follows as soon as both
  // channels are free again. W never runs ahead of its own AW.
  always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      aw_valid[PortSensor] <= 1'b0;
      w_valid [PortSensor] <= 1'b0;
    end else begin
      if (aw_valid[PortSensor] && narrow_rsp[PortSensor].aw_ready) begin
        sensor_accept_q.push_back(now_cyc);
      end
      if (!aw_valid[PortSensor] || narrow_rsp[PortSensor].aw_ready) begin
        if (sensor_awq.size() > 0) begin
          narrow_txn_t t;
          t = sensor_awq.pop_front();
          aw_addr [PortSensor] <= t.addr;
          aw_len  [PortSensor] <= t.len;
          aw_atop [PortSensor] <= t.atop;
          aw_valid[PortSensor] <= 1'b1;
          sensor_wq.push_back(t);
        end else begin
          aw_valid[PortSensor] <= 1'b0;
        end
      end
      if (!w_valid[PortSensor] || narrow_rsp[PortSensor].w_ready) begin
        if (sensor_wq.size() > 0) begin
          narrow_txn_t t;
          t = sensor_wq.pop_front();
          w_data [PortSensor] <= t.data;
          w_strb [PortSensor] <= t.strb;
          w_last [PortSensor] <= 1'b1;
          w_valid[PortSensor] <= 1'b1;
        end else begin
          w_valid[PortSensor] <= 1'b0;
        end
      end
    end
  end

  // The sensor uses a single AXI ID, so B responses come back in issue order
  always @(posedge clk) begin
    if (narrow_rsp[PortSensor].b_valid && narrow_req[PortSensor].b_ready &&
        sensor_inflight.size() > 0) begin
      narrow_txn_t     done;
      longint unsigned accepted;
      done = sensor_inflight.pop_front();
      if (sensor_outstanding > 0) sensor_outstanding--;
      accepted = (sensor_accept_q.size() > 0) ? sensor_accept_q.pop_front() : done.issue_cyc;
      if (done.counted) begin
        sensor_lat_sum += (now_cyc - done.issue_cyc);
        if ((now_cyc - done.issue_cyc) > sensor_lat_max) begin
          sensor_lat_max = now_cyc - done.issue_cyc;
        end
        sensor_acc_sum += (now_cyc - accepted);
        if ((now_cyc - accepted) > sensor_acc_max) sensor_acc_max = now_cyc - accepted;
      end
    end
  end

  // Wait for every sensor request to be answered on B
  task automatic drain_sensor();
    while (sensor_inflight.size() != 0) @(posedge clk);
  endtask

  //////////////////////
  // Event generation //
  //////////////////////

  // Issue one sensor write and mirror it in the shadow frame: an ATOP ADD with accumulation, a
  // plain write without it.
  task automatic sensor_event_write(input narrow_txn_t txn);
    if (AccumEnabled) begin
      txn.atop = AtopAdd;
      shadow_add(txn.addr, txn.data, txn.strb);
    end else begin
      shadow_write(txn.addr, txn.data, txn.strb);
    end
    sensor_send(txn);
  endtask

  // One cluster: 10 to 20 events on consecutive pixels of one row. MERGE=0 emits one AXI write
  // per event (single-lane strobe), MERGE=1 merges the pixels of each 32-bit word into one write.
  task automatic emit_cluster();
    int unsigned          x0, y0, n, x, i, lane;
    logic [AddrWidth-1:0] base, word_addr;
    logic [          7:0] addend;
    narrow_txn_t          txn;

    n  = $urandom_range(20, 10);
    y0 = $urandom_range(FrameH - 1, 0);
    x0 = $urandom_range(FrameW - 1 - n, 0);

    if (sensor_one_word) begin
      // Worst case: every add targets the same word, one lane at a time
      for (i = 0; i < n; i++) begin
        txn        = '{default: '0};
        txn.addr   = FrameBase;
        txn.strb   = NarrowStrbWidth'(1);
        txn.data   = 32'h0000_0001;
        txn.events = 1;
        sensor_event_write(txn);
      end
      return;
    end

    base   = FrameBase + y0 * FrameW;
    addend = $urandom_range(1, 0) ? 8'h01 : 8'hFF;  // polarity

    x = x0;
    while (x < x0 + n) begin
      word_addr = (base + x) & ~(AddrWidth'(NarrowStrbWidth - 1));
      txn       = '{default: '0};
      txn.addr  = word_addr;
      // One event per write, or with MERGE every event of the cluster that falls into this word
      do begin
        lane                = (base + x) % NarrowStrbWidth;
        txn.strb[lane]      = 1'b1;
        txn.data[8*lane+:8] = addend;
        txn.events++;
        x++;
      end while (merge != 0 && x < x0 + n &&
                 ((base + x) & ~(AddrWidth'(NarrowStrbWidth - 1))) == word_addr);
      sensor_event_write(txn);
    end
  endtask

  ////////////////////////
  // Background traffic //
  ////////////////////////

  // Host: single-beat random reads and writes, 30% of writes sub-word (triggers the ECC RMW)
  task automatic host_agent();
    logic [      AddrWidth-1:0] addr;
    logic [NarrowStrbWidth-1:0] strb;
    forever begin
      if (!background_on || !measure) begin
        @(posedge clk);
        continue;
      end
      if ($urandom_range(99, 0) >= 20) begin
        @(posedge clk);
        continue;
      end
      addr = HostBase + (AddrWidth'($urandom_range(HostSize / NarrowStrbWidth - 1, 0))
                         << NarrowWordBit);
      if ($urandom_range(1, 0)) begin
        strb = '1;
        if ($urandom_range(99, 0) < 30) begin
          if ($urandom_range(1, 0)) strb = NarrowStrbWidth'(1) << $urandom_range(3, 0);
          else strb = NarrowStrbWidth'(3) << (2 * $urandom_range(1, 0));
        end
        aw_addr [PortHost] <= addr;
        aw_len  [PortHost] <= 8'd0;
        aw_valid[PortHost] <= 1'b1;
        w_data  [PortHost] <= $urandom();
        w_strb  [PortHost] <= strb;
        w_last  [PortHost] <= 1'b1;
        w_valid [PortHost] <= 1'b1;
        fork
          begin
            do @(posedge clk); while (!narrow_rsp[PortHost].aw_ready);
            aw_valid[PortHost] <= 1'b0;
          end
          begin
            do @(posedge clk); while (!narrow_rsp[PortHost].w_ready);
            w_valid[PortHost] <= 1'b0;
          end
        join
      end else begin
        ar_addr [PortHost] <= addr;
        ar_len  [PortHost] <= 8'd0;
        ar_valid[PortHost] <= 1'b1;
        do @(posedge clk); while (!narrow_rsp[PortHost].ar_ready);
        ar_valid[PortHost] <= 1'b0;
      end
      @(posedge clk);
    end
  endtask

  // DmaR: back-to-back sequential read bursts, 64 B each and 64 B aligned (no 4 KiB crossing)
  task automatic dma_read_agent();
    int unsigned idx;
    idx = 0;
    forever begin
      if (!background_on || !measure) begin
        @(posedge clk);
        continue;
      end
      ar_addr [PortDmaR] <= DmaSrcBase +
          (AddrWidth'((idx * BurstLen) << NarrowWordBit) % (DmaSize - 32'd64));
      ar_len  [PortDmaR] <= 8'(BurstLen - 1);
      ar_valid[PortDmaR] <= 1'b1;
      do @(posedge clk); while (!narrow_rsp[PortDmaR].ar_ready);
      ar_valid[PortDmaR] <= 1'b0;
      idx++;
    end
  endtask

  // DmaW: back-to-back sequential write bursts
  task automatic dma_write_agent();
    int unsigned idx, beat;
    idx = 0;
    forever begin
      if (!background_on || !measure) begin
        @(posedge clk);
        continue;
      end
      aw_addr [PortDmaW] <= DmaDstBase +
          (AddrWidth'((idx * BurstLen) << NarrowWordBit) % (DmaSize - 32'd64));
      aw_len  [PortDmaW] <= 8'(BurstLen - 1);
      aw_valid[PortDmaW] <= 1'b1;
      w_strb  [PortDmaW] <= '1;
      fork
        begin
          do @(posedge clk); while (!narrow_rsp[PortDmaW].aw_ready);
          aw_valid[PortDmaW] <= 1'b0;
        end
        begin
          for (beat = 0; beat < BurstLen; beat++) begin
            w_data [PortDmaW] <= $urandom();
            w_last [PortDmaW] <= (beat == BurstLen - 1);
            w_valid[PortDmaW] <= 1'b1;
            do @(posedge clk); while (!narrow_rsp[PortDmaW].w_ready);
          end
          w_valid[PortDmaW] <= 1'b0;
        end
      join
      idx++;
    end
  endtask

  // Wide: sequential 512 B bursts, alternating read and write
  task automatic wide_agent();
    int unsigned idx, beat;
    idx = 0;
    forever begin
      if (!background_on || !measure) begin
        @(posedge clk);
        continue;
      end
      if (idx % 2 == 0) begin
        wd_aw_addr  <= WideBase + (AddrWidth'((idx * BurstLen) << WideWordBit) %
                                   (WideSize - 32'd512));
        wd_aw_len   <= 8'(BurstLen - 1);
        wd_aw_valid <= 1'b1;
        fork
          begin
            do @(posedge clk); while (!wide_rsp[0].aw_ready);
            wd_aw_valid <= 1'b0;
          end
          begin
            for (beat = 0; beat < BurstLen; beat++) begin
              wd_w_data  <= {WideDataWidth / 32{$urandom()}};
              wd_w_last  <= (beat == BurstLen - 1);
              wd_w_valid <= 1'b1;
              do @(posedge clk); while (!wide_rsp[0].w_ready);
            end
            wd_w_valid <= 1'b0;
          end
        join
      end else begin
        wd_ar_addr  <= WideBase + (AddrWidth'((idx * BurstLen) << WideWordBit) %
                                   (WideSize - 32'd512));
        wd_ar_len   <= 8'(BurstLen - 1);
        wd_ar_valid <= 1'b1;
        do @(posedge clk); while (!wide_rsp[0].ar_ready);
        wd_ar_valid <= 1'b0;
      end
      idx++;
    end
  endtask

  //////////////
  // Checking //
  //////////////

  int unsigned n_errors = 0;

  task automatic sensor_read(input logic [AddrWidth-1:0] addr,
                             output logic [NarrowDataWidth-1:0] data);
    ar_addr [PortSensor] <= addr;
    ar_len  [PortSensor] <= 8'd0;
    ar_valid[PortSensor] <= 1'b1;
    do @(posedge clk); while (!narrow_rsp[PortSensor].ar_ready);
    ar_valid[PortSensor] <= 1'b0;
    do @(posedge clk); while (!narrow_rsp[PortSensor].r_valid);
    data = narrow_rsp[PortSensor].r.data;
    @(posedge clk);
  endtask

  task automatic expect_word(input logic [AddrWidth-1:0] addr,
                             input logic [NarrowDataWidth-1:0] exp, input string what);
    logic [NarrowDataWidth-1:0] got;
    sensor_read(addr, got);
    if (got !== exp) begin
      n_errors++;
      $error("directed %s: at 0x%08x got 0x%08x expected 0x%08x", what, addr, got, exp);
    end
  endtask

  task automatic check_frame();
    logic [NarrowDataWidth-1:0] got;
    int unsigned                checked;
    checked = 0;
    foreach (shadow[a]) begin
      sensor_read(a, got);
      checked++;
      if (got !== shadow[a]) begin
        n_errors++;
        if (n_errors < 20) begin
          $error("frame mismatch at 0x%08x: got 0x%08x expected 0x%08x", a, got, shadow[a]);
        end
      end
    end
    $display("INFO checked %0d frame words, %0d error(s)", checked, n_errors);
  endtask

  /////////////////////
  // Directed checks //
  /////////////////////

  // Hand one single-beat write to the sensor master: a plain write, or an accumulate with AtopAdd
  task automatic sensor_write(input logic [AddrWidth-1:0] addr,
                              input logic [NarrowDataWidth-1:0] data,
                              input logic [NarrowStrbWidth-1:0] strb,
                              input axi_pkg::atop_t atop = '0);
    narrow_txn_t txn;
    txn      = '{default: '0};
    txn.addr = addr;
    txn.data = data;
    txn.strb = strb;
    txn.atop = atop;
    sensor_send(txn);
  endtask

  // Directed checks of the add semantics, run before the measurement window
  task automatic directed_phase();
    logic [NarrowDataWidth-1:0] exp;

    // 1. a single-byte +1 increments exactly once
    sensor_write(ScratchBase, 32'h0000_0005, '1);
    drain_sensor();
    sensor_write(ScratchBase, 32'h0000_0001, 4'b0001, AtopAdd);
    drain_sensor();
    expect_word(ScratchBase, 32'h0000_0006, "single byte +1");

    // 2. an addend of 0xFF decrements
    sensor_write(ScratchBase, 32'h0000_00FF, 4'b0001, AtopAdd);
    drain_sensor();
    expect_word(ScratchBase, 32'h0000_0005, "single byte -1");

    // 3. back-to-back adds, same byte then a neighbouring byte of the same word
    for (int i = 0; i < 4; i++) sensor_write(ScratchBase, 32'h0000_0001, 4'b0001, AtopAdd);
    for (int i = 0; i < 3; i++) sensor_write(ScratchBase, 32'h0000_0100, 4'b0010, AtopAdd);
    drain_sensor();
    expect_word(ScratchBase, 32'h0000_0309, "back-to-back same word");

    // 4. plain writes and reads on the same port still work around ATOPs
    sensor_write(ScratchBase + 4, 32'hDEAD_BEEF, '1);
    drain_sensor();
    sensor_write(ScratchBase, 32'h0000_0001, 4'b0001, AtopAdd);
    expect_word(ScratchBase + 4, 32'hDEAD_BEEF, "plain write");
    drain_sensor();
    expect_word(ScratchBase, 32'h0000_030A, "add after plain write");

    // 5. multi-lane add: every lane adds on its own, no carry into the neighbouring lane
    sensor_write(ScratchBase + 8, 32'h0505_0505, '1);
    drain_sensor();
    sensor_write(ScratchBase + 8, 32'h0101_0101, 4'b1111, AtopAdd);
    drain_sensor();
    exp = model_accum(32'h0505_0505, 32'h0101_0101, 4'b1111);
    expect_word(ScratchBase + 8, exp, "multi-lane add");

    // 6. clamp at both ends instead of wrapping
    sensor_write(ScratchBase + 12, 32'h807F_807F, '1);
    drain_sensor();
    sensor_write(ScratchBase + 12, 32'h01FF_FF01, 4'b1111, AtopAdd);
    drain_sensor();
    // lane0 7F+01 -> 7F, lane1 80+FF -> 80, lane2 7F+FF -> 7E, lane3 80+01 -> 81
    expect_word(ScratchBase + 12, 32'h817E_807F, "saturation clamp");

    $display("INFO directed phase done, %0d error(s)", n_errors);
  endtask

  ///////////////
  // Sequencer //
  ///////////////

  initial begin
    @(posedge rst_n);
    repeat (5) @(posedge clk);

    if (AccumEnabled) begin
      directed_phase();
      if (n_errors != 0) begin
        $display("SANITY FAIL");
        $finish;
      end
    end
    shadow.delete();

    fork
      host_agent();
      dma_read_agent();
      dma_write_agent();
      wide_agent();
    join_none

    measure = 1'b1;
    fork
      begin : sensor_thread
        // Pace on absolute cycles, not on "ClusterPeriod after the previous cluster finished
        // issuing": otherwise the achieved event rate depends on how fast the island retires the
        // adds, and the rate-limited scenario stops being a fixed 10 M events/s operating point.
        // If the island cannot keep up, the wait degenerates to zero and the shortfall shows up
        // in the event count.
        longint unsigned next_cluster;
        next_cluster = now_cyc;
        while (measure) begin
          emit_cluster();
          if (sensor_rate_limited) begin
            next_cluster += ClusterPeriod;
            while (now_cyc < next_cluster && measure) @(posedge clk);
          end
        end
      end
      begin : window
        repeat (cycles) @(posedge clk);
        measure = 1'b0;
      end
    join
    drain_sensor();
    repeat (100) @(posedge clk);

    check_frame();
    report();
    $finish;
  end

  // Watchdog: a stalled handshake must fail the run, not hang the regression
  initial begin
    repeat (WatchdogCycles) @(posedge clk);
    $display("SANITY FAIL");
    $fatal(1, "watchdog: simulation did not finish");
  end

  function automatic void report();
    $display({"RESULT kind=sensor scen=%s merge=%0d accum=%0d bf=%0d ",
              "cycles=%0d txn=%0d events=%0d lat_sum=%0d lat_max=%0d acc_sum=%0d acc_max=%0d"},
             scenario, merge, AccumEnabled, NarrowExtraBF, cyc,
             sensor_txn, sensor_events, sensor_lat_sum, sensor_lat_max, sensor_acc_sum,
             sensor_acc_max);
    for (int p = 0; p < NumNarrowReq; p++) begin
      $display({"RESULT kind=narrow scen=%s merge=%0d accum=%0d bf=%0d ",
                "cycles=%0d port=%0d wr_txn=%0d wr_beat=%0d rd_txn=%0d rd_beat=%0d"},
               scenario, merge, AccumEnabled, NarrowExtraBF, cyc, p,
               n_wr_txn[p], n_wr_beat[p], n_rd_txn[p], n_rd_beat[p]);
    end
    $display({"RESULT kind=wide scen=%s merge=%0d accum=%0d bf=%0d ",
              "cycles=%0d wr_beat=%0d rd_beat=%0d"},
             scenario, merge, AccumEnabled, NarrowExtraBF, cyc,
             wide_wr_beat, wide_rd_beat);
    $display("SANITY %s", n_errors == 0 ? "PASS" : "FAIL");
  endfunction

endmodule
