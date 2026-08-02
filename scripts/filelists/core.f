# Five-stage in-order pipeline core RTL filelist.
# Paths are relative to the repository root.

# PC stage
rtl/core/pc/pc_reg.sv
rtl/core/pc/stage_pc.sv

# IF stage
rtl/core/if/stage_if.sv

# ID stage
rtl/core/id/imm_unit.sv
rtl/core/id/regfile.sv
rtl/core/id/fregfile.sv
rtl/core/id/control_unit.sv
rtl/core/id/stage_id.sv

# EX stage
rtl/core/ex/alu.sv
rtl/core/ex/branch_cmp.sv
rtl/core/ex/stage_ex.sv
rtl/core/ex/rv32f_unit.sv

# M2 stage
rtl/core/m2/stage_m2.sv

# Memory
rtl/core/memory/DCache.sv

# WB stage
rtl/core/wb/stage_wb.sv

# Pipeline registers
rtl/core/pipeline_regs/reg_pc_if.sv
rtl/core/pipeline_regs/reg_if_id.sv
rtl/core/pipeline_regs/reg_id_ex.sv
rtl/core/pipeline_regs/reg_ex_m1.sv
rtl/core/pipeline_regs/reg_m1_m2.sv
rtl/core/pipeline_regs/reg_m2_wb.sv

# Control
rtl/core/control/forward_unit.sv
rtl/core/control/bpu_top.sv
rtl/core/control/hazard_unit.sv

# RV32M extension
rtl/core/ex/m_unit.sv

# CSR register file
rtl/core/regs/csr_file.sv

# Core top and CPU wrapper
rtl/core/core.sv
rtl/core/myCPU.sv
