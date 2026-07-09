package CoreUtilPkg;
    function automatic logic [31:0] core_abs32(input logic [31:0] value);
        core_abs32 = value[31] ? (~value + 32'd1) : value;
    endfunction

    function automatic logic [31:0] core_sext12(input logic [11:0] value);
        core_sext12 = {{20{value[11]}}, value};
    endfunction
endpackage : CoreUtilPkg
