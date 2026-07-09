import CoreTypesPkg::*;

module CoreStoreBuffer (
    input  logic clk,
    input  logic rst,
    input  logic clear_i,
    input  logic push_valid_i,
    input  AddrPath push_addr_i,
    input  DataPath push_data_i,
    input  logic [3:0] push_mask_i,
    output logic push_ready_o,
    DramAccessIF.StoreBuffer dmem
);
    typedef struct packed {
        AddrPath addr;
        DataPath data;
        logic [3:0] mask;
    } store_entry_t;

    store_entry_t entry_q;
    logic valid_q;

    assign push_ready_o = !valid_q;

    always_comb begin
        dmem.storeWriteEn = valid_q;
        dmem.storeWriteAddr = entry_q.addr;
        dmem.storeWriteData = entry_q.data;
        dmem.storeWriteMask = entry_q.mask;
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst || clear_i) begin
            valid_q <= 1'b0;
            entry_q <= '0;
        end else begin
            if (push_valid_i && push_ready_o) begin
                valid_q <= 1'b1;
                entry_q.addr <= push_addr_i;
                entry_q.data <= push_data_i;
                entry_q.mask <= push_mask_i;
            end else if (valid_q && dmem.storeWriteReady) begin
                valid_q <= 1'b0;
            end
        end
    end
endmodule : CoreStoreBuffer
