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
#   FPGA_FLATTEN_HIERARCHY=none
#   FPGA_KEEP_EQUIVALENT_REGISTERS=true
#   FPGA_ENABLE_POWER_OPT=false

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
set flatten_hierarchy none
set keep_equivalent_registers true
set enable_power_opt false
if {[info exists ::env(FPGA_INPUT_CLK_MHZ)]} {
    set input_clk_mhz $::env(FPGA_INPUT_CLK_MHZ)
}
if {[info exists ::env(FPGA_SYS_CLK_MHZ)]} {
    set sys_clk_mhz $::env(FPGA_SYS_CLK_MHZ)
}
if {[info exists ::env(FPGA_CPU_CLK_MHZ)]} {
    set cpu_clk_mhz $::env(FPGA_CPU_CLK_MHZ)
}
if {[info exists ::env(FPGA_FLATTEN_HIERARCHY)]} {
    set flatten_hierarchy $::env(FPGA_FLATTEN_HIERARCHY)
}
if {[info exists ::env(FPGA_KEEP_EQUIVALENT_REGISTERS)]} {
    set keep_equivalent_registers $::env(FPGA_KEEP_EQUIVALENT_REGISTERS)
}
if {[info exists ::env(FPGA_ENABLE_POWER_OPT)]} {
    set enable_power_opt $::env(FPGA_ENABLE_POWER_OPT)
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

proc write_sanity_report_script {script_path stage_name} {
    set fh [open $script_path w]
    puts $fh "set report_dir \[file normalize \[file join \[get_property DIRECTORY \[current_project\]\] reports\]\]"
    puts $fh {file mkdir $report_dir}
    puts $fh "set stage_name {$stage_name}"
    puts $fh {set util_file [file join $report_dir "${stage_name}_util_hier.rpt"]}
    puts $fh {set bb_file   [file join $report_dir "${stage_name}_blackbox.rpt"]}
    puts $fh {set chk_file  [file join $report_dir "${stage_name}_sanity.txt"]}
    puts $fh {catch {report_utilization -hierarchical -hierarchical_depth 12 -file $util_file}}
    puts $fh {catch {report_blackbox -file $bb_file}}
    puts $fh {set fh [open $chk_file w]}
    puts $fh {set core_cells [get_cells -hier -quiet *Core_cpu*]}
    puts $fh {set student_cells [get_cells -hier -quiet *student_top_inst*]}
    puts $fh {set issue_cells [get_cells -hier -quiet *IssueQueue*]}
    puts $fh {set rob_cells [get_cells -hier -quiet *ROB*]}
    puts $fh {set mul_stage_cells [get_cells -hier -quiet *ExecuteMulStage*]}
    puts $fh {set lut_cells [get_cells -hier -quiet -filter {REF_NAME =~ LUT*}]}
    puts $fh {set ff_cells [get_cells -hier -quiet -filter {REF_NAME =~ FD*}]}
    puts $fh {puts $fh "stage=$stage_name"}
    puts $fh {puts $fh "student_top_cells=[llength $student_cells]"}
    puts $fh {puts $fh "core_cpu_cells=[llength $core_cells]"}
    puts $fh {puts $fh "issuequeue_name_cells=[llength $issue_cells]"}
    puts $fh {puts $fh "rob_name_cells=[llength $rob_cells]"}
    puts $fh {puts $fh "execute_mul_stage_name_cells=[llength $mul_stage_cells]"}
    puts $fh {puts $fh "lut_cells=[llength $lut_cells]"}
    puts $fh {puts $fh "ff_cells=[llength $ff_cells]"}
    puts $fh {close $fh}
    puts $fh {puts "FPGA sanity report: $chk_file"}
    puts $fh {puts "FPGA hierarchical utilization: $util_file"}
    puts $fh {puts "FPGA blackbox report: $bb_file"}
    puts $fh {if {[llength $core_cells] == 0} {
    puts "CRITICAL WARNING: Core_cpu cell was not found after $stage_name. The CPU may have been optimized away or renamed unexpectedly."
}}
    puts $fh {if {[llength $lut_cells] < 1000 || [llength $ff_cells] < 500} {
    puts "CRITICAL WARNING: FPGA sanity check sees very low resource count after $stage_name. Inspect $util_file and $bb_file before trusting implementation results."
}}
    close $fh
}

proc write_cdc_constraint_file {script_path} {
    set fh [open $script_path w]
    puts $fh {# Late top-level CDC constraints for the two PLL output domains.}
    puts $fh {# The SoC treats clk_out1_pll (50 MHz system/twin/counter) and}
    puts $fh {# clk_out2_pll (CPU/IROM/DRAM/core) as CDC domains, even though}
    puts $fh {# both clocks are generated by the same clk_wiz instance.}
    puts $fh {# Keep this file as plain XDC: Vivado rejects Tcl control flow such as if/else here.}
    puts $fh {set_clock_groups -asynchronous -group [get_clocks -quiet clk_out1_pll] -group [get_clocks -quiet clk_out2_pll]}
    close $fh
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
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY $flatten_hierarchy [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS $keep_equivalent_registers [get_runs synth_1]
set_property STEPS.POWER_OPT_DESIGN.IS_ENABLED $enable_power_opt [get_runs impl_1]
set_property STEPS.POST_PLACE_POWER_OPT_DESIGN.IS_ENABLED $enable_power_opt [get_runs impl_1]

set report_script_dir [file normalize [file join $project_dir sanity]]
file mkdir $report_script_dir
set synth_sanity_script [file join $report_script_dir post_synth_sanity.tcl]
set impl_sanity_script  [file join $report_script_dir post_impl_sanity.tcl]
write_sanity_report_script $synth_sanity_script synth
write_sanity_report_script $impl_sanity_script impl
set_property STEPS.SYNTH_DESIGN.TCL.POST $synth_sanity_script [get_runs synth_1]
set_property STEPS.OPT_DESIGN.TCL.POST $impl_sanity_script [get_runs impl_1]

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

proc read_filelist_sources {filelist_path repo_dir} {
    set result {}
    set fh [open $filelist_path r]
    while {[gets $fh raw_line] >= 0} {
        set line [string trim [lindex [split $raw_line "#"] 0]]
        if {$line eq ""} {
            continue
        }
        set tokens [regexp -all -inline {\S+} $line]
        set idx 0
        while {$idx < [llength $tokens]} {
            set token [lindex $tokens $idx]
            if {$token eq "-f"} {
                incr idx
                set nested [file normalize [file join $repo_dir [lindex $tokens $idx]]]
                set result [concat $result [read_filelist_sources $nested $repo_dir]]
            } elseif {[string match "-f*" $token]} {
                set nested_rel [string range $token 2 end]
                set nested [file normalize [file join $repo_dir $nested_rel]]
                set result [concat $result [read_filelist_sources $nested $repo_dir]]
            } elseif {[regexp {\.s?vh?$|\.sv$} $token]} {
                if {[string match "rtl/ip/*" $token]} {
                    error "FPGA source filelist must not include Verilator IP model: $token"
                }
                lappend result [file normalize [file join $repo_dir $token]]
            }
            incr idx
        }
    }
    close $fh
    return $result
}

set core_filelist [file join $repo_dir scripts filelists core.f]
set soc_filelist  [file join $repo_dir scripts filelists soc.f]
set rtl_files [concat \
    [read_filelist_sources $core_filelist $repo_dir] \
    [read_filelist_sources $soc_filelist $repo_dir] \
]

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
set rtl_include_dir [file normalize [file join $repo_dir rtl include]]
set_property include_dirs [list $rtl_include_dir] [get_filesets sources_1]
if {[llength [get_filesets -quiet sim_1]] > 0} {
    set_property include_dirs [list $rtl_include_dir] [get_filesets sim_1]
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
    CONFIG.Memory_Type {Single_Port_ROM} \
    CONFIG.Write_Width_A {32} \
    CONFIG.Write_Depth_A {4096} \
    CONFIG.Read_Width_A {32} \
    CONFIG.Enable_A {Use_ENA_Pin} \
    CONFIG.Register_PortA_Output_of_Memory_Primitives {false} \
    CONFIG.Register_PortA_Output_of_Memory_Core {false} \
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
    CONFIG.Use_REGCEA_Pin {true} \
    CONFIG.Load_Init_File {true} \
    CONFIG.Coe_File $dram_coe \
] [get_ips DRAM_0]

create_ip -name mult_gen -vendor xilinx.com -library ip -version 12.0 -module_name MUL_0
set_ip_config_required MUL_0 {PortAType port_a_type} {Signed}
set_ip_config_required MUL_0 {PortAWidth port_a_width} {33}
set_ip_config_required MUL_0 {PortBType port_b_type} {Signed}
set_ip_config_required MUL_0 {PortBWidth port_b_width} {33}
set_ip_config_required MUL_0 {MultType multiplier_type} {Parallel_Multiplier}
set_ip_config_required MUL_0 {Multiplier_Construction multiplier_construction} {Use_Mults}
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

set cdc_constraint_dir [file normalize [file join $project_dir constraints]]
file mkdir $cdc_constraint_dir
set cdc_xdc_file [file join $cdc_constraint_dir digital_twin_cdc.xdc]
write_cdc_constraint_file $cdc_xdc_file
add_files -fileset constrs_1 $cdc_xdc_file
set_property PROCESSING_ORDER LATE [get_files $cdc_xdc_file]

generate_target all [get_ips]
export_ip_user_files -of_objects [get_ips] -no_script -sync -force -quiet
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "Created Vivado project: [file join $project_dir ${project_name}.xpr]"
puts "Memory profile: $mem_profile ($coe_dir)"
puts "Synthesis flatten hierarchy: $flatten_hierarchy"
puts "Sanity reports will be written under: [file join $project_dir reports]"
puts "Open the .xpr in Vivado, then run synthesis and implementation from the GUI."
