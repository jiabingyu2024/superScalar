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
    localparam int WORD_BITS = $clog2(WORDS_PER_LINE);
    localparam int INDEX_BITS = $clog2(SET_COUNT);
    localparam int OFFSET_BITS = WORD_BITS + 2;
    localparam int TAG_LSB = OFFSET_BITS + INDEX_BITS;
    localparam int TAG_BITS = 32 - TAG_LSB;
    localparam int DATA_ADDR_BITS = INDEX_BITS + WORD_BITS;
    localparam int DATA_DEPTH = SET_COUNT * WORDS_PER_LINE;
    localparam int REFILL_COUNT_BITS = $clog2(WORDS_PER_LINE + 1);
    localparam logic [WORDS_PER_LINE-1:0] REFILL_ALL_WORDS =
        {WORDS_PER_LINE{1'b1}};

    typedef enum logic [2:0] {
        DC_IDLE,
        DC_UNCACHED_REQ,
        DC_UNCACHED_WAIT,
        DC_WRITEBACK_PREP,
        DC_WRITEBACK_REQ,
        DC_REFILL_REQ,
        DC_REFILL_WAIT,
        DC_FINISH
    } DCacheState;

    DCacheState state_q;

    logic [WAYS-1:0][SET_COUNT-1:0] valid_q;
    logic [WAYS-1:0][SET_COUNT-1:0] dirty_q;
    // One asynchronous read and one synchronous write per way maps naturally
    // to Xilinx distributed RAM while preserving the current zero-cycle hit
    // lookup. A future BRAM version would require an extra lookup pipeline.
    (* ram_style = "distributed" *) logic [31:0] data_way0_q [0:DATA_DEPTH-1];
    (* ram_style = "distributed" *) logic [31:0] data_way1_q [0:DATA_DEPTH-1];
    (* ram_style = "distributed" *) logic [TAG_BITS-1:0] tag_way0_q [0:SET_COUNT-1];
    (* ram_style = "distributed" *) logic [TAG_BITS-1:0] tag_way1_q [0:SET_COUNT-1];
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
    logic [1:0] req_byte_q;
    logic [TAG_BITS-1:0] victim_tag_q;
    logic [WORD_BITS-1:0] burst_word_q;
    DataPath writeback_data_q;

    // A critical-word response can release the current load before the
    // blocking line fill completes. DramAccessIF may then pulse one new read;
    // retain that pulse locally and replay it after the fill.
    logic cpu_read_hold_valid_q;
    AddrPath cpu_read_hold_addr_q;
    logic cpu_read_hold_uncached_q;

    logic active_req_valid;
    logic active_req_write;
    AddrPath active_req_addr;
    DataPath active_req_wdata;
    logic [3:0] active_req_wstrb;
    logic active_req_uncached;

    logic [REFILL_COUNT_BITS-1:0] refill_issue_count_q;
    logic [REFILL_COUNT_BITS-1:0] refill_resp_count_q;
    logic [WORDS_PER_LINE-1:0] refill_valid_mask_q;
    logic refill_critical_seen_q;
    logic [WORD_BITS-1:0] refill_issue_word;
    logic [WORD_BITS-1:0] refill_resp_word;
    logic [WORDS_PER_LINE-1:0] refill_resp_onehot;
    logic refill_active;
    logic refill_req_fire;
    logic refill_resp_fire;
    logic refill_issue_last;
    logic refill_resp_last;
    logic refill_line_complete;
    logic writeback_req_fire;
    logic writeback_req_last;

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
    logic [DATA_ADDR_BITS-1:0] data_read_addr;
    logic [DATA_ADDR_BITS-1:0] data_write_addr;
    DataPath data_way0_read;
    DataPath data_way1_read;
    DataPath victim_read_word;
    DataPath data_write_data;
    logic [TAG_BITS-1:0] tag_way0_read;
    logic [TAG_BITS-1:0] tag_way1_read;
    logic data_way0_we;
    logic data_way1_we;
    logic tag_way0_we;
    logic tag_way1_we;
    logic data_write_valid_q;
    logic data_write_way_q;
    logic [DATA_ADDR_BITS-1:0] data_write_addr_q;
    DataPath data_write_data_q;
    DataPath data_way0_effective;
    DataPath data_way1_effective;

    function automatic DataPath align_load_word(
        input DataPath word,
        input logic [1:0] byte_off
    );
        begin
            align_load_word = word >> {byte_off, 3'b000};
        end
    endfunction

    function automatic DataPath align_store_data(
        input DataPath write_word,
        input logic [1:0] byte_off
    );
        begin
            align_store_data = write_word << {byte_off, 3'b000};
        end
    endfunction

    function automatic logic [3:0] align_store_mask(
        input logic [3:0] byte_en,
        input logic [1:0] byte_off
    );
        begin
            align_store_mask = (byte_en << byte_off) & 4'hf;
        end
    endfunction

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

    assign active_req_valid = cpu_read_hold_valid_q || cpu_req_valid;
    assign active_req_write = cpu_read_hold_valid_q ? 1'b0 : cpu_req_write;
    assign active_req_addr = cpu_read_hold_valid_q ? cpu_read_hold_addr_q : cpu_req_addr;
    assign active_req_wdata = cpu_read_hold_valid_q ? '0 : cpu_req_wdata;
    assign active_req_wstrb = cpu_read_hold_valid_q ? '0 : cpu_req_wstrb;
    assign active_req_uncached = cpu_read_hold_valid_q ?
                                 cpu_read_hold_uncached_q : cpu_req_uncached;

    assign req_cacheable = !active_req_uncached &&
                           (active_req_addr >= CACHE_ADDR_START) &&
                           (active_req_addr < CACHE_ADDR_END);
    assign req_index = active_req_addr[TAG_LSB-1:OFFSET_BITS];
    assign req_tag = active_req_addr[31:TAG_LSB];
    assign req_word = active_req_addr[OFFSET_BITS-1:2];
    assign tag_way0_read = tag_way0_q[req_index];
    assign tag_way1_read = tag_way1_q[req_index];
    assign hit_way0 = req_cacheable && valid_q[0][req_index] && (tag_way0_read == req_tag);
    assign hit_way1 = req_cacheable && valid_q[1][req_index] && (tag_way1_read == req_tag);
    assign hit = hit_way0 || hit_way1;
    assign hit_way = hit_way1;
    assign victim_way = !valid_q[0][req_index] ? 1'b0 :
                        !valid_q[1][req_index] ? 1'b1 :
                        lru_q[req_index];

    assign refill_active = (state_q == DC_REFILL_REQ) ||
                           (state_q == DC_REFILL_WAIT);
    assign refill_issue_word = req_word_q +
                               refill_issue_count_q[WORD_BITS-1:0];
    assign refill_resp_word = req_word_q +
                              refill_resp_count_q[WORD_BITS-1:0];
    assign refill_resp_onehot = WORDS_PER_LINE'(1) << refill_resp_word;
    assign refill_issue_last =
        refill_issue_count_q == REFILL_COUNT_BITS'(WORDS_PER_LINE - 1);
    assign refill_resp_last =
        refill_resp_count_q == REFILL_COUNT_BITS'(WORDS_PER_LINE - 1);
    assign refill_line_complete =
        (refill_valid_mask_q | refill_resp_onehot) == REFILL_ALL_WORDS;
    assign refill_req_fire = (state_q == DC_REFILL_REQ) &&
                             mem_req_valid && mem_req_ready;
    assign refill_resp_fire = refill_active && mem_resp_valid &&
                              (refill_resp_count_q < refill_issue_count_q);
    assign writeback_req_fire = (state_q == DC_WRITEBACK_REQ) &&
                                mem_req_valid && mem_req_ready;
    assign writeback_req_last =
        burst_word_q == WORD_BITS'(WORDS_PER_LINE - 1);

    always_comb begin
        data_read_addr = {req_index, req_word};
        if (state_q == DC_WRITEBACK_PREP) begin
            data_read_addr = {req_index_q, burst_word_q};
        end else if (state_q == DC_WRITEBACK_REQ) begin
            // While the registered current word is sent to DRAM, point the
            // asynchronous LUTRAM read port at the following word. The next
            // word is captured on the same acceptance edge, preserving a
            // one-write-per-cycle burst after the single PREP cycle.
            if (!writeback_req_last) begin
                data_read_addr = {
                    req_index_q, burst_word_q + WORD_BITS'(1)
                };
            end else begin
                data_read_addr = {req_index_q, burst_word_q};
            end
        end else if (state_q == DC_FINISH) begin
            data_read_addr = {req_index_q, req_word_q};
        end
    end

    assign data_way0_read = data_way0_q[data_read_addr];
    assign data_way1_read = data_way1_q[data_read_addr];
    assign data_way0_effective = data_write_valid_q && !data_write_way_q &&
                                 (data_write_addr_q == data_read_addr) ?
                                 data_write_data_q : data_way0_read;
    assign data_way1_effective = data_write_valid_q && data_write_way_q &&
                                 (data_write_addr_q == data_read_addr) ?
                                 data_write_data_q : data_way1_read;
    assign hit_word = hit_way ? data_way1_effective : data_way0_effective;
    assign victim_read_word = victim_way_q ? data_way1_effective : data_way0_effective;

    // The routed baseline allowed ROB recovery/read-arbitration control to
    // select a DCache LUTRAM word and propagate that word directly to the
    // external DRAM BRAM DI pin. Capture dirty-victim data locally first so
    // every DRAM writeback word is launched by this DCache register instead.
    // Payload has no reset: DC_WRITEBACK_PREP owns initialization before the
    // value becomes visible in DC_WRITEBACK_REQ.
    always_ff @(posedge clk) begin
        if (!rst) begin
            if (state_q == DC_WRITEBACK_PREP) begin
                writeback_data_q <= victim_read_word;
            end else if (writeback_req_fire && !writeback_req_last) begin
                writeback_data_q <= victim_read_word;
            end
        end
    end

    always_comb begin
        data_way0_we = 1'b0;
        data_way1_we = 1'b0;
        data_write_addr = '0;
        data_write_data = '0;

        case (state_q)
            DC_IDLE: begin
                if (active_req_valid && req_cacheable && hit && active_req_write) begin
                    data_write_addr = {req_index, req_word};
                    data_write_data = merge_word(
                        hit_word,
                        align_store_data(active_req_wdata, active_req_addr[1:0]),
                        align_store_mask(active_req_wstrb, active_req_addr[1:0])
                    );
                    data_way0_we = !hit_way;
                    data_way1_we = hit_way;
                end
            end

            DC_REFILL_REQ,
            DC_REFILL_WAIT: begin
                if (refill_resp_fire) begin
                    data_write_addr = {req_index_q, refill_resp_word};
                    data_write_data = mem_resp_rdata;
                    data_way0_we = !victim_way_q;
                    data_way1_we = victim_way_q;
                end
            end

            DC_FINISH: begin
                if (req_write_q) begin
                    data_write_addr = {req_index_q, req_word_q};
                    data_write_data = merge_word(
                        victim_read_word,
                        align_store_data(req_wdata_q, req_byte_q),
                        align_store_mask(req_wstrb_q, req_byte_q)
                    );
                    data_way0_we = !victim_way_q;
                    data_way1_we = victim_way_q;
                end
            end

            default: begin
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (!rst && data_way0_we) begin
            data_way0_q[data_write_addr] <= data_write_data;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst && data_way1_we) begin
            data_way1_q[data_write_addr] <= data_write_data;
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            data_write_valid_q <= 1'b0;
            data_write_way_q <= 1'b0;
            data_write_addr_q <= '0;
            data_write_data_q <= '0;
        end else begin
            data_write_valid_q <= data_way0_we || data_way1_we;
            if (data_way0_we || data_way1_we) begin
                data_write_way_q <= data_way1_we;
                data_write_addr_q <= data_write_addr;
                data_write_data_q <= data_write_data;
            end
        end
    end

    assign tag_way0_we = refill_resp_fire && refill_resp_last &&
                         refill_line_complete && !victim_way_q;
    assign tag_way1_we = refill_resp_fire && refill_resp_last &&
                         refill_line_complete && victim_way_q;

    always_ff @(posedge clk) begin
        if (!rst && tag_way0_we) begin
            tag_way0_q[req_index_q] <= req_tag_q;
        end
    end

    always_ff @(posedge clk) begin
        if (!rst && tag_way1_we) begin
            tag_way1_q[req_index_q] <= req_tag_q;
        end
    end

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
                // Data is don't-care unless a write request is valid. Drive it
                // directly from the store payload instead of conditioning it
                // on address classification, so read/recovery/address control
                // cannot become a select path into the external DRAM DI cone.
                mem_req_wdata = active_req_wdata;
                if (active_req_valid) begin
                    if (!req_cacheable) begin
                        mem_req_valid = 1'b1;
                        mem_req_write = active_req_write;
                        mem_req_addr = active_req_addr;
                        mem_req_wstrb = active_req_write ? active_req_wstrb : 4'b0000;
                        mem_req_uncached = 1'b1;
                        cpu_req_ready = active_req_write && mem_req_ready;
                    end else if (hit) begin
                        // A replayed held read is internal to the cache. Do
                        // not acknowledge a simultaneous external store with
                        // the held read's hit; its writePending must persist.
                        cpu_req_ready = !cpu_read_hold_valid_q;
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
                mem_req_wdata = writeback_data_q;
                mem_req_wstrb = 4'b1111;
                mem_req_uncached = 1'b0;
            end

            DC_REFILL_REQ: begin
                mem_req_valid =
                    refill_issue_count_q < REFILL_COUNT_BITS'(WORDS_PER_LINE);
                mem_req_write = 1'b0;
                mem_req_addr = {
                    req_addr_q[31:OFFSET_BITS], refill_issue_word, 2'b00
                };
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

`ifndef VERILATOR_TB
    assign perf_access_o = '0;
    assign perf_miss_o = '0;
    assign perf_stall_o = '0;
`endif

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
            req_byte_q <= '0;
            victim_tag_q <= '0;
            burst_word_q <= '0;
            cpu_read_hold_valid_q <= 1'b0;
            cpu_read_hold_addr_q <= '0;
            cpu_read_hold_uncached_q <= 1'b0;
            refill_issue_count_q <= '0;
            refill_resp_count_q <= '0;
            refill_valid_mask_q <= '0;
            refill_critical_seen_q <= 1'b0;
`ifdef VERILATOR_TB
            perf_access_o <= 64'b0;
            perf_miss_o <= 64'b0;
            perf_stall_o <= 64'b0;
`endif
            valid_q <= '0;
            dirty_q <= '0;
            lru_q <= '0;
        end else begin
            cpu_resp_valid <= 1'b0;

`ifdef VERILATOR_TB
            if (state_q != DC_IDLE ||
                (active_req_valid && !cpu_req_ready && !active_req_write)) begin
                perf_stall_o <= perf_stall_o + 64'd1;
            end
`endif

            if (refill_active && cpu_req_valid && !cpu_req_write &&
                !cpu_read_hold_valid_q) begin
                cpu_read_hold_valid_q <= 1'b1;
                cpu_read_hold_addr_q <= cpu_req_addr;
                cpu_read_hold_uncached_q <= cpu_req_uncached;
            end

            unique case (state_q)
                DC_IDLE: begin
                    if (active_req_valid) begin
                        if (cpu_read_hold_valid_q) begin
                            cpu_read_hold_valid_q <= 1'b0;
                        end
                        req_write_q <= active_req_write;
                        req_addr_q <= active_req_addr;
                        req_wdata_q <= active_req_wdata;
                        req_wstrb_q <= active_req_wstrb;
                        req_cacheable_q <= req_cacheable;
                        req_index_q <= req_index;
                        req_tag_q <= req_tag;
                        req_word_q <= req_word;
                        req_byte_q <= active_req_addr[1:0];
                        victim_way_q <= victim_way;
                        victim_tag_q <= victim_way ? tag_way1_read : tag_way0_read;

`ifdef VERILATOR_TB
                        if (req_cacheable) begin
                            perf_access_o <= perf_access_o + 64'd1;
                        end
`endif

                        if (!req_cacheable) begin
                            if (mem_req_ready) begin
                                if (active_req_write) begin
                                    state_q <= DC_IDLE;
                                end else begin
                                    state_q <= DC_UNCACHED_WAIT;
                                end
                            end else begin
                                state_q <= DC_UNCACHED_REQ;
                            end
                        end else if (hit) begin
                            lru_q[req_index] <= ~hit_way;
                            if (active_req_write) begin
                                dirty_q[hit_way][req_index] <= 1'b1;
                            end else begin
                                cpu_resp_valid <= 1'b1;
                                cpu_resp_rdata <= align_load_word(
                                    hit_word, active_req_addr[1:0]
                                );
                            end
                        end else begin
`ifdef VERILATOR_TB
                            perf_miss_o <= perf_miss_o + 64'd1;
`endif
                            burst_word_q <= '0;
                            refill_issue_count_q <= '0;
                            refill_resp_count_q <= '0;
                            refill_valid_mask_q <= '0;
                            refill_critical_seen_q <= 1'b0;
                            if (valid_q[victim_way][req_index] && dirty_q[victim_way][req_index]) begin
                                state_q <= DC_WRITEBACK_PREP;
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

                DC_WRITEBACK_PREP: begin
                    // req_index_q/victim_way_q were captured on the miss edge.
                    // Give the distributed RAM one cycle to read word zero and
                    // load writeback_data_q before exposing a DRAM request.
                    state_q <= DC_WRITEBACK_REQ;
                end

                DC_WRITEBACK_REQ: begin
                    if (mem_req_ready) begin
                        if (writeback_req_last) begin
                            burst_word_q <= '0;
                            dirty_q[victim_way_q][req_index_q] <= 1'b0;
                            valid_q[victim_way_q][req_index_q] <= 1'b0;
                            state_q <= DC_REFILL_REQ;
                        end else begin
                            burst_word_q <= burst_word_q + 1'b1;
                        end
                    end
                end

                DC_REFILL_REQ,
                DC_REFILL_WAIT: begin
                    if (refill_req_fire) begin
                        refill_issue_count_q <= refill_issue_count_q + 1'b1;
                        if (refill_issue_last) begin
                            state_q <= DC_REFILL_WAIT;
                        end
                    end

                    if (refill_resp_fire) begin
                        refill_resp_count_q <= refill_resp_count_q + 1'b1;
                        refill_valid_mask_q <=
                            refill_valid_mask_q | refill_resp_onehot;

                        if (refill_resp_word == req_word_q) begin
                            refill_critical_seen_q <= 1'b1;
                            if (!req_write_q && !refill_critical_seen_q) begin
                                cpu_resp_valid <= 1'b1;
                                cpu_resp_rdata <= align_load_word(
                                    mem_resp_rdata, req_byte_q
                                );
                            end
                        end

                        if (refill_resp_last && refill_line_complete) begin
                            valid_q[victim_way_q][req_index_q] <= 1'b1;
                            dirty_q[victim_way_q][req_index_q] <= 1'b0;
                            lru_q[req_index_q] <= ~victim_way_q;
                            if (req_write_q) begin
                                state_q <= DC_FINISH;
                            end else begin
                                state_q <= DC_IDLE;
                            end
                        end
                    end
                end

                DC_FINISH: begin
                    if (req_write_q) begin
                        dirty_q[victim_way_q][req_index_q] <= 1'b1;
                    end else begin
                        cpu_resp_valid <= 1'b1;
                        cpu_resp_rdata <= align_load_word(victim_read_word, req_byte_q);
                    end
                    state_q <= DC_IDLE;
                end

                default: begin
                    state_q <= DC_IDLE;
                end
            endcase
        end
    end

`ifdef VERILATOR_TB
    always_ff @(posedge clk) begin
        if (!rst && (state_q == DC_WRITEBACK_REQ)) begin
            assert (writeback_data_q ==
                    (victim_way_q ?
                     data_way1_q[{req_index_q, burst_word_q}] :
                     data_way0_q[{req_index_q, burst_word_q}]))
                else $error("DCache writeback data/word alignment mismatch");
        end

        if (!rst && refill_active) begin
            assert (refill_resp_count_q <= refill_issue_count_q)
                else $error("DCache refill responses exceeded issued reads");

            if (mem_resp_valid) begin
                assert (refill_resp_count_q < refill_issue_count_q)
                    else $error("DCache observed a refill response with no owner");
            end

            if (refill_resp_fire) begin
                assert (!refill_valid_mask_q[refill_resp_word])
                    else $error("DCache refill returned a duplicate word");
                if (refill_resp_word == req_word_q) begin
                    assert (!refill_critical_seen_q)
                        else $error("DCache critical word returned more than once");
                end
                if (refill_resp_last) begin
                    assert (refill_line_complete)
                        else $error("DCache refill completed with a missing word");
                    assert (refill_critical_seen_q ||
                            (refill_resp_word == req_word_q))
                        else $error("DCache refill completed without critical word");
                end
            end

            if (cpu_req_valid && !cpu_req_write) begin
                assert (!cpu_read_hold_valid_q)
                    else $error("DCache critical-return read hold overflow");
            end
        end
    end
`endif

    logic unused_req_cacheable;
    always_comb begin
        unused_req_cacheable = req_cacheable_q;
    end
endmodule : CoreDCache
