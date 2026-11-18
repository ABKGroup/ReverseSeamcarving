source $::env(ORD_CONFIG)
proc path {name} {return [file join $::cfg(out) $name]}
proc text {name value} {set f [open [path $name] w];puts $f $value;close $f}
proc report_file {name script} {
    utl::redirectFileBegin [path $name]
    set code [catch {uplevel 1 $script} result options]
    utl::redirectFileEnd
    if {$code} {return -options $options $result}
}
proc pg {net} {return [expr {$net ne "NULL" && $net ne "" && [$net getSigType] in {POWER GROUND}}]}
proc dump_graph {name} {
    set f [open [path ${name}_graph.tsv] w]
    foreach inst [[ord::get_db_block] getInsts] {
        set n [$inst getName];set m [[$inst getMaster] getName]
        puts $f [join [list C $n $m [regexp {^(BUF|HB)} $m] [regexp {^(INV|CKINV)} $m]] "\t"]
        foreach pin [$inst getITerms] {
            set term [$pin getMTerm]
            if {[$term getSigType] in {POWER GROUND}} {continue}
            set net [$pin getNet];if {[pg $net]} {continue}
            set nn "";if {$net ne "NULL" && $net ne ""} {set nn [$net getName]}
            set term [$pin getMTerm];set dir [$term getIoType]
            puts $f [join [list I $n [$term getName] $nn [expr {$dir in {INPUT INOUT}}] [expr {$dir in {OUTPUT INOUT}}]] "\t"]
        }
    }
    foreach pin [[ord::get_db_block] getBTerms] {
        set net [$pin getNet];if {[pg $net]} {continue}
        set nn "";if {$net ne "NULL" && $net ne ""} {set nn [$net getName]}
        set dir [$pin getIoType]
        puts $f [join [list P [$pin getName] $nn [expr {$dir in {INPUT INOUT}}] [expr {$dir in {OUTPUT INOUT}}]] "\t"]
    }
    close $f
}
proc snapshot {name} {dump_graph $name;write_def [path ${name}.def]}
proc timing {name method} {
    estimate_parasitics $method
    report_wns -digits 6 > [path ${name}_setup_wns.rpt]
    report_tns -digits 6 > [path ${name}_setup_tns.rpt]
    report_wns -min -digits 6 > [path ${name}_hold_wns.rpt]
    report_tns -min -digits 6 > [path ${name}_hold_tns.rpt]
    report_checks -path_delay max -group_path_count 5 > [path ${name}_setup_paths.rpt]
    report_power -scene SS > [path ${name}_power.rpt]
}
proc density {} {
    set block [ord::get_db_block];set core [$block getCoreArea]
    set area [expr {double([$core dx])*[$core dy]}];set cells 0.;set reserved 0.
    foreach inst [$block getInsts] {set m [$inst getMaster];set cells [expr {$cells+double([$m getWidth])*[$m getHeight]}]}
    foreach b [$block getBlockages] {set box [$b getBBox];set reserved [expr {$reserved+double([$box xMax]-[$box xMin])*([$box yMax]-[$box yMin])*(1.0-[$b getMaxDensity]/100.0)}]}
    set physical [expr {$cells/($area-$reserved)}]
    set d [expr {max(0.95,$physical+0.005)}]
    if {$d>=1.0} {error "infeasible requested utilization/seam capacity; no utilization reduction"}
    text gpl_density.txt [list physical_minimum $physical target $d]
    return $d
}
proc legalize {stage incremental} {
    set block [ord::get_db_block];set removed 0
    foreach b [$block getBlockages] {if {[$b getMaxDensity]>0} {odb::dbBlockage_destroy $b;incr removed}}
    set core [$block getCoreArea];set dbu [$block getDbUnitsPerMicron]
    set distance [expr {int(ceil(max([$core dx],[$core dy])/double($dbu)))+1}]
    text ${stage}_legalizer.txt [list partial_screens_global_only $removed max_displacement_um $distance incremental $incremental]
    set args [list -use_diamond_legalizer -max_displacement $distance]
    if {$incremental} {lappend args -incremental}
    detailed_placement {*}$args
    check_placement -verbose -report_file_name [path ${stage}_legality.rpt]
}

