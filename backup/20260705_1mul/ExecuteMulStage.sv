import BasicTypes::*;
import PipelineTypes::*;
import ReadRegTypes::*;

module ExecuteMulStage(
    ReadRegStageIF.ExecuteMulStage prev,
    ExecuteStageIF.ExecuteMulStage self,
    CtrlIF.ExecuteStage ctrl,
    BypassIF.ExecuteMulStage bypass
);
    localparam int MUL_LATENCY = 3;
    localparam int DIV_LATENCY = 36;

    RrToExMulPath pipeReg [WAY_NUM];

    typedef struct packed {
        logic         valid;
        MulSubType    mulSubType;
        PhyRegNumPath Rd;
        logic         writeRd;
        RobIndexPath  robIndex;
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
        DataPath      quotient;
        logic [32:0]  remainder;
        logic [5:0]   iterCount;
    } DivPipeEntry;

    MulMetaPath mulMetaPipe [WAY_NUM][0:MUL_LATENCY];
    MulMetaPath mulLaunch [WAY_NUM];
    logic signed [32:0] mulA [WAY_NUM];
    logic signed [32:0] mulB [WAY_NUM];
    logic signed [65:0] mulProduct [WAY_NUM];

    DivPipeEntry divPipe [WAY_NUM][DIV_LATENCY];
    DivPipeEntry divLaunch [WAY_NUM];
    ExMulToWbPath divOut [WAY_NUM];

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

    function automatic DivPipeEntry div_step(input DivPipeEntry in);
        DivPipeEntry out;
        logic [32:0] trial;
        logic [32:0] divisorExt;

        out = in;
        if (in.valid && !in.divByZero && !in.overflow && in.iterCount < 6'd32) begin
            trial = {in.remainder[31:0], in.dividend[31]};
            divisorExt = {1'b0, in.divisor};
            out.dividend = {in.dividend[30:0], 1'b0};
            out.iterCount = in.iterCount + 6'd1;
            if (trial >= divisorExt) begin
                out.remainder = trial - divisorExt;
                out.quotient = {in.quotient[30:0], 1'b1};
            end else begin
                out.remainder = trial;
                out.quotient = {in.quotient[30:0], 1'b0};
            end
        end
        return out;
    endfunction

    function automatic DataPath div_result(input DivPipeEntry in);
        DataPath quotient;
        DataPath remainder;

        quotient = in.quotNeg ? DataPath'(~in.quotient + 32'd1) : in.quotient;
        remainder = in.remNeg ? DataPath'(~in.remainder[31:0] + 32'd1) : in.remainder[31:0];

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

    genvar mul_gen;
    generate
        for (mul_gen = 0; mul_gen < WAY_NUM; mul_gen++) begin : gen_mul_ip
            MUL_0 mul_ip (
                .CLK(self.clk),
                .A  (mulA[mul_gen]),
                .B  (mulB[mul_gen]),
                .P  (mulProduct[mul_gen])
            );
        end
    endgenerate

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (ctrl.exPipe.flush) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                pipeReg[i] <= '0;
            end
        end else if (!ctrl.exPipe.stall) begin
            pipeReg <= prev.nextToMulStage;
        end
    end

    always_comb begin
        ctrl.mulStageEmpty = 1'b1;

        for (int i = 0; i < BYPASS_READ_PORT_NUM; i++) bypass.mulReadReq[i] = '0;

        for (int i = 0; i < WAY_NUM; i++) begin
            DataPath a;
            DataPath b;
            logic signedOp;

            mulLaunch[i] = '0;
            mulA[i] = '0;
            mulB[i] = '0;

            bypass.mulReadReq[i*2+0].valid = pipeReg[i].valid && pipeReg[i].srcAIsRs1;
            bypass.mulReadReq[i*2+0].phyRegNum = pipeReg[i].Rs1;
            bypass.mulReadReq[i*2+1].valid = pipeReg[i].valid && pipeReg[i].srcBIsRs2;
            bypass.mulReadReq[i*2+1].phyRegNum = pipeReg[i].Rs2;
            a = bypass.mulReadRes[i*2+0].hit ? bypass.mulReadRes[i*2+0].data : pipeReg[i].dataA;
            b = bypass.mulReadRes[i*2+1].hit ? bypass.mulReadRes[i*2+1].data : pipeReg[i].dataB;

            if (pipeReg[i].valid && !ctrl.exPipe.flush && !ctrl.exPipe.stall &&
                !is_divrem(pipeReg[i].subType)) begin
                mulLaunch[i].valid = 1'b1;
                mulLaunch[i].mulSubType = pipeReg[i].subType.mulSubType;
                mulLaunch[i].Rd = pipeReg[i].Rd;
                mulLaunch[i].writeRd = pipeReg[i].writeRd;
                mulLaunch[i].robIndex = pipeReg[i].robIndex;
                mulA[i] = mul_operand_a(pipeReg[i].subType.mulSubType, a);
                mulB[i] = mul_operand_b(pipeReg[i].subType.mulSubType, b);
            end

            divLaunch[i] = '0;
            divLaunch[i].valid = pipeReg[i].valid &&
                                 !ctrl.exPipe.flush &&
                                 !ctrl.exPipe.stall &&
                                 is_divrem(pipeReg[i].subType);
            divLaunch[i].subType = pipeReg[i].subType;
            divLaunch[i].Rd = pipeReg[i].Rd;
            divLaunch[i].writeRd = pipeReg[i].writeRd;
            divLaunch[i].robIndex = pipeReg[i].robIndex;
            divLaunch[i].origA = a;
            signedOp = pipeReg[i].subType.mulSubType inside {MUL_SUBTYPE_DIV, MUL_SUBTYPE_REM};
            divLaunch[i].divByZero = (b == '0);
            divLaunch[i].overflow = signedOp && (a == 32'h8000_0000) && (b == 32'hffff_ffff);
            divLaunch[i].quotNeg = signedOp && (a[31] ^ b[31]);
            divLaunch[i].remNeg = signedOp && a[31];
            divLaunch[i].dividend = signedOp ? abs32(a) : a;
            divLaunch[i].divisor = signedOp ? abs32(b) : b;
            divLaunch[i].quotient = '0;
            divLaunch[i].remainder = '0;
            divLaunch[i].iterCount = '0;

            ctrl.mulStageEmpty &= !(pipeReg[i].valid && !ctrl.exPipe.flush);
            for (int s = 0; s < DIV_LATENCY; s++) begin
                ctrl.mulStageEmpty &= !divPipe[i][s].valid;
            end
            ctrl.mulStageEmpty &= !divOut[i].valid;
        end

        for (int i = 0; i < WAY_NUM; i++) begin
            for (int s = 0; s <= MUL_LATENCY; s++) begin
                ctrl.mulStageEmpty &= !mulMetaPipe[i][s].valid;
            end
        end
    end

    always_comb begin
        for (int i = 0; i < WAY_NUM; i++) begin
            self.nextMulToStage[i] = divOut[i];
        end

        for (int i = 0; i < WAY_NUM; i++) begin
            if (mulMetaPipe[i][MUL_LATENCY].valid) begin
                self.nextMulToStage[i].valid = 1'b1;
                self.nextMulToStage[i].Rd = mulMetaPipe[i][MUL_LATENCY].Rd;
                self.nextMulToStage[i].writeRd = mulMetaPipe[i][MUL_LATENCY].writeRd;
                self.nextMulToStage[i].data =
                    mul_result(mulMetaPipe[i][MUL_LATENCY].mulSubType, mulProduct[i]);
                self.nextMulToStage[i].robIndex = mulMetaPipe[i][MUL_LATENCY].robIndex;
            end
        end
    end

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                for (int s = 0; s <= MUL_LATENCY; s++) begin
                    mulMetaPipe[i][s] <= '0;
                end
                for (int s = 0; s < DIV_LATENCY; s++) begin
                    divPipe[i][s] <= '0;
                end
                divOut[i] <= '0;
            end
        end else if (ctrl.exPipe.flush) begin
            for (int i = 0; i < WAY_NUM; i++) begin
                for (int s = 0; s <= MUL_LATENCY; s++) begin
                    mulMetaPipe[i][s] <= '0;
                end
                for (int s = 0; s < DIV_LATENCY; s++) begin
                    divPipe[i][s] <= '0;
                end
                divOut[i] <= '0;
            end
        end else begin
            for (int i = 0; i < WAY_NUM; i++) begin
                mulMetaPipe[i][0] <= mulLaunch[i];
                for (int s = 1; s <= MUL_LATENCY; s++) begin
                    mulMetaPipe[i][s] <= mulMetaPipe[i][s-1];
                end

                divOut[i] <= '0;
                if (divPipe[i][DIV_LATENCY-1].valid) begin
                    divOut[i].valid <= 1'b1;
                    divOut[i].Rd <= divPipe[i][DIV_LATENCY-1].Rd;
                    divOut[i].writeRd <= divPipe[i][DIV_LATENCY-1].writeRd;
                    divOut[i].data <= div_result(divPipe[i][DIV_LATENCY-1]);
                    divOut[i].robIndex <= divPipe[i][DIV_LATENCY-1].robIndex;
                end

                divPipe[i][0] <= divLaunch[i];
                for (int s = 1; s < DIV_LATENCY; s++) begin
                    divPipe[i][s] <= div_step(divPipe[i][s-1]);
                end
            end
        end
    end
endmodule
