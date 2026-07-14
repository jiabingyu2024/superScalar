`timescale 1ns / 1ps

module pynq_top #(
    parameter logic [31:0] PASS_SIGNATURE = 32'h0122_1c08,
    parameter logic [31:0] FAIL_SIGNATURE = 32'h2418_1824
) (
    input  logic       sys_clk_125mhz,
    input  logic [3:0] btn,
    input  logic [1:0] sw,
    output logic [3:0] led,
    output logic [7:0] daughter_seg_n,
    output logic [3:0] daughter_digit_n
);
    logic clk_50mhz;
    logic clk_feedback;
    logic clk_feedback_buf;
    logic clk_50mhz_raw;
    logic pll_locked;
    logic soc_rst;

    logic [63:0] virtual_sw;
    logic [7:0]  virtual_key;
    logic [31:0] virtual_led;
    logic [39:0] virtual_seg;

    (* ASYNC_REG = "TRUE" *) logic [1:0] sw_meta_q;
    (* ASYNC_REG = "TRUE" *) logic [1:0] sw_sync_q;
    (* ASYNC_REG = "TRUE" *) logic [3:0] btn_meta_q;
    (* ASYNC_REG = "TRUE" *) logic [3:0] btn_sync_q;

    logic [6:0] digit_pattern_q [0:7];
    logic [25:0] heartbeat_q;
    logic [16:0] scan_counter_q;
    logic        pass_q;
    logic        fail_q;
    logic [1:0]  scan_index;
    logic [2:0]  value_index;
    logic [6:0]  selected_pattern;

    PLLE2_BASE #(
        .BANDWIDTH       ("OPTIMIZED"),
        .CLKFBOUT_MULT   (8),
        .CLKIN1_PERIOD   (8.000),
        .CLKOUT0_DIVIDE  (20),
        .DIVCLK_DIVIDE   (1),
        .STARTUP_WAIT    ("FALSE")
    ) pll_inst (
        .CLKIN1   (sys_clk_125mhz),
        .CLKFBIN  (clk_feedback_buf),
        .RST      (btn[0]),
        .PWRDWN   (1'b0),
        .CLKFBOUT (clk_feedback),
        .CLKOUT0  (clk_50mhz_raw),
        .LOCKED   (pll_locked)
    );

    BUFG clk_feedback_buf_inst (
        .I(clk_feedback),
        .O(clk_feedback_buf)
    );

    BUFG clk_50mhz_buf_inst (
        .I(clk_50mhz_raw),
        .O(clk_50mhz)
    );

    assign soc_rst = btn[0] || !pll_locked;

    always_ff @(posedge clk_50mhz or posedge soc_rst) begin
        if (soc_rst) begin
            sw_meta_q  <= '0;
            sw_sync_q  <= '0;
            btn_meta_q <= '0;
            btn_sync_q <= '0;
        end else begin
            sw_meta_q  <= sw;
            sw_sync_q  <= sw_meta_q;
            btn_meta_q <= btn;
            btn_sync_q <= btn_meta_q;
        end
    end

    assign virtual_sw  = {62'd0, sw_sync_q};
    assign virtual_key = {4'd0, btn_sync_q};

    student_top student_top_inst (
        .w_cpu_clk   (clk_50mhz),
        .w_clk_50Mhz (clk_50mhz),
        .w_clk_rst   (soc_rst),
        .virtual_key (virtual_key),
        .virtual_sw  (virtual_sw),
        .virtual_led (virtual_led),
        .virtual_seg (virtual_seg)
    );

    always_ff @(posedge clk_50mhz or posedge soc_rst) begin
        if (soc_rst) begin
            digit_pattern_q[0] <= 7'd0;
            digit_pattern_q[1] <= 7'd0;
            digit_pattern_q[2] <= 7'd0;
            digit_pattern_q[3] <= 7'd0;
            digit_pattern_q[4] <= 7'd0;
            digit_pattern_q[5] <= 7'd0;
            digit_pattern_q[6] <= 7'd0;
            digit_pattern_q[7] <= 7'd0;
        end else begin
            case (virtual_seg[9:8])
                2'b01: begin
                    digit_pattern_q[0] <= virtual_seg[6:0];
                    digit_pattern_q[2] <= virtual_seg[16:10];
                    digit_pattern_q[4] <= virtual_seg[26:20];
                    digit_pattern_q[6] <= virtual_seg[36:30];
                end
                2'b10: begin
                    digit_pattern_q[1] <= virtual_seg[6:0];
                    digit_pattern_q[3] <= virtual_seg[16:10];
                    digit_pattern_q[5] <= virtual_seg[26:20];
                    digit_pattern_q[7] <= virtual_seg[36:30];
                end
                default: begin
                end
            endcase
        end
    end

    always_ff @(posedge clk_50mhz or posedge soc_rst) begin
        if (soc_rst) begin
            heartbeat_q    <= '0;
            scan_counter_q <= '0;
            pass_q         <= 1'b0;
            fail_q         <= 1'b0;
        end else begin
            heartbeat_q    <= heartbeat_q + 1'b1;
            scan_counter_q <= scan_counter_q + 1'b1;

            if (virtual_led == FAIL_SIGNATURE) begin
                fail_q <= 1'b1;
                pass_q <= 1'b0;
            end else if (!fail_q && virtual_led == PASS_SIGNATURE) begin
                pass_q <= 1'b1;
            end
        end
    end

    assign scan_index = scan_counter_q[16:15];

    always_comb begin
        value_index = {sw_sync_q[0], 2'b00} + (3 - scan_index);
        selected_pattern = digit_pattern_q[value_index];

        daughter_seg_n = {1'b1, ~selected_pattern};
        daughter_digit_n = 4'b1111;
        daughter_digit_n[scan_index] = 1'b0;

        led[0] = (!pass_q && !fail_q) ? heartbeat_q[24] : 1'b0;
        led[1] = pass_q;
        led[2] = fail_q;
        led[3] = sw_sync_q[0];
    end
endmodule
