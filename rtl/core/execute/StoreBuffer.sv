import CoreTypesPkg::*;
import CoreConfigPkg::*;

module CoreStoreBuffer (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,

    input  logic push_valid_i,
    input  RobIndexPath push_rob_idx_i,
    input  AddrPath push_addr_i,
    input  DataPath push_data_i,
    input  logic [3:0] push_mask_i,
    output logic push_ready_o,

    input  logic [RETIRE_WIDTH-1:0] commit_valid_i,
    input  RobIndexPath [RETIRE_WIDTH-1:0] commit_rob_idx_i,

    input  logic load_query_valid_i,
    input  AddrPath load_query_addr_i,
    input  logic [3:0] load_query_mask_i,
    output logic load_forward_hit_o,
    output logic load_forward_full_o,
    output DataPath load_forward_data_o,

    output logic empty_o,

    DramAccessIF.StoreBuffer dmem
);
    typedef struct packed {
        logic valid;
        logic retired;
        RobIndexPath rob_idx;
        AddrPath addr;
        DataPath data;
        logic [3:0] mask;
    } store_entry_t;

    localparam int COUNT_WIDTH = $clog2(STORE_BUF_DEPTH + 1);
    localparam int STORE_BUF_INDEX_WIDTH = (STORE_BUF_DEPTH <= 1) ? 1 : $clog2(STORE_BUF_DEPTH);
    localparam logic [COUNT_WIDTH-1:0] STORE_BUF_DEPTH_COUNT = COUNT_WIDTH'(STORE_BUF_DEPTH);

    store_entry_t entry_q [STORE_BUF_DEPTH-1:0];
    store_entry_t marked_entry [STORE_BUF_DEPTH-1:0];
    store_entry_t compact_entry [STORE_BUF_DEPTH-1:0];
    store_entry_t next_entry [STORE_BUF_DEPTH-1:0];
    logic [STORE_BUF_DEPTH-1:0] keep_entry;
    logic [COUNT_WIDTH-1:0] count_q;
    logic [COUNT_WIDTH-1:0] compact_count;
    logic pop_fire;
    logic push_fire;
    logic [3:0] forward_mask;
    DataPath forward_word;

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

    always_comb begin
        dmem.storeWriteEn = entry_q[0].valid && entry_q[0].retired;
        dmem.storeWriteAddr = entry_q[0].addr;
        dmem.storeWriteData = entry_q[0].data;
        dmem.storeWriteMask = entry_q[0].mask;

        pop_fire = dmem.storeWriteEn && dmem.storeWriteReady;
    end

    // A store can enter on the same cycle that the retired head drains.
    // This path is intentionally independent of push_valid_i.
    assign push_ready_o = !clear_i &&
                          ((count_q < STORE_BUF_DEPTH_COUNT) || pop_fire);
    assign empty_o = (count_q == '0);

    always_comb begin
        forward_mask = '0;
        forward_word = '0;
        load_forward_hit_o = 1'b0;
        load_forward_full_o = 1'b0;
        load_forward_data_o = '0;

        for (int i = 0; i < STORE_BUF_DEPTH; i = i + 1) begin
            if (load_query_valid_i &&
                entry_q[i].valid &&
                (entry_q[i].addr[31:2] == load_query_addr_i[31:2])) begin
                load_forward_hit_o = 1'b1;
                forward_word = merge_word(forward_word,
                                          align_store_data(entry_q[i].data, entry_q[i].addr[1:0]),
                                          align_store_mask(entry_q[i].mask, entry_q[i].addr[1:0]));
                forward_mask = forward_mask |
                               align_store_mask(entry_q[i].mask, entry_q[i].addr[1:0]);
            end
        end

        load_forward_full_o = load_query_valid_i &&
                              ((forward_mask & load_query_mask_i) == load_query_mask_i);
        load_forward_data_o = forward_word >> {load_query_addr_i[1:0], 3'b000};
    end

    always_comb begin
        for (int i = 0; i < STORE_BUF_DEPTH; i = i + 1) begin
            marked_entry[i] = entry_q[i];
            for (int c = 0; c < RETIRE_WIDTH; c = c + 1) begin
                if (commit_valid_i[c] &&
                    marked_entry[i].valid &&
                    !marked_entry[i].retired &&
                    (marked_entry[i].rob_idx == commit_rob_idx_i[c])) begin
                    marked_entry[i].retired = 1'b1;
                end
            end

            keep_entry[i] = marked_entry[i].valid &&
                            !(pop_fire && (i == 0)) &&
                            (!clear_i || marked_entry[i].retired);
            compact_entry[i] = '0;
            next_entry[i] = '0;
        end

        compact_count = '0;
        for (int i = 0; i < STORE_BUF_DEPTH; i = i + 1) begin
            if (keep_entry[i]) begin
                compact_entry[compact_count[STORE_BUF_INDEX_WIDTH-1:0]] = marked_entry[i];
                compact_count = compact_count + 1'b1;
            end
        end

        push_fire = push_valid_i && push_ready_o;

        for (int i = 0; i < STORE_BUF_DEPTH; i = i + 1) begin
            next_entry[i] = compact_entry[i];
        end
        if (push_fire) begin
            next_entry[compact_count[STORE_BUF_INDEX_WIDTH-1:0]].valid = 1'b1;
            next_entry[compact_count[STORE_BUF_INDEX_WIDTH-1:0]].retired = 1'b0;
            next_entry[compact_count[STORE_BUF_INDEX_WIDTH-1:0]].rob_idx = push_rob_idx_i;
            next_entry[compact_count[STORE_BUF_INDEX_WIDTH-1:0]].addr = push_addr_i;
            next_entry[compact_count[STORE_BUF_INDEX_WIDTH-1:0]].data = push_data_i;
            next_entry[compact_count[STORE_BUF_INDEX_WIDTH-1:0]].mask = push_mask_i;
        end

    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            count_q <= '0;
            for (int i = 0; i < STORE_BUF_DEPTH; i = i + 1) begin
                entry_q[i] <= '0;
            end
        end else begin
            for (int i = 0; i < STORE_BUF_DEPTH; i = i + 1) begin
                entry_q[i] <= next_entry[i];
            end
            count_q <= compact_count + COUNT_WIDTH'(push_fire);
        end
    end
endmodule : CoreStoreBuffer
