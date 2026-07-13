# 全量 setup 违例路径聚类

- 原始违例路径数：4401
- 聚类数：363
- 聚类规则：仅把数字位选和综合复制后缀归一化；每一条原始路径仍保留在 CSV/RPT。

## 模块级覆盖矩阵

| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点模块 | 终点模块 |
|---:|---:|---:|---:|---:|---|---|
| 1 | 210 | -0.786 | 5.631 | 11 | `Core.Other` | `Core.DCache` |
| 2 | 8 | -0.725 | 5.646 | 9 | `Core.DCache` | `Core.Other` |
| 3 | 354 | -0.710 | 5.446 | 7 | `Core.DCache` | `Core.Scoreboard` |
| 4 | 239 | -0.650 | 5.054 | 0 | `SoC.Other` | `Core.StoreBuffer` |
| 5 | 1270 | -0.646 | 5.182 | 12 | `Core.Scoreboard` | `Core.Scoreboard` |
| 6 | 390 | -0.645 | 5.056 | 0 | `SoC.Other` | `Core.RegFile` |
| 7 | 91 | -0.642 | 5.040 | 0 | `SoC.Other` | `Core.LoadQueue` |
| 8 | 249 | -0.633 | 5.323 | 8 | `Core.DecodeStage` | `Core.Scoreboard` |
| 9 | 61 | -0.633 | 4.858 | 0 | `SoC.Other` | `Core.Scoreboard` |
| 10 | 37 | -0.629 | 4.842 | 0 | `SoC.Other` | `Core.ExecuteStage` |
| 11 | 20 | -0.615 | 4.834 | 0 | `SoC.Other` | `Core.MulDiv` |
| 12 | 55 | -0.608 | 5.005 | 1 | `SoC.Other` | `Core.Other` |
| 13 | 19 | -0.593 | 5.351 | 0 | `SoC.MemBridge` | `SoC.MemBridge` |
| 14 | 88 | -0.591 | 5.297 | 12 | `Core.Scoreboard` | `Core.Frontend` |
| 15 | 4 | -0.585 | 5.609 | 10 | `Core.MulDiv` | `Core.Other` |
| 16 | 204 | -0.568 | 5.039 | 10 | `Core.Scoreboard` | `Core.DecodeStage` |
| 17 | 199 | -0.565 | 5.032 | 11 | `Core.Scoreboard` | `Core.ExecuteStage` |
| 18 | 196 | -0.524 | 5.239 | 11 | `Core.Other` | `Core.Other` |
| 19 | 164 | -0.522 | 5.150 | 13 | `Core.Scoreboard` | `Core.LoadQueue` |
| 20 | 54 | -0.509 | 5.380 | 7 | `Core.DCache` | `Core.ExecuteStage` |
| 21 | 20 | -0.505 | 5.538 | 16 | `Core.ExecuteStage` | `Core.Other` |
| 22 | 27 | -0.498 | 5.453 | 8 | `Core.MulDiv` | `Core.Scoreboard` |
| 23 | 104 | -0.497 | 5.308 | 6 | `Core.Other` | `SoC.MemBridge` |
| 24 | 55 | -0.422 | 5.137 | 12 | `Core.Scoreboard` | `Core.ProducerMap` |
| 25 | 4 | -0.398 | 5.220 | 8 | `Core.MulDiv` | `Core.ExecuteStage` |
| 26 | 38 | -0.375 | 5.276 | 11 | `Core.Other` | `Core.LoadQueue` |
| 27 | 15 | -0.359 | 4.660 | 10 | `Core.Scoreboard` | `Core.DCache` |
| 28 | 23 | -0.346 | 5.248 | 11 | `Core.ExecuteStage` | `Core.Scoreboard` |
| 29 | 54 | -0.319 | 5.049 | 13 | `Core.Scoreboard` | `Core.Other` |
| 30 | 3 | -0.284 | 5.085 | 11 | `Core.ExecuteStage` | `Core.ExecuteStage` |
| 31 | 65 | -0.272 | 4.814 | 10 | `Core.Scoreboard` | `Core.MulDiv` |
| 32 | 19 | -0.230 | 4.976 | 5 | `SoC.MemBridge` | `Core.Other` |
| 33 | 43 | -0.174 | 4.470 | 1 | `SoC.Other` | `Core.Frontend` |
| 34 | 2 | -0.167 | 4.589 | 8 | `Core.Scoreboard` | `SoC.Other` |
| 35 | 16 | -0.166 | 4.884 | 1 | `Core.DCache` | `Core.DCache` |
| 36 | 1 | -0.022 | 4.723 | 3 | `Core.ExecuteStage` | `Core.MulDiv` |

## 精细起终点族

| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点族 | 终点族 | 时钟组 |
|---:|---:|---:|---:|---:|---|---|---|
| 1 | 18 | -0.786 | 5.631 | 11 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_read_q_reg[*]/D` | `setup` |
| 2 | 8 | -0.725 | 5.646 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/D` | `setup` |
| 3 | 39 | -0.710 | 5.432 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_src][*]/D` | `setup` |
| 4 | 142 | -0.660 | 5.437 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_src][*]/D` | `setup` |
| 5 | 122 | -0.650 | 5.054 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/store_q_reg[*][wdata][*]/R` | `setup` |
| 6 | 254 | -0.646 | 5.113 | 12 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_tval][*]/CE` | `setup` |
| 7 | 390 | -0.645 | 5.056 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_regfile/regs_q_reg[*][*]/R` | `setup` |
| 8 | 16 | -0.644 | 5.041 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/store_q_reg[*][wstrb][*]/R` | `setup` |
| 9 | 97 | -0.643 | 5.042 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/store_q_reg[*][addr][*]/R` | `setup` |
| 10 | 41 | -0.642 | 5.040 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][forward_data][*]/R` | `setup` |
| 11 | 106 | -0.633 | 5.323 | 8 | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_src][*]/R` | `setup` |
| 12 | 51 | -0.633 | 4.858 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_tval][*]/R` | `setup` |
| 13 | 5 | -0.629 | 4.842 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][pred_next_pc][*]/R` | `setup` |
| 14 | 3 | -0.629 | 4.842 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][pc][*]/R` | `setup` |
| 15 | 2 | -0.629 | 4.842 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][rd][*]/R` | `setup` |
| 16 | 1 | -0.629 | 4.842 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/R` | `setup` |
| 17 | 32 | -0.621 | 5.082 | 12 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_cause][*]/CE` | `setup` |
| 18 | 17 | -0.615 | 4.834 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/a_q_reg[*]/R` | `setup` |
| 19 | 2 | -0.615 | 4.839 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_valid]/R` | `setup` |
| 20 | 6 | -0.613 | 4.837 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_cause][*]/R` | `setup` |
| 21 | 221 | -0.611 | 5.141 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][result][*]/R` | `setup` |
| 22 | 9 | -0.608 | 4.835 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/wb_data_q_reg[*]/R` | `setup` |
| 23 | 3 | -0.604 | 5.000 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/next_store_seq_q_reg[*]/R` | `setup` |
| 24 | 10 | -0.603 | 5.005 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[forward_data][*]/R` | `setup` |
| 25 | 2 | -0.603 | 4.999 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[trans_id][*]/R` | `setup` |
| 26 | 153 | -0.602 | 5.446 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][result][*]/D` | `setup` |
| 27 | 4 | -0.602 | 4.999 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/store_q_reg[*][store_seq][*]/R` | `setup` |
| 28 | 2 | -0.600 | 4.997 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/store_tail_q_reg[*]/R` | `setup` |
| 29 | 105 | -0.599 | 5.182 | 12 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_src][*]/R` | `setup` |
| 30 | 7 | -0.593 | 5.351 | 0 | `student_top_inst/mem_bridge/dram_adapter/read_valid_d1_reg/C` | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/REGCEAREGCE` | `setup` |
| 31 | 3 | -0.591 | 5.297 | 12 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/count_q_reg[*]/D` | `setup` |
| 32 | 4 | -0.585 | 5.609 | 10 | `student_top_inst/Core_cpu/u_core_top/u_muldiv/b_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/D` | `setup` |
| 33 | 39 | -0.578 | 4.996 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][addr][*]/R` | `setup` |
| 34 | 32 | -0.568 | 5.017 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[imm][*]/CE` | `setup` |
| 35 | 32 | -0.568 | 5.039 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[pc][*]/CE` | `setup` |
| 36 | 4 | -0.568 | 5.348 | 0 | `student_top_inst/mem_bridge/dram_adapter/read_valid_d1_reg/C` | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/has_mux_a.A/douta[*]_INST_0_i_6_psbram/CE` | `setup` |
| 37 | 3 | -0.568 | 5.017 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[branch_op][*]/CE` | `setup` |
| 38 | 8 | -0.566 | 5.344 | 0 | `student_top_inst/mem_bridge/dram_adapter/read_valid_d1_reg/C` | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/has_mux_a.A/douta[*]_INST_0_i_4_psbram/CE` | `setup` |
| 39 | 4 | -0.565 | 5.023 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][alu_op][*]/CE` | `setup` |
| 40 | 3 | -0.560 | 5.364 | 11 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/D` | `setup` |
| 41 | 32 | -0.550 | 5.020 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[pred_next_pc][*]/CE` | `setup` |
| 42 | 32 | -0.549 | 5.012 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][imm][*]/CE` | `setup` |
| 43 | 1 | -0.540 | 4.990 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[serialize]/CE` | `setup` |
| 44 | 32 | -0.539 | 5.143 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_data_q_reg[*]/CE` | `setup` |
| 45 | 30 | -0.539 | 5.143 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_addr_q_reg[*]/CE` | `setup` |
| 46 | 17 | -0.538 | 5.149 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_tag_q_reg[*]/CE` | `setup` |
| 47 | 2 | -0.536 | 5.218 | 12 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/head_q_reg[*]/D` | `setup` |
| 48 | 4 | -0.533 | 5.138 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_mask_q_reg[*]/CE` | `setup` |
| 49 | 213 | -0.526 | 4.974 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][pc][*]/CE` | `setup` |
| 50 | 199 | -0.526 | 4.979 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][link_addr][*]/CE` | `setup` |
| 51 | 93 | -0.526 | 4.979 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_addr][*]/CE` | `setup` |
| 52 | 29 | -0.524 | 5.216 | 7 | `student_top_inst/Core_cpu/u_core_top/commit_ptr_q_reg[*]_rep/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mstatus_q_reg[*]/D` | `setup` |
| 53 | 64 | -0.522 | 5.150 | 13 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][forward_data][*]/CE` | `setup` |
| 54 | 32 | -0.511 | 4.977 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_tval][*]/CE` | `setup` |
| 55 | 5 | -0.511 | 4.958 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs2]_rep[*]/CE` | `setup` |
| 56 | 3 | -0.511 | 4.958 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_cause][*]/CE` | `setup` |
| 57 | 1 | -0.511 | 4.958 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[uses_rs2]/CE` | `setup` |
| 58 | 1 | -0.511 | 4.958 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[writes_rd]/CE` | `setup` |
| 59 | 29 | -0.509 | 5.239 | 7 | `student_top_inst/Core_cpu/u_core_top/commit_ptr_q_reg[*]_rep/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mepc_q_reg[*]/D` | `setup` |
| 60 | 28 | -0.509 | 5.129 | 6 | `student_top_inst/Core_cpu/u_core_top/commit_ptr_q_reg[*]_rep/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mscratch_q_reg[*]/D` | `setup` |
| 61 | 19 | -0.509 | 5.380 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/D` | `setup` |
| 62 | 19 | -0.505 | 5.538 | 16 | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][imm][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/D` | `setup` |
| 63 | 8 | -0.501 | 4.958 | 12 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_valid]/CE` | `setup` |
| 64 | 27 | -0.498 | 5.453 | 8 | `student_top_inst/Core_cpu/u_core_top/u_muldiv/b_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_src][*]/D` | `setup` |
| 65 | 85 | -0.497 | 5.308 | 0 | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_addr_q_reg[*]/C` | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/ADDRARDADDR[*]` | `setup` |
| 66 | 17 | -0.491 | 5.353 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/D` | `setup` |
| 67 | 1 | -0.490 | 4.962 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_valid]/CE` | `setup` |
| 68 | 1 | -0.486 | 4.934 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[csr_imm]/CE` | `setup` |
| 69 | 4 | -0.483 | 4.876 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][store_seq_cutoff][*]/R` | `setup` |
| 70 | 3 | -0.480 | 4.927 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[sys_op][*]/CE` | `setup` |
| 71 | 2 | -0.480 | 4.927 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[csr_op][*]/CE` | `setup` |
| 72 | 6 | -0.479 | 5.338 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/D` | `setup` |
| 73 | 28 | -0.476 | 5.140 | 6 | `student_top_inst/Core_cpu/u_core_top/commit_ptr_q_reg[*]_rep/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mtvec_q_reg[*]/D` | `setup` |
| 74 | 12 | -0.476 | 5.295 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/D` | `setup` |
| 75 | 1 | -0.474 | 4.935 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][uses_rs2]/CE` | `setup` |
| 76 | 18 | -0.472 | 5.087 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_read_q_reg[*]/CE` | `setup` |
| 77 | 30 | -0.466 | 5.079 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/req_addr_q_reg[*]/CE` | `setup` |
| 78 | 1 | -0.466 | 5.079 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__9/CE` | `setup` |
| 79 | 1 | -0.466 | 5.079 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__9_rep__3/CE` | `setup` |
| 80 | 1 | -0.464 | 5.078 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__6/CE` | `setup` |
| 81 | 1 | -0.464 | 5.078 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__6_rep__0/CE` | `setup` |
| 82 | 1 | -0.464 | 5.078 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__6_rep__3/CE` | `setup` |
| 83 | 32 | -0.462 | 4.917 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][pred_next_pc][*]/CE` | `setup` |
| 84 | 7 | -0.462 | 4.925 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][instr][*]/CE` | `setup` |
| 85 | 5 | -0.462 | 4.925 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][rd][*]/CE` | `setup` |
| 86 | 31 | -0.461 | 5.099 | 7 | `student_top_inst/Core_cpu/u_core_top/commit_ptr_q_reg[*]_rep/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mcause_q_reg[*]/D` | `setup` |
| 87 | 8 | -0.458 | 4.905 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][is_return]/CE` | `setup` |
| 88 | 32 | -0.454 | 4.910 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][pc][*]/CE` | `setup` |
| 89 | 1 | -0.453 | 4.871 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][load_unsigned]/R` | `setup` |
| 90 | 5 | -0.447 | 4.896 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rd][*]/CE` | `setup` |
| 91 | 3 | -0.447 | 4.896 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[fu][*]/CE` | `setup` |
| 92 | 1 | -0.447 | 4.896 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[load_unsigned]/CE` | `setup` |
| 93 | 12 | -0.446 | 4.895 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[csr_addr][*]/CE` | `setup` |
| 94 | 1 | -0.446 | 5.051 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__2/CE` | `setup` |
| 95 | 3 | -0.445 | 4.901 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][muldiv_op][*]/CE` | `setup` |
| 96 | 2 | -0.445 | 4.901 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][mem_size][*]/CE` | `setup` |
| 97 | 1 | -0.444 | 5.049 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__0/CE` | `setup` |
| 98 | 7 | -0.443 | 4.891 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[instr][*]/CE` | `setup` |
| 99 | 1 | -0.441 | 5.112 | 13 | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/C` | `student_top_inst/Core_cpu/u_core_top/branch_miss_reg/D` | `setup` |
| 100 | 11 | -0.439 | 5.052 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_index_q_reg[*]/CE` | `setup` |
| 101 | 2 | -0.438 | 4.828 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][trans_id][*]/R` | `setup` |
| 102 | 1 | -0.438 | 4.828 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][size][*]/R` | `setup` |
| 103 | 2 | -0.427 | 5.039 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_word_q_reg[*]/CE` | `setup` |
| 104 | 31 | -0.422 | 5.137 | 12 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_valid_q_reg[*]/D` | `setup` |
| 105 | 1 | -0.420 | 5.034 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__5_rep__0/CE` | `setup` |
| 106 | 1 | -0.420 | 5.034 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__5_rep__3/CE` | `setup` |
| 107 | 1 | -0.420 | 5.034 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__8/CE` | `setup` |
| 108 | 1 | -0.420 | 5.034 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__8_rep__3/CE` | `setup` |
| 109 | 58 | -0.417 | 5.125 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_src][*]/CE` | `setup` |
| 110 | 5 | -0.416 | 4.886 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1]_rep[*]/CE` | `setup` |
| 111 | 5 | -0.416 | 4.886 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs2][*]/CE` | `setup` |
| 112 | 10 | -0.415 | 4.863 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_op][*]/CE` | `setup` |
| 113 | 8 | -0.415 | 4.863 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][is_call]/CE` | `setup` |
| 114 | 22 | -0.409 | 4.804 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/R` | `setup` |
| 115 | 26 | -0.403 | 5.108 | 7 | `student_top_inst/Core_cpu/u_core_top/commit_ptr_q_reg[*]_rep/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mtval_q_reg[*]/D` | `setup` |
| 116 | 1 | -0.402 | 5.017 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__7_rep__0/CE` | `setup` |
| 117 | 4 | -0.398 | 5.220 | 8 | `student_top_inst/Core_cpu/u_core_top/u_muldiv/b_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/D` | `setup` |
| 118 | 32 | -0.397 | 5.083 | 7 | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][result][*]/R` | `setup` |
| 119 | 4 | -0.397 | 4.845 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[alu_op][*]/CE` | `setup` |
| 120 | 10 | -0.394 | 5.084 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/CE` | `setup` |
| 121 | 9 | -0.394 | 5.084 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][sys_op][*]/CE` | `setup` |
| 122 | 1 | -0.394 | 5.008 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__4/CE` | `setup` |
| 123 | 1 | -0.394 | 5.008 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__4_rep__0/CE` | `setup` |
| 124 | 1 | -0.394 | 5.008 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__4_rep__3/CE` | `setup` |
| 125 | 1 | -0.394 | 5.008 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__7/CE` | `setup` |
| 126 | 1 | -0.394 | 5.008 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__7_rep__3/CE` | `setup` |
| 127 | 1 | -0.391 | 4.839 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[uses_rs1]/CE` | `setup` |
| 128 | 1 | -0.388 | 5.001 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__1/CE` | `setup` |
| 129 | 1 | -0.388 | 5.001 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__5_rep__1/CE` | `setup` |
| 130 | 1 | -0.388 | 5.001 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__9_rep__0/CE` | `setup` |
| 131 | 1 | -0.388 | 4.996 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__6_rep/CE` | `setup` |
| 132 | 1 | -0.388 | 4.996 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__6_rep__2/CE` | `setup` |
| 133 | 1 | -0.388 | 4.996 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__9_rep/CE` | `setup` |
| 134 | 4 | -0.385 | 4.630 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/branch_target_reg[*]/R` | `setup` |
| 135 | 1 | -0.383 | 4.993 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__4_rep__1/CE` | `setup` |
| 136 | 37 | -0.375 | 5.276 | 11 | `student_top_inst/Core_cpu/u_core_top/store_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][forward_data][*]/D` | `setup` |
| 137 | 1 | -0.372 | 4.984 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__6_rep__1/CE` | `setup` |
| 138 | 1 | -0.372 | 4.984 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__7_rep__1/CE` | `setup` |
| 139 | 5 | -0.371 | 4.838 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/CE` | `setup` |
| 140 | 3 | -0.371 | 4.838 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[muldiv_op][*]/CE` | `setup` |
| 141 | 2 | -0.371 | 4.786 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/store_head_q_reg[*]/R` | `setup` |
| 142 | 1 | -0.367 | 4.976 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__9_rep__2/CE` | `setup` |
| 143 | 2 | -0.365 | 4.812 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[mem_size][*]/CE` | `setup` |
| 144 | 1 | -0.365 | 4.812 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[is_jal]/CE` | `setup` |
| 145 | 1 | -0.365 | 4.812 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[is_jalr]/CE` | `setup` |
| 146 | 20 | -0.363 | 5.202 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][result][*]/D` | `setup` |
| 147 | 4 | -0.361 | 4.845 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][rs1][*]/CE` | `setup` |
| 148 | 21 | -0.359 | 5.208 | 6 | `student_top_inst/Core_cpu/u_core_top/commit_ptr_q_reg[*]_rep/C` | `student_top_inst/Core_cpu/u_core_top/wb_data_q_reg[*]/D` | `setup` |
| 149 | 11 | -0.359 | 4.624 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/ADDRARDADDR[*]` | `setup` |
| 150 | 15 | -0.346 | 5.148 | 7 | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_src][*]/D` | `setup` |
| 151 | 1 | -0.345 | 4.957 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_write_q_reg/CE` | `setup` |
| 152 | 2 | -0.344 | 5.157 | 8 | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_tval][*]/CE` | `setup` |
| 153 | 32 | -0.332 | 5.032 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/CE` | `setup` |
| 154 | 1 | -0.332 | 4.789 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][is_jalr]/CE` | `setup` |
| 155 | 3 | -0.330 | 4.719 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][forward_mask][*]/R` | `setup` |
| 156 | 3 | -0.330 | 4.796 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][branch_op][*]/CE` | `setup` |
| 157 | 1 | -0.330 | 4.936 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out/CE` | `setup` |
| 158 | 1 | -0.330 | 4.936 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__3/CE` | `setup` |
| 159 | 64 | -0.325 | 4.976 | 13 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][addr][*]/CE` | `setup` |
| 160 | 32 | -0.319 | 5.033 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/CE` | `setup` |
| 161 | 8 | -0.316 | 4.941 | 13 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][forward_mask][*]/CE` | `setup` |
| 162 | 32 | -0.311 | 4.958 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/CE` | `setup` |
| 163 | 11 | -0.303 | 5.093 | 7 | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][sys_op][*]/CE` | `setup` |
| 164 | 8 | -0.298 | 4.501 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_perf_counters/cycle_o_reg[*]/R` | `setup` |
| 165 | 1 | -0.295 | 4.904 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__5/CE` | `setup` |
| 166 | 1 | -0.295 | 4.904 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__5_rep__2/CE` | `setup` |
| 167 | 1 | -0.295 | 4.904 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__7_rep/CE` | `setup` |
| 168 | 1 | -0.295 | 4.904 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__7_rep__2/CE` | `setup` |
| 169 | 1 | -0.295 | 4.904 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__8_rep__1/CE` | `setup` |
| 170 | 1 | -0.295 | 4.904 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__9_rep__1/CE` | `setup` |
| 171 | 1 | -0.288 | 4.896 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__8_rep/CE` | `setup` |
| 172 | 1 | -0.288 | 4.896 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__8_rep__0/CE` | `setup` |
| 173 | 1 | -0.288 | 4.896 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__8_rep__2/CE` | `setup` |
| 174 | 8 | -0.286 | 5.248 | 11 | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][imm][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_src][*]/D` | `setup` |
| 175 | 1 | -0.286 | 4.631 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMA/WE` | `setup` |
| 176 | 1 | -0.286 | 4.631 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMA_D1/WE` | `setup` |
| 177 | 1 | -0.286 | 4.631 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMB/WE` | `setup` |
| 178 | 1 | -0.286 | 4.631 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMB_D1/WE` | `setup` |
| 179 | 1 | -0.286 | 4.631 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMC/WE` | `setup` |
| 180 | 1 | -0.286 | 4.631 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMC_D1/WE` | `setup` |
| 181 | 1 | -0.286 | 4.631 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMD/WE` | `setup` |
| 182 | 1 | -0.286 | 4.631 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMD_D1/WE` | `setup` |
| 183 | 1 | -0.284 | 5.085 | 11 | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][imm][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/D` | `setup` |
| 184 | 1 | -0.283 | 4.508 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mstatus_q_reg[*]/R` | `setup` |
| 185 | 1 | -0.282 | 4.892 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__5_rep/CE` | `setup` |
| 186 | 1 | -0.276 | 4.621 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMA/WE` | `setup` |
| 187 | 1 | -0.276 | 4.621 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMA_D1/WE` | `setup` |
| 188 | 1 | -0.276 | 4.621 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMB/WE` | `setup` |
| 189 | 1 | -0.276 | 4.621 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMB_D1/WE` | `setup` |
| 190 | 1 | -0.276 | 4.621 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMC/WE` | `setup` |
| 191 | 1 | -0.276 | 4.621 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMC_D1/WE` | `setup` |
| 192 | 1 | -0.276 | 4.621 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMD/WE` | `setup` |
| 193 | 1 | -0.276 | 4.621 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMD_D1/WE` | `setup` |
| 194 | 3 | -0.274 | 4.690 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[trans_id][*]/R` | `setup` |
| 195 | 1 | -0.274 | 4.619 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMA/WE` | `setup` |
| 196 | 1 | -0.274 | 4.619 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMA_D1/WE` | `setup` |
| 197 | 1 | -0.274 | 4.619 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMB/WE` | `setup` |
| 198 | 1 | -0.274 | 4.619 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMB_D1/WE` | `setup` |
| 199 | 1 | -0.274 | 4.619 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMC/WE` | `setup` |
| 200 | 1 | -0.274 | 4.619 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMC_D1/WE` | `setup` |
| 201 | 1 | -0.274 | 4.619 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMD/WE` | `setup` |
| 202 | 1 | -0.274 | 4.619 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMD_D1/WE` | `setup` |
| 203 | 32 | -0.272 | 4.733 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/u_div/U0/i_synth/i_has_input_skid.i_2to1/gen_has_z_tready.reg1_a_tdata_reg[*]/CE` | `setup` |
| 204 | 27 | -0.265 | 4.959 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][rd][*]/CE` | `setup` |
| 205 | 7 | -0.265 | 4.959 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][writes_rd]/CE` | `setup` |
| 206 | 6 | -0.251 | 4.874 | 13 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][trans_id][*]/CE` | `setup` |
| 207 | 4 | -0.251 | 4.885 | 13 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][size][*]/CE` | `setup` |
| 208 | 2 | -0.251 | 4.884 | 13 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][load_unsigned]/CE` | `setup` |
| 209 | 32 | -0.247 | 4.692 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/u_div/U0/i_synth/i_has_input_skid.i_2to1/gen_has_z_tready.reg1_b_tdata_reg[*]/CE` | `setup` |
| 210 | 2 | -0.247 | 4.670 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/tid_q_reg[*]/R` | `setup` |
| 211 | 1 | -0.247 | 4.670 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/is_div_q_reg/R` | `setup` |
| 212 | 2 | -0.240 | 5.220 | 7 | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_tval][*]/D` | `setup` |
| 213 | 16 | -0.239 | 4.865 | 13 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][store_seq_cutoff][*]/CE` | `setup` |
| 214 | 70 | -0.230 | 5.020 | 7 | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_src][*]/CE` | `setup` |
| 215 | 18 | -0.230 | 4.976 | 5 | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/has_mux_a.A/no_softecc_norm_sel2.has_mem_regs.WITHOUT_ECC_PIPE.ce_pri.sel_pipe_d1_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/resp_rdata_q_reg[*]/D` | `setup` |
| 216 | 3 | -0.229 | 4.859 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][fu][*]/CE` | `setup` |
| 217 | 1 | -0.217 | 4.480 | 7 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/ADDRBWRADDR[*]` | `setup` |
| 218 | 15 | -0.213 | 4.846 | 12 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[forward_data][*]/CE` | `setup` |
| 219 | 16 | -0.211 | 5.171 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_wdata_q_reg[*]/C` | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/DIADI[*]` | `setup` |
| 220 | 4 | -0.198 | 4.405 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_perf_counters/commit_o_reg[*]/R` | `setup` |
| 221 | 1 | -0.198 | 4.589 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[addr][*]/R` | `setup` |
| 222 | 6 | -0.196 | 4.403 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mepc_q_reg[*]/R` | `setup` |
| 223 | 1 | -0.196 | 4.805 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__4_rep/CE` | `setup` |
| 224 | 1 | -0.196 | 4.805 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/p_2_out__4_rep__2/CE` | `setup` |
| 225 | 6 | -0.195 | 4.986 | 7 | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/CE` | `setup` |
| 226 | 1 | -0.195 | 4.587 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[forward_mask][*]/R` | `setup` |
| 227 | 7 | -0.191 | 4.982 | 7 | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][link_addr][*]/CE` | `setup` |
| 228 | 2 | -0.189 | 4.990 | 7 | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/D` | `setup` |
| 229 | 1 | -0.174 | 4.470 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/target_q_reg_0_63_6_8/RAMA/WE` | `setup` |
| 230 | 1 | -0.174 | 4.470 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/target_q_reg_0_63_6_8/RAMB/WE` | `setup` |
| 231 | 1 | -0.174 | 4.470 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/target_q_reg_0_63_6_8/RAMC/WE` | `setup` |
| 232 | 1 | -0.174 | 4.470 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/target_q_reg_0_63_6_8/RAMD/WE` | `setup` |
| 233 | 1 | -0.169 | 4.463 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_4_4/DP/WE` | `setup` |
| 234 | 1 | -0.169 | 4.463 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_4_4/SP/WE` | `setup` |
| 235 | 1 | -0.169 | 4.463 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_5_5/DP/WE` | `setup` |
| 236 | 1 | -0.169 | 4.463 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_5_5/SP/WE` | `setup` |
| 237 | 2 | -0.167 | 4.589 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Mem_IROM/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/ENARDEN` | `setup` |
| 238 | 1 | -0.166 | 4.884 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1792_1855_6_8/RAMA/WADR4` | `setup` |
| 239 | 1 | -0.166 | 4.884 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1792_1855_6_8/RAMB/WADR4` | `setup` |
| 240 | 1 | -0.166 | 4.884 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1792_1855_6_8/RAMC/WADR4` | `setup` |
| 241 | 1 | -0.166 | 4.884 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1792_1855_6_8/RAMD/WADR4` | `setup` |
| 242 | 4 | -0.165 | 5.186 | 8 | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][done]/D` | `setup` |
| 243 | 1 | -0.164 | 4.796 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/issue_ptr_q_reg[*]/D` | `setup` |
| 244 | 1 | -0.164 | 4.953 | 10 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_valid_q_reg/D` | `setup` |
| 245 | 1 | -0.164 | 4.517 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/ENBWREN` | `setup` |
| 246 | 1 | -0.151 | 4.870 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1408_1471_6_8/RAMA/WADR4` | `setup` |
| 247 | 1 | -0.151 | 4.870 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1408_1471_6_8/RAMB/WADR4` | `setup` |
| 248 | 1 | -0.151 | 4.870 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1408_1471_6_8/RAMC/WADR4` | `setup` |
| 249 | 1 | -0.151 | 4.870 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1408_1471_6_8/RAMD/WADR4` | `setup` |
| 250 | 1 | -0.139 | 4.559 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][imm][*]/R` | `setup` |
| 251 | 1 | -0.136 | 4.431 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_8_8/DP/WE` | `setup` |
| 252 | 1 | -0.136 | 4.431 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_8_8/SP/WE` | `setup` |
| 253 | 1 | -0.136 | 4.431 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_9_9/DP/WE` | `setup` |
| 254 | 1 | -0.136 | 4.431 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_9_9/SP/WE` | `setup` |
| 255 | 3 | -0.134 | 4.766 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[trans_id][*]/CE` | `setup` |
| 256 | 2 | -0.132 | 4.776 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/issue_ptr_q_reg[*]_rep/D` | `setup` |
| 257 | 7 | -0.126 | 4.363 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/valid_q_reg[*]/R` | `setup` |
| 258 | 2 | -0.124 | 4.389 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/ADDRBWRADDR[*]` | `setup` |
| 259 | 1 | -0.123 | 5.049 | 13 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_valid_q_reg/D` | `setup` |
| 260 | 1 | -0.122 | 4.417 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_0_0/DP/WE` | `setup` |
| 261 | 1 | -0.122 | 4.417 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_0_0/SP/WE` | `setup` |
| 262 | 1 | -0.122 | 4.417 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_10_10/DP/WE` | `setup` |
| 263 | 1 | -0.122 | 4.417 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_10_10/SP/WE` | `setup` |
| 264 | 3 | -0.120 | 4.813 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_addr_q_reg[*]/C` | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/WEA[*]` | `setup` |
| 265 | 1 | -0.115 | 4.317 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mscratch_q_reg[*]/R` | `setup` |
| 266 | 35 | -0.109 | 4.614 | 7 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/ras_q_reg[*][*]/CE` | `setup` |
| 267 | 4 | -0.106 | 5.041 | 11 | `student_top_inst/Core_cpu/u_core_top/store_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[forward_data][*]/D` | `setup` |
| 268 | 1 | -0.105 | 4.919 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[valid]/D` | `setup` |
| 269 | 1 | -0.103 | 4.814 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/u_div/U0/i_synth/i_has_input_skid.i_2to1/gen_has_z_tready.reg1_b_ready_reg/D` | `setup` |
| 270 | 2 | -0.101 | 5.124 | 8 | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][occupied]/D` | `setup` |
| 271 | 1 | -0.093 | 4.521 | 7 | `student_top_inst/Core_cpu/u_core_top/load_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/ADDRBWRADDR[*]` | `setup` |
| 272 | 1 | -0.091 | 4.383 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_13_13/DP/WE` | `setup` |
| 273 | 1 | -0.091 | 4.383 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_13_13/SP/WE` | `setup` |
| 274 | 1 | -0.091 | 4.383 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_14_14/DP/WE` | `setup` |
| 275 | 1 | -0.091 | 4.383 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_14_14/SP/WE` | `setup` |
| 276 | 1 | -0.087 | 4.381 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_19_19/DP/WE` | `setup` |
| 277 | 1 | -0.087 | 4.381 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_19_19/SP/WE` | `setup` |
| 278 | 1 | -0.087 | 4.381 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_1_1/DP/WE` | `setup` |
| 279 | 1 | -0.087 | 4.381 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_1_1/SP/WE` | `setup` |
| 280 | 1 | -0.086 | 4.716 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][is_jal]/CE` | `setup` |
| 281 | 1 | -0.086 | 4.716 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][load_unsigned]/CE` | `setup` |
| 282 | 2 | -0.083 | 4.949 | 13 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[forward_data][*]/D` | `setup` |
| 283 | 2 | -0.081 | 5.006 | 12 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][store_slot][*]/D` | `setup` |
| 284 | 1 | -0.078 | 4.742 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_valid_q_reg/D` | `setup` |
| 285 | 1 | -0.075 | 4.793 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1344_1407_6_8/RAMA/WADR4` | `setup` |
| 286 | 1 | -0.075 | 4.793 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1344_1407_6_8/RAMB/WADR4` | `setup` |
| 287 | 1 | -0.075 | 4.793 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1344_1407_6_8/RAMC/WADR4` | `setup` |
| 288 | 1 | -0.075 | 4.793 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1344_1407_6_8/RAMD/WADR4` | `setup` |
| 289 | 1 | -0.069 | 4.660 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/ENBWREN` | `setup` |
| 290 | 1 | -0.067 | 4.326 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_18_23/RAMA/WE` | `setup` |
| 291 | 1 | -0.067 | 4.326 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_18_23/RAMA_D1/WE` | `setup` |
| 292 | 1 | -0.067 | 4.326 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_18_23/RAMB/WE` | `setup` |
| 293 | 1 | -0.067 | 4.326 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_18_23/RAMB_D1/WE` | `setup` |
| 294 | 1 | -0.067 | 4.326 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_18_23/RAMC/WE` | `setup` |
| 295 | 1 | -0.067 | 4.326 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_18_23/RAMC_D1/WE` | `setup` |
| 296 | 1 | -0.067 | 4.326 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_18_23/RAMD/WE` | `setup` |
| 297 | 1 | -0.067 | 4.326 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_18_23/RAMD_D1/WE` | `setup` |
| 298 | 4 | -0.059 | 5.082 | 8 | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][store_slot][*]/D` | `setup` |
| 299 | 1 | -0.059 | 4.786 | 5 | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/resp_rdata_q_reg[*]/D` | `setup` |
| 300 | 1 | -0.055 | 4.314 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_6_11/RAMA/WE` | `setup` |
| 301 | 1 | -0.055 | 4.314 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_6_11/RAMA_D1/WE` | `setup` |
| 302 | 1 | -0.055 | 4.314 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_6_11/RAMB/WE` | `setup` |
| 303 | 1 | -0.055 | 4.314 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_6_11/RAMB_D1/WE` | `setup` |
| 304 | 1 | -0.055 | 4.314 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_6_11/RAMC/WE` | `setup` |
| 305 | 1 | -0.055 | 4.314 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_6_11/RAMC_D1/WE` | `setup` |
| 306 | 1 | -0.055 | 4.314 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_6_11/RAMD/WE` | `setup` |
| 307 | 1 | -0.055 | 4.314 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_6_11/RAMD_D1/WE` | `setup` |
| 308 | 1 | -0.055 | 4.348 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_11_11/DP/WE` | `setup` |
| 309 | 1 | -0.055 | 4.348 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_11_11/SP/WE` | `setup` |
| 310 | 1 | -0.055 | 4.348 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_12_12/DP/WE` | `setup` |
| 311 | 1 | -0.055 | 4.348 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_12_12/SP/WE` | `setup` |
| 312 | 2 | -0.053 | 4.265 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_addr][*]/R` | `setup` |
| 313 | 1 | -0.053 | 4.771 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1536_1599_6_8/RAMA/WADR4` | `setup` |
| 314 | 1 | -0.053 | 4.771 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1536_1599_6_8/RAMB/WADR4` | `setup` |
| 315 | 1 | -0.053 | 4.771 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1536_1599_6_8/RAMC/WADR4` | `setup` |
| 316 | 1 | -0.053 | 4.771 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dcache/state_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/tag_q_reg_r1_1536_1599_6_8/RAMD/WADR4` | `setup` |
| 317 | 2 | -0.051 | 5.073 | 8 | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][store_slot_valid]/D` | `setup` |
| 318 | 1 | -0.050 | 4.311 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_0_5/RAMA/WE` | `setup` |
| 319 | 1 | -0.050 | 4.311 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_0_5/RAMA_D1/WE` | `setup` |
| 320 | 1 | -0.050 | 4.311 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_0_5/RAMB/WE` | `setup` |
| 321 | 1 | -0.050 | 4.311 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_0_5/RAMB_D1/WE` | `setup` |
| 322 | 1 | -0.050 | 4.311 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_0_5/RAMC/WE` | `setup` |
| 323 | 1 | -0.050 | 4.311 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_0_5/RAMC_D1/WE` | `setup` |
| 324 | 1 | -0.050 | 4.311 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_0_5/RAMD/WE` | `setup` |
| 325 | 1 | -0.050 | 4.311 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pred_next_pc]_0_3_0_5/RAMD_D1/WE` | `setup` |
| 326 | 1 | -0.038 | 4.964 | 12 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_addr_q_reg[*]/D` | `setup` |
| 327 | 1 | -0.028 | 4.324 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_2_2/DP/WE` | `setup` |
| 328 | 1 | -0.028 | 4.324 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_2_2/SP/WE` | `setup` |
| 329 | 1 | -0.028 | 4.324 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_3_3/DP/WE` | `setup` |
| 330 | 1 | -0.028 | 4.324 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_3_3/SP/WE` | `setup` |
| 331 | 1 | -0.022 | 4.723 | 3 | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/u_mul/U0/i_mult/gLUT.gLUT_speed.iLUT/NxM_mult.pp_gen_pipeline.pp_gen_loop[*].b_is_even.pp_out_reg_reg[*][*]/D` | `setup` |
| 332 | 1 | -0.022 | 4.281 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_18_23/RAMA/WE` | `setup` |
| 333 | 1 | -0.022 | 4.281 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_18_23/RAMA_D1/WE` | `setup` |
| 334 | 1 | -0.022 | 4.281 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_18_23/RAMB/WE` | `setup` |
| 335 | 1 | -0.022 | 4.281 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_18_23/RAMB_D1/WE` | `setup` |
| 336 | 1 | -0.022 | 4.281 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_18_23/RAMC/WE` | `setup` |
| 337 | 1 | -0.022 | 4.281 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_18_23/RAMC_D1/WE` | `setup` |
| 338 | 1 | -0.022 | 4.281 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_18_23/RAMD/WE` | `setup` |
| 339 | 1 | -0.022 | 4.281 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_18_23/RAMD_D1/WE` | `setup` |
| 340 | 1 | -0.021 | 4.907 | 10 | `student_top_inst/Core_cpu/u_core_top/store_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][forward_mask][*]/D` | `setup` |
| 341 | 1 | -0.018 | 4.278 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_12_17/RAMA/WE` | `setup` |
| 342 | 1 | -0.018 | 4.278 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_12_17/RAMA_D1/WE` | `setup` |
| 343 | 1 | -0.018 | 4.278 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_12_17/RAMB/WE` | `setup` |
| 344 | 1 | -0.018 | 4.278 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_12_17/RAMB_D1/WE` | `setup` |
| 345 | 1 | -0.018 | 4.278 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_12_17/RAMC/WE` | `setup` |
| 346 | 1 | -0.018 | 4.278 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_12_17/RAMC_D1/WE` | `setup` |
| 347 | 1 | -0.018 | 4.278 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_12_17/RAMD/WE` | `setup` |
| 348 | 1 | -0.018 | 4.278 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][pc]_0_3_12_17/RAMD_D1/WE` | `setup` |
| 349 | 3 | -0.011 | 4.645 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][result][*]/CE` | `setup` |
| 350 | 3 | -0.009 | 4.736 | 11 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_tval][*]/D` | `setup` |
| 351 | 1 | -0.009 | 4.266 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][instr]_0_3_12_17/RAMA/WE` | `setup` |
| 352 | 1 | -0.009 | 4.266 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][instr]_0_3_12_17/RAMA_D1/WE` | `setup` |
| 353 | 1 | -0.009 | 4.266 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][instr]_0_3_12_17/RAMB/WE` | `setup` |
| 354 | 1 | -0.009 | 4.266 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][instr]_0_3_12_17/RAMB_D1/WE` | `setup` |
| 355 | 1 | -0.009 | 4.266 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][instr]_0_3_12_17/RAMC/WE` | `setup` |
| 356 | 1 | -0.009 | 4.266 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][instr]_0_3_12_17/RAMC_D1/WE` | `setup` |
| 357 | 1 | -0.009 | 4.266 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][instr]_0_3_12_17/RAMD/WE` | `setup` |
| 358 | 1 | -0.009 | 4.266 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/entries_q_reg[*][instr]_0_3_12_17/RAMD_D1/WE` | `setup` |
| 359 | 1 | -0.008 | 4.799 | 7 | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][pc][*]/CE` | `setup` |
| 360 | 1 | -0.002 | 4.295 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_17_17/DP/WE` | `setup` |
| 361 | 1 | -0.002 | 4.295 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_17_17/SP/WE` | `setup` |
| 362 | 1 | -0.002 | 4.295 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_18_18/DP/WE` | `setup` |
| 363 | 1 | -0.002 | 4.295 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/tag_q_reg_0_63_18_18/SP/WE` | `setup` |