proc seams {} {
    set b [ord::get_db_block];set core [$b getCoreArea];set dbu [$b getDbUnitsPerMicron]
    set x0 [expr {double([$core xMin])/$dbu}];set y0 [expr {double([$core yMin])/$dbu}]
    set x1 [expr {double([$core xMax])/$dbu}];set y1 [expr {double([$core yMax])/$dbu}]
    text floorplan.txt [list $x0 $y0 $x1 $y1]
    if {!$::cfg(width) && !$::cfg(height)} {return}
    set sw [expr {$::cfg(width)*0.054}];set sh [expr {$::cfg(height)*0.270}]
    set px [expr {$::cfg(pitch_x)*0.054}];set py [expr {$::cfg(pitch_y)*0.270}]
    set vs {};set hs {};set vw 0.;set hh 0.
    if {$sw>0} {for {set x [expr {$x0+$px}]} {$x<$x1-1e-9} {set x [expr {$x+$px}]} {set xe [expr {min($x+$sw,$x1)}];lappend vs [list $x $xe];set vw [expr {$vw+$xe-$x}]}}
    if {$sh>0} {for {set y [expr {$y0+$py}]} {$y<$y1-1e-9} {set y [expr {$y+$py}]} {set ye [expr {min($y+$sh,$y1)}];lappend hs [list $y $ye];set hh [expr {$hh+$ye-$y}]}}
    set area [expr {($x1-$x0)*($y1-$y0)}]
    set f [expr {($vw*($y1-$y0)+$hh*($x1-$x0)-$vw*$hh)/$area}]
    if {$f<=0} {error "empty seam geometry"}
    set outside [expr {$::cfg(util)+$::cfg(delta)}]
    set requested [expr {($::cfg(util)-(1-$f)*$outside)/$f}]
    if {$requested>1} {error "infeasible requested seam density"}
    set hard [expr {$requested<0.05}]
    set d [expr {$hard ? 0.0 : round(100*$requested)}]
    set boxes {}
    foreach v $vs {lassign $v x xe;lappend boxes [list $x $y0 $xe $y1]}
    foreach h $hs {
        lassign $h y ye;set start $x0
        foreach v $vs {lassign $v x xe;if {$x>$start} {lappend boxes [list $start $y $x $ye]};set start $xe}
        if {$start<$x1} {lappend boxes [list $start $y $x1 $ye]}
    }
    foreach box $boxes {if {$hard} {create_blockage -region $box} else {create_blockage -region $box -max_density $d}}
    text seams.txt [list fraction $f requested $requested command_density_percent $d hard $hard outside_target $outside boxes $boxes]
}
# Map imported literal constant nets to ASAP7 RVT tie cells. Only POWER/GROUND
# nets connected to logical pins/ports are candidates; supply-only nets stay PG.
proc map_literal_ties {} {
    set block [ord::get_db_block];set db [ord::get_db];set count 0
    set endpoints [open [path constant_endpoints.tsv] w]
    set audit [open [path tie_mapping.tsv] w]
    puts $audit "net\tvalue\ttie_instance\tmaster\tsignal_pins\tports"
    foreach net [$block getNets] {
        set type [$net getSigType]
        if {$type ni {POWER GROUND}} {continue}
        set loads {};set ports {}
        foreach pin [$net getITerms] {
            set term [$pin getMTerm]
            if {[$term getSigType] in {POWER GROUND}} {continue}
            if {[$term getIoType] ne "INPUT"} {error "constant net [$net getName] has a non-input logical ITerm"}
            lappend loads $pin
        }
        foreach port [$net getBTerms] {
            if {[$port getIoType] ne "OUTPUT"} {error "constant net [$net getName] has non-output top-level port"}
            lappend ports $port
        }
        if {![llength $loads] && ![llength $ports]} {continue}
        set value [expr {$type eq "POWER" ? 1 : 0}]
        foreach pin $loads {puts $endpoints [join [list I [[$pin getInst] getName] [[$pin getMTerm] getName] $value] "\t"]}
        foreach port $ports {puts $endpoints [join [list P [$port getName] $value] "\t"]}
        set master_name [expr {$value ? "TIEHIx1_ASAP7_75t_R" : "TIELOx1_ASAP7_75t_R"}]
        set pin_name [expr {$value ? "H" : "L"}]
        set master [$db findMaster $master_name]
        if {$master eq "NULL" || $master eq ""} {error "missing tie master $master_name"}
        set name __literal_tie_${count}
        if {[$block findInst $name] ne "NULL"} {error "tie instance collision $name"}
        # Changing the constant-net type makes its loads visible to STA and GRT.
        $net setSigType SIGNAL
        foreach port $ports {$port setSigType SIGNAL}
        set inst [odb::dbInst_create $block $master $name]
        set output [$inst findITerm $pin_name];$output connect $net
        puts $audit [join [list [$net getName] $value $name $master_name [llength $loads] [llength $ports]] "\t"]
        incr count
    }
    close $endpoints
    close $audit
    puts "Mapped $count literal constant nets to ASAP7 tie drivers."
}
proc repair_literal_ties {} {
    repair_tie_fanout TIELOx1_ASAP7_75t_R/L
    repair_tie_fanout TIEHIx1_ASAP7_75t_R/H
    set count 0
    foreach inst [[ord::get_db_block] getInsts] {
        if {[[$inst getMaster] getName] in {TIEHIx1_ASAP7_75t_R TIELOx1_ASAP7_75t_R}} {incr count}
    }
    text tie_count.txt $count
    # No logical pin may remain on an unroutable supply net.
    foreach net [[ord::get_db_block] getNets] {
        if {[$net getSigType] ni {POWER GROUND}} {continue}
        foreach pin [$net getITerms] {
            if {[[$pin getMTerm] getSigType] ni {POWER GROUND}} {error "unmapped constant pin on [$net getName]"}
        }
        if {[llength [$net getBTerms]]} {error "unmapped constant port on [$net getName]"}
    }
}


