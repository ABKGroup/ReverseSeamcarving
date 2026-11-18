# Reconstruct the input checkpoint from the released repaired Verilog.
source [file join [file dirname [file normalize [info script]]] config.tcl]
set script_dir [file dirname [file normalize [info script]]]
foreach module {common platform} {
    source [file join $script_dir ${module}.tcl]
}

rsc::read_libraries
read_lef $cfg(tech_lef)
read_lef $cfg(cell_lef)
read_verilog $cfg(netlist)
link_design $cfg(top)
rsc::mark_primary_clocks
foreach instance [[ord::get_db_block] getInsts] {
    $instance setPlacementStatus NONE
}
file mkdir [file dirname $cfg(handoff_odb)]
write_db $cfg(handoff_odb)
exit
