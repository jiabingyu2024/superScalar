//==============================================================================
// 模块: csr_file
// 功能概述：
//   最小化 CSR 寄存器堆，支持机器模式（M-mode）。
//   实现 mtvec/mepc/mcause/mstatus/mscratch 读写，其余 CSR 存根（写入接受，读出0）。
//   Trap 入口：trap_en 拉高时保存 mepc、写 mcause，输出 mtvec 供 EX 级跳转。
//   Mret：mret_en 拉高时输出 mepc 供 EX 级跳转。
//==============================================================================
`include "cpu_defines.svh"

module csr_file (
    input  logic        i_clk,
    input  logic        i_rst_n,

    // --- 通用读端口（组合）---
    input  logic [11:0] i_raddr,
    output logic [31:0] o_rdata,

    // --- 通用写端口（时序）---
    input  logic        i_we,          // 写使能
    input  logic [11:0] i_waddr,
    input  logic [31:0] i_wdata,
    input  logic [1:0]  i_wmode,       // 00=write，01=set，10=clear
    input  logic        i_fflags_we,
    input  logic [4:0]  i_fflags,
    output logic [2:0]  o_frm,

    // --- Trap 入口（ecall/ebreak）---
    input  logic        i_trap_en,
    input  logic [31:0] i_trap_pc,     // 陷入时 PC，写入 mepc
    input  logic [31:0] i_trap_cause,  // 写入 mcause

    // --- Trap 返回（mret）---
    input  logic        i_mret_en,     // 未使用，mepc 始终通过 o_mepc 输出

    // --- 直接输出（供 EX 级跳转用）---
    output logic [31:0] o_mtvec,
    output logic [31:0] o_mepc
);

    // ---- CSR 存储 ----
    logic [31:0] mstatus;   // 0x300
    logic [31:0] mtvec_r;   // 0x305
    logic [31:0] mscratch_r;// 0x340
    logic [31:0] mepc_r;    // 0x341
    logic [31:0] mcause_r;  // 0x342
    logic [2:0]  frm_r;
    logic [4:0]  fflags_r;
    // 存根：mie, medeleg, mideleg, satp, stvec, pmpaddr0, pmpcfg0 等
    // 写入接受但读出 0，节省资源

    assign o_mtvec = mtvec_r;
    assign o_mepc  = mepc_r;
    assign o_frm   = frm_r;

    // ---- 读出（组合）----
    always_comb begin
        case (i_raddr)
            12'h001: o_rdata = {27'b0, fflags_r};
            12'h002: o_rdata = {29'b0, frm_r};
            12'h003: o_rdata = {24'b0, frm_r, fflags_r};
            12'h300: o_rdata = mstatus;
            12'h305: o_rdata = mtvec_r;
            12'h340: o_rdata = mscratch_r;
            12'h341: o_rdata = mepc_r;
            12'h342: o_rdata = mcause_r;
            12'hF14: o_rdata = 32'h0;   // mhartid = 0
            default: o_rdata = 32'h0;   // 所有存根 CSR 读出 0
        endcase
    end

    // ---- 写入辅助函数（组合） ----
    function automatic logic [31:0] apply_wmode(
        input logic [31:0] old_val,
        input logic [31:0] wdata,
        input logic [1:0]  wmode
    );
        case (wmode)
            2'b00: apply_wmode = wdata;           // write
            2'b01: apply_wmode = old_val | wdata; // set
            2'b10: apply_wmode = old_val & ~wdata;// clear
            default: apply_wmode = old_val;
        endcase
    endfunction

    logic [31:0] fflags_write_value;
    logic [31:0] frm_write_value;
    logic [31:0] fcsr_write_value;
    assign fflags_write_value = apply_wmode({27'b0, fflags_r}, i_wdata, i_wmode);
    assign frm_write_value    = apply_wmode({29'b0, frm_r}, i_wdata, i_wmode);
    assign fcsr_write_value   = apply_wmode({24'b0, frm_r, fflags_r}, i_wdata, i_wmode);

    // ---- 时序写入 ----
    always_ff @(posedge i_clk) begin
        if (!i_rst_n) begin
            mstatus  <= 32'h0000_1800;  // MPP=3（M-mode），其余0
            mtvec_r  <= 32'h0;
            mscratch_r <= 32'h0;
            mepc_r   <= 32'h0;
            mcause_r <= 32'h0;
            frm_r    <= 3'b000;
            fflags_r <= 5'b00000;
        end else begin
            // Trap 入口优先级高于普通写
            if (i_trap_en) begin
                mepc_r   <= i_trap_pc;
                mcause_r <= i_trap_cause;
                // 保存 MIE→MPIE，清 MIE（简化处理）
                mstatus  <= {mstatus[31:8], mstatus[3], mstatus[6:4], 1'b0, mstatus[2:0]};
            end else if (i_we) begin
                case (i_waddr)
                    12'h001: fflags_r <= fflags_write_value[4:0];
                    12'h002: frm_r    <= frm_write_value[2:0];
                    12'h003: begin
                        frm_r    <= fcsr_write_value[7:5];
                        fflags_r <= fcsr_write_value[4:0];
                    end
                    12'h300: mstatus  <= apply_wmode(mstatus,  i_wdata, i_wmode);
                    12'h305: mtvec_r  <= apply_wmode(mtvec_r,  i_wdata, i_wmode);
                    12'h340: mscratch_r <= apply_wmode(mscratch_r, i_wdata, i_wmode);
                    12'h341: mepc_r   <= apply_wmode(mepc_r,   i_wdata, i_wmode);
                    12'h342: mcause_r <= apply_wmode(mcause_r, i_wdata, i_wmode);
                    default: ; // 存根 CSR：接受写入但不存储
                endcase
            end else if (i_fflags_we) begin
                fflags_r <= fflags_r | i_fflags;
            end
        end
    end

endmodule
