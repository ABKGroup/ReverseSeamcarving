# Contra2 Genus RTL-to-RVT synthesis driver.
proc need_env {name} {
    if {![info exists ::env($name)] || $::env($name) eq ""} { error "missing environment variable $name" }
    return $::env($name)
}

set_db max_cpus_per_server [need_env CONTRA2_SYNTH_THREADS]
set_db super_thread_servers localhost
setDesignMode -process 7
set_db hdl_flatten_complex_port true
set_db hdl_record_naming_style %s_%s
set_db auto_ungroup none
set_db lbr_seq_in_out_phase_opto true

set libraries [split [need_env CONTRA2_SYNTH_LIBS]]
create_library_set -name TT_LIB -timing $libraries
create_timing_condition -name TT_CONDITION -library_sets {TT_LIB}
create_rc_corner -name RC
create_delay_corner -name TT -timing_condition {TT_CONDITION} -rc_corner RC
create_constraint_mode -name CON -sdc_file [need_env CONTRA2_SYNTH_SDC]
create_analysis_view -name TT_VIEW -delay_corner TT -constraint_mode CON
set_analysis_view -setup {TT_VIEW} -hold {TT_VIEW}

set include_dirs [split $::env(CONTRA2_SYNTH_INCLUDES)]
if {[llength $include_dirs]} { set_db init_hdl_search_path $include_dirs }
set rtl_files [split [need_env CONTRA2_SYNTH_RTL]]
set defines [split $::env(CONTRA2_SYNTH_DEFINES)]
if {[llength $defines]} {
    read_hdl -sv -define $defines {*}$rtl_files
} else {
    read_hdl -sv {*}$rtl_files
}
elaborate [need_env CONTRA2_SYNTH_TOP]
init_design


set_db syn_generic_effort low
set_db syn_map_effort low
set_db syn_opt_effort low
syn_generic
syn_map
report_timing -max_paths 10 > [file join [need_env CONTRA2_SYNTH_OUT] timing_map.rpt]
syn_opt

set out [need_env CONTRA2_SYNTH_OUT]
write_netlist > [file join $out netlist.v]
write_sdc -view TT_VIEW > [file join $out constraints.sdc]
report_area > [file join $out area.rpt]
report_gates > [file join $out gates.rpt]
report_timing -max_paths 10 > [file join $out timing_final.rpt]
report_qor > [file join $out qor_final.rpt]
report_messages > [file join $out messages.rpt]
puts "CONTRA2_SYNTHESIS_OK"
exit
