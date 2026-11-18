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
proc main {} {
    set_thread_count $::cfg(threads)
    define_corners SS FF
    foreach corner {SS FF} {foreach lib $::cfg(lib_$corner) {read_liberty -corner $corner $lib}}
    if {$::cfg(stage) eq "grt"} {
        read_db $::cfg(handoff_odb)
    } else {read_db [path grt.odb]}
    read_sdc [path input.sdc]
    set_units -time ps -capacitance fF -resistance kOhm -power mW
    report_file units.rpt {report_units}
    source $::cfg(rc)
    if {$::cfg(stage) ne "grt"} {set_routing_layers -signal M1-M6 -clock M1-M6; set_global_routing_layer_adjustment M1-M6 0.25}
    if {$::cfg(stage) eq "grt"} {
        set ::phase import
        dump_graph original
        initialize_floorplan -utilization [expr {100*$::cfg(util)}] -aspect_ratio 1 -core_space 0.2 -site asap7sc7p5t
        source $::cfg(tracks)
        set_routing_layers -signal M1-M6 -clock M1-M6; set_global_routing_layer_adjustment M1-M6 0.25
        seams
        set_dont_touch [get_cells -hierarchical *]
        set_dont_touch [get_nets -hierarchical *]
        set ::phase initial_skip_io
        set d [density]
        global_placement -random_seed $::cfg(placement_seed) -skip_io -disable_pin_density_adjust -density $d
        snapshot skip_io
        set ::phase io_placement
        place_pins -hor_layers {M4 M6} -ver_layers {M3 M5}
        foreach term [[ord::get_db_block] getBTerms] {foreach pin [$term getBPins] {$pin setPlacementStatus FIRM}}
        snapshot assigned_io
        set ::phase global_placement
        set args [list -random_seed $::cfg(placement_seed) -force_center_initial_place -routability_driven -disable_pin_density_adjust -overflow $::cfg(placement_overflow) -density $d]
        if {$::cfg(mode) eq "timing_routability"} {lappend args -timing_driven -keep_resize_below_overflow 0.0}
        global_placement {*}$args
        set ::phase legalization
        write_db [path global_placed.odb]
        legalize placed 0
        snapshot placed
        timing placed -placement
        set ::phase cts
        unset_dont_touch [get_nets -hierarchical *]
        # OpenDB forbids reconnecting a dont-touch instance clock pin. Only CTS
        # runs in this window; graph/master checks enforce preservation afterward.
        unset_dont_touch [get_cells -hierarchical *]
        # The installed CTS crashes/misses sink lookups with preclustering.
        # Use a uniform x2 tree to avoid that path and excessive clock-cell area.
        clock_tree_synthesis -buf_list {BUFx2_ASAP7_75t_R} -root_buf BUFx2_ASAP7_75t_R -tree_buf BUFx2_ASAP7_75t_R -dont_use_dummy_load -repair_clock_nets
        write_db [path cts_unlegalized.odb]
        legalize cts 0
        set_propagated_clock [all_clocks]
        snapshot postcts
        set f [open [path clock_members.txt] w]
        set n [open [path clock_nets.txt] w]
        foreach net [[ord::get_db_block] getNets] {if {[$net getSigType] eq "CLOCK"} {puts $n [$net getName];foreach pin [$net getITerms] {puts $f [[$pin getInst] getName]}}}
        close $f;close $n
        timing postcts -placement
        set_dont_touch [get_cells -hierarchical *];set_dont_touch [get_nets -hierarchical *]
        foreach inst [[ord::get_db_block] getInsts] {$inst setPlacementStatus FIRM}
        set ::phase global_routing
        global_route -guide_file [path route.guide] -congestion_iterations 50 -congestion_report_file [path congestion.rpt] -allow_congestion -verbose
        report_wire_length -net {*} -global_route -file [path grt_wirelength.csv]
        report_wire_length -global_route -summary
        write_global_route_segments [path route.segments]
        timing grt -global_routing
        snapshot grt
        write_db [path grt.odb]
        text grt_done.marker "global route completed; inspect overflow and guards"
    } else {
        set ::phase detail_route
        read_guides [path route.guide]
        set_dont_touch [get_cells -hierarchical *];set_dont_touch [get_nets -hierarchical *]
        set_propagated_clock [all_clocks]
        detailed_route -output_drc [path drc.rpt] -output_guide_coverage [path guide_coverage.rpt] -droute_end_iter 32 -or_seed 1 -verbose 1
        text routed_status.txt [design_is_routed -verbose]
        text drc_count.txt [drt::detailed_route_num_drvs]
        snapshot routed
        write_db [path routed.odb]
        set ::phase extracted_timing
        define_process_corner -ext_model_index 0 ORD_NOMINAL_RC
        extract_parasitics -ext_model_file $::cfg(rcx)
        write_spef [path routed.spef]
        read_spef -corner SS [path routed.spef]
        read_spef -corner FF [path routed.spef]
        report_wns -digits 6 > [path routed_setup_wns.rpt]
        report_tns -digits 6 > [path routed_setup_tns.rpt]
        report_wns -min -digits 6 > [path routed_hold_wns.rpt]
        report_tns -min -digits 6 > [path routed_hold_tns.rpt]
        report_checks -path_delay max -group_path_count 5 > [path routed_setup_paths.rpt]
        report_power -scene SS > [path routed_power.rpt]
        text detail_done.marker "detail route completed; inspect DRC, route coverage, guards"
    }
}
proc phase_trace {args} {puts "ORD_PHASE $::phase";flush stdout}
trace add variable ::phase write phase_trace
set ::phase setup
if {[catch {main} message options]} {
    text failure.txt [list phase $::phase message $message]
    puts stderr [dict get $options -errorinfo]
    exit 1
}
exit
