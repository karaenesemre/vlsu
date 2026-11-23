`timescale 1ns/1ps
`include "axi/typedef.svh"

module tb_vlsu;
  import ara_pkg::*;
  import rvv_pkg::*;

  localparam int NrLanes = 2, VLEN = 256;
  localparam config_pkg::cva6_cfg_t Cfg =
      build_config_pkg::build_config(cva6_config_pkg::cva6_cfg);
  typedef logic [$clog2(VLEN+1)-1:0] vlen_t;
  `include "ara/ara_typedef.svh"
  typedef logic [$clog2(32 * VLEN / 8 / NrLanes)-1:0] vaddr_t;
  typedef logic [63:0] addr_t;
  typedef logic [63:0] data_t;
  typedef logic [3:0] id_t;
  typedef logic [7:0] strb_t;
  typedef logic user_t;
  `AXI_TYPEDEF_ALL(bus, addr_t, id_t, data_t, strb_t, user_t)
  `include "ara/intf_typedef.svh"
  `CVA6_TYPEDEF_EXCEPTION(exception_t, Cfg);
  localparam addr_t SRC = 'h1000, DST = 'h2000;
  localparam data_t BEAT0 = {32'd20, 32'd10}, BEAT1 = {32'd40, 32'd30};

  bit clk_i;
  always #5 clk_i = ~clk_i;
  bit rst_ni;
  pe_req_t pe_req_i;
  logic pe_req_valid_i;
  logic [NrVInsn-1:0] pe_vinsn_running_i;
  logic [1:0] pe_req_ready_o;
  logic addrgen_ack_o, load_complete_o, store_complete_o;
  exception_t addrgen_exception_o;
  bus_req_t axi_req_o;
  bus_resp_t axi_resp_i;
  logic [NrLanes-1:0] ldu_result_req_o, ldu_result_gnt_i, ldu_result_final_gnt_i;
  elen_t [NrLanes-1:0] ldu_result_wdata_o, lane_word;
  strb_t [NrLanes-1:0] ldu_result_be_o;
  logic [NrLanes-1:0] stu_operand_valid_i, stu_operand_ready_o;

  vlsu #(
    .NrLanes(NrLanes), .VLEN(VLEN), .vaddr_t(vaddr_t),
    .pe_req_t(pe_req_t), .pe_resp_t(pe_resp_t), .CVA6Cfg(Cfg), .exception_t(exception_t),
    .AxiAddrWidth(64), .AxiDataWidth(64), .axi_ar_t(bus_ar_chan_t), .axi_r_t(bus_r_chan_t),
    .axi_aw_t(bus_aw_chan_t), .axi_w_t(bus_w_chan_t), .axi_b_t(bus_b_chan_t),
    .axi_req_t(bus_req_t), .axi_resp_t(bus_resp_t)
  ) dut (
    .clk_i, .rst_ni, .axi_req_o, .axi_resp_i,
    .core_st_pending_i(1'b0), .load_complete_o, .store_complete_o, .store_pending_o(),
    .pe_req_i, .pe_req_valid_i, .pe_vinsn_running_i, .pe_req_ready_o, .pe_resp_o(),
    .addrgen_ack_o, .addrgen_exception_o, .addrgen_exception_vstart_o(),
    .addrgen_fof_exception_o(), .lsu_current_burst_exception_o(),
    .stu_operand_i(lane_word), .stu_operand_valid_i, .stu_operand_ready_o,
    .addrgen_operand_i('0), .addrgen_operand_valid_i('0), .addrgen_operand_ready_o(),
    .lsu_ex_flush_i(1'b0), .lsu_ex_flush_done_o(), .mask_i('0), .mask_valid_i('0),
    .vldu_mask_ready_o(), .vstu_mask_ready_o(), .en_ld_st_translation_i(1'b0),
    .mmu_misaligned_ex_o(), .mmu_req_o(), .mmu_vaddr_o(), .mmu_is_store_o(),
    .mmu_dtlb_hit_i(1'b0), .mmu_dtlb_ppn_i('0), .mmu_valid_i(1'b0),
    .mmu_paddr_i('0), .mmu_exception_i('0),
    .ldu_result_req_o, .ldu_result_id_o(), .ldu_result_addr_o(), .ldu_result_wdata_o,
    .ldu_result_be_o, .ldu_result_gnt_i, .ldu_result_final_gnt_i
  );

  // AXI slave: tek outstanding burst, AR/AW ve W ayri handshake yapar.
  bit read_active, write_active, b_pending;
  bit read_index, write_index;
  id_t read_id, write_id;
  data_t dst_word [2];
  int ar_count, r_count, aw_count, w_count, b_count, ack_count;
  wire ar_fire = axi_req_o.ar_valid && axi_resp_i.ar_ready;
  wire r_fire  = axi_resp_i.r_valid && axi_req_o.r_ready;
  wire aw_fire = axi_req_o.aw_valid && axi_resp_i.aw_ready;
  wire w_fire  = axi_req_o.w_valid && axi_resp_i.w_ready;
  wire b_fire  = axi_resp_i.b_valid && axi_req_o.b_ready;

  always_comb begin
    axi_resp_i = '0;
    axi_resp_i.ar_ready = rst_ni && !read_active;
    axi_resp_i.r_valid = read_active;
    axi_resp_i.r.id = read_id;
    axi_resp_i.r.data = read_index ? BEAT1 : BEAT0;
    axi_resp_i.r.last = read_index;
    axi_resp_i.aw_ready = rst_ni && !write_active && !b_pending;
    axi_resp_i.w_ready = write_active;
    axi_resp_i.b_valid = b_pending;
    axi_resp_i.b.id = write_id;
  end

  always @(posedge clk_i) if (!rst_ni) begin
    ar_count <= 0; r_count <= 0; aw_count <= 0; w_count <= 0;
    b_count <= 0; ack_count <= 0;
    read_active <= 0; write_active <= 0; b_pending <= 0;
    read_index <= 0; write_index <= 0;
    read_id <= '0; write_id <= '0;
    dst_word[0] <= '0; dst_word[1] <= '0;
  end else begin
    if (addrgen_exception_o.valid) $fatal(1, "Unexpected address exception");
    if (addrgen_ack_o) ack_count <= ack_count + 1;
    if (ar_fire) begin
      if ({axi_req_o.ar.addr,axi_req_o.ar.len,axi_req_o.ar.size,axi_req_o.ar.burst}
          !== {SRC,8'd1,3'd3,2'b01}) $fatal(1, "Unexpected AR");
      read_active <= 1;
      read_index <= 0;
      read_id <= axi_req_o.ar.id;
      ar_count <= ar_count + 1;
    end
    if (r_fire) begin
      r_count <= r_count + 1;
      read_index <= 1;
      if (axi_resp_i.r.last) read_active <= 0;
    end
    if (aw_fire) begin
      if ({axi_req_o.aw.addr,axi_req_o.aw.len,axi_req_o.aw.size,axi_req_o.aw.burst}
          !== {DST,8'd1,3'd3,2'b01}) $fatal(1, "Unexpected AW");
      write_active <= 1;
      write_index <= 0;
      write_id <= axi_req_o.aw.id;
      aw_count <= aw_count + 1;
    end
    if (w_fire) begin
      if (axi_req_o.w.strb !== 8'hff || axi_req_o.w.last !== write_index)
        $fatal(1, "Unexpected WSTRB/WLAST");
      dst_word[write_index] <= axi_req_o.w.data;
      write_index <= 1;
      w_count <= w_count + 1;
      if (axi_req_o.w.last) begin
        write_active <= 0;
        b_pending <= 1;
      end
    end
    if (b_fire) begin
      b_pending <= 0;
      b_count <= b_count + 1;
    end
  end

  // Lane 0 hemen kabul eder. Lane 1 kendi req sinyalinden iki cycle sonra grant verir.
  int lane1_wait;
  logic [1:0] captured;
  wire [1:0] lane_fire = ldu_result_req_o & ldu_result_gnt_i;
  assign ldu_result_gnt_i = {lane1_wait >= 2, 1'b1};
  always @(posedge clk_i) begin
    if (!rst_ni) begin
      ldu_result_final_gnt_i <= '0;
      lane_word <= '0;
      captured <= '0;
      lane1_wait <= 0;
    end else begin
      ldu_result_final_gnt_i <= lane_fire;
      if (ldu_result_req_o[1] && !lane_fire[1]) lane1_wait <= lane1_wait + 1;
      for (int lane=0; lane<NrLanes; lane++) begin
        if (lane_fire[lane]) begin
          if (ldu_result_be_o[lane] !== 8'hff || captured[lane] !== 1'b0)
            $fatal(1, "Unexpected writeback on lane %0d", lane);
          lane_word[lane] <= ldu_result_wdata_o[lane];
          captured[lane] <= 1;
        end
      end
    end
  end

  task automatic issue(input bit store);
    // Caller enters at a negedge. Data stays stable over the acceptance edge.
    pe_req_i = '0;
    pe_req_i.op = store ? VSE : VLE;
    pe_req_i.vfu = store ? VFU_StoreUnit : VFU_LoadUnit;
    pe_req_i.id = vid_t'(store);
    pe_req_i.vl = 4;
    pe_req_i.vm = 1;
    pe_req_i.vtype.vsew = EW32;
    pe_req_i.old_eew_vs1 = EW32;
    pe_req_i.eew_vs2 = EW32;
    pe_req_i.vd = 5;
    pe_req_i.vs1 = 5;
    pe_req_i.use_vd = !store;
    pe_req_i.use_vs1 = store;
    pe_req_i.scalar_op = store ? DST : SRC;
    while (pe_req_ready_o[store] !== 1'b1) @(negedge clk_i);
    pe_vinsn_running_i[pe_req_i.id] = 1;
    pe_req_valid_i = 1;
    @(negedge clk_i);
    pe_req_valid_i = 0;
  endtask

  initial begin
    logic [1:0] accepted;
    pe_req_i = '0;
    pe_req_valid_i = 0;
    pe_vinsn_running_i = '0;
    stu_operand_valid_i = '0;
    repeat (3) @(negedge clk_i);
    rst_ni = 1;
    @(negedge clk_i);
    issue(0);
    do @(posedge clk_i); while (load_complete_o !== 1'b1);
    @(negedge clk_i);
    if (captured !== 2'b11 || lane_word[0] !== {32'd30,32'd10} ||
        lane_word[1] !== {32'd40,32'd20}) $fatal(1, "Unexpected lane mapping");
    pe_vinsn_running_i = '0;
    repeat (2) @(negedge clk_i);
    issue(1);
    stu_operand_valid_i = '1;
    while (|stu_operand_valid_i) begin
      @(posedge clk_i);
      accepted = stu_operand_valid_i & stu_operand_ready_o;
      @(negedge clk_i);
      stu_operand_valid_i &= ~accepted;
    end
    do @(posedge clk_i); while (store_complete_o !== 1'b1);
    @(negedge clk_i);
    pe_vinsn_running_i = '0;
    if (dst_word[0] !== BEAT0 || dst_word[1] !== BEAT1 ||
        ar_count != 1 || r_count != 2 || aw_count != 1 || w_count != 2 ||
        b_count != 1 || ack_count != 2) $fatal(1, "End-to-end check failed");
    $display("PASS: VLE32 -> lane 0/1 -> VSE32; dst = 10, 20, 30, 40");
    $finish;
  end
  initial begin
    repeat (160) @(posedge clk_i);
    $fatal(1, "Timeout AR=%0d R=%0d AW=%0d W=%0d B=%0d", ar_count,r_count,aw_count,w_count,b_count);
  end
`ifdef VERILATOR
  initial begin
    $dumpfile("vlsu_load_store.fst");
    $dumpvars(0, tb_vlsu);
  end
`endif
endmodule
