import BasicTypes::*;
import ReadRegTypes::*;

module RegFile(RegFileIF.RegFile self);
    DataPath regs [PHYREG_NUM];

    integer i;

    always_comb begin
        for (i = 0; i < REGFILE_READ_PORT_NUM; i++) begin
            if (self.regFileReadReq[i].enaRead && self.regFileReadReq[i].regIndex != '0) begin
                self.regFileReadRes[i].data = regs[self.regFileReadReq[i].regIndex];
            end else begin
                self.regFileReadRes[i].data = '0;
            end
        end
    end

    always_ff @(negedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (i = 0; i < PHYREG_NUM; i++) begin
                regs[i] <= '0;
            end
        end else begin
            for (i = 0; i < REGFILE_WRITE_PORT_NUM; i++) begin
                if (self.regFileWriteReq[i].enaWrite && self.regFileWriteReq[i].regIndex != '0) begin
                    regs[self.regFileWriteReq[i].regIndex] <= self.regFileWriteReq[i].data;
                end
            end
            regs[0] <= '0;
        end
    end
endmodule
