# Create a self-contained PYNQ-Z2 Vivado project without modifying the main
# FPGA flow. Usage:
#   vivado -mode batch -source fpga/test_prj/create_project.tcl -tclargs srcSmoke

set script_dir [file normalize [file dirname [info script]]]
set repo_dir [file normalize [file join $script_dir ../..]]

set mem_profile srcSmoke
if {[info exists ::env(FPGA_MEM_PROFILE)]} {
    set mem_profile $::env(FPGA_MEM_PROFILE)
}
if {[info exists argv] && [llength $argv] >= 1} {
    set mem_profile [lindex $argv 0]
}

set cpu_clk_mhz 50.000
if {[info exists ::env(FPGA_CPU_CLK_MHZ)]} {
    set cpu_clk_mhz $::env(FPGA_CPU_CLK_MHZ)
}
if {[expr {abs(double($cpu_clk_mhz) - 50.0)}] > 0.0001} {
    error "PYNQ wrapper PLL is fixed at 50.000 MHz; FPGA_CPU_CLK_MHZ=$cpu_clk_mhz is unsupported"
}

set part xc7z020clg400-1
set project_name pynq_superscalar
set project_dir [file normalize [file join $script_dir build $mem_profile]]
set source_filelist [file join $script_dir pynq_sources.f]
set xdc_file [file join $script_dir pynq_z2.xdc]
set coe_dir [file normalize [file join $repo_dir data $mem_profile]]
set irom_coe [file join $coe_dir irom.coe]
set dram_coe [file join $coe_dir dram.coe]

foreach required [list $source_filelist $xdc_file $irom_coe $dram_coe] {
    if {![file exists $required]} {
        error "Required file does not exist: $required"
    }
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
        set index 0
        while {$index < [llength $tokens]} {
            set token [lindex $tokens $index]
            if {$token eq "-f"} {
                incr index
                set nested [file normalize [file join $repo_dir [lindex $tokens $index]]]
                set result [concat $result [read_filelist_sources $nested $repo_dir]]
            } elseif {[string match "-f*" $token]} {
                set nested [file normalize [file join $repo_dir [string range $token 2 end]]]
                set result [concat $result [read_filelist_sources $nested $repo_dir]]
            } elseif {[regexp {\.s?vh?$|\.sv$} $token]} {
                lappend result [file normalize [file join $repo_dir $token]]
            }
            incr index
        }
    }
    close $fh
    return $result
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
    error "IP $ip_name does not expose a required property from: $keys"
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
}

set rtl_files [read_filelist_sources $source_filelist $repo_dir]
foreach source_file $rtl_files {
    if {![file exists $source_file]} {
        error "RTL source does not exist: $source_file"
    }
}

create_project -force $project_name $project_dir -part $part
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property default_lib xil_defaultlib [current_project]
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]
set_property STEPS.SYNTH_DESIGN.ARGS.KEEP_EQUIVALENT_REGISTERS true [get_runs synth_1]

add_files -norecurse -fileset sources_1 $rtl_files
foreach source_file $rtl_files {
    set_property file_type SystemVerilog [get_files $source_file]
}
add_files -norecurse -fileset constrs_1 $xdc_file
set_property top pynq_top [get_filesets sources_1]

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

puts "PYNQ_PROJECT_CREATED [file join $project_dir ${project_name}.xpr]"
puts "PYNQ_MEMORY_PROFILE $mem_profile"
puts "PYNQ_CPU_CLK_MHZ $cpu_clk_mhz"
