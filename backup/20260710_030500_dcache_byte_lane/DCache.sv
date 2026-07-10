import CoreConfigPkg::*;
import CoreTypesPkg::*;

module CoreDCache #(
    parameter int SET_COUNT = 128,
    parameter int WAYS = 2,
    parameter int WORDS_PER_LINE = 8,
    parameter logic [31:0] CACHE_ADDR_START = 32'h8010_0000,
    parameter logic [31:0] CACHE_ADDR_END   = 32'h8014_0000
) (
    input  logic clk,
    input  logic rst,

    input  logic        cpu_req_valid,
    output logic        cpu_req_ready,
    input  logic        cpu_req_write,
    input  AddrPath     cpu_req_addr,
    input  DataPath     cpu_req_wdata,
    input  logic [3:0]  cpu_req_wstrb,
    input  logic        cpu_req_uncached,
    output logic        cpu_resp_valid,
    output DataPath     cpu_resp_rdata,

    output logic        mem_req_valid,
    input  logic        mem_req_ready,
    output logic        mem_req_write,
    output AddrPath     mem_req_addr,
    output DataPath     mem_req_wdata,
    output logic [3:0]  mem_req_wstrb,
    output logic        mem_req_uncached,
    input  logic        mem_resp_valid,
    input  DataPath     mem_resp_rdata,

    output logic [63:0] perf_access_o,
    output logic [63:0] perf_miss_o,
    output logic [63:0] perf_stall_o
);
    localparam int OFFSET_BITS = 5;
    localparam int WORD_BITS = $clog2(WORDS_PER_LINE);
    localparam int INDEX_BITS = $clog2(SET_COUNT);
    localparam int TAG_LSB = OFFSET_BITS + INDEX_BITS;
    localparam int TAG_BITS = 32 - TAG_LSB;

    typedef enum logic [2:0] {
        DC_IDLE,
        DC_UNCACHED_REQ,
        DC_UNCACHED_WAIT,
        DC_WRITEBACK_REQ,
        DC_REFILL_REQ,
        DC_REFILL_WAIT,
        DC_FINISH
    } DCacheState;

    DCacheState state_q;

    logic [WAYS-1:0][SET_COUNT-1:0] valid_q;
    logic [WAYS-1:0][SET_COUNT-1:0] dirty_q;
    logic [WAYS-1:0][SET_COUNT-1:0][TAG_BITS-1:0] tag_q;
    DataPath data_q [WAYS-1:0][SET_COUNT-1:0][WORDS_PER_LINE-1:0];
    logic [SET_COUNT-1:0] lru_q;

    logic req_write_q;
    AddrPath req_addr_q;
    DataPath req_wdata_q;
    logic [3:0] req_wstrb_q;
    logic req_cacheable_q;
    logic victim_way_q;
    logic [INDEX_BITS-1:0] req_index_q;
    logic [TAG_BITS-1:0] req_tag_q;
    logic [WORD_BITS-1:0] req_word_q;
    logic [TAG_BITS-1:0] victim_tag_q;
    logic [WORD_BITS-1:0] burst_word_q;

    logic req_cacheable;
    logic [INDEX_BITS-1:0] req_index;
    logic [TAG_BITS-1:0] req_tag;
    logic [WORD_BITS-1:0] req_word;
    logic hit_way0;
    logic hit_way1;
    logic hit;
    logic hit_way;
    logic victim_way;
    DataPath hit_word;

    function automatic DataPath merge_word(
        input DataPath old_word,
        input DataPath write_word,
        input logic [3:0] byte_en
    );
        DataPath merged;
        begin
            merged = old_word;
            for (int b = 0; b < 4; b = b + 1) begin
                if (byte_en[b]) begin
                    merged[b*8 +: 8] = write_word[b*8 +: 8];
                end
            end
            merge_word = merged;
        end
    endfunction

    assign req_cacheable = !cpu_req_uncached &&
                           (cpu_req_addr >= CACHE_ADDR_START) &&
                           (cpu_req_addr < CACHE_ADDR_END);
    assign req_index = cpu_req_addr[TAG_LSB-1:OFFSET_BITS];
    assign req_tag = cpu_req_addr[31:TAG_LSB];
    assign req_word = cpu_req_addr[OFFSET_BITS-1:2];
    assign hit_way0 = req_cacheable && valid_q[0][req_index] && (tag_q[0][req_index] == req_tag);
    assign hit_way1 = req_cacheable && valid_q[1][req_index] && (tag_q[1][req_index] == req_tag);
    assign hit = hit_way0 || hit_way1;
    assign hit_way = hit_way1;
    assign victim_way = !valid_q[0][req_index] ? 1'b0 :
                        !valid_q[1][req_index] ? 1'b1 :
                        lru_q[req_index];
    assign hit_word = data_q[hit_way][req_index][req_word];

    always_comb begin
        cpu_req_ready = 1'b0;
        mem_req_valid = 1'b0;
        mem_req_write = 1'b0;
        mem_req_addr = '0;
        mem_req_wdata = '0;
        mem_req_wstrb = '0;
        mem_req_uncached = 1'b0;

        unique case (state_q)
            DC_IDLE: begin
                if (cpu_req_valid) begin
                    if (!req_cacheable) begin
                        mem_req_valid = 1'b1;
                        mem_req_write = cpu_req_write;
                        mem_req_addr = cpu_req_addr;
                        mem_req_wdata = cpu_req_wdata;
                        mem_req_wstrb = cpu_req_write ? cpu_req_wstrb : 4'b0000;
                        mem_req_uncached = 1'b1;
                        cpu_req_ready = cpu_req_write && mem_req_ready;
                    end else if (hit) begin
                        cpu_req_ready = 1'b1;
                    end
                end
            end

            DC_UNCACHED_REQ: begin
                mem_req_valid = 1'b1;
                mem_req_write = req_write_q;
                mem_req_addr = req_addr_q;
                mem_req_wdata = req_wdata_q;
                mem_req_wstrb = req_write_q ? req_wstrb_q : 4'b0000;
                mem_req_uncached = 1'b1;
                cpu_req_ready = req_write_q && mem_req_ready;
            end

            DC_WRITEBACK_REQ: begin
                mem_req_valid = 1'b1;
                mem_req_write = 1'b1;
                mem_req_addr = {victim_tag_q, req_index_q, burst_word_q, 2'b00};
                mem_req_wdata = data_q[victim_way_q][req_index_q][burst_word_q];
                mem_req_wstrb = 4'b1111;
                mem_req_uncached = 1'b0;
            end

            DC_REFILL_REQ: begin
                mem_req_valid = 1'b1;
                mem_req_write = 1'b0;
                mem_req_addr = {req_addr_q[31:OFFSET_BITS], burst_word_q, 2'b00};
                mem_req_wstrb = 4'b0000;
                mem_req_uncached = 1'b0;
            end

            DC_FINISH: begin
                cpu_req_ready = req_write_q;
            end

            default: begin
            end
        endcase
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state_q <= DC_IDLE;
            cpu_resp_valid <= 1'b0;
            cpu_resp_rdata <= '0;
            req_write_q <= 1'b0;
            req_addr_q <= '0;
            req_wdata_q <= '0;
            req_wstrb_q <= '0;
            req_cacheable_q <= 1'b0;
            victim_way_q <= 1'b0;
            req_index_q <= '0;
            req_tag_q <= '0;
            req_word_q <= '0;
            victim_tag_q <= '0;
            burst_word_q <= '0;
            perf_access_o <= 64'b0;
            perf_miss_o <= 64'b0;
            perf_stall_o <= 64'b0;
            valid_q <= '0;
            dirty_q <= '0;
            tag_q <= '0;
            lru_q <= '0;
            for (int w = 0; w < WAYS; w = w + 1) begin
                for (int s = 0; s < SET_COUNT; s = s + 1) begin
                    for (int word = 0; word < WORDS_PER_LINE; word = word + 1) begin
                        data_q[w][s][word] <= '0;
                    end
                end
            end
        end else begin
            cpu_resp_valid <= 1'b0;

            if (state_q != DC_IDLE || (cpu_req_valid && !cpu_req_ready && !cpu_req_write)) begin
                perf_stall_o <= perf_stall_o + 64'd1;
            end

            unique case (state_q)
                DC_IDLE: begin
                    if (cpu_req_valid) begin
                        req_write_q <= cpu_req_write;
                        req_addr_q <= cpu_req_addr;
                        req_wdata_q <= cpu_req_wdata;
                        req_wstrb_q <= cpu_req_wstrb;
                        req_cacheable_q <= req_cacheable;
                        req_index_q <= req_index;
                        req_tag_q <= req_tag;
                        req_word_q <= req_word;
                        victim_way_q <= victim_way;
                        victim_tag_q <= tag_q[victim_way][req_index];

                        if (req_cacheable) begin
                            perf_access_o <= perf_access_o + 64'd1;
                        end

                        if (!req_cacheable) begin
                            if (mem_req_ready) begin
                                if (cpu_req_write) begin
                                    state_q <= DC_IDLE;
                                end else begin
                                    state_q <= DC_UNCACHED_WAIT;
                                end
                            end else begin
                                state_q <= DC_UNCACHED_REQ;
                            end
                        end else if (hit) begin
                            lru_q[req_index] <= ~hit_way;
                            if (cpu_req_write) begin
                                data_q[hit_way][req_index][req_word] <=
                                    merge_word(hit_word, cpu_req_wdata, cpu_req_wstrb);
                                dirty_q[hit_way][req_index] <= 1'b1;
                            end else begin
                                cpu_resp_valid <= 1'b1;
                                cpu_resp_rdata <= hit_word;
                            end
                        end else begin
                            perf_miss_o <= perf_miss_o + 64'd1;
                            burst_word_q <= '0;
                            if (valid_q[victim_way][req_index] && dirty_q[victim_way][req_index]) begin
                                state_q <= DC_WRITEBACK_REQ;
                            end else begin
                                state_q <= DC_REFILL_REQ;
                            end
                        end
                    end
                end

                DC_UNCACHED_REQ: begin
                    if (mem_req_ready) begin
                        if (req_write_q) begin
                            state_q <= DC_IDLE;
                        end else begin
                            state_q <= DC_UNCACHED_WAIT;
                        end
                    end
                end

                DC_UNCACHED_WAIT: begin
                    if (mem_resp_valid) begin
                        cpu_resp_valid <= 1'b1;
                        cpu_resp_rdata <= mem_resp_rdata;
                        state_q <= DC_IDLE;
                    end
                end

                DC_WRITEBACK_REQ: begin
                    if (mem_req_ready) begin
                        if (burst_word_q == WORD_BITS'(WORDS_PER_LINE - 1)) begin
                            burst_word_q <= '0;
                            dirty_q[victim_way_q][req_index_q] <= 1'b0;
                            valid_q[victim_way_q][req_index_q] <= 1'b0;
                            state_q <= DC_REFILL_REQ;
                        end else begin
                            burst_word_q <= burst_word_q + 1'b1;
                        end
                    end
                end

                DC_REFILL_REQ: begin
                    if (mem_req_ready) begin
                        state_q <= DC_REFILL_WAIT;
                    end
                end

                DC_REFILL_WAIT: begin
                    if (mem_resp_valid) begin
                        data_q[victim_way_q][req_index_q][burst_word_q] <= mem_resp_rdata;
                        if (burst_word_q == WORD_BITS'(WORDS_PER_LINE - 1)) begin
                            tag_q[victim_way_q][req_index_q] <= req_tag_q;
                            valid_q[victim_way_q][req_index_q] <= 1'b1;
                            dirty_q[victim_way_q][req_index_q] <= 1'b0;
                            lru_q[req_index_q] <= ~victim_way_q;
                            state_q <= DC_FINISH;
                        end else begin
                            burst_word_q <= burst_word_q + 1'b1;
                            state_q <= DC_REFILL_REQ;
                        end
                    end
                end

                DC_FINISH: begin
                    if (req_write_q) begin
                        data_q[victim_way_q][req_index_q][req_word_q] <=
                            merge_word(data_q[victim_way_q][req_index_q][req_word_q],
                                       req_wdata_q,
                                       req_wstrb_q);
                        dirty_q[victim_way_q][req_index_q] <= 1'b1;
                    end else begin
                        cpu_resp_valid <= 1'b1;
                        cpu_resp_rdata <= data_q[victim_way_q][req_index_q][req_word_q];
                    end
                    state_q <= DC_IDLE;
                end

                default: begin
                    state_q <= DC_IDLE;
                end
            endcase
        end
    end

    logic unused_req_cacheable;
    always_comb begin
        unused_req_cacheable = req_cacheable_q;
    end
endmodule : CoreDCache
