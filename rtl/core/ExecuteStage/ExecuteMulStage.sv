import BasicTypes::*;
import PipelineTypes::*;
import ReadRegTypes::*;

module ExecuteMulStage(
    ReadRegStageIF.ExecuteMulStage prev,
    ExecuteStageIF.ExecuteMulStage self,
    CtrlIF.ExecuteStage ctrl,
    BypassIF.ExecuteMulStage bypass
);
    localparam int MUL_LATENCY = 2;
    localparam int DIV_LATENCY = 34;

    RrToExMulPath pipeReg [MUL_ISSUE_WIDTH];

    typedef struct packed {
        logic         valid;
        MulSubType    mulSubType;
        PhyRegNumPath Rd;
        logic         writeRd;
        RobIndexPath  robIndex;
        WayNumPath    lane;
    } MulMetaPath;

    typedef struct packed {
        logic         valid;
        SubTypePath   subType;
        PhyRegNumPath Rd;
        logic         writeRd;
        RobIndexPath  robIndex;

        logic         divByZero;
        logic         overflow;
        logic         quotNeg;
        logic         remNeg;
        DataPath      origA;

        DataPath      dividend;
        DataPath      divisor;
        WayNumPath    lane;
    } DivPipeEntry;

    MulMetaPath mulMetaPipe [0:MUL_LATENCY];
    MulMetaPath mulLaunch;
    logic signed [32:0] mulA;
    logic signed [32:0] mulB;
    logic signed [65:0] mulProduct;

    DivPipeEntry divMetaPipe [0:DIV_LATENCY];
    DivPipeEntry divLaunch;
    logic        divInputValid;
    logic        divDividendReady;
    logic        divDivisorReady;
    DataPath     divDividend;
    DataPath     divDivisor;
    logic        divOutputValid;
    logic [63:0] divOutputData;

    function automatic logic is_divrem(input SubTypePath st);
        return st.mulSubType inside {MUL_SUBTYPE_DIV, MUL_SUBTYPE_DIVU,
                                     MUL_SUBTYPE_REM, MUL_SUBTYPE_REMU};
    endfunction

    function automatic DataPath abs32(input DataPath value);
        return value[31] ? DataPath'(~value + 32'd1) : value;
    endfunction

    function automatic logic signed [32:0] mul_operand_a(
        input MulSubType st,
        input DataPath value
    );
        unique case (st)
            MUL_SUBTYPE_MULHU: mul_operand_a = {1'b0, value};
            default:           mul_operand_a = {value[31], value};
        endcase
    endfunction

    function automatic logic signed [32:0] mul_operand_b(
        input MulSubType st,
        input DataPath value
    );
        unique case (st)
            MUL_SUBTYPE_MULH:  mul_operand_b = {value[31], value};
            default:           mul_operand_b = {1'b0, value};
        endcase
    endfunction

    function automatic DataPath mul_result(
        input MulSubType st,
        input logic signed [65:0] product
    );
        unique case (st)
            MUL_SUBTYPE_MULH,
            MUL_SUBTYPE_MULHSU,
            MUL_SUBTYPE_MULHU: mul_result = product[63:32];
            default:           mul_result = product[31:0];
        endcase
    endfunction

    function automatic DataPath div_result(
        input DivPipeEntry in,
        input DataPath quotientIn,
        input DataPath remainderIn
    );
        DataPath quotient;
        DataPath remainder;

        quotient = in.quotNeg ? DataPath'(~quotientIn + 32'd1) : quotientIn;
        remainder = in.remNeg ? DataPath'(~remainderIn + 32'd1) : remainderIn;

        if (in.divByZero) begin
            if (in.subType.mulSubType inside {MUL_SUBTYPE_REM, MUL_SUBTYPE_REMU}) begin
                div_result = in.origA;
            end else begin
                div_result = 32'hffff_ffff;
            end
        end else if (in.overflow) begin
            if (in.subType.mulSubType == MUL_SUBTYPE_REM) begin
                div_result = '0;
            end else begin
                div_result = 32'h8000_0000;
            end
        end else begin
            unique case (in.subType.mulSubType)
                MUL_SUBTYPE_DIV,
                MUL_SUBTYPE_DIVU: div_result = quotient;
                default:          div_result = remainder;
            endcase
        end
    endfunction

    MUL_0 mul_ip (
        .CLK(self.clk),
        .A  (mulA),
        .B  (mulB),
        .P  (mulProduct)
    );

    DIV_0 div_ip (
        .aclk                    (self.clk),
        .s_axis_dividend_tvalid  (divInputValid),
        .s_axis_dividend_tready  (divDividendReady),
        .s_axis_dividend_tdata   (divDividend),
        .s_axis_divisor_tvalid   (divInputValid),
        .s_axis_divisor_tready   (divDivisorReady),
        .s_axis_divisor_tdata    (divDivisor),
        .m_axis_dout_tvalid      (divOutputValid),
        .m_axis_dout_tdata       (divOutputData)
    );

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < MUL_ISSUE_WIDTH; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (ctrl.exPipe.flush) begin
            for (int i = 0; i < MUL_ISSUE_WIDTH; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (!ctrl.exPipe.stall) begin
            pipeReg <= prev.nextToMulStage;
        end
    end

    always_comb begin
        ctrl.mulStageEmpty = 1'b1;
        mulLaunch = '0;
        mulA = '0;
        mulB = '0;
        divLaunch = '0;
        divInputValid = 1'b0;
        divDividend = '0;
        divDivisor = 32'd1;

        for (int i = 0; i < BYPASS_READ_PORT_NUM; i++) bypass.mulReadReq[i] = '0;

        for (int i = 0; i < MUL_ISSUE_WIDTH; i++) begin
            DataPath a;
            DataPath b;
            logic signedOp;

            bypass.mulReadReq[i*2+0].valid = pipeReg[i].valid && pipeReg[i].srcAIsRs1;
            bypass.mulReadReq[i*2+0].phyRegNum = pipeReg[i].Rs1;
            bypass.mulReadReq[i*2+1].valid = pipeReg[i].valid && pipeReg[i].srcBIsRs2;
            bypass.mulReadReq[i*2+1].phyRegNum = pipeReg[i].Rs2;
            a = bypass.mulReadRes[i*2+0].hit ? bypass.mulReadRes[i*2+0].data : pipeReg[i].dataA;
            b = bypass.mulReadRes[i*2+1].hit ? bypass.mulReadRes[i*2+1].data : pipeReg[i].dataB;

            if (pipeReg[i].valid && !ctrl.exPipe.flush && !ctrl.exPipe.stall &&
                !is_divrem(pipeReg[i].subType) && !mulLaunch.valid) begin
                mulLaunch.valid = 1'b1;
                mulLaunch.mulSubType = pipeReg[i].subType.mulSubType;
                mulLaunch.Rd = pipeReg[i].Rd;
                mulLaunch.writeRd = pipeReg[i].writeRd;
                mulLaunch.robIndex = pipeReg[i].robIndex;
                mulLaunch.lane = WayNumPath'(i);
                mulA = mul_operand_a(pipeReg[i].subType.mulSubType, a);
                mulB = mul_operand_b(pipeReg[i].subType.mulSubType, b);
            end

            if (pipeReg[i].valid && !ctrl.exPipe.flush && !ctrl.exPipe.stall &&
                is_divrem(pipeReg[i].subType) && !divLaunch.valid) begin
                divLaunch.valid = 1'b1;
                divLaunch.subType = pipeReg[i].subType;
                divLaunch.Rd = pipeReg[i].Rd;
                divLaunch.writeRd = pipeReg[i].writeRd;
                divLaunch.robIndex = pipeReg[i].robIndex;
                divLaunch.origA = a;
                divLaunch.lane = WayNumPath'(i);
                signedOp = pipeReg[i].subType.mulSubType inside {MUL_SUBTYPE_DIV, MUL_SUBTYPE_REM};
                divLaunch.divByZero = (b == '0);
                divLaunch.overflow = signedOp && (a == 32'h8000_0000) && (b == 32'hffff_ffff);
                divLaunch.quotNeg = signedOp && (a[31] ^ b[31]);
                divLaunch.remNeg = signedOp && a[31];
                divLaunch.dividend = signedOp ? abs32(a) : a;
                divLaunch.divisor = signedOp ? abs32(b) : b;
            end

            ctrl.mulStageEmpty &= !(pipeReg[i].valid && !ctrl.exPipe.flush);
        end

        for (int s = 0; s <= MUL_LATENCY; s++) begin
            ctrl.mulStageEmpty &= !mulMetaPipe[s].valid;
        end
        for (int s = 0; s <= DIV_LATENCY; s++) begin
            ctrl.mulStageEmpty &= !divMetaPipe[s].valid;
        end

        if (divLaunch.valid) begin
            divInputValid = 1'b1;
            divDividend = (divLaunch.divByZero || divLaunch.overflow) ? '0 : divLaunch.dividend;
            divDivisor = (divLaunch.divByZero || divLaunch.overflow) ? 32'd1 : divLaunch.divisor;
        end
    end

    always_comb begin
        for (int i = 0; i < MUL_WB_WIDTH; i++) begin
            self.nextMulToStage[i] = '0;
        end

        if (divMetaPipe[DIV_LATENCY].valid && divOutputValid) begin
            self.nextMulToStage[divMetaPipe[DIV_LATENCY].lane].valid = 1'b1;
            self.nextMulToStage[divMetaPipe[DIV_LATENCY].lane].Rd = divMetaPipe[DIV_LATENCY].Rd;
            self.nextMulToStage[divMetaPipe[DIV_LATENCY].lane].writeRd =
                divMetaPipe[DIV_LATENCY].writeRd;
            self.nextMulToStage[divMetaPipe[DIV_LATENCY].lane].data =
                div_result(divMetaPipe[DIV_LATENCY],
                           DataPath'(divOutputData[31:0]),
                           DataPath'(divOutputData[63:32]));
            self.nextMulToStage[divMetaPipe[DIV_LATENCY].lane].robIndex =
                divMetaPipe[DIV_LATENCY].robIndex;
        end

        if (mulMetaPipe[MUL_LATENCY].valid) begin
            self.nextMulToStage[mulMetaPipe[MUL_LATENCY].lane].valid = 1'b1;
            self.nextMulToStage[mulMetaPipe[MUL_LATENCY].lane].Rd = mulMetaPipe[MUL_LATENCY].Rd;
            self.nextMulToStage[mulMetaPipe[MUL_LATENCY].lane].writeRd =
                mulMetaPipe[MUL_LATENCY].writeRd;
            self.nextMulToStage[mulMetaPipe[MUL_LATENCY].lane].data =
                mul_result(mulMetaPipe[MUL_LATENCY].mulSubType, mulProduct);
            self.nextMulToStage[mulMetaPipe[MUL_LATENCY].lane].robIndex =
                mulMetaPipe[MUL_LATENCY].robIndex;
        end
    end

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int s = 0; s <= MUL_LATENCY; s++) begin
                mulMetaPipe[s] <= '0;
            end
            for (int s = 0; s <= DIV_LATENCY; s++) begin
                divMetaPipe[s] <= '0;
            end
        end else if (ctrl.exPipe.flush) begin
            for (int s = 0; s <= MUL_LATENCY; s++) begin
                mulMetaPipe[s] <= '0;
            end
            for (int s = 0; s <= DIV_LATENCY; s++) begin
                divMetaPipe[s] <= '0;
            end
        end else begin
            mulMetaPipe[0] <= mulLaunch;
            for (int s = 1; s <= MUL_LATENCY; s++) begin
                mulMetaPipe[s] <= mulMetaPipe[s-1];
            end

            divMetaPipe[0] <= divLaunch;
            for (int s = 1; s <= DIV_LATENCY; s++) begin
                divMetaPipe[s] <= divMetaPipe[s-1];
            end
        end
    end
endmodule
