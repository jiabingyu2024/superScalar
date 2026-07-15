# 全量 setup 违例路径聚类

- 原始违例路径数：1249
- 聚类数：91
- 聚类规则：仅把数字位选和综合复制后缀归一化；每一条原始路径仍保留在 CSV/RPT。

## 模块级覆盖矩阵

| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点模块 | 终点模块 |
|---:|---:|---:|---:|---:|---|---|
| 1 | 340 | -5.270 | 9.737 | 21 | `Core.Other` | `Core.DCache` |
| 2 | 510 | -4.625 | 9.207 | 25 | `Core.Other` | `Core.Other` |
| 3 | 55 | -1.136 | 5.733 | 11 | `Core.Other` | `Core.ProducerMap` |
| 4 | 56 | -0.978 | 5.809 | 10 | `Core.DCache` | `Core.ExecuteStage` |
| 5 | 288 | -0.665 | 5.496 | 9 | `Core.DCache` | `Core.Other` |

## 精细起终点族

| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点族 | 终点族 | 时钟组 |
|---:|---:|---:|---:|---:|---|---|---|
| 1 | 1 | -5.270 | 9.737 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/ENBWREN` | `setup` |
| 2 | 32 | -5.042 | 9.638 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_data_q_reg[*]/CE` | `setup` |
| 3 | 30 | -5.042 | 9.638 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_addr_q_reg[*]/CE` | `setup` |
| 4 | 11 | -5.042 | 9.638 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_index_q_reg[*]/CE` | `setup` |
| 5 | 4 | -5.042 | 9.638 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_mask_q_reg[*]/CE` | `setup` |
| 6 | 3 | -5.042 | 9.638 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_tag_q_reg[*]/CE` | `setup` |
| 7 | 2 | -5.042 | 9.638 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_word_q_reg[*]/CE` | `setup` |
| 8 | 1 | -5.042 | 9.638 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_write_q_reg/CE` | `setup` |
| 9 | 30 | -5.017 | 9.613 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/req_addr_q_reg[*]/CE` | `setup` |
| 10 | 6 | -4.979 | 9.575 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/FSM_onehot_state_q_reg[*]/CE` | `setup` |
| 11 | 8 | -4.625 | 9.114 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_data][*]/R` | `setup` |
| 12 | 2 | -4.625 | 9.114 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_mask][*]/R` | `setup` |
| 13 | 1 | -4.440 | 9.271 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_valid_q_reg/D` | `setup` |
| 14 | 64 | -4.376 | 9.207 | 25 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_data][*]/D` | `setup` |
| 15 | 32 | -4.376 | 9.207 | 25 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[forward_data][*]/D` | `setup` |
| 16 | 64 | -4.253 | 8.849 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][addr][*]/CE` | `setup` |
| 17 | 64 | -4.253 | 8.849 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_data][*]/CE` | `setup` |
| 18 | 16 | -4.253 | 8.849 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][store_seq_cutoff][*]/CE` | `setup` |
| 19 | 8 | -4.253 | 8.849 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_mask][*]/CE` | `setup` |
| 20 | 6 | -4.253 | 8.849 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][trans_id][*]/CE` | `setup` |
| 21 | 4 | -4.253 | 8.849 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][size][*]/CE` | `setup` |
| 22 | 44 | -3.961 | 8.261 | 19 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/ADDRBWRADDR[*]` | `setup` |
| 23 | 44 | -3.961 | 8.261 | 19 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/ADDRBWRADDR[*]` | `setup` |
| 24 | 11 | -3.961 | 8.261 | 19 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/ADDRBWRADDR[*]` | `setup` |
| 25 | 2 | -3.960 | 8.791 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][load_unsigned]/D` | `setup` |
| 26 | 4 | -3.833 | 8.664 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_store_buffer/committed_o_reg[*]/D` | `setup` |
| 27 | 4 | -3.833 | 8.664 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_store_buffer/entries_o_reg[*][valid]/D` | `setup` |
| 28 | 32 | -3.825 | 8.421 | 19 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[forward_data][*]/CE` | `setup` |
| 29 | 4 | -3.825 | 8.421 | 19 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[forward_mask][*]/CE` | `setup` |
| 30 | 3 | -3.825 | 8.421 | 19 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[trans_id][*]/CE` | `setup` |
| 31 | 2 | -3.825 | 8.421 | 19 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[addr][*]/CE` | `setup` |
| 32 | 2 | -3.825 | 8.421 | 19 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[size][*]/CE` | `setup` |
| 33 | 8 | -3.789 | 8.620 | 22 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_mask][*]/D` | `setup` |
| 34 | 4 | -3.764 | 8.595 | 23 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[forward_mask][*]/D` | `setup` |
| 35 | 4 | -3.760 | 8.591 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_mask_q_reg[*]/D` | `setup` |
| 36 | 32 | -3.749 | 8.580 | 21 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_data_q_reg[*]/D` | `setup` |
| 37 | 4 | -3.674 | 8.141 | 18 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/ENBWREN` | `setup` |
| 38 | 4 | -3.674 | 8.141 | 18 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/ENBWREN` | `setup` |
| 39 | 3 | -3.652 | 8.483 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[trans_id][*]/D` | `setup` |
| 40 | 2 | -3.652 | 8.483 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[addr][*]/D` | `setup` |
| 41 | 2 | -3.652 | 8.483 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[size][*]/D` | `setup` |
| 42 | 2 | -3.652 | 8.483 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/count_o_reg[*]/D` | `setup` |
| 43 | 1 | -3.652 | 8.483 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[load_unsigned]/D` | `setup` |
| 44 | 63 | -3.647 | 8.478 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][addr][*]/D` | `setup` |
| 45 | 8 | -3.647 | 8.478 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][store_seq_cutoff][*]/D` | `setup` |
| 46 | 3 | -3.647 | 8.478 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][trans_id][*]/D` | `setup` |
| 47 | 2 | -3.647 | 8.478 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][size][*]/D` | `setup` |
| 48 | 1 | -3.552 | 8.383 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_o_reg/D` | `setup` |
| 49 | 3 | -3.520 | 8.351 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_store_buffer/count_o_reg[*]/D` | `setup` |
| 50 | 2 | -3.520 | 8.351 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_store_buffer/head_o_reg[*]/D` | `setup` |
| 51 | 32 | -3.436 | 8.267 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_addr_q_reg[*]/D` | `setup` |
| 52 | 30 | -3.406 | 8.237 | 20 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/req_addr_q_reg[*]/D` | `setup` |
| 53 | 30 | -3.341 | 8.037 | 19 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_addr_q_reg[*]/D` | `setup` |
| 54 | 11 | -3.341 | 8.037 | 19 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_index_q_reg[*]/D` | `setup` |
| 55 | 3 | -3.315 | 8.011 | 19 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_tag_q_reg[*]/D` | `setup` |
| 56 | 2 | -3.315 | 8.011 | 19 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_word_q_reg[*]/D` | `setup` |
| 57 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMA/WE` | `setup` |
| 58 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMA_D1/WE` | `setup` |
| 59 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMB/WE` | `setup` |
| 60 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMB_D1/WE` | `setup` |
| 61 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMC/WE` | `setup` |
| 62 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMC_D1/WE` | `setup` |
| 63 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMD/WE` | `setup` |
| 64 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMD_D1/WE` | `setup` |
| 65 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMA/WE` | `setup` |
| 66 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMA_D1/WE` | `setup` |
| 67 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMB/WE` | `setup` |
| 68 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMB_D1/WE` | `setup` |
| 69 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMC/WE` | `setup` |
| 70 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMC_D1/WE` | `setup` |
| 71 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMD/WE` | `setup` |
| 72 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMD_D1/WE` | `setup` |
| 73 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMA/WE` | `setup` |
| 74 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMA_D1/WE` | `setup` |
| 75 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMB/WE` | `setup` |
| 76 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMB_D1/WE` | `setup` |
| 77 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMC/WE` | `setup` |
| 78 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMC_D1/WE` | `setup` |
| 79 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMD/WE` | `setup` |
| 80 | 1 | -1.136 | 5.632 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMD_D1/WE` | `setup` |
| 81 | 32 | -0.978 | 5.809 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/D` | `setup` |
| 82 | 31 | -0.902 | 5.733 | 11 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_valid_q_reg[*]/D` | `setup` |
| 83 | 24 | -0.813 | 5.644 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/D` | `setup` |
| 84 | 30 | -0.739 | 5.583 | 15 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/D` | `setup` |
| 85 | 192 | -0.665 | 5.496 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][result][*]/D` | `setup` |
| 86 | 96 | -0.639 | 5.235 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][result][*]/CE` | `setup` |
| 87 | 1 | -0.564 | 5.395 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/exec_load_submitted_q_reg/D` | `setup` |
| 88 | 8 | -0.534 | 5.365 | 10 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/D` | `setup` |
| 89 | 4 | -0.415 | 5.011 | 8 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/count_o_reg[*]/CE` | `setup` |
| 90 | 8 | -0.221 | 5.052 | 9 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][occupied]/D` | `setup` |
| 91 | 2 | -0.208 | 5.039 | 9 | `student_top_inst/Core_cpu/u_core_top/id_head_q_reg/C` | `student_top_inst/Core_cpu/u_core_top/id_count_q_reg[*]/D` | `setup` |
