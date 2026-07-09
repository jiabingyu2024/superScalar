`timescale 1ns / 1ps

module DCache #(
    parameter int unsigned LINE_COUNT = 128,
    parameter logic [31:0] CACHE_ADDR_START = 32'h8010_0000,
    parameter logic [31:0] CACHE_ADDR_END   = 32'h8014_0000
) (
    input  logic        clk,
    input  logic        rst,

    input  logic        cpu_req_valid,
    output logic        cpu_req_ready,
    input  logic        cpu_req_write,
    input  logic [31:0] cpu_req_addr,
    input  logic [31:0] cpu_req_wdata,
    input  logic [3:0]  cpu_req_wstrb,
    input  logic        cpu_req_uncached,
    output logic        cpu_resp_valid,
    output logic [31:0] cpu_resp_rdata,

    output logic        mem_req_valid,
    input  logic        mem_req_ready,
    output logic        mem_req_write,
    output logic [31:0] mem_req_addr,
    output logic [31:0] mem_req_wdata,
    output logic [3:0]  mem_req_wstrb,
    output logic        mem_req_uncached,
    input  logic        mem_resp_valid,
    input  logic [31:0] mem_resp_rdata,

    output logic [63:0] perf_dcache_access,
    output logic [63:0] perf_dcache_miss,
    output logic [63:0] perf_stall_mem
);
    localparam int unsigned WORDS_PER_LINE = 4;
    localparam int unsigned INDEX_W = $clog2(LINE_COUNT);
    localparam int unsigned TAG_LSB = 4 + INDEX_W;

    typedef enum logic [2:0] {
        DC_IDLE,
        DC_UNCACHED_WAIT,
        DC_MISS_REQ,
        DC_MISS_WAIT
    } state_e;

    state_e state_q;

    logic              valid_q [0:LINE_COUNT-1];
    logic [31:TAG_LSB] tag_q [0:LINE_COUNT-1];
    logic [31:0]       data_q [0:LINE_COUNT-1][0:WORDS_PER_LINE-1];

    logic [31:0] miss_addr_q;
    logic [1:0]  miss_target_word_q;
    logic [1:0]  fill_word_q;
    logic [31:0] fill_data_q [0:WORDS_PER_LINE-1];
    logic [31:0] uncached_addr_q;
    logic        cpu_resp_valid_q;
    logic [31:0] cpu_resp_rdata_q;

    logic [INDEX_W-1:0] req_index_c;
    logic [31:TAG_LSB]  req_tag_c;
    logic [1:0]         req_word_c;
    logic               req_cacheable_c;
    logic               req_hit_c;
    logic [31:0]        cache_word_c;
    logic [31:0]        store_data_shifted_c;
    logic [3:0]         store_mask_shifted_c;
    logic [31:0]        store_word_next_c;
    logic               hit_resp_c;

    assign req_cacheable_c = !cpu_req_uncached &&
                             (cpu_req_addr >= CACHE_ADDR_START) &&
                             (cpu_req_addr < CACHE_ADDR_END);
    assign req_index_c = cpu_req_addr[TAG_LSB-1:4];
    assign req_tag_c = cpu_req_addr[31:TAG_LSB];
    assign req_word_c = cpu_req_addr[3:2];
    assign req_hit_c = req_cacheable_c &&
                       valid_q[req_index_c] &&
                       (tag_q[req_index_c] == req_tag_c);
    assign cache_word_c = data_q[req_index_c][req_word_c];
    assign store_data_shifted_c = cpu_req_wdata << {cpu_req_addr[1:0], 3'b000};
    assign store_mask_shifted_c = (cpu_req_wstrb << cpu_req_addr[1:0]) & 4'hf;
    assign hit_resp_c = (state_q == DC_IDLE) && cpu_req_valid && !cpu_req_write &&
                        req_cacheable_c && req_hit_c;
    assign cpu_resp_valid = hit_resp_c || cpu_resp_valid_q;
    assign cpu_resp_rdata = hit_resp_c ? cache_word_c : cpu_resp_rdata_q;

    always_comb begin
        store_word_next_c = cache_word_c;
        for (int b = 0; b < 4; b++) begin
            if (store_mask_shifted_c[b]) begin
                store_word_next_c[b*8 +: 8] = store_data_shifted_c[b*8 +: 8];
            end
        end
    end

    always_comb begin
        cpu_req_ready = 1'b0;
        mem_req_valid = 1'b0;
        mem_req_write = 1'b0;
        mem_req_addr = 32'd0;
        mem_req_wdata = 32'd0;
        mem_req_wstrb = 4'b0000;
        mem_req_uncached = 1'b0;

        unique case (state_q)
            DC_IDLE: begin
                if (cpu_req_valid) begin
                    if (cpu_req_write) begin
                        mem_req_valid = 1'b1;
                        mem_req_write = 1'b1;
                        mem_req_addr = cpu_req_addr;
                        mem_req_wdata = cpu_req_wdata;
                        mem_req_wstrb = cpu_req_wstrb;
                        mem_req_uncached = !req_cacheable_c;
                        cpu_req_ready = mem_req_ready;
                    end else if (!req_cacheable_c || !req_hit_c) begin
                        mem_req_valid = 1'b1;
                        mem_req_write = 1'b0;
                        mem_req_addr = req_cacheable_c ? {cpu_req_addr[31:4], 4'b0000} : cpu_req_addr;
                        mem_req_uncached = !req_cacheable_c;
                        cpu_req_ready = mem_req_ready;
                    end else begin
                        cpu_req_ready = 1'b1;
                    end
                end
            end

            DC_MISS_REQ: begin
                mem_req_valid = 1'b1;
                mem_req_write = 1'b0;
                mem_req_addr = {miss_addr_q[31:4], fill_word_q, 2'b00};
                mem_req_uncached = 1'b0;
            end

            default: begin
            end
        endcase
    end

    integer idx;
    always_ff @(posedge clk) begin
        if (rst) begin
            state_q <= DC_IDLE;
            cpu_resp_valid_q <= 1'b0;
            cpu_resp_rdata_q <= 32'd0;
            miss_addr_q <= 32'd0;
            miss_target_word_q <= 2'd0;
            fill_word_q <= 2'd0;
            uncached_addr_q <= 32'd0;
            perf_dcache_access <= 64'd0;
            perf_dcache_miss <= 64'd0;
            perf_stall_mem <= 64'd0;
            for (idx = 0; idx < LINE_COUNT; idx++) begin
                valid_q[idx] <= 1'b0;
            end
        end else begin
            cpu_resp_valid_q <= 1'b0;

            if (state_q != DC_IDLE || (cpu_req_valid && !cpu_req_ready)) begin
                perf_stall_mem <= perf_stall_mem + 64'd1;
            end

            unique case (state_q)
                DC_IDLE: begin
                    if (cpu_req_valid && cpu_req_ready) begin
                        if (req_cacheable_c) begin
                            perf_dcache_access <= perf_dcache_access + 64'd1;
                        end

                        if (cpu_req_write) begin
                            if (req_cacheable_c) begin
                                if (req_hit_c) begin
                                    data_q[req_index_c][req_word_c] <= store_word_next_c;
                                end else begin
                                    perf_dcache_miss <= perf_dcache_miss + 64'd1;
                                end
                            end
                        end else if (!req_cacheable_c) begin
                            uncached_addr_q <= cpu_req_addr;
                            state_q <= DC_UNCACHED_WAIT;
                        end else if (req_hit_c) begin
                            cpu_resp_valid_q <= 1'b0;
                        end else begin
                            perf_dcache_miss <= perf_dcache_miss + 64'd1;
                            miss_addr_q <= cpu_req_addr;
                            miss_target_word_q <= req_word_c;
                            fill_word_q <= 2'd0;
                            state_q <= DC_MISS_WAIT;
                        end
                    end
                end

                DC_UNCACHED_WAIT: begin
                    if (mem_resp_valid) begin
                        cpu_resp_valid_q <= 1'b1;
                        cpu_resp_rdata_q <= mem_resp_rdata;
                        state_q <= DC_IDLE;
                    end
                end

                DC_MISS_REQ: begin
                    if (mem_req_ready) begin
                        state_q <= DC_MISS_WAIT;
                    end
                end

                DC_MISS_WAIT: begin
                    if (mem_resp_valid) begin
                        logic [INDEX_W-1:0] fill_index;
                        fill_index = miss_addr_q[TAG_LSB-1:4];
                        fill_data_q[fill_word_q] <= mem_resp_rdata;

                        if (fill_word_q == 2'd3) begin
                            for (int word = 0; word < WORDS_PER_LINE; word++) begin
                                if (word == fill_word_q) begin
                                    data_q[fill_index][word] <= mem_resp_rdata;
                                end else begin
                                    data_q[fill_index][word] <= fill_data_q[word];
                                end
                            end
                            tag_q[fill_index] <= miss_addr_q[31:TAG_LSB];
                            valid_q[fill_index] <= 1'b1;
                            unique case (miss_target_word_q)
                                2'd0: cpu_resp_rdata_q <= fill_data_q[0];
                                2'd1: cpu_resp_rdata_q <= fill_data_q[1];
                                2'd2: cpu_resp_rdata_q <= fill_data_q[2];
                                default: cpu_resp_rdata_q <= mem_resp_rdata;
                            endcase
                            cpu_resp_valid_q <= 1'b1;
                            state_q <= DC_IDLE;
                        end else begin
                            fill_word_q <= fill_word_q + 2'd1;
                            state_q <= DC_MISS_REQ;
                        end
                    end
                end

                default: state_q <= DC_IDLE;
            endcase
        end
    end

    logic unused_uncached_addr;
    always_comb begin
        unused_uncached_addr = ^uncached_addr_q;
    end
endmodule
