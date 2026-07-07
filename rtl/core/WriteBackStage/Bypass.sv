import BasicTypes::*;
import ReadRegTypes::*;

module Bypass(BypassIF.Bypass self);
    integer i;
    integer j;

    always_comb begin
        for (i = 0; i < BYPASS_READ_PORT_NUM; i++) begin
            self.aluReadRes[i] = '0;
            self.memReadRes[i] = '0;
            self.mulReadRes[i] = '0;
            self.brcReadRes[i] = '0;
            self.sysReadRes[i] = '0;
        end
        for (i = 0; i < INT_ISSUE_WIDTH * 2; i++) begin
            self.aluReadRes[i] = match(self.aluReadReq[i]);
            self.brcReadRes[i] = match(self.brcReadReq[i]);
            self.sysReadRes[i] = match(self.sysReadReq[i]);
        end
        for (i = 0; i < MEM_ISSUE_WIDTH * 2; i++) begin
            self.memReadRes[i] = match(self.memReadReq[i]);
        end
        for (i = 0; i < MUL_ISSUE_WIDTH * 2; i++) begin
            self.mulReadRes[i] = match(self.mulReadReq[i]);
        end
    end

    function automatic BypassReadResPath match(input BypassReadReqPath req);
        BypassReadResPath res;
        res.hit = 1'b0;
        res.data = '0;
        for (j = 0; j < BYPASS_WB_PORT_NUM; j++) begin
            if (req.valid && req.phyRegNum != '0 &&
                self.wbForward[j].valid && self.wbForward[j].writeRd &&
                self.wbForward[j].rd != '0 &&
                self.wbForward[j].rd == req.phyRegNum) begin
                res.hit = 1'b1;
                res.data = self.wbForward[j].data;
            end
        end
        return res;
    endfunction
endmodule
