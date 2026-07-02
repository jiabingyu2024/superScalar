import BasicTypes::*;
import RenameTypes::*;

module ArchRAT(ArchRATIF.ArchRAT self);
    PhyRegNumPath rat [LOGICREG_NUM];

    integer i;

    always_ff @(posedge self.clk or posedge self.rst) begin
        if (self.rst) begin
            for (i = 0; i < LOGICREG_NUM; i++) begin
                rat[i] <= PhyRegNumPath'(i);
            end
        end else begin
            for (i = 0; i < ARCHRAT_WRITE_PORT_NUM; i++) begin
                if (self.archRATUpdate[i].UpdateEn &&
                    self.archRATUpdate[i].UpdateLgcRegNum != '0) begin
                    rat[self.archRATUpdate[i].UpdateLgcRegNum] <= self.archRATUpdate[i].UpdatePhyRegNum;
                end
            end
            rat[0] <= '0;
        end
    end
endmodule
