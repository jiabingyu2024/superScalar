`timescale 1ns / 1ps

// Minimal single-hart machine timer.  The MMIO layout follows the conventional
// CLINT addresses so a future RTOS BSP does not need a project-specific timer
// abstraction.
module MachineTimer (
    input  logic        clk,
    input  logic        rst,
    input  logic        req_valid_i,
    input  logic        req_write_i,
    input  logic [31:0] req_addr_i,
    input  logic [31:0] req_wdata_i,
    input  logic [3:0]  req_wstrb_i,
    output logic        resp_valid_o,
    output logic [31:0] resp_rdata_o,
    output logic        timer_irq_o
);
    localparam logic [31:0] MTIMECMP_LO_ADDR = 32'h0200_4000;
    localparam logic [31:0] MTIMECMP_HI_ADDR = 32'h0200_4004;
    localparam logic [31:0] MTIME_LO_ADDR    = 32'h0200_BFF8;
    localparam logic [31:0] MTIME_HI_ADDR    = 32'h0200_BFFC;

    logic [63:0] mtime_q, mtimecmp_q;
    logic        read_valid_q;
    logic [31:0] read_data_q;

    function automatic logic [31:0] merge_bytes(
        input logic [31:0] old_value,
        input logic [31:0] new_value,
        input logic [3:0]  byte_enable
    );
        logic [31:0] merged;
        integer i;
        begin
            merged = old_value;
            for (i = 0; i < 4; i = i + 1)
                if (byte_enable[i]) merged[i*8 +: 8] = new_value[i*8 +: 8];
            merge_bytes = merged;
        end
    endfunction

    assign resp_valid_o = read_valid_q;
    assign resp_rdata_o = read_data_q;
    assign timer_irq_o = mtime_q >= mtimecmp_q;

    always_ff @(posedge clk) begin
        if (rst) begin
            mtime_q <= 64'd0;
            mtimecmp_q <= 64'hffff_ffff_ffff_ffff;
            read_valid_q <= 1'b0;
            read_data_q <= 32'd0;
        end else begin
            read_valid_q <= req_valid_i && !req_write_i;
            if (req_valid_i && !req_write_i) begin
                unique case (req_addr_i)
                    MTIMECMP_LO_ADDR: read_data_q <= mtimecmp_q[31:0];
                    MTIMECMP_HI_ADDR: read_data_q <= mtimecmp_q[63:32];
                    MTIME_LO_ADDR:    read_data_q <= mtime_q[31:0];
                    MTIME_HI_ADDR:    read_data_q <= mtime_q[63:32];
                    default:          read_data_q <= 32'd0;
                endcase
            end
            if (req_valid_i && req_write_i) begin
                unique case (req_addr_i)
                    MTIMECMP_LO_ADDR:
                        mtimecmp_q[31:0] <= merge_bytes(mtimecmp_q[31:0], req_wdata_i, req_wstrb_i);
                    MTIMECMP_HI_ADDR:
                        mtimecmp_q[63:32] <= merge_bytes(mtimecmp_q[63:32], req_wdata_i, req_wstrb_i);
                    MTIME_LO_ADDR:
                        mtime_q[31:0] <= merge_bytes(mtime_q[31:0], req_wdata_i, req_wstrb_i);
                    MTIME_HI_ADDR:
                        mtime_q[63:32] <= merge_bytes(mtime_q[63:32], req_wdata_i, req_wstrb_i);
                    default: begin end
                endcase
            end
            if (!(req_valid_i && req_write_i &&
                  (req_addr_i == MTIME_LO_ADDR || req_addr_i == MTIME_HI_ADDR)))
                mtime_q <= mtime_q + 64'd1;
        end
    end
endmodule
