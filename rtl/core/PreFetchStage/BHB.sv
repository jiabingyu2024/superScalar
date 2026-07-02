import BasicTypes::*;

module BHB #(
    parameter int PHT_ENTRY_NUM = 64,
    parameter int LOCAL_ENTRY_NUM = 64,
    parameter int PHT_INDEX_WIDTH = $clog2(PHT_ENTRY_NUM),
    parameter int LOCAL_INDEX_WIDTH = $clog2(LOCAL_ENTRY_NUM),
    parameter int LOCAL_HISTORY_WIDTH = 4,
    parameter int GLOBAL_HISTORY_WIDTH = 6
) (
    input  logic clk,
    input  logic rst,

    input  PcPath lookupPc [WAY_NUM],
    input  logic  lookupBtbHit [WAY_NUM],
    output logic  taken [WAY_NUM],

    input  logic  updateValid,
    input  PcPath updatePc,
    input  logic  updateTaken
);
    localparam int PC_OFFSET_WIDTH = 2;

    logic [GLOBAL_HISTORY_WIDTH-1:0] globalHistory;
    logic [LOCAL_HISTORY_WIDTH-1:0]  localHistoryTable [LOCAL_ENTRY_NUM];

    logic [1:0] globalPht [PHT_ENTRY_NUM];
    logic [1:0] localPht  [PHT_ENTRY_NUM];
    logic [1:0] chooser   [PHT_ENTRY_NUM];

    function automatic logic [LOCAL_INDEX_WIDTH-1:0] get_local_index(input PcPath pc);
        get_local_index = pc[PC_OFFSET_WIDTH +: LOCAL_INDEX_WIDTH];
    endfunction

    function automatic logic [PHT_INDEX_WIDTH-1:0] get_pc_pht_index(input PcPath pc);
        get_pc_pht_index = pc[PC_OFFSET_WIDTH +: PHT_INDEX_WIDTH];
    endfunction

    function automatic logic [PHT_INDEX_WIDTH-1:0] get_global_index(
        input PcPath pc,
        input logic [GLOBAL_HISTORY_WIDTH-1:0] history
    );
        logic [PHT_INDEX_WIDTH-1:0] historyExt;

        historyExt = '0;
        historyExt[GLOBAL_HISTORY_WIDTH-1:0] = history;
        get_global_index = get_pc_pht_index(pc) ^ historyExt;
    endfunction

    function automatic logic [PHT_INDEX_WIDTH-1:0] get_local_pht_index(
        input PcPath pc,
        input logic [LOCAL_HISTORY_WIDTH-1:0] history
    );
        logic [PHT_INDEX_WIDTH-1:0] historyExt;

        historyExt = '0;
        historyExt[LOCAL_HISTORY_WIDTH-1:0] = history;
        get_local_pht_index = get_pc_pht_index(pc) ^ historyExt;
    endfunction

    function automatic logic [1:0] sat_inc(input logic [1:0] value);
        sat_inc = (value == 2'b11) ? value : value + 2'b01;
    endfunction

    function automatic logic [1:0] sat_dec(input logic [1:0] value);
        sat_dec = (value == 2'b00) ? value : value - 2'b01;
    endfunction

    always_comb begin
        for (int i = 0; i < WAY_NUM; i++) begin
            logic [LOCAL_INDEX_WIDTH-1:0] localIndex;
            logic [PHT_INDEX_WIDTH-1:0]   globalIndex;
            logic [PHT_INDEX_WIDTH-1:0]   localPhtIndex;
            logic [PHT_INDEX_WIDTH-1:0]   chooserIndex;
            logic                         globalTaken;
            logic                         localTaken;
            logic                         useGlobal;

            localIndex = get_local_index(lookupPc[i]);
            globalIndex = get_global_index(lookupPc[i], globalHistory);
            localPhtIndex = get_local_pht_index(lookupPc[i], localHistoryTable[localIndex]);
            chooserIndex = get_pc_pht_index(lookupPc[i]);

            globalTaken = globalPht[globalIndex][1];
            localTaken = localPht[localPhtIndex][1];
            useGlobal = chooser[chooserIndex][1];

            taken[i] = lookupBtbHit[i] && (useGlobal ? globalTaken : localTaken);
        end
    end

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            globalHistory <= '0;
            for (int i = 0; i < LOCAL_ENTRY_NUM; i++) begin
                localHistoryTable[i] <= '0;
            end
            for (int i = 0; i < PHT_ENTRY_NUM; i++) begin
                globalPht[i] <= 2'b01;
                localPht[i] <= 2'b01;
                chooser[i] <= 2'b01;
            end
        end else if (updateValid) begin
            logic [LOCAL_INDEX_WIDTH-1:0] updateLocalIndex;
            logic [PHT_INDEX_WIDTH-1:0]   updateGlobalIndex;
            logic [PHT_INDEX_WIDTH-1:0]   updateLocalPhtIndex;
            logic [PHT_INDEX_WIDTH-1:0]   updateChooserIndex;
            logic                         globalWasTaken;
            logic                         localWasTaken;

            updateLocalIndex = get_local_index(updatePc);
            updateGlobalIndex = get_global_index(updatePc, globalHistory);
            updateLocalPhtIndex = get_local_pht_index(updatePc, localHistoryTable[updateLocalIndex]);
            updateChooserIndex = get_pc_pht_index(updatePc);

            globalWasTaken = globalPht[updateGlobalIndex][1];
            localWasTaken = localPht[updateLocalPhtIndex][1];

            globalPht[updateGlobalIndex] <= updateTaken ? sat_inc(globalPht[updateGlobalIndex]) :
                                                          sat_dec(globalPht[updateGlobalIndex]);
            localPht[updateLocalPhtIndex] <= updateTaken ? sat_inc(localPht[updateLocalPhtIndex]) :
                                                           sat_dec(localPht[updateLocalPhtIndex]);

            if (globalWasTaken != localWasTaken) begin
                if (globalWasTaken == updateTaken) begin
                    chooser[updateChooserIndex] <= sat_inc(chooser[updateChooserIndex]);
                end else if (localWasTaken == updateTaken) begin
                    chooser[updateChooserIndex] <= sat_dec(chooser[updateChooserIndex]);
                end
            end

            localHistoryTable[updateLocalIndex] <= {localHistoryTable[updateLocalIndex][LOCAL_HISTORY_WIDTH-2:0],
                                                    updateTaken};
            globalHistory <= {globalHistory[GLOBAL_HISTORY_WIDTH-2:0], updateTaken};
        end
    end
endmodule
