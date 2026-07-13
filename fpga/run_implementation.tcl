# Create the selected profile and run routed implementation in one Vivado process.
set profile srcWithMext
set jobs 8
set cpu_mhz 200.000
set reuse_project 0
if {[info exists argv] && [llength $argv] >= 1} {
    set profile [lindex $argv 0]
}
if {[info exists argv] && [llength $argv] >= 2} {
    set jobs [lindex $argv 1]
}
if {[info exists argv] && [llength $argv] >= 3} {
    set cpu_mhz [lindex $argv 2]
}
if {[info exists argv] && [llength $argv] >= 4} {
    set reuse_project [lindex $argv 3]
}

# Set the frequency inside Tcl instead of relying on cmd.exe environment
# quoting.  This must happen before create_vivado_project.tcl configures PLL_0.
set ::env(FPGA_CPU_CLK_MHZ) $cpu_mhz

# Reuse keeps generated IP checkpoints and avoids paying the project/IP setup
# cost for a targeted RTL timing iteration.
set script_dir [file normalize [file dirname [info script]]]
set repo_dir [file normalize [file join $script_dir ..]]
set project_name digital_twin
set project_dir [file normalize [file join $script_dir build ${project_name}_${profile}]]
set project_file [file join $project_dir ${project_name}.xpr]
if {$reuse_project && [file exists $project_file]} {
    open_project $project_file

    # An existing XPR does not automatically notice sources newly added to the
    # repository filelists.  Refresh both RTL filelists before resetting the
    # run, otherwise an incremental timing iteration can synthesize a stale
    # design or fail with "module ... not found".
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
    reset_run synth_1
} else {
    # create_vivado_project.tcl consumes argv[0] as the memory profile and
    # leaves project_dir/project_name in this interpreter.
    set argv [list $profile]
    source [file join $script_dir create_vivado_project.tcl]
}

launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property STATUS [get_runs synth_1]] ne "synth_design Complete!"} {
    error "Synthesis failed: [get_property STATUS [get_runs synth_1]]"
}

launch_runs impl_1 -to_step route_design -jobs $jobs
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
if {![string match "route_design Complete*" $impl_status]} {
    error "Implementation failed: $impl_status"
}

open_run impl_1
set report_dir [file normalize [file join $project_dir reports]]
file mkdir $report_dir
report_timing_summary -delay_type max -report_unconstrained -check_timing_verbose \
    -max_paths 20 -file [file join $report_dir routed_timing_summary.rpt]
report_utilization -hierarchical -hierarchical_depth 8 \
    -file [file join $report_dir routed_utilization_hier.rpt]
report_clock_utilization -file [file join $report_dir routed_clock_utilization.rpt]
report_methodology -file [file join $report_dir routed_methodology.rpt]

set wns [get_property STATS.WNS [get_runs impl_1]]
set tns [get_property STATS.TNS [get_runs impl_1]]
puts "IMPLEMENTATION_RESULT profile=$profile cpu_mhz=$::env(FPGA_CPU_CLK_MHZ) WNS=$wns TNS=$tns"
puts "IMPLEMENTATION_REPORT_DIR $report_dir"
close_project
