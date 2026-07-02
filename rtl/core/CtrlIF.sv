//------------------------------------------------------------------------------
// CtrlIF.sv
// 作用：定义全流水控制接口，承载各级 stall/flush 和资源阻塞请求。
// 微架构定位：CtrlUnit 根据 RecoveryManager 的恢复事件、ROB/IQ/FreeList 资源状态、
// serialBlock 和各级本地 stallReq 生成每个流水级的 PipeCtrlPath。该接口不传
// 业务 payload，不承载 recoverPc；flush 优先级应高于 stall，避免错误路径被保持。
//------------------------------------------------------------------------------

  import BasicTypes::*;
  import PipelineTypes::*;

  interface CtrlIF(
      input logic clk,
      input logic rst
  );

      PipeCtrlPath pfPipe;
      PipeCtrlPath ifPipe;
      PipeCtrlPath idPipe;
      PipeCtrlPath rnPipe;
      PipeCtrlPath dsPipe;
      PipeCtrlPath isPipe;
      PipeCtrlPath rrPipe;
      PipeCtrlPath exPipe;
      PipeCtrlPath wbPipe;

      // 各级向 Ctrl 请求 stall
      logic idStallReq;
      logic rnStallReq;
      logic dsStallReq;
      logic isStallReq;
      logic rrStallReq;
      logic exStallReq;
      logic wbStallReq;

      // 资源/顺序化阻塞
      logic robFull;
      logic issueQueueFull;
      logic freeListEmpty;
      logic serialBlock;

      // 可选：用于判断是否可以安全处理 serial/system inst
      logic idStageEmpty;
      logic rnStageEmpty;
      logic dsStageEmpty;
      logic isStageEmpty;
      logic rrStageEmpty;
      logic exStageEmpty;
      logic aluStageEmpty;
      logic memStageEmpty;
      logic mulStageEmpty;
      logic brcStageEmpty;
      logic sysStageEmpty;
      logic wbStageEmpty;

      modport CtrlUnit(
          input  clk,
          input  rst,

          input  idStallReq,
          input  rnStallReq,
          input  dsStallReq,
          input  isStallReq,
          input  rrStallReq,
          input  exStallReq,
          input  wbStallReq,

          input  robFull,
          input  issueQueueFull,
          input  freeListEmpty,
          input  serialBlock,

          input  idStageEmpty,
          input  rnStageEmpty,
          input  dsStageEmpty,
          input  isStageEmpty,
          input  rrStageEmpty,
          input  aluStageEmpty,
          input  memStageEmpty,
          input  mulStageEmpty,
          input  brcStageEmpty,
          input  sysStageEmpty,
          input  wbStageEmpty,

          output pfPipe,
          output ifPipe,
          output idPipe,
          output rnPipe,
          output dsPipe,
          output isPipe,
          output rrPipe,
          output exPipe,
          output wbPipe,
          output exStageEmpty
      );

      modport PreFetchStage(
          input pfPipe
      );

      modport FetchStage(
          input ifPipe
      );

      modport DecodeStage(
          input  idPipe,
          input  rnPipe,
          output idStallReq,
          output idStageEmpty
      );

      modport RenameStage(
          input  rnPipe,
          input  dsStageEmpty,
          input  isStageEmpty,
          input  rrStageEmpty,
          input  exStageEmpty,
          input  wbStageEmpty,
          output rnStallReq,
          output rnStageEmpty,
          output freeListEmpty
      );

      modport DispatchStage(
          input  dsPipe,
          output dsStallReq,
          output dsStageEmpty,
          output robFull,
          output issueQueueFull
      );

      modport IssueStage(
          input  isPipe,
          output isStallReq,
          output isStageEmpty
      );

      modport ReadRegStage(
          input  rrPipe,
          output rrStallReq,
          output rrStageEmpty
      );

      modport ExecuteStage(
          input  exPipe,
          output exStallReq,
          output aluStageEmpty,
          output memStageEmpty,
          output mulStageEmpty,
          output brcStageEmpty,
          output sysStageEmpty
      );

      modport WriteBackStage(
          input  wbPipe,
          output wbStallReq,
          output wbStageEmpty
      );

      modport CommitStage(
          output serialBlock
      );

  endinterface
