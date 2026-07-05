# Rebuild the FPGA Vivado project from repository sources.
#
# Usage:
#   vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs src0
#   vivado fpga/build/digital_twin_src0/digital_twin.xpr
#
# Optional environment overrides:
#   FPGA_PART=xc7k325tffg900-2
#   FPGA_SYS_CLK_MHZ=50.000
#   FPGA_CPU_CLK_MHZ=50.000

set script_dir [file normalize [file dirname [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]

set project_name digital_twin
set mem_profile src0
if {[llength $argv] >= 1} {
    set mem_profile [lindex $argv 0]
}

set part xc7k325tffg900-2
if {[info exists ::env(FPGA_PART)]} {
    set part $::env(FPGA_PART)
}

set input_clk_mhz 200.000
set sys_clk_mhz   50.000
set cpu_clk_mhz   50.000
if {[info exists ::env(FPGA_INPUT_CLK_MHZ)]} {
    set input_clk_mhz $::env(FPGA_INPUT_CLK_MHZ)
}
if {[info exists ::env(FPGA_SYS_CLK_MHZ)]} {
    set sys_clk_mhz $::env(FPGA_SYS_CLK_MHZ)
}
if {[info exists ::env(FPGA_CPU_CLK_MHZ)]} {
    set cpu_clk_mhz $::env(FPGA_CPU_CLK_MHZ)
}

set coe_dir  [file normalize [file join $script_dir coe $mem_profile]]
set irom_coe [file join $coe_dir irom.coe]
set dram_coe [file join $coe_dir dram.coe]
set xdc_file [file normalize [file join $script_dir constraints digital_twin.xdc]]

foreach required_file [list $irom_coe $dram_coe $xdc_file] {
    if {![file exists $required_file]} {
        error "Required FPGA input file not found: $required_file"
    }
}

set project_dir [file normalize [file join $script_dir build ${project_name}_${mem_profile}]]
create_project -force $project_name $project_dir -part $part

set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]

proc collect_sv_files {dir} {
    set result {}
    foreach entry [glob -nocomplain -directory $dir *] {
        if {[file isdirectory $entry]} {
            set result [concat $result [collect_sv_files $entry]]
        } elseif {[file extension $entry] eq ".sv"} {
            lappend result [file normalize $entry]
        }
    }
    return $result
}

set core_files [collect_sv_files [file join $repo_dir rtl core]]
set soc_files  [collect_sv_files [file join $repo_dir rtl soc]]
set rtl_files  [lsort [concat $core_files $soc_files]]

# Keep packages and shared type files ahead of users; Vivado will still update
# compile order after all sources and IP are present.
set ordered_rtl {}
foreach special [list BasicTypes.sv PipelineTypes.sv RecoveryTypes.sv DecodeTypes.sv RenameTypes.sv IssueTypes.sv ROBTypes.sv StoreBufferTypes.sv ReadRegTypes.sv] {
    foreach src $rtl_files {
        if {[file tail $src] eq $special} {
            lappend ordered_rtl $src
        }
    }
}
foreach src $rtl_files {
    if {[lsearch -exact $ordered_rtl $src] < 0} {
        lappend ordered_rtl $src
    }
}

add_files -norecurse -fileset sources_1 $ordered_rtl
foreach src $ordered_rtl {
    set_property file_type SystemVerilog [get_files $src]
}

add_files -fileset constrs_1 $xdc_file
set_property top top [get_filesets sources_1]

create_ip -name clk_wiz -vendor xilinx.com -library ip -version 6.0 -module_name pll
set_property -dict [list \
    CONFIG.PRIM_SOURCE {Differential_clock_capable_pin} \
    CONFIG.PRIM_IN_FREQ $input_clk_mhz \
    CONFIG.CLKOUT1_USED {true} \
    CONFIG.CLKOUT2_USED {true} \
    CONFIG.NUM_OUT_CLKS {2} \
    CONFIG.CLK_OUT1_PORT {clk_out1} \
    CONFIG.CLK_OUT2_PORT {clk_out2} \
    CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $sys_clk_mhz \
    CONFIG.CLKOUT2_REQUESTED_OUT_FREQ $cpu_clk_mhz \
    CONFIG.CLKOUT1_REQUESTED_PHASE {0.000} \
    CONFIG.CLKOUT2_REQUESTED_PHASE {0.000} \
    CONFIG.CLKOUT1_REQUESTED_DUTY_CYCLE {50.000} \
    CONFIG.CLKOUT2_REQUESTED_DUTY_CYCLE {50.000} \
    CONFIG.USE_RESET {false} \
    CONFIG.USE_LOCKED {true} \
] [get_ips pll]

create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 -module_name IROM_0
set_property -dict [list \
    CONFIG.Memory_Type {Dual_Port_ROM} \
    CONFIG.Write_Width_A {32} \
    CONFIG.Write_Depth_A {4096} \
    CONFIG.Read_Width_A {32} \
    CONFIG.Read_Width_B {32} \
    CONFIG.Enable_A {Use_ENA_Pin} \
    CONFIG.Enable_B {Use_ENB_Pin} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortB_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortA_Output_of_Memory_Core {false} \
    CONFIG.Register_PortB_Output_of_Memory_Core {false} \
    CONFIG.Load_Init_File {true} \
    CONFIG.Coe_File $irom_coe \
] [get_ips IROM_0]

create_ip -name blk_mem_gen -vendor xilinx.com -library ip -version 8.4 -module_name DRAM_0
set_property -dict [list \
    CONFIG.Memory_Type {Single_Port_RAM} \
    CONFIG.Write_Width_A {32} \
    CONFIG.Write_Depth_A {65536} \
    CONFIG.Read_Width_A {32} \
    CONFIG.Enable_A {Use_ENA_Pin} \
    CONFIG.Use_Byte_Write_Enable {true} \
    CONFIG.Byte_Size {8} \
    CONFIG.Operating_Mode_A {READ_FIRST} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {true} \
    CONFIG.Register_PortA_Output_of_Memory_Core {false} \
    CONFIG.Load_Init_File {true} \
    CONFIG.Coe_File $dram_coe \
] [get_ips DRAM_0]

create_ip -name mult_gen -vendor xilinx.com -library ip -version 12.0 -module_name MUL_0
set_property -dict [list \
    CONFIG.PortAType {Signed} \
    CONFIG.PortAWidth {33} \
    CONFIG.PortBType {Signed} \
    CONFIG.PortBWidth {33} \
    CONFIG.MultType {Parallel_Multiplier} \
    CONFIG.OptGoal {Speed} \
    CONFIG.PipeStages {3} \
    CONFIG.Use_Custom_Output_Width {true} \
    CONFIG.OutputWidthHigh {65} \
    CONFIG.OutputWidthLow {0} \
] [get_ips MUL_0]

create_ip -name div_gen -vendor xilinx.com -library ip -version 5.1 -module_name DIV_0
set_property -dict [list \
    CONFIG.algorithm_type {Radix2} \
    CONFIG.dividend_and_quotient_width {32} \
    CONFIG.divisor_width {32} \
    CONFIG.remainder_type {Remainder} \
    CONFIG.operand_sign {Unsigned} \
    CONFIG.clocks_per_division {1} \
    CONFIG.latency_configuration {Manual} \
    CONFIG.latency {34} \
    CONFIG.FlowControl {Blocking} \
] [get_ips DIV_0]

generate_target all [get_ips]
export_ip_user_files -of_objects [get_ips] -no_script -sync -force -quiet
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Created Vivado project: [file join $project_dir ${project_name}.xpr]"
puts "Memory profile: $mem_profile ($coe_dir)"
puts "Open the .xpr in Vivado, then run synthesis and implementation from the GUI."
