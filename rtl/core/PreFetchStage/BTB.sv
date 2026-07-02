import BasicTypes::*;

module BTB #(
    parameter int ENTRY_NUM = 32,
    parameter int INDEX_WIDTH = $clog2(ENTRY_NUM),
    parameter int TAG_WIDTH = 10
) (
    input  logic  clk,
    input  logic  rst,

    input  PcPath lookupPc [WAY_NUM],
    output logic  hit      [WAY_NUM],
    output PcPath target   [WAY_NUM],

    input  logic  updateValid,
    input  PcPath updatePc,
    input  PcPath updateTarget
);
    localparam int PC_OFFSET_WIDTH = 2;

    logic [TAG_WIDTH-1:0] tagTable    [ENTRY_NUM];
    PcPath                targetTable [ENTRY_NUM];
    logic                 validTable  [ENTRY_NUM];

    function automatic logic [INDEX_WIDTH-1:0] get_index(input PcPath pc);
        get_index = pc[PC_OFFSET_WIDTH +: INDEX_WIDTH];
    endfunction

    function automatic logic [TAG_WIDTH-1:0] get_tag(input PcPath pc);
        get_tag = pc[PC_OFFSET_WIDTH + INDEX_WIDTH +: TAG_WIDTH];
    endfunction

    always_comb begin
        for (int i = 0; i < WAY_NUM; i++) begin
            logic [INDEX_WIDTH-1:0] index;
            logic [TAG_WIDTH-1:0]   tag;

            index = get_index(lookupPc[i]);
            tag = get_tag(lookupPc[i]);

            hit[i] = validTable[index] && (tagTable[index] == tag);
            target[i] = hit[i] ? targetTable[index] : (lookupPc[i] + PcPath'(4));
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            for (int i = 0; i < ENTRY_NUM; i++) begin
                validTable[i] <= 1'b0;
                tagTable[i] <= '0;
                targetTable[i] <= '0;
            end
        end else if (updateValid) begin
            logic [INDEX_WIDTH-1:0] updateIndex;

            updateIndex = get_index(updatePc);
            validTable[updateIndex] <= 1'b1;
            tagTable[updateIndex] <= get_tag(updatePc);
            targetTable[updateIndex] <= updateTarget;
        end
    end
endmodule
