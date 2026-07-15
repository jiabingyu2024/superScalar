# 全量 setup 违例路径聚类

- 原始违例路径数：1759
- 聚类数：132
- 聚类规则：仅把数字位选和综合复制后缀归一化；每一条原始路径仍保留在 CSV/RPT。

## 模块级覆盖矩阵

| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点模块 | 终点模块 |
|---:|---:|---:|---:|---:|---|---|
| 1 | 340 | -4.721 | 9.187 | 18 | `Core.DCache` | `Core.DCache` |
| 2 | 1254 | -4.021 | 8.727 | 23 | `Core.DCache` | `Core.Other` |
| 3 | 14 | -1.269 | 6.100 | 12 | `Core.Frontend` | `Core.Frontend` |
| 4 | 56 | -0.985 | 5.816 | 10 | `Core.DCache` | `Core.ExecuteStage` |
| 5 | 48 | -0.756 | 5.134 | 8 | `Core.Frontend` | `SoC.Other` |
| 6 | 47 | -0.710 | 5.304 | 9 | `Core.DCache` | `Core.ProducerMap` |

## 精细起终点族

| # | 数量 | 最差 slack/ns | 最大 data path/ns | 最大逻辑级数 | 起点族 | 终点族 | 时钟组 |
|---:|---:|---:|---:|---:|---|---|---|
| 1 | 1 | -4.721 | 9.187 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/ENBWREN` | `setup` |
| 2 | 32 | -4.493 | 9.089 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_data_q_reg[*]/CE` | `setup` |
| 3 | 30 | -4.493 | 9.089 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_addr_q_reg[*]/CE` | `setup` |
| 4 | 11 | -4.493 | 9.089 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_index_q_reg[*]/CE` | `setup` |
| 5 | 4 | -4.493 | 9.089 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_mask_q_reg[*]/CE` | `setup` |
| 6 | 3 | -4.493 | 9.089 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_tag_q_reg[*]/CE` | `setup` |
| 7 | 2 | -4.493 | 9.089 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_word_q_reg[*]/CE` | `setup` |
| 8 | 1 | -4.493 | 9.089 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_write_q_reg/CE` | `setup` |
| 9 | 30 | -4.468 | 9.064 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/req_addr_q_reg[*]/CE` | `setup` |
| 10 | 6 | -4.430 | 9.026 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/FSM_onehot_state_q_reg[*]/CE` | `setup` |
| 11 | 16 | -4.021 | 8.510 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_data][*]/R` | `setup` |
| 12 | 4 | -4.021 | 8.510 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_mask][*]/R` | `setup` |
| 13 | 64 | -3.896 | 8.727 | 23 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_data][*]/D` | `setup` |
| 14 | 32 | -3.896 | 8.727 | 23 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[forward_data][*]/D` | `setup` |
| 15 | 1 | -3.891 | 8.722 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_valid_q_reg/D` | `setup` |
| 16 | 64 | -3.635 | 8.231 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][addr][*]/CE` | `setup` |
| 17 | 64 | -3.635 | 8.231 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_data][*]/CE` | `setup` |
| 18 | 16 | -3.635 | 8.231 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][store_seq_cutoff][*]/CE` | `setup` |
| 19 | 8 | -3.635 | 8.231 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_mask][*]/CE` | `setup` |
| 20 | 6 | -3.635 | 8.231 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][trans_id][*]/CE` | `setup` |
| 21 | 4 | -3.635 | 8.231 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][size][*]/CE` | `setup` |
| 22 | 32 | -3.604 | 8.200 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[forward_data][*]/CE` | `setup` |
| 23 | 4 | -3.604 | 8.200 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[forward_mask][*]/CE` | `setup` |
| 24 | 3 | -3.604 | 8.200 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[trans_id][*]/CE` | `setup` |
| 25 | 2 | -3.604 | 8.200 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[addr][*]/CE` | `setup` |
| 26 | 2 | -3.604 | 8.200 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[size][*]/CE` | `setup` |
| 27 | 44 | -3.601 | 7.979 | 16 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/ADDRBWRADDR[*]` | `setup` |
| 28 | 44 | -3.601 | 7.979 | 16 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/ADDRBWRADDR[*]` | `setup` |
| 29 | 11 | -3.601 | 7.979 | 16 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/ADDRBWRADDR[*]` | `setup` |
| 30 | 2 | -3.434 | 8.265 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][load_unsigned]/D` | `setup` |
| 31 | 1 | -3.410 | 8.241 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[load_unsigned]/D` | `setup` |
| 32 | 32 | -3.386 | 8.217 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_data_q_reg[*]/D` | `setup` |
| 33 | 4 | -3.363 | 8.194 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_store_buffer/committed_o_reg[*]/D` | `setup` |
| 34 | 4 | -3.363 | 8.194 | 18 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_store_buffer/entries_o_reg[*][valid]/D` | `setup` |
| 35 | 8 | -3.340 | 8.171 | 21 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][forward_mask][*]/D` | `setup` |
| 36 | 4 | -3.340 | 8.171 | 21 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[forward_mask][*]/D` | `setup` |
| 37 | 4 | -3.125 | 7.591 | 15 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_0/ENBWREN` | `setup` |
| 38 | 4 | -3.125 | 7.591 | 15 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/g_data_bank[*].u_data_bank/mem_q_reg_1/ENBWREN` | `setup` |
| 39 | 32 | -3.073 | 7.904 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_addr_q_reg[*]/D` | `setup` |
| 40 | 4 | -3.073 | 7.904 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_store_mask_q_reg[*]/D` | `setup` |
| 41 | 1 | -3.070 | 7.901 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_valid_q_reg_inv/D` | `setup` |
| 42 | 3 | -3.050 | 7.881 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_store_buffer/count_o_reg[*]/D` | `setup` |
| 43 | 2 | -3.050 | 7.881 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_store_buffer/head_o_reg[*]/D` | `setup` |
| 44 | 30 | -3.046 | 7.877 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/req_addr_q_reg[*]/D` | `setup` |
| 45 | 2 | -3.040 | 7.871 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/count_o_reg[*]/D` | `setup` |
| 46 | 3 | -3.034 | 7.865 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[trans_id][*]/D` | `setup` |
| 47 | 2 | -3.034 | 7.865 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[addr][*]/D` | `setup` |
| 48 | 2 | -3.034 | 7.865 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_meta_o_reg[size][*]/D` | `setup` |
| 49 | 63 | -3.026 | 7.857 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][addr][*]/D` | `setup` |
| 50 | 8 | -3.026 | 7.857 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][store_seq_cutoff][*]/D` | `setup` |
| 51 | 3 | -3.026 | 7.857 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][trans_id][*]/D` | `setup` |
| 52 | 2 | -3.026 | 7.857 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/entries_q_reg[*][size][*]/D` | `setup` |
| 53 | 1 | -3.018 | 7.849 | 17 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_load_queue/active_o_reg/D` | `setup` |
| 54 | 4 | -2.693 | 7.524 | 16 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_wstrb_q_reg[*]/D` | `setup` |
| 55 | 32 | -2.687 | 7.518 | 16 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_wdata_q_reg[*]/D` | `setup` |
| 56 | 1 | -2.687 | 7.518 | 16 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dmem_regslice/req_write_q_reg/D` | `setup` |
| 57 | 30 | -2.683 | 7.514 | 16 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_addr_q_reg[*]/D` | `setup` |
| 58 | 11 | -2.683 | 7.514 | 16 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_index_q_reg[*]/D` | `setup` |
| 59 | 3 | -2.683 | 7.514 | 16 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_tag_q_reg[*]/D` | `setup` |
| 60 | 2 | -2.683 | 7.514 | 16 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_dcache/lookup_word_q_reg[*]/D` | `setup` |
| 61 | 2 | -1.269 | 6.100 | 12 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/u_btb_bank/mem_q_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/read_pht_counter_q_reg[*]/D` | `setup` |
| 62 | 32 | -0.985 | 5.816 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op1][*]/D` | `setup` |
| 63 | 12 | -0.883 | 5.372 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][exception_tval][*]/R` | `setup` |
| 64 | 6 | -0.867 | 5.356 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][imm][*]/R` | `setup` |
| 65 | 2 | -0.846 | 5.335 | 7 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][csr_op][*]/R` | `setup` |
| 66 | 24 | -0.820 | 5.651 | 10 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_q_reg[op2][*]/D` | `setup` |
| 67 | 1 | -0.795 | 5.626 | 11 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/u_btb_bank/mem_q_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/pht_collision_q_reg/D` | `setup` |
| 68 | 48 | -0.756 | 5.134 | 8 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/u_btb_bank/mem_q_reg/CLKARDCLK` | `student_top_inst/Mem_IROM/U0/inst_blk_mem_gen/gnbram.gnativebmg.native_blk_mem_gen/valid.cstr/ramloop[*].ram.r/prim_init.ram/DEVICE_7SERIES.NO_BMM_INFO.SP.SIMPLE_PRIM36.ram/ADDRARDADDR[*]` | `setup` |
| 69 | 7 | -0.756 | 5.134 | 8 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/u_btb_bank/mem_q_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/u_btb_bank/mem_q_reg/ADDRARDADDR[*]` | `setup` |
| 70 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMA/WE` | `setup` |
| 71 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMA_D1/WE` | `setup` |
| 72 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMB/WE` | `setup` |
| 73 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMB_D1/WE` | `setup` |
| 74 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMC/WE` | `setup` |
| 75 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMC_D1/WE` | `setup` |
| 76 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMD/WE` | `setup` |
| 77 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r1_0_31_0_2/RAMD_D1/WE` | `setup` |
| 78 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMA/WE` | `setup` |
| 79 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMA_D1/WE` | `setup` |
| 80 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMB/WE` | `setup` |
| 81 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMB_D1/WE` | `setup` |
| 82 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMC/WE` | `setup` |
| 83 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMC_D1/WE` | `setup` |
| 84 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMD/WE` | `setup` |
| 85 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r2_0_31_0_2/RAMD_D1/WE` | `setup` |
| 86 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMA/WE` | `setup` |
| 87 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMA_D1/WE` | `setup` |
| 88 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMB/WE` | `setup` |
| 89 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMB_D1/WE` | `setup` |
| 90 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMC/WE` | `setup` |
| 91 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMC_D1/WE` | `setup` |
| 92 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMD/WE` | `setup` |
| 93 | 1 | -0.710 | 5.206 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_tid_q_reg_r3_0_31_0_2/RAMD_D1/WE` | `setup` |
| 94 | 192 | -0.672 | 5.503 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][result][*]/D` | `setup` |
| 95 | 96 | -0.652 | 5.248 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][result][*]/CE` | `setup` |
| 96 | 1 | -0.558 | 5.389 | 8 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_load_submitted_q_reg/D` | `setup` |
| 97 | 1 | -0.482 | 5.313 | 10 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/u_btb_bank/mem_q_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/btb_collision_q_reg/D` | `setup` |
| 98 | 23 | -0.473 | 5.304 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/producer_valid_q_reg[*]/D` | `setup` |
| 99 | 8 | -0.387 | 5.218 | 9 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/u_scoreboard/entries_q_reg[*][done]/D` | `setup` |
| 100 | 21 | -0.280 | 5.124 | 13 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/exec_mem_addr_q_reg[*]/D` | `setup` |
| 101 | 3 | -0.169 | 5.000 | 9 | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/u_btb_bank/mem_q_reg/CLKARDCLK` | `student_top_inst/Core_cpu/u_core_top/u_frontend/u_branch_predictor/read_pht_index_q_reg[*]/D` | `setup` |
| 102 | 64 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][exception_tval][*]/CE` | `setup` |
| 103 | 64 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][imm][*]/CE` | `setup` |
| 104 | 64 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][pc][*]/CE` | `setup` |
| 105 | 64 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][pred_next_pc][*]/CE` | `setup` |
| 106 | 24 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][csr_addr][*]/CE` | `setup` |
| 107 | 16 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][pred_index][*]/CE` | `setup` |
| 108 | 14 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][instr][*]/CE` | `setup` |
| 109 | 10 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][rd][*]/CE` | `setup` |
| 110 | 10 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][rs1][*]/CE` | `setup` |
| 111 | 10 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][rs2][*]/CE` | `setup` |
| 112 | 8 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][alu_op][*]/CE` | `setup` |
| 113 | 6 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][branch_op][*]/CE` | `setup` |
| 114 | 6 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][fu][*]/CE` | `setup` |
| 115 | 6 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][muldiv_op][*]/CE` | `setup` |
| 116 | 6 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][sys_op][*]/CE` | `setup` |
| 117 | 4 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][csr_op][*]/CE` | `setup` |
| 118 | 4 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][exception_cause][*]/CE` | `setup` |
| 119 | 4 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][mem_size][*]/CE` | `setup` |
| 120 | 4 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][pred_counter][*]/CE` | `setup` |
| 121 | 2 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][csr_imm]/CE` | `setup` |
| 122 | 2 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][exception_valid]/CE` | `setup` |
| 123 | 2 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][is_jal]/CE` | `setup` |
| 124 | 2 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][is_jalr]/CE` | `setup` |
| 125 | 2 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][load_unsigned]/CE` | `setup` |
| 126 | 2 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][rs1][*]_rep/CE` | `setup` |
| 127 | 2 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][rs1][*]_rep__0/CE` | `setup` |
| 128 | 2 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][serialize]/CE` | `setup` |
| 129 | 2 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][uses_rs1]/CE` | `setup` |
| 130 | 2 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][uses_rs2]/CE` | `setup` |
| 131 | 2 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][writes_rd]/CE` | `setup` |
| 132 | 1 | -0.094 | 4.690 | 6 | `student_top_inst/Core_cpu/u_core_top/u_dcache/u_tag_bank/mem_q_reg/CLKBWRCLK` | `student_top_inst/Core_cpu/u_core_top/id_entries_q_reg[*][rs1][*]_rep__1/CE` | `setup` |