set_thread_count $cfg(threads)
define_corners SS FF
foreach corner {SS FF} {foreach lib $cfg(lib_$corner) {read_liberty -corner $corner $lib}}
read_lef $cfg(tech_lef)
read_lef $cfg(cell_lef)
read_verilog $cfg(netlist)
link_design $cfg(top)
read_sdc [path input.sdc]
set_units -time ps -capacitance fF -resistance kOhm -power mW
source $cfg(rc)
dump_graph synthesized
map_literal_ties
repair_literal_ties
dump_graph original
set clocks [open [path primary_clock_nets.txt] w]
foreach name $cfg(clock_ports) {
    set port [[ord::get_db_block] findBTerm $name]
    if {$port eq "NULL"} {error "clock port not found: $name"}
    set net [$port getNet]
    $net setSigType CLOCK
    set_dont_touch [get_nets [$net getName]]
    puts $clocks [$net getName]
}
close $clocks
proc fanouts {stage} {
    set f [open [path ${stage}_fanout.tsv] w]
    puts $f "net\tloads\tclock"
    foreach net [[ord::get_db_block] getNets] {
        if {[$net getSigType] in {POWER GROUND}} {continue}
        set loads 0
        foreach pin [$net getITerms] {if {[[$pin getMTerm] getIoType] in {INPUT INOUT}} {incr loads}}
        foreach pin [$net getBTerms] {if {[$pin getIoType] in {OUTPUT INOUT}} {incr loads}}
        puts $f [join [list [$net getName] $loads [expr {[$net getSigType] eq "CLOCK"}]] "\t"]
    }
    close $f
}
fanouts before
repair_design -pre_placement -verbose
fanouts after
set b [ord::get_db_block]
set core [$b getCoreArea]
if {[$core dx] != 0 || [$core dy] != 0 || [llength [$b getRows]]} {error "repair must precede floorplanning"}
foreach inst [$b getInsts] {$inst setPlacementStatus NONE}
dump_graph frozen
write_db [path handoff.odb]
write_verilog [path netlist.v]
text done.marker "pre-floorplan repair complete; no rows or physical core"
exit
