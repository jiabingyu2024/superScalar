import BasicTypes::*;
import ReadRegTypes::*;

module Bypass(BypassIF.Bypass self);
    integer i;
    integer j;

    always_comb begin
        for (i = 0; i < BYPASS_READ_PORT_NUM; i++) begin
            self.aluReadRes[i] = match(self.aluReadReq[i]);
            self.memReadRes[i] = match(self.memReadReq[i]);
            self.mulReadRes[i] = match(self.mulReadReq[i]);
            self.brcReadRes[i] = match(self.brcReadReq[i]);
            self.sysReadRes[i] = match(self.sysReadReq[i]);
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
