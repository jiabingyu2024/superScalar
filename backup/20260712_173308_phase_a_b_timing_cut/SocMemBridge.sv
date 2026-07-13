`timescale 1ns / 1ps

module SocMemBridge #(
    parameter logic [31:0] P_DRAM_ADDR_START = 32'h8010_0000,
    parameter logic [31:0] P_DRAM_ADDR_END   = 32'h8014_0000
) (
    input  logic        clk,
    input  logic        cnt_clk,
    input  logic        rst,
    input  logic        cnt_rst,

    input  logic        req_valid,
    output logic        req_ready,
    input  logic        req_write,
    input  logic [31:0] req_addr,
    input  logic [31:0] req_wdata,
    input  logic [3:0]  req_wstrb,
    input  logic        req_uncached,

    output logic        resp_valid,
    output logic [31:0] resp_rdata,

    input  logic [63:0] virtual_sw_input,
    input  logic [7:0]  virtual_key_input,
    output logic [39:0] virtual_seg_output,
    output logic [31:0] virtual_led_output
);
    localparam logic [31:0] SW0_ADDR = 32'h8020_0000;
    localparam logic [31:0] SW1_ADDR = 32'h8020_0004;
    localparam logic [31:0] KEY_ADDR = 32'h8020_0010;
    localparam logic [31:0] SEG_ADDR = 32'h8020_0020;
    localparam logic [31:0] LED_ADDR = 32'h8020_0040;
    localparam logic [31:0] CNT_ADDR = 32'h8020_0050;
    localparam logic [31:0] CNT_START_CMD = 32'h8000_0000;
    localparam logic [31:0] CNT_STOP_CMD  = 32'hffff_ffff;

    logic dram_sel;
    logic mmio_sel;
    logic cnt_sel;
    logic dram_req_valid;
    logic dram_req_ready;
    logic dram_resp_valid;
    logic [31:0] dram_resp_rdata;
    logic mmio_resp_valid_q;
    logic [31:0] mmio_resp_rdata_q;
    logic [31:0] led_q;
    logic [31:0] seg_wdata_q;
    (* ASYNC_REG = "TRUE" *) logic [31:0] seg_wdata_cnt_d1;
    (* ASYNC_REG = "TRUE" *) logic [31:0] seg_wdata_cnt_d2;
    logic [39:0] seg_output;
    logic cnt_enable_cfg_q;
    logic [31:0] cnt_rdata;

    assign dram_sel = (req_addr >= P_DRAM_ADDR_START) && (req_addr < P_DRAM_ADDR_END);
    assign cnt_sel = req_addr == CNT_ADDR;
    assign mmio_sel = (req_addr == SW0_ADDR) || (req_addr == SW1_ADDR) ||
                      (req_addr == KEY_ADDR) || (req_addr == SEG_ADDR) ||
                      (req_addr == LED_ADDR);

    assign dram_req_valid = req_valid && dram_sel;
    assign req_ready = dram_sel ? dram_req_ready : 1'b1;

    DramBramAdapter dram_adapter (
        .clk       (clk),
        .rst       (rst),
        .req_valid (dram_req_valid),
        .req_ready (dram_req_ready),
        .req_write (req_write),
        .req_addr  (req_addr - P_DRAM_ADDR_START),
        .req_wdata (req_wdata),
        .req_wstrb (req_wstrb),
        .resp_valid(dram_resp_valid),
        .resp_rdata(dram_resp_rdata)
    );

    always_ff @(posedge clk) begin
        if (rst) begin
            led_q <= 32'd0;
            seg_wdata_q <= 32'd0;
            cnt_enable_cfg_q <= 1'b0;
            mmio_resp_valid_q <= 1'b0;
            mmio_resp_rdata_q <= 32'd0;
        end else begin
            mmio_resp_valid_q <= req_valid && !dram_sel && !req_write;
            mmio_resp_rdata_q <= 32'd0;
            if (req_valid && !dram_sel && !req_write) begin
                unique case (req_addr)
                    SW0_ADDR: mmio_resp_rdata_q <= virtual_sw_input[31:0];
                    SW1_ADDR: mmio_resp_rdata_q <= virtual_sw_input[63:32];
                    KEY_ADDR: mmio_resp_rdata_q <= {24'd0, virtual_key_input};
                    SEG_ADDR: mmio_resp_rdata_q <= seg_wdata_q;
                    CNT_ADDR: mmio_resp_rdata_q <= cnt_rdata;
                    default:  mmio_resp_rdata_q <= 32'd0;
                endcase
            end

            if (req_valid && !dram_sel && req_write) begin
                unique case (req_addr)
                    LED_ADDR: led_q <= req_wdata;
                    SEG_ADDR: seg_wdata_q <= req_wdata;
                    CNT_ADDR: begin
                        if (req_wdata == CNT_START_CMD) begin
                            cnt_enable_cfg_q <= 1'b1;
                        end else if (req_wdata == CNT_STOP_CMD) begin
                            cnt_enable_cfg_q <= 1'b0;
                        end
                    end
                    default: begin
                    end
                endcase
            end
        end
    end

    always_ff @(posedge cnt_clk) begin
        if (cnt_rst) begin
            seg_wdata_cnt_d1 <= 32'd0;
            seg_wdata_cnt_d2 <= 32'd0;
        end else begin
            seg_wdata_cnt_d1 <= seg_wdata_q;
            seg_wdata_cnt_d2 <= seg_wdata_cnt_d1;
        end
    end

    display_seg seg_driver (
        .clk (cnt_clk),
        .rst (cnt_rst),
        .s   (seg_wdata_cnt_d2),
        .seg1(seg_output[6:0]),
        .seg2(seg_output[16:10]),
        .seg3(seg_output[26:20]),
        .seg4(seg_output[36:30]),
        .ans ({seg_output[39:38], seg_output[29:28], seg_output[19:18], seg_output[9:8]})
    );

    assign seg_output[7]  = 1'b0;
    assign seg_output[17] = 1'b0;
    assign seg_output[27] = 1'b0;
    assign seg_output[37] = 1'b0;

    counter counter_inst (
        .cpu_clk      (clk),
        .cnt_clk      (cnt_clk),
        .cpu_rst      (rst),
        .cnt_rst      (cnt_rst),
        .cnt_enable_cpu(cnt_enable_cfg_q),
        .perip_rdata  (cnt_rdata)
    );

    always_comb begin
        if (dram_resp_valid) begin
            resp_valid = 1'b1;
            resp_rdata = dram_resp_rdata;
        end else begin
            resp_valid = mmio_resp_valid_q;
            resp_rdata = mmio_resp_rdata_q;
        end
    end

    assign virtual_led_output = led_q;
    assign virtual_seg_output = seg_output;

    logic unused_req_uncached;
    always_comb begin
        unused_req_uncached = req_uncached || mmio_sel || cnt_sel;
    end
endmodule
