# 全量 setup 违例路径聚类

- 原始违例路径数：835
- 聚类数：83
- 聚类规则：仅把数字位选和综合复制后缀归一化；每一条原始路径仍保留在 CSV/RPT。

## 模块级覆盖矩阵

| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点模块 | 终点模块 |
|---:|---:|---:|---:|---:|---|---|
| 1 | 418 | -0.739 | 5.583 | 14 | `Core.DCache` | `Core.Other` |
| 2 | 120 | -0.635 | 5.102 | 9 | `Core.Other` | `Core.DCache` |
| 3 | 210 | -0.490 | 5.086 | 6 | `Core.DCache` | `Core.DecodeStage` |
| 4 | 47 | -0.487 | 5.071 | 7 | `Core.DCache` | `Core.ProducerMap` |
| 5 | 5 | -0.296 | 5.127 | 7 | `Core.DCache` | `Core.Frontend` |
| 6 | 35 | -0.180 | 5.011 | 7 | `Core.DCache` | `Core.ExecuteStage` |

## 精细起终点族

| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点族 | 终点族 | 时钟组 |
|---:|---:|---:|---:|---:|---|---|---|
| 1 | 31 | -0.739 | 5.583 | 14 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/D` | `setup` |
| 2 | 1 | -0.635 | 5.102 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/ENBWREN` | `setup` |
| 3 | 32 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_tval][*]/CE` | `setup` |
| 4 | 32 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[imm][*]/CE` | `setup` |
| 5 | 32 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[pc][*]/CE` | `setup` |
| 6 | 32 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[pred_next_pc][*]/CE` | `setup` |
| 7 | 12 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[csr_addr][*]/CE` | `setup` |
| 8 | 8 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[pred_index][*]/CE` | `setup` |
| 9 | 7 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[instr][*]/CE` | `setup` |
| 10 | 5 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rd][*]/CE` | `setup` |
| 11 | 5 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]/CE` | `setup` |
| 12 | 5 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs2][*]/CE` | `setup` |
| 13 | 4 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[alu_op][*]/CE` | `setup` |
| 14 | 3 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[branch_op][*]/CE` | `setup` |
| 15 | 3 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_cause][*]/CE` | `setup` |
| 16 | 3 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[fu][*]/CE` | `setup` |
| 17 | 3 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[muldiv_op][*]/CE` | `setup` |
| 18 | 3 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[sys_op][*]/CE` | `setup` |
| 19 | 2 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[csr_op][*]/CE` | `setup` |
| 20 | 2 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[mem_size][*]/CE` | `setup` |
| 21 | 2 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[pred_counter][*]/CE` | `setup` |
| 22 | 2 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]_rep/CE` | `setup` |
| 23 | 2 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]_rep__0/CE` | `setup` |
| 24 | 2 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[rs1][*]_rep__1/CE` | `setup` |
| 25 | 1 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[csr_imm]/CE` | `setup` |
| 26 | 1 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[exception_valid]/CE` | `setup` |
| 27 | 1 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[is_jal]/CE` | `setup` |
| 28 | 1 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[is_jalr]/CE` | `setup` |
| 29 | 1 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[load_unsigned]/CE` | `setup` |
| 30 | 1 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[serialize]/CE` | `setup` |
| 31 | 1 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[uses_rs1]/CE` | `setup` |
| 32 | 1 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[uses_rs2]/CE` | `setup` |
| 33 | 1 | -0.490 | 5.086 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_uop_q_reg[writes_rd]/CE` | `setup` |
| 34 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMA/WE` | `setup` |
| 35 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMA_D1/WE` | `setup` |
| 36 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMB/WE` | `setup` |
| 37 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMB_D1/WE` | `setup` |
| 38 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMC/WE` | `setup` |
| 39 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMC_D1/WE` | `setup` |
| 40 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMD/WE` | `setup` |
| 41 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMD_D1/WE` | `setup` |
| 42 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMA/WE` | `setup` |
| 43 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMA_D1/WE` | `setup` |
| 44 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMB/WE` | `setup` |
| 45 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMB_D1/WE` | `setup` |
| 46 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMC/WE` | `setup` |
| 47 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMC_D1/WE` | `setup` |
| 48 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMD/WE` | `setup` |
| 49 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMD_D1/WE` | `setup` |
| 50 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMA/WE` | `setup` |
| 51 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMA_D1/WE` | `setup` |
| 52 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMB/WE` | `setup` |
| 53 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMB_D1/WE` | `setup` |
| 54 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMC/WE` | `setup` |
| 55 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMC_D1/WE` | `setup` |
| 56 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMD/WE` | `setup` |
| 57 | 1 | -0.487 | 4.983 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMD_D1/WE` | `setup` |
| 58 | 16 | -0.470 | 4.959 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_data][*]/R` | `setup` |
| 59 | 4 | -0.470 | 4.959 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_mask][*]/R` | `setup` |
| 60 | 4 | -0.427 | 5.023 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/count_o_reg[*]/CE` | `setup` |
| 61 | 32 | -0.407 | 5.003 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_data_q_reg[*]/CE` | `setup` |
| 62 | 30 | -0.407 | 5.003 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_addr_q_reg[*]/CE` | `setup` |
| 63 | 11 | -0.407 | 5.003 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_index_q_reg[*]/CE` | `setup` |
| 64 | 4 | -0.407 | 5.003 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_mask_q_reg[*]/CE` | `setup` |
| 65 | 3 | -0.407 | 5.003 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_tag_q_reg[*]/CE` | `setup` |
| 66 | 2 | -0.407 | 5.003 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_word_q_reg[*]/CE` | `setup` |
| 67 | 1 | -0.407 | 5.003 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_write_q_reg/CE` | `setup` |
| 68 | 30 | -0.388 | 4.984 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/req_addr_q_reg[*]/CE` | `setup` |
| 69 | 6 | -0.344 | 4.940 | 9 | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/C` | `student_top_inst/Core_cpu/u_core_top/u_dcache/FSM_onehot_state_q_reg[*]/CE` | `setup` |
| 70 | 3 | -0.296 | 5.127 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/count_q_reg[*]/D` | `setup` |
| 71 | 2 | -0.296 | 5.127 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_fetch_queue/head_q_reg[*]/D` | `setup` |
| 72 | 1 | -0.296 | 5.127 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_valid_q_reg/D` | `setup` |
| 73 | 23 | -0.240 | 5.071 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_valid_q_reg[*]/D` | `setup` |
| 74 | 25 | -0.180 | 5.011 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/D` | `setup` |
| 75 | 10 | -0.180 | 5.011 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/D` | `setup` |
| 76 | 8 | -0.177 | 5.008 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/D` | `setup` |
| 77 | 64 | -0.104 | 4.700 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][addr][*]/CE` | `setup` |
| 78 | 64 | -0.104 | 4.700 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_data][*]/CE` | `setup` |
| 79 | 16 | -0.104 | 4.700 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][store_seq_cutoff][*]/CE` | `setup` |
| 80 | 8 | -0.104 | 4.700 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_mask][*]/CE` | `setup` |
| 81 | 6 | -0.104 | 4.700 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][trans_id][*]/CE` | `setup` |
| 82 | 4 | -0.104 | 4.700 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][size][*]/CE` | `setup` |
| 83 | 192 | -0.035 | 4.631 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][result][*]/CE` | `setup` |
