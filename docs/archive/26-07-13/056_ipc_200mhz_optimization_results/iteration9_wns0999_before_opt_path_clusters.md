# 全量 setup 违例路径聚类

- 原始违例路径数：4567
- 聚类数：253
- 聚类规则：仅把数字位选和综合复制后缀归一化；每一条原始路径仍保留在 CSV/RPT。

## 模块级覆盖矩阵

| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点模块 | 终点模块 |
|---:|---:|---:|---:|---:|---|---|
| 1 | 196 | -0.999 | 5.940 | 16 | `Core.DCache` | `Core.Other` |
| 2 | 1899 | -0.923 | 5.688 | 10 | `Core.DCache` | `Core.Scoreboard` |
| 3 | 237 | -0.880 | 5.507 | 10 | `Core.DCache` | `Core.DCache` |
| 4 | 229 | -0.867 | 5.537 | 10 | `Core.DCache` | `Core.LoadQueue` |
| 5 | 619 | -0.865 | 5.545 | 10 | `Core.Scoreboard` | `Core.Scoreboard` |
| 6 | 27 | -0.815 | 5.016 | 0 | `SoC.Other` | `Core.MulDiv` |
| 7 | 262 | -0.764 | 5.677 | 10 | `Core.DCache` | `Core.ExecuteStage` |
| 8 | 49 | -0.710 | 5.271 | 8 | `Core.DCache` | `Core.ProducerMap` |
| 9 | 97 | -0.689 | 5.100 | 2 | `SoC.Other` | `Core.Other` |
| 10 | 99 | -0.662 | 5.140 | 9 | `Core.Scoreboard` | `Core.MulDiv` |
| 11 | 131 | -0.577 | 5.320 | 6 | `Core.Other` | `SoC.MemBridge` |
| 12 | 44 | -0.574 | 5.537 | 12 | `Core.Other` | `Core.LoadQueue` |
| 13 | 168 | -0.568 | 5.505 | 12 | `Core.Other` | `Core.Other` |
| 14 | 25 | -0.518 | 4.956 | 0 | `SoC.Other` | `Core.ExecuteStage` |
| 15 | 204 | -0.469 | 5.162 | 7 | `Core.DCache` | `Core.DecodeStage` |
| 16 | 53 | -0.434 | 4.997 | 8 | `Core.Scoreboard` | `Core.DCache` |
| 17 | 5 | -0.417 | 5.395 | 9 | `Core.DCache` | `Core.Frontend` |
| 18 | 46 | -0.367 | 4.866 | 0 | `SoC.Other` | `Core.DecodeStage` |
| 19 | 16 | -0.345 | 5.028 | 5 | `SoC.MemBridge` | `Core.Other` |
| 20 | 132 | -0.307 | 5.016 | 7 | `Core.Scoreboard` | `Core.Frontend` |
| 21 | 4 | -0.298 | 5.195 | 10 | `Core.DCache` | `Core.StoreBuffer` |
| 22 | 7 | -0.220 | 4.717 | 0 | `SoC.Other` | `Core.Frontend` |
| 23 | 4 | -0.184 | 4.833 | 0 | `SoC.MemBridge` | `SoC.MemBridge` |
| 24 | 3 | -0.154 | 5.093 | 9 | `Core.ExecuteStage` | `Core.Scoreboard` |
| 25 | 8 | -0.115 | 4.825 | 10 | `Core.ExecuteStage` | `Core.MulDiv` |
| 26 | 2 | -0.080 | 4.952 | 4 | `Core.DecodeStage` | `Core.Scoreboard` |
| 27 | 1 | -0.039 | 4.999 | 11 | `Core.ExecuteStage` | `Core.Other` |

## 精细起终点族

| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点族 | 终点族 | 时钟组 |
|---:|---:|---:|---:|---:|---|---|---|
| 1 | 32 | -0.999 | 5.940 | 16 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/D` | `setup` |
| 2 | 192 | -0.923 | 5.478 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_src][*]/R` | `setup` |
| 3 | 160 | -0.918 | 5.515 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_tval][*]/CE` | `setup` |
| 4 | 20 | -0.918 | 5.515 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_cause][*]/CE` | `setup` |
| 5 | 4 | -0.880 | 5.452 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/ENBWREN` | `setup` |
| 6 | 16 | -0.867 | 5.535 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][store_seq_cutoff][*]/CE` | `setup` |
| 7 | 64 | -0.865 | 5.456 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_src][*]/R` | `setup` |
| 8 | 64 | -0.845 | 5.537 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][forward_data][*]/CE` | `setup` |
| 9 | 8 | -0.845 | 5.537 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][forward_mask][*]/CE` | `setup` |
| 10 | 96 | -0.820 | 5.545 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_tval][*]/CE` | `setup` |
| 11 | 3 | -0.820 | 5.545 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_valid]/CE` | `setup` |
| 12 | 10 | -0.815 | 5.016 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/b_q_reg[*]/R` | `setup` |
| 13 | 64 | -0.814 | 5.501 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][addr][*]/CE` | `setup` |
| 14 | 6 | -0.812 | 5.495 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/FSM_onehot_state_q_reg[*]/CE` | `setup` |
| 15 | 6 | -0.798 | 5.472 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][trans_id][*]/CE` | `setup` |
| 16 | 2 | -0.798 | 5.467 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][load_unsigned]/CE` | `setup` |
| 17 | 4 | -0.787 | 5.479 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][size][*]/CE` | `setup` |
| 18 | 32 | -0.783 | 5.507 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_data_q_reg[*]/CE` | `setup` |
| 19 | 30 | -0.783 | 5.507 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_addr_q_reg[*]/CE` | `setup` |
| 20 | 17 | -0.783 | 5.507 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_tag_q_reg[*]/CE` | `setup` |
| 21 | 11 | -0.783 | 5.507 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_index_q_reg[*]/CE` | `setup` |
| 22 | 5 | -0.774 | 5.430 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_valid]/CE` | `setup` |
| 23 | 250 | -0.765 | 5.688 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][result][*]/D` | `setup` |
| 24 | 30 | -0.765 | 5.488 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/req_addr_q_reg[*]/CE` | `setup` |
| 25 | 32 | -0.764 | 5.660 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/D` | `setup` |
| 26 | 32 | -0.748 | 5.677 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/D` | `setup` |
| 27 | 12 | -0.741 | 5.465 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_cause][*]/CE` | `setup` |
| 28 | 200 | -0.726 | 5.592 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_tval][*]/D` | `setup` |
| 29 | 1 | -0.710 | 5.271 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMA/WE` | `setup` |
| 30 | 1 | -0.710 | 5.271 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMA_D1/WE` | `setup` |
| 31 | 1 | -0.710 | 5.271 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMB/WE` | `setup` |
| 32 | 1 | -0.710 | 5.271 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMB_D1/WE` | `setup` |
| 33 | 1 | -0.710 | 5.271 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMC/WE` | `setup` |
| 34 | 1 | -0.710 | 5.271 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMC_D1/WE` | `setup` |
| 35 | 1 | -0.710 | 5.271 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMD/WE` | `setup` |
| 36 | 1 | -0.710 | 5.271 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r1_0_31_0_2/RAMD_D1/WE` | `setup` |
| 37 | 40 | -0.689 | 5.100 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_perf_counters/commit_o_reg[*]/R` | `setup` |
| 38 | 4 | -0.686 | 5.409 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_mask_q_reg[*]/CE` | `setup` |
| 39 | 2 | -0.678 | 5.402 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_word_q_reg[*]/CE` | `setup` |
| 40 | 1 | -0.674 | 5.362 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_write_q_reg/CE` | `setup` |
| 41 | 32 | -0.662 | 5.140 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/u_div/U0/i_synth/i_has_input_skid.i_2to1/gen_has_z_tready.reg1_b_tdata_reg[*]/CE` | `setup` |
| 42 | 32 | -0.651 | 5.316 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[forward_data][*]/CE` | `setup` |
| 43 | 4 | -0.646 | 5.282 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/ENBWREN` | `setup` |
| 44 | 1 | -0.635 | 4.836 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/op_q_reg[*]/R` | `setup` |
| 45 | 35 | -0.632 | 5.265 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_addr][*]/CE` | `setup` |
| 46 | 1 | -0.629 | 5.294 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][uses_rs2]/CE` | `setup` |
| 47 | 4 | -0.625 | 5.014 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mscratch_q_reg[*]/R` | `setup` |
| 48 | 2 | -0.623 | 5.011 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mstatus_q_reg[*]/R` | `setup` |
| 49 | 249 | -0.619 | 5.282 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][result][*]/CE` | `setup` |
| 50 | 32 | -0.618 | 5.308 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/CE` | `setup` |
| 51 | 16 | -0.614 | 4.816 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/a_q_reg[*]/R` | `setup` |
| 52 | 160 | -0.609 | 5.169 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][result][*]/R` | `setup` |
| 53 | 60 | -0.605 | 5.200 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_addr][*]/CE` | `setup` |
| 54 | 23 | -0.602 | 5.453 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_cause][*]/D` | `setup` |
| 55 | 1 | -0.599 | 5.161 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMA/WE` | `setup` |
| 56 | 1 | -0.599 | 5.161 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMA_D1/WE` | `setup` |
| 57 | 1 | -0.599 | 5.161 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMB/WE` | `setup` |
| 58 | 1 | -0.599 | 5.161 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMB_D1/WE` | `setup` |
| 59 | 1 | -0.599 | 5.161 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMC/WE` | `setup` |
| 60 | 1 | -0.599 | 5.161 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMC_D1/WE` | `setup` |
| 61 | 1 | -0.599 | 5.161 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMD/WE` | `setup` |
| 62 | 1 | -0.599 | 5.161 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r2_0_31_0_2/RAMD_D1/WE` | `setup` |
| 63 | 1 | -0.596 | 5.157 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMA/WE` | `setup` |
| 64 | 1 | -0.596 | 5.157 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMA_D1/WE` | `setup` |
| 65 | 1 | -0.596 | 5.157 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMB/WE` | `setup` |
| 66 | 1 | -0.596 | 5.157 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMB_D1/WE` | `setup` |
| 67 | 1 | -0.596 | 5.157 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMC/WE` | `setup` |
| 68 | 1 | -0.596 | 5.157 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMC_D1/WE` | `setup` |
| 69 | 1 | -0.596 | 5.157 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMD/WE` | `setup` |
| 70 | 1 | -0.596 | 5.157 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_tid_q_reg_r3_0_31_0_2/RAMD_D1/WE` | `setup` |
| 71 | 1 | -0.586 | 5.033 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/branch_target_reg[*]/R` | `setup` |
| 72 | 1 | -0.586 | 5.197 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/ENBWREN` | `setup` |
| 73 | 40 | -0.585 | 5.133 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/ADDRBWRADDR[*]` | `setup` |
| 74 | 105 | -0.577 | 5.314 | 0 | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_addr_q_reg[*]/C` | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/ADDRARDADDR[*]` | `setup` |
| 75 | 38 | -0.574 | 5.537 | 12 | `student_top_inst/Core_cpu/u_core_top/store_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][forward_data][*]/D` | `setup` |
| 76 | 44 | -0.571 | 5.103 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/ADDRBWRADDR[*]` | `setup` |
| 77 | 28 | -0.568 | 5.505 | 12 | `student_top_inst/Core_cpu/u_core_top/store_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[forward_data][*]/D` | `setup` |
| 78 | 4 | -0.566 | 5.235 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[forward_mask][*]/CE` | `setup` |
| 79 | 1 | -0.562 | 5.522 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_valid_q_reg/D` | `setup` |
| 80 | 32 | -0.561 | 5.249 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/CE` | `setup` |
| 81 | 32 | -0.560 | 5.247 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][imm][*]/CE` | `setup` |
| 82 | 32 | -0.553 | 5.228 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][pc][*]/CE` | `setup` |
| 83 | 7 | -0.542 | 5.228 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][instr][*]/CE` | `setup` |
| 84 | 4 | -0.542 | 5.228 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][alu_op][*]/CE` | `setup` |
| 85 | 32 | -0.538 | 5.122 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/u_div/U0/i_synth/i_has_input_skid.i_2to1/gen_has_z_tready.reg1_a_tdata_reg[*]/CE` | `setup` |
| 86 | 96 | -0.535 | 5.140 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][result][*]/R` | `setup` |
| 87 | 26 | -0.534 | 5.155 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][rd][*]/CE` | `setup` |
| 88 | 5 | -0.534 | 5.218 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][is_return]/CE` | `setup` |
| 89 | 32 | -0.526 | 5.213 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/CE` | `setup` |
| 90 | 1 | -0.525 | 5.390 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_valid_q_reg/D` | `setup` |
| 91 | 6 | -0.518 | 4.956 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/R` | `setup` |
| 92 | 4 | -0.518 | 4.956 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/R` | `setup` |
| 93 | 4 | -0.518 | 4.956 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][rs1][*]/R` | `setup` |
| 94 | 1 | -0.518 | 4.956 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][instr][*]/R` | `setup` |
| 95 | 3 | -0.503 | 5.167 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[trans_id][*]/CE` | `setup` |
| 96 | 162 | -0.495 | 5.155 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][pc][*]/CE` | `setup` |
| 97 | 4 | -0.495 | 4.956 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/R` | `setup` |
| 98 | 14 | -0.488 | 5.180 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][rd][*]/CE` | `setup` |
| 99 | 82 | -0.485 | 5.179 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][pc][*]/CE` | `setup` |
| 100 | 160 | -0.480 | 5.137 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_src][*]/CE` | `setup` |
| 101 | 89 | -0.471 | 5.167 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][link_addr][*]/CE` | `setup` |
| 102 | 32 | -0.469 | 5.162 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[pc][*]/CE` | `setup` |
| 103 | 2 | -0.465 | 5.129 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[addr][*]/CE` | `setup` |
| 104 | 2 | -0.465 | 5.129 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[size][*]/CE` | `setup` |
| 105 | 21 | -0.462 | 5.363 | 7 | `student_top_inst/Core_cpu/u_core_top/commit_ptr_q_reg[*]_rep/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mepc_q_reg[*]/D` | `setup` |
| 106 | 17 | -0.457 | 5.391 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][forward_data][*]/D` | `setup` |
| 107 | 5 | -0.448 | 5.114 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs2][*]/CE` | `setup` |
| 108 | 4 | -0.438 | 5.369 | 12 | `student_top_inst/Core_cpu/u_core_top/store_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][forward_mask][*]/D` | `setup` |
| 109 | 3 | -0.438 | 5.121 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][muldiv_op][*]/CE` | `setup` |
| 110 | 4 | -0.435 | 5.158 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[alu_op][*]/CE` | `setup` |
| 111 | 30 | -0.434 | 4.945 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/ADDRARDADDR[*]` | `setup` |
| 112 | 20 | -0.434 | 4.651 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_perf_counters/cycle_o_reg[*]/R` | `setup` |
| 113 | 3 | -0.432 | 5.130 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][is_return]/CE` | `setup` |
| 114 | 32 | -0.428 | 5.112 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][pred_next_pc][*]/CE` | `setup` |
| 115 | 3 | -0.428 | 5.112 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][fu][*]/CE` | `setup` |
| 116 | 2 | -0.428 | 5.112 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][mem_size][*]/CE` | `setup` |
| 117 | 2 | -0.426 | 5.324 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/store_head_q_reg[*]/D` | `setup` |
| 118 | 1 | -0.425 | 5.307 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_write_q_reg/D` | `setup` |
| 119 | 8 | -0.421 | 5.322 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][store_seq_cutoff][*]/D` | `setup` |
| 120 | 1 | -0.418 | 5.142 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[serialize]/CE` | `setup` |
| 121 | 1 | -0.418 | 5.142 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[uses_rs1]/CE` | `setup` |
| 122 | 96 | -0.417 | 5.137 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_src][*]/CE` | `setup` |
| 123 | 2 | -0.417 | 5.374 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/head_q_reg[*]/D` | `setup` |
| 124 | 1 | -0.416 | 5.080 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[load_unsigned]/CE` | `setup` |
| 125 | 12 | -0.413 | 5.074 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/CE` | `setup` |
| 126 | 3 | -0.413 | 5.135 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][is_call]/CE` | `setup` |
| 127 | 5 | -0.409 | 5.073 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][is_call]/CE` | `setup` |
| 128 | 5 | -0.408 | 5.076 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/CE` | `setup` |
| 129 | 3 | -0.405 | 5.395 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/count_q_reg[*]/D` | `setup` |
| 130 | 1 | -0.404 | 4.842 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/branch_kind_reg[*]/R` | `setup` |
| 131 | 3 | -0.392 | 5.292 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/store_count_q_reg[*]/D` | `setup` |
| 132 | 3 | -0.390 | 5.327 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_wstrb_q_reg[*]/D` | `setup` |
| 133 | 32 | -0.386 | 5.078 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[pred_next_pc][*]/CE` | `setup` |
| 134 | 4 | -0.378 | 5.305 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/store_committed_q_reg[*]/D` | `setup` |
| 135 | 32 | -0.375 | 5.287 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_wdata_q_reg[*]/D` | `setup` |
| 136 | 5 | -0.375 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1]_rep[*]/CE` | `setup` |
| 137 | 5 | -0.375 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs2]_rep[*]/CE` | `setup` |
| 138 | 31 | -0.372 | 5.335 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_addr_q_reg[*]/D` | `setup` |
| 139 | 4 | -0.371 | 5.033 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][rs1][*]/CE` | `setup` |
| 140 | 2 | -0.367 | 4.866 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[alu_op][*]/R` | `setup` |
| 141 | 155 | -0.362 | 5.018 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][link_addr][*]/CE` | `setup` |
| 142 | 23 | -0.360 | 5.207 | 7 | `student_top_inst/Core_cpu/u_core_top/commit_ptr_q_reg[*]_rep/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mcause_q_reg[*]/D` | `setup` |
| 143 | 3 | -0.359 | 5.081 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[sys_op][*]/CE` | `setup` |
| 144 | 32 | -0.358 | 5.042 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_tval][*]/CE` | `setup` |
| 145 | 7 | -0.358 | 5.042 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[instr][*]/CE` | `setup` |
| 146 | 5 | -0.358 | 5.042 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rd][*]/CE` | `setup` |
| 147 | 3 | -0.358 | 5.042 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_cause][*]/CE` | `setup` |
| 148 | 3 | -0.358 | 5.042 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[muldiv_op][*]/CE` | `setup` |
| 149 | 25 | -0.357 | 5.265 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/producer_valid_q_reg[*]/D` | `setup` |
| 150 | 1 | -0.357 | 5.049 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/u_div/U0/i_synth/i_has_input_skid.i_2to1/gen_has_z_tready.reg1_b_ready_reg/D` | `setup` |
| 151 | 1 | -0.352 | 5.044 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/u_div/U0/i_synth/i_has_input_skid.i_2to1/gen_has_z_tready.z_valid_reg/D` | `setup` |
| 152 | 10 | -0.349 | 5.008 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_op][*]/CE` | `setup` |
| 153 | 3 | -0.348 | 5.008 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[trans_id][*]/CE` | `setup` |
| 154 | 3 | -0.348 | 5.008 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][branch_op][*]/CE` | `setup` |
| 155 | 3 | -0.345 | 4.844 | 5 | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/resp_rdata_q_reg[*]/D` | `setup` |
| 156 | 22 | -0.340 | 5.242 | 7 | `student_top_inst/Core_cpu/u_core_top/commit_ptr_q_reg[*]_rep/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mtval_q_reg[*]/D` | `setup` |
| 157 | 18 | -0.337 | 4.833 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_tval][*]/R` | `setup` |
| 158 | 7 | -0.337 | 4.833 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[imm][*]/R` | `setup` |
| 159 | 2 | -0.337 | 4.833 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[branch_op][*]/R` | `setup` |
| 160 | 1 | -0.336 | 5.035 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][writes_rd]/CE` | `setup` |
| 161 | 2 | -0.335 | 4.831 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[fu][*]/R` | `setup` |
| 162 | 2 | -0.335 | 4.831 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rd][*]/R` | `setup` |
| 163 | 1 | -0.335 | 4.831 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[is_jal]/R` | `setup` |
| 164 | 5 | -0.333 | 5.023 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_op][*]/CE` | `setup` |
| 165 | 5 | -0.331 | 5.229 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][occupied]/D` | `setup` |
| 166 | 8 | -0.327 | 5.221 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][done]/D` | `setup` |
| 167 | 23 | -0.325 | 5.182 | 6 | `student_top_inst/Core_cpu/u_core_top/commit_ptr_q_reg[*]_rep/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mtvec_q_reg[*]/D` | `setup` |
| 168 | 1 | -0.321 | 5.063 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_valid]/CE` | `setup` |
| 169 | 3 | -0.320 | 5.256 | 12 | `student_top_inst/Core_cpu/u_core_top/store_head_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[forward_mask][*]/D` | `setup` |
| 170 | 13 | -0.317 | 5.028 | 5 | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/has_mux_a.A/no_softecc_norm_sel2.has_mem_regs.WITHOUT_ECC_PIPE.ce_pri.sel_pipe_d1_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/resp_rdata_q_reg[*]/D` | `setup` |
| 171 | 9 | -0.317 | 5.011 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/CE` | `setup` |
| 172 | 8 | -0.317 | 5.011 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][sys_op][*]/CE` | `setup` |
| 173 | 4 | -0.317 | 4.981 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][writes_rd]/CE` | `setup` |
| 174 | 132 | -0.307 | 5.016 | 7 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/ras_q_reg[*][*]/CE` | `setup` |
| 175 | 32 | -0.306 | 5.206 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][addr][*]/D` | `setup` |
| 176 | 1 | -0.306 | 5.027 | 9 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/u_div/U0/i_synth/i_has_input_skid.i_2to1/gen_has_z_tready.reg1_a_ready_reg/D` | `setup` |
| 177 | 21 | -0.299 | 5.126 | 6 | `student_top_inst/Core_cpu/u_core_top/commit_ptr_q_reg[*]_rep/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mscratch_q_reg[*]/D` | `setup` |
| 178 | 4 | -0.298 | 5.195 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/store_q_reg[*][valid]/D` | `setup` |
| 179 | 12 | -0.295 | 5.014 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[csr_addr][*]/CE` | `setup` |
| 180 | 1 | -0.295 | 5.014 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[load_unsigned]/CE` | `setup` |
| 181 | 32 | -0.293 | 4.993 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[imm][*]/CE` | `setup` |
| 182 | 1 | -0.293 | 4.959 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[is_jalr]/CE` | `setup` |
| 183 | 1 | -0.293 | 4.959 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[uses_rs2]/CE` | `setup` |
| 184 | 2 | -0.289 | 5.009 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[csr_op][*]/CE` | `setup` |
| 185 | 25 | -0.287 | 5.197 | 7 | `student_top_inst/Core_cpu/u_core_top/commit_ptr_q_reg[*]_rep/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mstatus_q_reg[*]/D` | `setup` |
| 186 | 5 | -0.285 | 4.945 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][rd][*]/CE` | `setup` |
| 187 | 3 | -0.284 | 4.985 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[fu][*]/CE` | `setup` |
| 188 | 3 | -0.270 | 4.993 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[branch_op][*]/CE` | `setup` |
| 189 | 1 | -0.270 | 4.993 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[csr_imm]/CE` | `setup` |
| 190 | 2 | -0.266 | 5.009 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[mem_size][*]/CE` | `setup` |
| 191 | 1 | -0.265 | 4.985 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[is_jal]/CE` | `setup` |
| 192 | 3 | -0.260 | 5.188 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][store_slot_valid]/D` | `setup` |
| 193 | 15 | -0.258 | 4.918 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][sys_op][*]/CE` | `setup` |
| 194 | 1 | -0.258 | 4.945 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][is_jalr]/CE` | `setup` |
| 195 | 1 | -0.258 | 4.945 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][load_unsigned]/CE` | `setup` |
| 196 | 8 | -0.243 | 4.997 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/DIADI[*]` | `setup` |
| 197 | 13 | -0.239 | 4.797 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/ADDRARDADDR[*]` | `setup` |
| 198 | 1 | -0.239 | 4.878 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/u_div/U0/i_synth/i_has_input_skid.i_2to1/gen_has_z_tready.reg2_b_valid_reg/D` | `setup` |
| 199 | 10 | -0.235 | 5.320 | 1 | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_addr_q_reg[*]/C` | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/DIADI[*]` | `setup` |
| 200 | 2 | -0.230 | 5.162 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][forward_mask][*]/D` | `setup` |
| 201 | 5 | -0.227 | 4.663 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[csr_addr][*]/R` | `setup` |
| 202 | 1 | -0.222 | 4.720 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[sys_op][*]/R` | `setup` |
| 203 | 2 | -0.220 | 4.717 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/pending_pc_q_reg[*]/R` | `setup` |
| 204 | 5 | -0.212 | 4.674 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][imm][*]/R` | `setup` |
| 205 | 2 | -0.212 | 5.150 | 10 | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[forward_data][*]/D` | `setup` |
| 206 | 5 | -0.205 | 4.728 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/ADDRBWRADDR[*]` | `setup` |
| 207 | 1 | -0.205 | 4.812 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/ENARDEN` | `setup` |
| 208 | 2 | -0.201 | 5.131 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][size][*]/D` | `setup` |
| 209 | 1 | -0.201 | 4.849 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/u_div/U0/i_synth/i_has_input_skid.i_2to1/gen_has_z_tready.reg2_a_valid_reg/D` | `setup` |
| 210 | 1 | -0.200 | 5.099 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_active_q_reg/D` | `setup` |
| 211 | 4 | -0.199 | 4.887 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_count_q_reg[*]/CE` | `setup` |
| 212 | 3 | -0.193 | 5.109 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][trans_id][*]/D` | `setup` |
| 213 | 1 | -0.193 | 4.915 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[writes_rd]/CE` | `setup` |
| 214 | 5 | -0.189 | 5.079 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_valid]/D` | `setup` |
| 215 | 1 | -0.187 | 5.145 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_valid_q_reg/D` | `setup` |
| 216 | 4 | -0.184 | 4.833 | 0 | `student_top_inst/mem_bridge/dram_adapter/read_valid_d1_reg/C` | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/REGCEAREGCE` | `setup` |
| 217 | 5 | -0.177 | 5.096 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][store_slot][*]/D` | `setup` |
| 218 | 1 | -0.174 | 4.840 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][is_jal]/CE` | `setup` |
| 219 | 3 | -0.154 | 5.093 | 9 | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][exception_tval][*]/D` | `setup` |
| 220 | 1 | -0.140 | 4.575 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][rd][*]/R` | `setup` |
| 221 | 1 | -0.136 | 4.608 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/valid_q_reg[*]/R` | `setup` |
| 222 | 20 | -0.133 | 4.601 | 1 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mcause_q_reg[*]/R` | `setup` |
| 223 | 1 | -0.119 | 5.050 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/scoreboard_count_q_reg[*]/D` | `setup` |
| 224 | 8 | -0.115 | 4.825 | 10 | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][muldiv_op][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/u_mul/U0/i_mult/gLUT.gLUT_speed.iLUT/NxM_mult.pp_gen_pipeline.pp_gen_loop[*].b_is_even.pp_out_reg_reg[*][*]/D` | `setup` |
| 225 | 2 | -0.114 | 4.610 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[csr_op][*]/R` | `setup` |
| 226 | 1 | -0.114 | 4.610 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_cause][*]/R` | `setup` |
| 227 | 4 | -0.113 | 4.560 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_frontend/pending_pred_next_q_reg[*]/R` | `setup` |
| 228 | 4 | -0.113 | 4.499 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mtval_q_reg[*]/R` | `setup` |
| 229 | 23 | -0.111 | 4.571 | 7 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/b_q_reg[*]/CE` | `setup` |
| 230 | 1 | -0.101 | 4.618 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_valid]/R` | `setup` |
| 231 | 2 | -0.098 | 5.027 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_count_q_reg[*]/D` | `setup` |
| 232 | 12 | -0.095 | 4.961 | 5 | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_addr_q_reg[*]/C` | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/ENARDEN` | `setup` |
| 233 | 4 | -0.092 | 4.716 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_addr_q_reg[*]/C` | `student_top_inst/mem_bridge/dram_adapter/dram/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/WEA[*]` | `setup` |
| 234 | 2 | -0.091 | 4.610 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[mem_size][*]/R` | `setup` |
| 235 | 1 | -0.089 | 5.018 | 9 | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][forward_data][*]/D` | `setup` |
| 236 | 1 | -0.082 | 4.986 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_active_meta_q_reg[forward_data][*]/D` | `setup` |
| 237 | 2 | -0.080 | 4.952 | 4 | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][csr_src][*]/D` | `setup` |
| 238 | 1 | -0.080 | 4.991 | 8 | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/C` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][forward_mask][*]/D` | `setup` |
| 239 | 5 | -0.079 | 4.539 | 7 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/a_q_reg[*]/CE` | `setup` |
| 240 | 1 | -0.077 | 4.767 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/u_div/U0/i_synth/i_has_input_skid.i_2to1/gen_has_z_tready.reg1_b_valid_reg/D` | `setup` |
| 241 | 1 | -0.070 | 4.875 | 2 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_csr/mstatus_q_reg[*]/D` | `setup` |
| 242 | 1 | -0.060 | 4.992 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/load_q_reg[*][load_unsigned]/D` | `setup` |
| 243 | 1 | -0.057 | 4.518 | 7 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_muldiv/op_q_reg[*]/CE` | `setup` |
| 244 | 3 | -0.052 | 4.491 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][pc][*]/R` | `setup` |
| 245 | 2 | -0.041 | 5.008 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_data_q_reg[*]/D` | `setup` |
| 246 | 2 | -0.040 | 4.536 | 4 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/WEA[*]` | `setup` |
| 247 | 1 | -0.039 | 4.999 | 11 | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/C` | `student_top_inst/Core_cpu/u_core_top/branch_miss_reg/D` | `setup` |
| 248 | 2 | -0.030 | 4.995 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][store_slot][*]/D` | `setup` |
| 249 | 1 | -0.029 | 4.491 | 0 | `student_top_inst/cpu_rst_sync_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][alu_op][*]/R` | `setup` |
| 250 | 1 | -0.022 | 4.838 | 8 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/DIADI[*]` | `setup` |
| 251 | 1 | -0.013 | 4.907 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/issue_ptr_q_reg[*]/D` | `setup` |
| 252 | 1 | -0.011 | 4.970 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/req_addr_q_reg[*]/D` | `setup` |
| 253 | 1 | -0.003 | 4.966 | 10 | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][fu][*]/C` | `student_top_inst/Core_cpu/u_core_top/scoreboard_q_reg[*][store_slot_valid]/D` | `setup` |
