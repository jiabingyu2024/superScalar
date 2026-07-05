# Rebuild the FPGA Vivado project from repository sources.
#
# Usage:
#   vivado -mode batch -source fpga/create_vivado_project.tcl -tclargs src0
#   set ::env(FPGA_MEM_PROFILE) src0; source fpga/create_vivado_project.tcl
#   vivado fpga/build/digital_twin_src0/digital_twin.xpr
#
# Optional environment overrides:
#   FPGA_MEM_PROFILE=src0
#   FPGA_INPUT_CLK_MHZ=200.000
#   FPGA_PART=xc7k325tffg900-2
#   FPGA_SYS_CLK_MHZ=50.000
#   FPGA_CPU_CLK_MHZ=50.000

set script_dir [file normalize [file dirname [info script]]]
set repo_dir   [file normalize [file join $script_dir ..]]

set project_name digital_twin
set mem_profile src0
if {[info exists ::env(FPGA_MEM_PROFILE)]} {
    set mem_profile $::env(FPGA_MEM_PROFILE)
}
if {[info exists argv] && [llength $argv] >= 1} {
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

proc first_existing_dir {candidates description} {
    foreach candidate $candidates {
        set normalized [file normalize $candidate]
        if {[file isdirectory $normalized]} {
            return $normalized
        }
    }
    error "Required $description directory not found. Tried: $candidates"
}

proc first_existing_file {candidates description} {
    foreach candidate $candidates {
        set normalized [file normalize $candidate]
        if {[file exists $normalized]} {
            return $normalized
        }
    }
    error "Required $description file not found. Tried: $candidates"
}

proc set_ip_config_required {ip_name keys value} {
    set ip_obj [get_ips $ip_name]
    set props [list_property $ip_obj]
    foreach key $keys {
        set prop "CONFIG.$key"
        if {[lsearch -exact $props $prop] >= 0} {
            set_property $prop $value $ip_obj
            return
        }
    }
    error "IP $ip_name does not expose any of required properties: $keys"
}

proc set_ip_config_optional {ip_name keys value} {
    set ip_obj [get_ips $ip_name]
    set props [list_property $ip_obj]
    foreach key $keys {
        set prop "CONFIG.$key"
        if {[lsearch -exact $props $prop] >= 0} {
            set_property $prop $value $ip_obj
            return
        }
    }
    puts "WARNING: IP $ip_name does not expose optional properties: $keys"
}

set coe_dir [first_existing_dir [list \
    [file join $script_dir coe $mem_profile] \
    [file join $repo_dir data $mem_profile] \
] "COE profile"]
set irom_coe [file join $coe_dir irom.coe]
set dram_coe [file join $coe_dir dram.coe]
set xdc_file [first_existing_file [list \
    [file join $script_dir constraints digital_twin.xdc] \
    [file join $script_dir digital_twin.xdc] \
] "XDC constraint"]

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
foreach special [list BasicTypes.sv DecodeTypes.sv StoreBufferTypes.sv ROBTypes.sv RecoveryTypes.sv PipelineTypes.sv RenameTypes.sv ReadRegTypes.sv IssueTypes.sv] {
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
set_ip_config_required MUL_0 {PortAType port_a_type} {Signed}
set_ip_config_required MUL_0 {PortAWidth port_a_width} {33}
set_ip_config_required MUL_0 {PortBType port_b_type} {Signed}
set_ip_config_required MUL_0 {PortBWidth port_b_width} {33}
set_ip_config_required MUL_0 {MultType multiplier_type} {Parallel_Multiplier}
set_ip_config_optional MUL_0 {OptGoal optimization_goal} {Speed}
set_ip_config_required MUL_0 {PipeStages pipeline_stages} {3}
set_ip_config_required MUL_0 {Use_Custom_Output_Width use_custom_output_width} {true}
set_ip_config_required MUL_0 {OutputWidthHigh output_width_high} {65}
set_ip_config_required MUL_0 {OutputWidthLow output_width_low} {0}

create_ip -name div_gen -vendor xilinx.com -library ip -version 5.1 -module_name DIV_0
set_ip_config_required DIV_0 {algorithm_type Algorithm_Type} {Radix2}
set_ip_config_required DIV_0 {dividend_and_quotient_width Dividend_and_Quotient_Width} {32}
set_ip_config_required DIV_0 {divisor_width Divisor_Width} {32}
set_ip_config_required DIV_0 {remainder_type Remainder_Type} {Remainder}
set_ip_config_required DIV_0 {operand_sign Operand_Sign} {Unsigned}
set_ip_config_required DIV_0 {clocks_per_division Clocks_Per_Division} {1}
set_ip_config_required DIV_0 {latency_configuration Latency_Configuration} {Manual}
set_ip_config_required DIV_0 {latency Latency} {34}
set_ip_config_required DIV_0 {FlowControl flow_control} {Blocking}

generate_target all [get_ips]
export_ip_user_files -of_objects [get_ips] -no_script -sync -force -quiet
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Created Vivado project: [file join $project_dir ${project_name}.xpr]"
puts "Memory profile: $mem_profile ($coe_dir)"
puts "Open the .xpr in Vivado, then run synthesis and implementation from the GUI."
