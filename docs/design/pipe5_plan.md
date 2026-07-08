接下来我不准备使用超标量了
该分支采用普通的单发射顺序五级流水线riscv_cpu，需要支持rv32ui,rv32um,rv32mi,ecall,ebreak,fence
我需要做d-cathe,但不做i-cathe,我没有做cathe的经验
我现在预计的一个流水架构是
PC -IF -ID -EX -MA -WB
当前PC时，会把预计的nextPC值送往Irom和分支预测器,此时irom和分支预测器输出的pc的指令和分支预测结果,IF reg保存当前pc，IF阶段把分支预测结果，指令，pc打包送往id