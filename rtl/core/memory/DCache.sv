`timescale 1ns / 1ps

//------------------------------------------------------------------------------
// Blocking, direct-mapped D-cache for the current five-stage in-order core.
//
// Timing contract:
// - External memory is a single-outstanding ready/valid port. Reads complete
//   only when mem_resp_valid is asserted; writes complete on req handshake.
// - Cacheable hit data is registered on the clock edge that lets M1 advance, so
//   the existing M2 stage can consume it in the next cycle.
// - Returned load data is shifted down by the original byte offset, matching the
//   current DramBramAdapter contract used by stage_m2.
// - Miss refill uses ordinary 32-bit reads and is fully blocking: fill the whole
//   line first, then replay the original load to the core. This keeps the M1/M2
//   timing identical for hit and miss paths on the current five-stage pipeline.
//------------------------------------------------------------------------------
module DCache #(
    parameter int unsigned LINE_COUNT = 512,
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
        DC_UNCACHED_REPLAY,
        DC_MISS_REQ,
        DC_MISS_WAIT,
        DC_MISS_REPLAY
    } state_e;

    state_e state_q;

    logic [LINE_COUNT-1:0] valid_q;
    logic [31:TAG_LSB] tag_q   [0:LINE_COUNT-1];
    logic [31:0]       data_q  [0:LINE_COUNT-1][0:WORDS_PER_LINE-1];

    logic [31:0] miss_addr_q;
    logic [1:0]  miss_target_word_q;
    logic [1:0]  fill_word_q;
    logic [2:0]  fill_count_q;
    logic [31:0] resp_rdata_q;
    logic        resp_valid_q;

    logic [INDEX_W-1:0] req_index_c;
    logic [31:TAG_LSB]  req_tag_c;
    logic [1:0]         req_word_c;
    logic               req_cacheable_c;
    logic               req_hit_c;
    logic [31:0]        cache_word_c;

    logic [INDEX_W-1:0] miss_index_c;
    logic [31:TAG_LSB]  miss_tag_c;
    logic [1:0]         next_fill_word_c;
    logic [31:0]        fill_resp_shifted_c;

    assign req_cacheable_c = !cpu_req_uncached &&
                             (cpu_req_addr >= CACHE_ADDR_START) &&
                             (cpu_req_addr < CACHE_ADDR_END);
    assign req_index_c = cpu_req_addr[TAG_LSB-1:4];
    assign req_tag_c   = cpu_req_addr[31:TAG_LSB];
    assign req_word_c  = cpu_req_addr[3:2];
    assign req_hit_c   = req_cacheable_c &&
                         valid_q[req_index_c] &&
                         (tag_q[req_index_c] == req_tag_c);
    assign cache_word_c = data_q[req_index_c][req_word_c];

    assign miss_index_c = miss_addr_q[TAG_LSB-1:4];
    assign miss_tag_c   = miss_addr_q[31:TAG_LSB];
    assign next_fill_word_c = fill_word_q + 2'd1;
    assign fill_resp_shifted_c = mem_resp_rdata >> {miss_addr_q[1:0], 3'b000};

    function automatic logic [31:0] merge_store_word(
        input logic [31:0] old_word,
        input logic [31:0] store_data,
        input logic [3:0]  store_mask,
        input logic [1:0]  byte_offset
    );
        logic [31:0] shifted_data;
        logic [3:0]  shifted_mask;
        logic [31:0] merged;
        begin
            shifted_data = store_data << {byte_offset, 3'b000};
            shifted_mask = (store_mask << byte_offset) & 4'hf;
            merged = old_word;
            for (int lane = 0; lane < 4; lane++) begin
                if (shifted_mask[lane]) begin
                    merged[lane*8 +: 8] = shifted_data[lane*8 +: 8];
                end
            end
            merge_store_word = merged;
        end
    endfunction

    always_comb begin
        cpu_req_ready   = 1'b0;
        mem_req_valid   = 1'b0;
        mem_req_write   = 1'b0;
        mem_req_addr    = 32'd0;
        mem_req_wdata   = 32'd0;
        mem_req_wstrb   = 4'b0000;
        mem_req_uncached = 1'b0;

        unique case (state_q)
            DC_IDLE: begin
                if (cpu_req_valid) begin
                    if (cpu_req_write) begin
                        mem_req_valid    = 1'b1;
                        mem_req_write    = 1'b1;
                        mem_req_addr     = cpu_req_addr;
                        mem_req_wdata    = cpu_req_wdata;
                        mem_req_wstrb    = cpu_req_wstrb;
                        mem_req_uncached = !req_cacheable_c;
                        cpu_req_ready    = mem_req_ready;
                    end else if (req_cacheable_c && req_hit_c) begin
                        cpu_req_ready    = 1'b1;
                    end else begin
                        mem_req_valid    = 1'b1;
                        mem_req_write    = 1'b0;
                        mem_req_addr     = req_cacheable_c ? {cpu_req_addr[31:4], 4'b0000}
                                                           : cpu_req_addr;
                        mem_req_uncached = !req_cacheable_c;
                        cpu_req_ready    = 1'b0;
                    end
                end
            end

            DC_UNCACHED_REPLAY,
            DC_MISS_REPLAY: begin
                cpu_req_ready = 1'b1;
            end

            DC_MISS_REQ: begin
                mem_req_valid    = 1'b1;
                mem_req_write    = 1'b0;
                mem_req_addr     = {miss_addr_q[31:4], fill_word_q, 2'b00};
                mem_req_uncached = 1'b0;
            end

            default: begin
            end
        endcase
    end

    assign cpu_resp_valid = resp_valid_q ||
                            (state_q == DC_UNCACHED_REPLAY) ||
                            (state_q == DC_MISS_REPLAY);
    assign cpu_resp_rdata = resp_rdata_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            state_q <= DC_IDLE;
            miss_addr_q <= 32'd0;
            miss_target_word_q <= 2'd0;
            fill_word_q <= 2'd0;
            fill_count_q <= 3'd0;
            resp_rdata_q <= 32'd0;
            resp_valid_q <= 1'b0;
            perf_dcache_access <= 64'd0;
            perf_dcache_miss <= 64'd0;
            perf_stall_mem <= 64'd0;
            valid_q <= '0;
        end else begin
            resp_valid_q <= 1'b0;

            if ((state_q != DC_IDLE) || (cpu_req_valid && !cpu_req_ready)) begin
                perf_stall_mem <= perf_stall_mem + 64'd1;
            end

            unique case (state_q)
                DC_IDLE: begin
                    if (cpu_req_valid) begin
                        if (cpu_req_write) begin
                            if (mem_req_ready) begin
                                if (req_cacheable_c) begin
                                    perf_dcache_access <= perf_dcache_access + 64'd1;
                                    if (req_hit_c) begin
                                        data_q[req_index_c][req_word_c] <=
                                            merge_store_word(cache_word_c,
                                                             cpu_req_wdata,
                                                             cpu_req_wstrb,
                                                             cpu_req_addr[1:0]);
                                    end else begin
                                        perf_dcache_miss <= perf_dcache_miss + 64'd1;
                                    end
                                end
                            end
                        end else if (req_cacheable_c && req_hit_c) begin
                            perf_dcache_access <= perf_dcache_access + 64'd1;
                            resp_rdata_q <= cache_word_c >> {cpu_req_addr[1:0], 3'b000};
                            resp_valid_q <= 1'b1;
                        end else if (mem_req_ready) begin
                            if (req_cacheable_c) begin
                                perf_dcache_access <= perf_dcache_access + 64'd1;
                                perf_dcache_miss <= perf_dcache_miss + 64'd1;
                                miss_addr_q <= cpu_req_addr;
                                miss_target_word_q <= req_word_c;
                                fill_word_q <= 2'd0;
                                fill_count_q <= 3'd0;
                                state_q <= DC_MISS_WAIT;
                            end else begin
                                state_q <= DC_UNCACHED_WAIT;
                            end
                        end
                    end
                end

                DC_UNCACHED_WAIT: begin
                    if (mem_resp_valid) begin
                        resp_rdata_q <= mem_resp_rdata;
                        state_q <= DC_UNCACHED_REPLAY;
                    end
                end

                DC_UNCACHED_REPLAY: begin
                    if (cpu_req_valid) begin
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
                        data_q[miss_index_c][fill_word_q] <= mem_resp_rdata;

                        if (fill_word_q == miss_target_word_q) begin
                            resp_rdata_q <= fill_resp_shifted_c;
                        end

                        if (fill_count_q == 3'(WORDS_PER_LINE - 1)) begin
                            tag_q[miss_index_c] <= miss_tag_c;
                            valid_q[miss_index_c] <= 1'b1;
                            fill_count_q <= 3'd0;
                            fill_word_q <= miss_target_word_q;
                            state_q <= DC_MISS_REPLAY;
                        end else begin
                            fill_count_q <= fill_count_q + 3'd1;
                            fill_word_q <= next_fill_word_c;
                            state_q <= DC_MISS_REQ;
                        end
                    end
                end

                DC_MISS_REPLAY: begin
                    if (cpu_req_valid) begin
                        state_q <= DC_IDLE;
                    end
                end

                default: begin
                    state_q <= DC_IDLE;
                end
            endcase
        end
    end

endmodule
