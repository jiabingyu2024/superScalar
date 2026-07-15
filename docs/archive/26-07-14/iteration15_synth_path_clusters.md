# 全量 setup 违例路径聚类

- 原始违例路径数：1960
- 聚类数：129
- 聚类规则：仅把数字位选和综合复制后缀归一化；每一条原始路径仍保留在 CSV/RPT。

## 模块级覆盖矩阵

| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点模块 | 终点模块 |
|---:|---:|---:|---:|---:|---|---|
| 1 | 331 | -2.311 | 6.907 | 11 | `Core.DCache` | `Core.DCache` |
| 2 | 1226 | -1.668 | 6.264 | 13 | `Core.DCache` | `Core.Other` |
| 3 | 12 | -0.962 | 5.793 | 11 | `Core.Frontend` | `Core.Frontend` |
| 4 | 64 | -0.793 | 5.624 | 9 | `Core.DCache` | `Core.ExecuteStage` |
| 5 | 47 | -0.754 | 5.348 | 9 | `Core.DCache` | `Core.ProducerMap` |
| 6 | 48 | -0.746 | 5.124 | 8 | `Core.Frontend` | `SoC.Other` |
| 7 | 8 | -0.396 | 5.227 | 16 | `Core.ExecuteStage` | `Core.Other` |
| 8 | 8 | -0.138 | 4.605 | 8 | `Core.Other` | `Core.DCache` |
| 9 | 216 | -0.079 | 4.568 | 7 | `Core.Other` | `Core.Other` |

## 精细起终点族

| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点族 | 终点族 | 时钟组 |
|---:|---:|---:|---:|---:|---|---|---|
| 1 | 30 | -2.311 | 6.907 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/req_addr_q_reg[*]/CE` | `setup` |
| 2 | 6 | -2.136 | 6.732 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/FSM_onehot_state_q_reg[*]/CE` | `setup` |
| 3 | 32 | -2.001 | 6.597 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_data_q_reg[*]/CE` | `setup` |
| 4 | 30 | -2.001 | 6.597 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_addr_q_reg[*]/CE` | `setup` |
| 5 | 11 | -2.001 | 6.597 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_index_q_reg[*]/CE` | `setup` |
| 6 | 4 | -2.001 | 6.597 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_mask_q_reg[*]/CE` | `setup` |
| 7 | 3 | -2.001 | 6.597 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_tag_q_reg[*]/CE` | `setup` |
| 8 | 2 | -2.001 | 6.597 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_word_q_reg[*]/CE` | `setup` |
| 9 | 1 | -2.001 | 6.597 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_write_q_reg/CE` | `setup` |
| 10 | 64 | -1.668 | 6.264 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][addr][*]/CE` | `setup` |
| 11 | 64 | -1.668 | 6.264 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_data][*]/CE` | `setup` |
| 12 | 16 | -1.668 | 6.264 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][store_seq_cutoff][*]/CE` | `setup` |
| 13 | 8 | -1.668 | 6.264 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_mask][*]/CE` | `setup` |
| 14 | 6 | -1.668 | 6.264 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][trans_id][*]/CE` | `setup` |
| 15 | 4 | -1.668 | 6.264 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][size][*]/CE` | `setup` |
| 16 | 1 | -1.399 | 6.230 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_valid_q_reg/D` | `setup` |
| 17 | 44 | -1.378 | 5.677 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/ADDRBWRADDR[*]` | `setup` |
| 18 | 44 | -1.378 | 5.677 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/ADDRBWRADDR[*]` | `setup` |
| 19 | 11 | -1.378 | 5.677 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/ADDRBWRADDR[*]` | `setup` |
| 20 | 2 | -1.377 | 6.208 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][load_unsigned]/D` | `setup` |
| 21 | 4 | -1.251 | 6.082 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_store_buffer/committed_o_reg[*]/D` | `setup` |
| 22 | 4 | -1.251 | 6.082 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_store_buffer/entries_o_reg[*][valid]/D` | `setup` |
| 23 | 32 | -1.242 | 5.838 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[forward_data][*]/CE` | `setup` |
| 24 | 4 | -1.242 | 5.838 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[forward_mask][*]/CE` | `setup` |
| 25 | 3 | -1.242 | 5.838 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[trans_id][*]/CE` | `setup` |
| 26 | 2 | -1.242 | 5.838 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[addr][*]/CE` | `setup` |
| 27 | 2 | -1.242 | 5.838 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[size][*]/CE` | `setup` |
| 28 | 56 | -1.204 | 6.035 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_data][*]/D` | `setup` |
| 29 | 8 | -1.204 | 6.035 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_mask][*]/D` | `setup` |
| 30 | 4 | -1.177 | 6.008 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_mask_q_reg[*]/D` | `setup` |
| 31 | 32 | -1.166 | 5.997 | 11 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_data_q_reg[*]/D` | `setup` |
| 32 | 3 | -1.067 | 5.898 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[trans_id][*]/D` | `setup` |
| 33 | 2 | -1.067 | 5.898 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[addr][*]/D` | `setup` |
| 34 | 2 | -1.067 | 5.898 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[size][*]/D` | `setup` |
| 35 | 2 | -1.067 | 5.898 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/count_o_reg[*]/D` | `setup` |
| 36 | 1 | -1.067 | 5.898 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[load_unsigned]/D` | `setup` |
| 37 | 32 | -1.064 | 5.895 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][addr][*]/D` | `setup` |
| 38 | 8 | -1.064 | 5.895 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][store_seq_cutoff][*]/D` | `setup` |
| 39 | 3 | -1.064 | 5.895 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][trans_id][*]/D` | `setup` |
| 40 | 2 | -1.064 | 5.895 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][size][*]/D` | `setup` |
| 41 | 1 | -0.975 | 5.806 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_o_reg/D` | `setup` |
| 42 | 2 | -0.962 | 5.793 | 10 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/u_btb_bank/mem_q_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/read_pht_counter_q_reg[*]/D` | `setup` |
| 43 | 3 | -0.938 | 5.769 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_store_buffer/count_o_reg[*]/D` | `setup` |
| 44 | 2 | -0.938 | 5.769 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_store_buffer/head_o_reg[*]/D` | `setup` |
| 45 | 12 | -0.930 | 5.419 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][exception_tval][*]/R` | `setup` |
| 46 | 6 | -0.914 | 5.403 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][imm][*]/R` | `setup` |
| 47 | 2 | -0.893 | 5.382 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][csr_op][*]/R` | `setup` |
| 48 | 32 | -0.853 | 5.684 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_addr_q_reg[*]/D` | `setup` |
| 49 | 30 | -0.823 | 5.654 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/req_addr_q_reg[*]/D` | `setup` |
| 50 | 1 | -0.795 | 5.626 | 11 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/u_btb_bank/mem_q_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/pht_collision_q_reg/D` | `setup` |
| 51 | 32 | -0.793 | 5.624 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/D` | `setup` |
| 52 | 30 | -0.758 | 5.454 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_addr_q_reg[*]/D` | `setup` |
| 53 | 11 | -0.758 | 5.454 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_index_q_reg[*]/D` | `setup` |
| 54 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMA/WE` | `setup` |
| 55 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMA_D1/WE` | `setup` |
| 56 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMB/WE` | `setup` |
| 57 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMB_D1/WE` | `setup` |
| 58 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMC/WE` | `setup` |
| 59 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMC_D1/WE` | `setup` |
| 60 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMD/WE` | `setup` |
| 61 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMD_D1/WE` | `setup` |
| 62 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMA/WE` | `setup` |
| 63 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMA_D1/WE` | `setup` |
| 64 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMB/WE` | `setup` |
| 65 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMB_D1/WE` | `setup` |
| 66 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMC/WE` | `setup` |
| 67 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMC_D1/WE` | `setup` |
| 68 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMD/WE` | `setup` |
| 69 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMD_D1/WE` | `setup` |
| 70 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMA/WE` | `setup` |
| 71 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMA_D1/WE` | `setup` |
| 72 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMB/WE` | `setup` |
| 73 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMB_D1/WE` | `setup` |
| 74 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMC/WE` | `setup` |
| 75 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMC_D1/WE` | `setup` |
| 76 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMD/WE` | `setup` |
| 77 | 1 | -0.754 | 5.250 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMD_D1/WE` | `setup` |
| 78 | 48 | -0.746 | 5.124 | 8 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/u_btb_bank/mem_q_reg/CLKARDCLK` | `student_top_inst/Mem_IROM/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/ADDRARDADDR[*]` | `setup` |
| 79 | 3 | -0.732 | 5.428 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_tag_q_reg[*]/D` | `setup` |
| 80 | 2 | -0.732 | 5.428 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_word_q_reg[*]/D` | `setup` |
| 81 | 32 | -0.728 | 5.559 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[forward_data][*]/D` | `setup` |
| 82 | 96 | -0.645 | 5.241 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][result][*]/CE` | `setup` |
| 83 | 32 | -0.628 | 5.459 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/D` | `setup` |
| 84 | 4 | -0.628 | 5.459 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[forward_mask][*]/D` | `setup` |
| 85 | 23 | -0.517 | 5.348 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_valid_q_reg[*]/D` | `setup` |
| 86 | 1 | -0.486 | 5.317 | 10 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/u_btb_bank/mem_q_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/btb_collision_q_reg/D` | `setup` |
| 87 | 192 | -0.480 | 5.311 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][result][*]/D` | `setup` |
| 88 | 2 | -0.463 | 5.294 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_early_valid_q_reg[*]/D` | `setup` |
| 89 | 7 | -0.432 | 4.810 | 7 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/u_btb_bank/mem_q_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/u_btb_bank/mem_q_reg/ADDRARDADDR[*]` | `setup` |
| 90 | 8 | -0.396 | 5.227 | 16 | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_data][*]/D` | `setup` |
| 91 | 8 | -0.380 | 5.211 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/D` | `setup` |
| 92 | 21 | -0.273 | 5.117 | 13 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/D` | `setup` |
| 93 | 1 | -0.169 | 5.000 | 9 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/u_btb_bank/mem_q_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/read_pht_index_q_reg[*]/D` | `setup` |
| 94 | 64 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_early_addr_q_reg[*][*]/CE` | `setup` |
| 95 | 64 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][exception_tval][*]/CE` | `setup` |
| 96 | 64 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][imm][*]/CE` | `setup` |
| 97 | 64 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][pc][*]/CE` | `setup` |
| 98 | 64 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][pred_next_pc][*]/CE` | `setup` |
| 99 | 24 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][csr_addr][*]/CE` | `setup` |
| 100 | 16 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][pred_index][*]/CE` | `setup` |
| 101 | 14 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][instr][*]/CE` | `setup` |
| 102 | 10 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][rd][*]/CE` | `setup` |
| 103 | 10 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][rs1][*]/CE` | `setup` |
| 104 | 10 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][rs2][*]/CE` | `setup` |
| 105 | 8 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][alu_op][*]/CE` | `setup` |
| 106 | 6 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][branch_op][*]/CE` | `setup` |
| 107 | 6 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][fu][*]/CE` | `setup` |
| 108 | 6 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][muldiv_op][*]/CE` | `setup` |
| 109 | 6 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][sys_op][*]/CE` | `setup` |
| 110 | 4 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][csr_op][*]/CE` | `setup` |
| 111 | 4 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][exception_cause][*]/CE` | `setup` |
| 112 | 4 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][mem_size][*]/CE` | `setup` |
| 113 | 4 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][pred_counter][*]/CE` | `setup` |
| 114 | 2 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][csr_imm]/CE` | `setup` |
| 115 | 2 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][exception_valid]/CE` | `setup` |
| 116 | 2 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][is_jal]/CE` | `setup` |
| 117 | 2 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][is_jalr]/CE` | `setup` |
| 118 | 2 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][load_unsigned]/CE` | `setup` |
| 119 | 2 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][rs1][*]_rep/CE` | `setup` |
| 120 | 2 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][rs1][*]_rep__0/CE` | `setup` |
| 121 | 2 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][serialize]/CE` | `setup` |
| 122 | 2 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][uses_rs1]/CE` | `setup` |
| 123 | 2 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][uses_rs2]/CE` | `setup` |
| 124 | 2 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][writes_rd]/CE` | `setup` |
| 125 | 1 | -0.142 | 4.738 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][rs1][*]_rep__1/CE` | `setup` |
| 126 | 4 | -0.138 | 4.605 | 8 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][occupied]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/ENARDEN` | `setup` |
| 127 | 4 | -0.138 | 4.605 | 8 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][occupied]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/ENARDEN` | `setup` |
| 128 | 216 | -0.079 | 4.568 | 7 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][occupied]/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][csr_src][*]/R` | `setup` |
| 129 | 4 | -0.044 | 4.640 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/count_o_reg[*]/CE` | `setup` |
