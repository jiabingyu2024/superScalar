`timescale 1ns / 1ps

module post_impl_dcache_monitor (
    input logic        clk,
    input logic        rst,
    input logic        cpu_req_valid,
    input logic        cpu_req_ready,
    input logic        cpu_req_write,
    input logic [31:0] cpu_req_addr,
    input logic [31:0] cpu_req_wdata,
    input logic [3:0]  cpu_req_wstrb,
    input logic        cpu_resp_valid,
    input logic [31:0] cpu_resp_rdata,
    input logic        mem_req_valid,
    input logic        mem_req_ready,
    input logic        mem_req_write,
    input logic [31:0] mem_req_addr,
    input logic        mem_resp_valid,
    input logic [31:0] mem_resp_rdata
);
    logic [31:0] pending_load_addr;
    logic [31:0] pending_mem_addr;
    longint unsigned cycle;

    always_ff @(posedge clk) begin
        if (rst) begin
            cycle <= 0;
            pending_load_addr <= '0;
            pending_mem_addr <= '0;
        end else begin
            cycle <= cycle + 1;
            if (cpu_req_valid && cpu_req_ready &&
                ((cpu_req_addr >= 32'h8010_0000 &&
                  cpu_req_addr < 32'h8010_0040) ||
                 cpu_req_addr >= 32'h8020_0000)) begin
                if (cpu_req_write) begin
                    $display("DCACHE_REQ cycle=%0d kind=W addr=%08x data=%08x strb=%x",
                             cycle, cpu_req_addr, cpu_req_wdata, cpu_req_wstrb);
                end else begin
                    pending_load_addr <= cpu_req_addr;
                    $display("DCACHE_REQ cycle=%0d kind=R addr=%08x lane=%0d",
                             cycle, cpu_req_addr, cpu_req_addr[1:0]);
                end
            end
            if (cpu_resp_valid &&
                (pending_load_addr >= 32'h8010_0000 &&
                 pending_load_addr < 32'h8010_0040)) begin
                $display("DCACHE_RSP cycle=%0d addr=%08x lane=%0d data=%08x",
                         cycle, pending_load_addr, pending_load_addr[1:0],
                         cpu_resp_rdata);
            end
            if (mem_req_valid && !mem_req_write) begin
                pending_mem_addr <= mem_req_addr;
                if (mem_req_addr >= 32'h8010_0000 &&
                    mem_req_addr < 32'h8010_0040) begin
                    $display("DCACHE_MEM_REQ cycle=%0d addr=%08x",
                             cycle, mem_req_addr);
                end
            end
            if (mem_resp_valid &&
                pending_mem_addr >= 32'h8010_0000 &&
                pending_mem_addr < 32'h8010_0040) begin
                $display("DCACHE_MEM_RSP cycle=%0d addr=%08x data=%08x",
                         cycle, pending_mem_addr, mem_resp_rdata);
            end
        end
    end
endmodule

module post_impl_dram_adapter_monitor (
    input logic        clk,
    input logic        rst,
    input logic        req_valid,
    input logic        req_ready,
    input logic        req_write,
    input logic [31:0] req_addr,
    input logic        resp_valid,
    input logic [31:0] resp_rdata
);
    logic [31:0] pending_addr;
    longint unsigned cycle;

    always_ff @(posedge clk) begin
        if (rst) begin
            cycle <= 0;
            pending_addr <= '0;
        end else begin
            cycle <= cycle + 1;
            if (req_valid && !req_write) begin
                pending_addr <= req_addr;
                if (req_addr < 32'h8010_0040) begin
                    $display("DRAM_REQ cycle=%0d addr=%08x", cycle, req_addr);
                end
            end
            if (resp_valid && pending_addr < 32'h8010_0040) begin
                $display("DRAM_RSP cycle=%0d addr=%08x data=%08x",
                         cycle, pending_addr, resp_rdata);
            end
        end
    end
endmodule

bind CoreDCache post_impl_dcache_monitor post_impl_dcache_monitor_i (
    .clk            (clk),
    .rst            (rst),
    .cpu_req_valid  (cpu_req_valid),
    .cpu_req_ready  (cpu_req_ready),
    .cpu_req_write  (cpu_req_write),
    .cpu_req_addr   (cpu_req_addr),
    .cpu_req_wdata  (cpu_req_wdata),
    .cpu_req_wstrb  (cpu_req_wstrb),
    .cpu_resp_valid (cpu_resp_valid),
    .cpu_resp_rdata (cpu_resp_rdata),
    .mem_req_valid  (mem_req_valid),
    .mem_req_ready  (mem_req_ready),
    .mem_req_write  (mem_req_write),
    .mem_req_addr   (mem_req_addr),
    .mem_resp_valid (mem_resp_valid),
    .mem_resp_rdata (mem_resp_rdata)
);

bind DramBramAdapter post_impl_dram_adapter_monitor post_impl_dram_adapter_monitor_i (
    .clk        (clk),
    .rst        (rst),
    .req_valid  (req_valid),
    .req_ready  (req_ready),
    .req_write  (req_write),
    .req_addr   (req_addr),
    .resp_valid (resp_valid),
    .resp_rdata (resp_rdata)
);

module post_impl_load_trace_tb;
    logic        cpu_clk = 1'b0;
    logic        clk_50m = 1'b0;
    logic        rst = 1'b1;
    logic [7:0]  virtual_key = '0;
    logic [63:0] virtual_sw = '0;
    wire [31:0]  virtual_led;
    wire [39:0]  virtual_seg;
    logic [39:0] last_seg = 'x;
    longint unsigned cycle = 0;

    always #10 cpu_clk = ~cpu_clk;
    always #10 clk_50m = ~clk_50m;

    student_top dut (
        .w_cpu_clk  (cpu_clk),
        .w_clk_50Mhz(clk_50m),
        .w_clk_rst  (rst),
        .virtual_key(virtual_key),
        .virtual_sw (virtual_sw),
        .virtual_led(virtual_led),
        .virtual_seg(virtual_seg)
    );

    always @(posedge cpu_clk) begin
        cycle <= cycle + 1;
        if (dut.dmem_req_valid && dut.dmem_req_addr >= 32'h8020_0000) begin
            $display("SOC_REQ cycle=%0d kind=%s addr=%08x data=%08x strb=%x",
                     cycle, dut.dmem_req_write ? "W" : "R",
                     dut.dmem_req_addr, dut.dmem_req_wdata,
                     dut.dmem_req_wstrb);
        end
    end

    initial begin
        repeat (10) @(posedge cpu_clk);
        rst = 1'b0;
        repeat (120) @(posedge cpu_clk);
        $display("TIMEOUT cycle=%0d seg=%010x led=%08x", cycle,
                 virtual_seg, virtual_led);
        $finish;
    end
endmodule
