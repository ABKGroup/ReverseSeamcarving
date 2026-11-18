# Reconstruct an OpenDB handoff from the released repaired netlist.
source $::env(ORD_CONFIG)
set_thread_count $cfg(threads)
define_corners SS FF
foreach corner {SS FF} {
    foreach lib $cfg(lib_$corner) {read_liberty -corner $corner $lib}
}
read_lef $cfg(tech_lef)
read_lef $cfg(cell_lef)
read_verilog $cfg(netlist)
link_design $cfg(top)
foreach port_name $cfg(clock_ports) {
    set port [[ord::get_db_block] findBTerm $port_name]
    if {$port eq "NULL"} {error "missing clock port $port_name"}
    [$port getNet] setSigType CLOCK
}
foreach inst [[ord::get_db_block] getInsts] {
    $inst setPlacementStatus NONE
}
file mkdir [file dirname $cfg(handoff_odb)]
write_db $cfg(handoff_odb)
exit
