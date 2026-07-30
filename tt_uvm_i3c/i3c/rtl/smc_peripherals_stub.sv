///////////////////////////////////////////////////////////////////////
// File   : smc_peripherals_stub.sv
// Desc   : PRE-RTL behavioral AXI4-Lite register slave for the SMC
//          peripherals env. Generic full-RW associative memory so the shared
//          axi4lite_vip can drive first valid traffic before real RTL exists.
//          Swap for real smc_peripherals RTL (keep the AXI4-Lite port set).
///////////////////////////////////////////////////////////////////////

`ifndef SMC_PERIPHERALS_STUB_SV
`define SMC_PERIPHERALS_STUB_SV

module smc_peripherals_stub #(parameter int ADDR_WIDTH = 32,
                              parameter int DATA_WIDTH = 32)
(
  input  logic                      clk,
  input  logic                      rst_n,
  input  logic [ADDR_WIDTH-1:0]     awaddr,
  input  logic                      awvalid,
  output logic                      awready,
  input  logic [DATA_WIDTH-1:0]     wdata,
  input  logic [(DATA_WIDTH/8)-1:0] wstrb,
  input  logic                      wvalid,
  output logic                      wready,
  output logic [1:0]                bresp,
  output logic                      bvalid,
  input  logic                      bready,
  input  logic [ADDR_WIDTH-1:0]     araddr,
  input  logic                      arvalid,
  output logic                      arready,
  output logic [DATA_WIDTH-1:0]     rdata,
  output logic [1:0]                rresp,
  output logic                      rvalid,
  input  logic                      rready
);
  logic [DATA_WIDTH-1:0] mem [longint unsigned];
  logic                  have_aw, have_w;
  longint unsigned       pend_awaddr;
  logic [DATA_WIDTH-1:0] pend_wdata;
  logic [(DATA_WIDTH/8)-1:0] pend_wstrb;

  function automatic logic [DATA_WIDTH-1:0] apply_mask(input logic [DATA_WIDTH-1:0] cur,
                                                       input logic [DATA_WIDTH-1:0] wr,
                                                       input logic [(DATA_WIDTH/8)-1:0] be);
    logic [DATA_WIDTH-1:0] m;
    m = '0;
    for (int i = 0; i < (DATA_WIDTH/8); i++) if (be[i]) m[(i*8)+:8] = 8'hFF;
    return (cur & ~m) | (wr & m);
  endfunction

  initial begin
    awready = 1'b1; wready = 1'b1; bresp = 2'b00; bvalid = 1'b0;
    arready = 1'b1; rdata = '0; rresp = 2'b00; rvalid = 1'b0;
    have_aw = 1'b0; have_w = 1'b0;
  end

  always @(posedge clk) begin
    longint unsigned waddr;
    logic aw_fire, w_fire;
    if (!rst_n) begin
      awready <= 1'b1; wready <= 1'b1; arready <= 1'b1;
      bvalid <= 1'b0; rvalid <= 1'b0; have_aw <= 1'b0; have_w <= 1'b0;
    end else begin
      aw_fire = awvalid && awready;
      w_fire  = wvalid  && wready;
      if (bvalid && bready) bvalid <= 1'b0;
      if (rvalid && rready) rvalid <= 1'b0;
      if (aw_fire) begin pend_awaddr <= {{(64-ADDR_WIDTH){1'b0}}, awaddr}; have_aw <= 1'b1; end
      if (w_fire)  begin pend_wdata <= wdata; pend_wstrb <= wstrb; have_w <= 1'b1; end
      if (!bvalid && (have_aw || aw_fire) && (have_w || w_fire)) begin
        waddr = aw_fire ? {{(64-ADDR_WIDTH){1'b0}}, awaddr} : pend_awaddr;
        mem[waddr] = apply_mask(mem[waddr], (w_fire ? wdata : pend_wdata), (w_fire ? wstrb : pend_wstrb));
        bresp <= 2'b00; bvalid <= 1'b1; have_aw <= 1'b0; have_w <= 1'b0;
      end
      if (!rvalid && arvalid && arready) begin
        rdata <= mem[{{(64-ADDR_WIDTH){1'b0}}, araddr}];
        rresp <= 2'b00; rvalid <= 1'b1;
      end
    end
  end
endmodule

`endif // SMC_PERIPHERALS_STUB_SV
