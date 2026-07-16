# Run synthesis only and export timing/utilization reports for an RTL iteration.
#
# Usage:
#   vivado -mode batch -source fpga/run_synthesis.tcl \
#     -tclargs srcWithMext 8 200 1 iteration10 100000
#
# Arguments: profile jobs cpu_mhz reuse_project report_tag max_paths reuse_checkpoint synth_retiming

set profile srcWithMext
set jobs 8
set cpu_mhz 200.000
set reuse_project 0
set report_tag synth_latest
set max_paths 100000
set reuse_checkpoint 0
set synth_retiming 0
foreach {index variable} {
    0 profile
    1 jobs
    2 cpu_mhz
    3 reuse_project
    4 report_tag
    5 max_paths
    6 reuse_checkpoint
    7 synth_retiming
} {
    if {[info exists argv] && [llength $argv] > $index} {
        set $variable [lindex $argv $index]
    }
}

set ::env(FPGA_CPU_CLK_MHZ) $cpu_mhz
set script_dir [file normalize [file dirname [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set project_name digital_twin
set project_dir [file normalize [file join $script_dir build ${project_name}_${profile}]]
set project_file [file join $project_dir ${project_name}.xpr]
set created_project 0

proc assert_project_ip_config {script_dir project_dir cpu_mhz} {
    set pll_ip [get_ips pll]
    set actual_cpu_mhz [get_property CONFIG.CLKOUT2_REQUESTED_OUT_FREQ $pll_ip]
    if {abs(double($actual_cpu_mhz) - double($cpu_mhz)) > 0.001} {
        error "Stale PLL configuration: project=$actual_cpu_mhz MHz requested=$cpu_mhz MHz. Regenerate the project/IP checkpoints before timing analysis."
    }

    set create_script [file join $script_dir create_vivado_project.tcl]
    set fh [open $create_script r]
    set create_text [read $fh]
    close $fh
    if {![regexp {set_ip_config_required MUL_0 \{PipeStages pipeline_stages\} \{([0-9]+)\}} $create_text -> expected_mul_stages]} {
        error "Cannot determine expected MUL_0 PipeStages from $create_script"
    }
    set actual_mul_stages [get_property CONFIG.PipeStages [get_ips MUL_0]]
    if {$actual_mul_stages != $expected_mul_stages} {
        error "Stale MUL_0 configuration: project PipeStages=$actual_mul_stages source PipeStages=$expected_mul_stages. Regenerate the project/IP checkpoints before timing analysis."
    }

    set actual_irom_type [get_property CONFIG.Memory_Type [get_ips IROM_0]]
    set actual_irom_width_b [get_property CONFIG.Read_Width_B [get_ips IROM_0]]
    set actual_irom_enable_b [get_property CONFIG.Enable_B [get_ips IROM_0]]
    if {$actual_irom_type ne "Dual_Port_ROM" ||
        $actual_irom_width_b != 32 ||
        $actual_irom_enable_b ne "Use_ENB_Pin"} {
        error "Stale IROM_0 configuration: Memory_Type=$actual_irom_type Read_Width_B=$actual_irom_width_b Enable_B=$actual_irom_enable_b. Regenerate the dual-port ROM before timing analysis."
    }

    foreach ip_name {pll MUL_0 IROM_0} {
        set xci [get_property IP_FILE [get_ips $ip_name]]
        set dcp [file join $project_dir digital_twin.gen sources_1 ip $ip_name ${ip_name}.dcp]
        if {![file exists $dcp]} {
            error "Missing $ip_name OOC checkpoint: $dcp. Rebuild IP checkpoints before top-level synthesis."
        }
        if {[file mtime $dcp] < [file mtime $xci]} {
            error "Stale $ip_name OOC checkpoint: $dcp is older than $xci. Rebuild IP checkpoints before timing analysis."
        }
    }
    puts "IP_CONFIG_CHECK cpu_mhz=$actual_cpu_mhz mul_pipe_stages=$actual_mul_stages irom_type=$actual_irom_type status=PASS"
}

if {$reuse_project && [file exists $project_file]} {
    open_project $project_file

    foreach filelist_rel {scripts/filelists/core.f scripts/filelists/soc.f} {
        set filelist [file join $repo_dir $filelist_rel]
        set fh [open $filelist r]
        while {[gets $fh raw_line] >= 0} {
            set line [string trim [lindex [split $raw_line "#"] 0]]
            if {$line eq ""} {
                continue
            }
            foreach token [regexp -all -inline {\S+} $line] {
                if {[regexp {\.s?vh?$|\.sv$} $token]} {
                    if {[string match "rtl/ip/*" $token]} {
                        error "FPGA source filelist must not include Verilator IP model: $token"
                    }
                    set source_file [file normalize [file join $repo_dir $token]]
                    if {![file exists $source_file]} {
                        error "RTL source from $filelist_rel does not exist: $source_file"
                    }
                    if {[llength [get_files -quiet $source_file]] == 0} {
                        add_files -norecurse -fileset sources_1 $source_file
                    }
                    set_property file_type SystemVerilog [get_files $source_file]
                }
            }
        }
        close $fh
    }
    update_compile_order -fileset sources_1
} else {
    set argv [list $profile]
    source [file join $script_dir create_vivado_project.tcl]
    set created_project 1
}

if {$created_project} {
    # Direct synth_design requires real OOC netlists for generated IP.  Target
    # generation alone only creates wrappers, so a fresh project must build
    # the checkpoints before top-level synthesis.
    foreach ip [get_ips] {
        set xci [get_files [get_property IP_FILE $ip]]
        set_property GENERATE_SYNTH_CHECKPOINT true $xci
    }
    synth_ip [get_ips] -force
}

assert_project_ip_config $script_dir $project_dir $cpu_mhz

set report_dir [file normalize [file join $project_dir reports]]
file mkdir $report_dir
set checkpoint_file [file join $report_dir ${report_tag}_post_synth.dcp]
if {$reuse_checkpoint && [file exists $checkpoint_file]} {
    close_project
    open_checkpoint $checkpoint_file
} else {
    # Run in the current Vivado process.  Project-mode launch_runs uses the
    # Windows WSH run launcher, which can be blocked by host security policy
    # and leave wait_on_run sleeping forever without starting synth_design.
    set top_name [get_property top [get_filesets sources_1]]
    set part_name [get_property part [current_project]]
    set synth_args [list -top $top_name -part $part_name \
        -flatten_hierarchy rebuilt -keep_equivalent_registers]
    if {$synth_retiming} {
        lappend synth_args -retiming
    }
    synth_design {*}$synth_args
    write_checkpoint -force $checkpoint_file
}
report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose \
    -max_paths 100 -file [file join $report_dir ${report_tag}_timing_summary.rpt]
report_utilization -hierarchical -hierarchical_depth 12 \
    -file [file join $report_dir ${report_tag}_utilization_hier.rpt]
report_methodology -file [file join $report_dir ${report_tag}_methodology.rpt]

set raw_report [file join $report_dir ${report_tag}_all_violating_setup_paths.rpt]
report_timing -setup -slack_lesser_than 0.0 -max_paths $max_paths \
    -nworst 1 -sort_by group -file $raw_report
set paths [get_timing_paths -setup -slack_lesser_than 0.0 \
    -max_paths $max_paths -nworst 1]
set csv_file [file join $report_dir ${report_tag}_all_violating_setup_paths.csv]
set summary_file [file join $report_dir ${report_tag}_all_violating_setup_paths_summary.txt]
set csv [open $csv_file w]
puts $csv "index,slack_ns,requirement_ns,datapath_delay_ns,logic_levels,startpoint_pin,endpoint_pin,path_group"
set index 0
foreach path $paths {
    incr index
    set startpoint [get_property STARTPOINT_PIN $path]
    set endpoint [get_property ENDPOINT_PIN $path]
    set path_group "setup"
    foreach value_name {startpoint endpoint path_group} {
        set value [string map [list "\"" "\"\""] [set $value_name]]
        set $value_name "\"$value\""
    }
    puts $csv "$index,[get_property SLACK $path],[get_property REQUIREMENT $path],[get_property DATAPATH_DELAY $path],[get_property LOGIC_LEVELS $path],$startpoint,$endpoint,$path_group"
}
close $csv

set summary [open $summary_file w]
puts $summary "stage=synthesis"
puts $summary "profile=$profile"
puts $summary "report_tag=$report_tag"
puts $summary "cpu_mhz=$cpu_mhz"
puts $summary "slack_filter=slack<0.0ns"
puts $summary "nworst_per_endpoint=1"
puts $summary "max_paths=$max_paths"
puts $summary "exported_path_count=$index"
puts $summary "raw_report=$raw_report"
puts $summary "csv=$csv_file"
close $summary

set wns 0.0
set tns 0.0
if {$index != 0} {
    set wns [get_property SLACK [lindex $paths 0]]
    foreach path $paths {
        set tns [expr {$tns + [get_property SLACK $path]}]
    }
}
puts "SYNTHESIS_RESULT profile=$profile cpu_mhz=$cpu_mhz WNS=$wns TNS=$tns violating_paths=$index"
puts "SYNTHESIS_REPORT_DIR $report_dir"
close_project
