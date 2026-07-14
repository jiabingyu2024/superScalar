`timescale 1ns / 1ps

module store_forwarding #(
    parameter int unsigned DEPTH = core_config_pkg::STORE_BUFFER_DEPTH,
    parameter int unsigned CNT_W = $clog2(DEPTH + 1)
) (
    input  logic load_valid_i,
    input  logic load_cacheable_i,
    input  logic [31:0] load_addr_i,
    input  core_types_pkg::store_entry_t store_entries_i [0:DEPTH-1],
    input  logic [core_config_pkg::STORE_ID_W-1:0] store_head_i,
    input  logic [CNT_W-1:0] store_count_i,
    output logic [3:0] forward_mask_o,
    output logic [31:0] forward_data_o
);
    logic [3:0] shifted_mask;
    logic [31:0] shifted_data;
    integer entry_offset;
    integer entry_index;
    integer byte_lane;

    always_comb begin
        forward_mask_o = 4'd0;
        forward_data_o = 32'd0;
        shifted_mask = 4'd0;
        shifted_data = 32'd0;
        entry_index = 0;
        if (load_valid_i && load_cacheable_i) begin
            // Program-order walk makes the youngest overlapping store win.
            for (entry_offset = 0; entry_offset < DEPTH; entry_offset = entry_offset + 1) begin
                entry_index = (int'(store_head_i) + entry_offset) % DEPTH;
                if (entry_offset < int'(store_count_i) &&
                    store_entries_i[entry_index].valid &&
                    store_entries_i[entry_index].addr[31:2] == load_addr_i[31:2]) begin
                    shifted_mask = (store_entries_i[entry_index].wstrb <<
                                    store_entries_i[entry_index].addr[1:0]) & 4'hf;
                    shifted_data = store_entries_i[entry_index].wdata <<
                                   {store_entries_i[entry_index].addr[1:0], 3'b000};
                    for (byte_lane = 0; byte_lane < 4; byte_lane = byte_lane + 1) begin
                        if (shifted_mask[byte_lane]) begin
                            forward_mask_o[byte_lane] = 1'b1;
                            forward_data_o[byte_lane*8 +: 8] =
                                shifted_data[byte_lane*8 +: 8];
                        end
                    end
                end
            end
        end
    end
endmodule
