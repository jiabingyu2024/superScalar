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

    always_comb begin
        dmem.storeWriteEn = entry_q[0].valid && entry_q[0].retired;
        dmem.storeWriteAddr = entry_q[0].addr;
        dmem.storeWriteData = entry_q[0].data;
        dmem.storeWriteMask = entry_q[0].mask;

        pop_fire = dmem.storeWriteEn && dmem.storeWriteReady;

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
                compact_entry[compact_count] = marked_entry[i];
                compact_count = compact_count + 1'b1;
            end
        end

        push_ready_o = !clear_i && (compact_count < STORE_BUF_DEPTH_COUNT);
        push_fire = push_valid_i && push_ready_o;

        for (int i = 0; i < STORE_BUF_DEPTH; i = i + 1) begin
            next_entry[i] = compact_entry[i];
        end
        if (push_fire) begin
            next_entry[compact_count].valid = 1'b1;
            next_entry[compact_count].retired = 1'b0;
            next_entry[compact_count].rob_idx = push_rob_idx_i;
            next_entry[compact_count].addr = push_addr_i;
            next_entry[compact_count].data = push_data_i;
            next_entry[compact_count].mask = push_mask_i;
        end

        empty_o = (count_q == '0);
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
            count_q <= compact_count + (push_fire ? 1'b1 : 1'b0);
        end
    end
endmodule : CoreStoreBuffer
