`timescale 1ns / 1ps

module load_data_path #(
    parameter int unsigned CNT_W = $clog2(core_config_pkg::LOAD_QUEUE_DEPTH + 1)
) (
    input  logic load_active_i,
    input  logic [CNT_W-1:0] load_count_i,
    input  core_types_pkg::load_entry_t load_head_i,
    input  core_types_pkg::load_entry_t active_meta_i,
    input  logic [31:0] memory_data_i,
    output logic forward_complete_o,
    output core_types_pkg::load_entry_t completion_meta_o,
    output logic [31:0] result_o
);
    import core_config_pkg::*;
    import core_types_pkg::*;

    logic [3:0] needed_mask;
    logic [31:0] forward_byte_mask;
    logic [31:0] merged_word;
    logic [31:0] shifted_word;
    integer byte_lane;

    function automatic logic [3:0] load_byte_mask(
        input mem_size_e size,
        input logic [1:0] byte_offset
    );
        begin
            unique case (size)
                MEM_BYTE: load_byte_mask = 4'b0001 << byte_offset;
                MEM_HALF: load_byte_mask = 4'b0011 << byte_offset;
                default: load_byte_mask = 4'b1111;
            endcase
        end
    endfunction

    always_comb begin
        needed_mask = load_byte_mask(load_head_i.size, load_head_i.addr[1:0]);
        forward_complete_o = !load_active_i && load_count_i != 0 &&
                             load_head_i.addr[31:18] == DRAM_START[31:18] &&
                             ((load_head_i.forward_mask & needed_mask) == needed_mask);
        completion_meta_o = forward_complete_o ? load_head_i : active_meta_i;

        forward_byte_mask = 32'd0;
        for (byte_lane = 0; byte_lane < 4; byte_lane = byte_lane + 1)
            forward_byte_mask[byte_lane*8 +: 8] =
                {8{completion_meta_o.forward_mask[byte_lane]}};
        merged_word = forward_complete_o ? completion_meta_o.forward_data :
                      ((memory_data_i & ~forward_byte_mask) |
                       (completion_meta_o.forward_data & forward_byte_mask));
        shifted_word = merged_word >> {completion_meta_o.addr[1:0], 3'b000};
        unique case (completion_meta_o.size)
            MEM_BYTE: result_o = completion_meta_o.load_unsigned ?
                {24'd0, shifted_word[7:0]} : {{24{shifted_word[7]}}, shifted_word[7:0]};
            MEM_HALF: result_o = completion_meta_o.load_unsigned ?
                {16'd0, shifted_word[15:0]} : {{16{shifted_word[15]}}, shifted_word[15:0]};
            default: result_o = shifted_word;
        endcase
    end
endmodule
