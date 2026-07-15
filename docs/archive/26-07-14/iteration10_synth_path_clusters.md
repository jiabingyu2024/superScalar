# 全量 setup 违例路径聚类

- 原始违例路径数：2672
- 聚类数：123
- 聚类规则：仅把数字位选和综合复制后缀归一化；每一条原始路径仍保留在 CSV/RPT。

## 模块级覆盖矩阵

| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点模块 | 终点模块 |
|---:|---:|---:|---:|---:|---|---|
| 1 | 13 | -1.266 | 6.097 | 10 | `Core.Frontend` | `Core.Frontend` |
| 2 | 2014 | -0.980 | 5.469 | 13 | `Core.DCache` | `Core.Other` |
| 3 | 120 | -0.636 | 5.103 | 9 | `Core.Other` | `Core.DCache` |
| 4 | 24 | -0.542 | 5.038 | 7 | `Core.DCache` | `Core.ProducerMap` |
| 5 | 48 | -0.425 | 4.803 | 7 | `Core.Frontend` | `SoC.Other` |
| 6 | 243 | -0.196 | 5.011 | 7 | `Core.DCache` | `Core.ExecuteStage` |
| 7 | 209 | -0.193 | 4.789 | 6 | `Core.DCache` | `Core.DecodeStage` |
| 8 | 1 | -0.005 | 4.836 | 7 | `Core.DCache` | `Core.Frontend` |

## 精细起终点族

| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点族 | 终点族 | 时钟组 |
|---:|---:|---:|---:|---:|---|---|---|
| 1 | 1 | -1.266 | 6.097 | 10 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/btb_mem_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/read_pht_valid_q_reg/D` | `setup` |
| 2 | 216 | -0.980 | 5.469 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][csr_src][*]/R` | `setup` |
| 3 | 1 | -0.912 | 5.755 | 10 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/btb_mem_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/read_entry_valid_q_reg/D` | `setup` |
| 4 | 1 | -0.636 | 5.103 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/ENBWREN` | `setup` |
| 5 | 256 | -0.556 | 5.152 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][csr_src][*]/CE` | `setup` |
| 6 | 2 | -0.548 | 5.379 | 9 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/btb_mem_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/read_pht_counter_q_reg[*]/D` | `setup` |
| 7 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMA/WE` | `setup` |
| 8 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMA_D1/WE` | `setup` |
| 9 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMB/WE` | `setup` |
| 10 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMB_D1/WE` | `setup` |
| 11 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMC/WE` | `setup` |
| 12 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMC_D1/WE` | `setup` |
| 13 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMD/WE` | `setup` |
| 14 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMD_D1/WE` | `setup` |
| 15 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMA/WE` | `setup` |
| 16 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMA_D1/WE` | `setup` |
| 17 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMB/WE` | `setup` |
| 18 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMB_D1/WE` | `setup` |
| 19 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMC/WE` | `setup` |
| 20 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMC_D1/WE` | `setup` |
| 21 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMD/WE` | `setup` |
| 22 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMD_D1/WE` | `setup` |
| 23 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMA/WE` | `setup` |
| 24 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMA_D1/WE` | `setup` |
| 25 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMB/WE` | `setup` |
| 26 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMB_D1/WE` | `setup` |
| 27 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMC/WE` | `setup` |
| 28 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMC_D1/WE` | `setup` |
| 29 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMD/WE` | `setup` |
| 30 | 1 | -0.542 | 5.038 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMD_D1/WE` | `setup` |
| 31 | 16 | -0.472 | 4.961 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_data][*]/R` | `setup` |
| 32 | 4 | -0.472 | 4.961 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_mask][*]/R` | `setup` |
| 33 | 48 | -0.425 | 4.803 | 7 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/btb_mem_reg/CLKARDCLK` | `student_top_inst/Mem_IROM/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/ADDRARDADDR[*]` | `setup` |
| 34 | 7 | -0.425 | 4.803 | 7 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/btb_mem_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/btb_mem_reg/ADDRARDADDR[*]` | `setup` |
| 35 | 32 | -0.408 | 5.004 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_data_q_reg[*]/CE` | `setup` |
| 36 | 30 | -0.408 | 5.004 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_addr_q_reg[*]/CE` | `setup` |
| 37 | 11 | -0.408 | 5.004 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_index_q_reg[*]/CE` | `setup` |
| 38 | 4 | -0.408 | 5.004 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_mask_q_reg[*]/CE` | `setup` |
| 39 | 3 | -0.408 | 5.004 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_tag_q_reg[*]/CE` | `setup` |
| 40 | 2 | -0.408 | 5.004 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_word_q_reg[*]/CE` | `setup` |
| 41 | 1 | -0.408 | 5.004 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_write_q_reg/CE` | `setup` |
| 42 | 30 | -0.389 | 4.985 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/req_addr_q_reg[*]/CE` | `setup` |
| 43 | 28 | -0.380 | 5.224 | 13 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/D` | `setup` |
| 44 | 6 | -0.345 | 4.941 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/FSM_onehot_state_q_reg[*]/CE` | `setup` |
| 45 | 1 | -0.330 | 5.161 | 9 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/btb_mem_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/pht_collision_q_reg/D` | `setup` |
| 46 | 1 | -0.299 | 5.130 | 9 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/btb_mem_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/btb_collision_q_reg/D` | `setup` |
| 47 | 32 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/CE` | `setup` |
| 48 | 32 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/CE` | `setup` |
| 49 | 32 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/CE` | `setup` |
| 50 | 32 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][imm][*]/CE` | `setup` |
| 51 | 32 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][pc][*]/CE` | `setup` |
| 52 | 32 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][pred_next_pc][*]/CE` | `setup` |
| 53 | 8 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][pred_index][*]/CE` | `setup` |
| 54 | 7 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][instr][*]/CE` | `setup` |
| 55 | 5 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][rd][*]/CE` | `setup` |
| 56 | 4 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][alu_op][*]/CE` | `setup` |
| 57 | 4 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][rs1][*]/CE` | `setup` |
| 58 | 3 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[trans_id][*]/CE` | `setup` |
| 59 | 3 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][branch_op][*]/CE` | `setup` |
| 60 | 3 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][fu][*]/CE` | `setup` |
| 61 | 3 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][muldiv_op][*]/CE` | `setup` |
| 62 | 2 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][mem_size][*]/CE` | `setup` |
| 63 | 2 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][pred_counter][*]/CE` | `setup` |
| 64 | 1 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][is_jal]/CE` | `setup` |
| 65 | 1 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][is_jalr]/CE` | `setup` |
| 66 | 1 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][load_unsigned]/CE` | `setup` |
| 67 | 1 | -0.196 | 4.792 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[uop][uses_rs2]/CE` | `setup` |
| 68 | 32 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_tval][*]/CE` | `setup` |
| 69 | 32 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[imm][*]/CE` | `setup` |
| 70 | 32 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[pc][*]/CE` | `setup` |
| 71 | 32 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[pred_next_pc][*]/CE` | `setup` |
| 72 | 12 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[csr_addr][*]/CE` | `setup` |
| 73 | 8 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[pred_index][*]/CE` | `setup` |
| 74 | 7 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[instr][*]/CE` | `setup` |
| 75 | 5 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rd][*]/CE` | `setup` |
| 76 | 5 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/CE` | `setup` |
| 77 | 5 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs2][*]/CE` | `setup` |
| 78 | 4 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[alu_op][*]/CE` | `setup` |
| 79 | 3 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[branch_op][*]/CE` | `setup` |
| 80 | 3 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_cause][*]/CE` | `setup` |
| 81 | 3 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[fu][*]/CE` | `setup` |
| 82 | 3 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[muldiv_op][*]/CE` | `setup` |
| 83 | 3 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[sys_op][*]/CE` | `setup` |
| 84 | 2 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[csr_op][*]/CE` | `setup` |
| 85 | 2 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[mem_size][*]/CE` | `setup` |
| 86 | 2 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[pred_counter][*]/CE` | `setup` |
| 87 | 2 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]_rep/CE` | `setup` |
| 88 | 2 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]_rep__0/CE` | `setup` |
| 89 | 1 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[csr_imm]/CE` | `setup` |
| 90 | 1 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_valid]/CE` | `setup` |
| 91 | 1 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[is_jal]/CE` | `setup` |
| 92 | 1 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[is_jalr]/CE` | `setup` |
| 93 | 1 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[load_unsigned]/CE` | `setup` |
| 94 | 1 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]_rep__1/CE` | `setup` |
| 95 | 1 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[serialize]/CE` | `setup` |
| 96 | 1 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[uses_rs1]/CE` | `setup` |
| 97 | 1 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[uses_rs2]/CE` | `setup` |
| 98 | 1 | -0.193 | 4.789 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[writes_rd]/CE` | `setup` |
| 99 | 25 | -0.180 | 5.011 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/D` | `setup` |
| 100 | 10 | -0.180 | 5.011 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/D` | `setup` |
| 101 | 256 | -0.172 | 4.768 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][link_addr][*]/CE` | `setup` |
| 102 | 256 | -0.172 | 4.768 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][pc][*]/CE` | `setup` |
| 103 | 96 | -0.172 | 4.768 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][csr_addr][*]/CE` | `setup` |
| 104 | 40 | -0.172 | 4.768 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][rd][*]/CE` | `setup` |
| 105 | 24 | -0.172 | 4.768 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][fu][*]/CE` | `setup` |
| 106 | 24 | -0.172 | 4.768 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][sys_op][*]/CE` | `setup` |
| 107 | 16 | -0.172 | 4.768 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][csr_op][*]/CE` | `setup` |
| 108 | 8 | -0.172 | 4.768 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][is_call]/CE` | `setup` |
| 109 | 8 | -0.172 | 4.768 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][is_return]/CE` | `setup` |
| 110 | 8 | -0.172 | 4.768 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][writes_rd]/CE` | `setup` |
| 111 | 256 | -0.149 | 4.745 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][exception_tval][*]/CE` | `setup` |
| 112 | 32 | -0.149 | 4.745 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][exception_cause][*]/CE` | `setup` |
| 113 | 8 | -0.149 | 4.745 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][exception_valid]/CE` | `setup` |
| 114 | 64 | -0.106 | 4.702 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][addr][*]/CE` | `setup` |
| 115 | 64 | -0.106 | 4.702 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_data][*]/CE` | `setup` |
| 116 | 16 | -0.106 | 4.702 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][store_seq_cutoff][*]/CE` | `setup` |
| 117 | 8 | -0.106 | 4.702 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_mask][*]/CE` | `setup` |
| 118 | 6 | -0.106 | 4.702 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][trans_id][*]/CE` | `setup` |
| 119 | 4 | -0.106 | 4.702 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][size][*]/CE` | `setup` |
| 120 | 4 | -0.098 | 4.694 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/count_o_reg[*]/CE` | `setup` |
| 121 | 8 | -0.089 | 4.920 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/D` | `setup` |
| 122 | 1 | -0.005 | 4.836 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/count_q_reg[*]/D` | `setup` |
| 123 | 256 | -0.002 | 4.598 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][result][*]/CE` | `setup` |
