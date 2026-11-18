proc rsc::seam_intervals {lo hi pitch width} {
    set spans {}
    if {$width <= 0} { return $spans }
    for {set x [expr {$lo+$pitch}]} {$x < $hi-1e-9} {set x [expr {$x+$pitch}]} { lappend spans [list $x [expr {min($x+$width,$hi)}]] }
    return $spans
}
proc rsc::apply_seams {util delta width height pitch_x pitch_y} {
    if {$width == 0 && $height == 0} { return }
    set block [ord::get_db_block]; set core [$block getCoreArea]; set dbu [$block getDbUnitsPerMicron]
    lassign [lmap v [list [$core xMin] [$core yMin] [$core xMax] [$core yMax]] {expr {double($v)/$dbu}}] x0 y0 x1 y1
    set vertical [seam_intervals $x0 $x1 [expr {$pitch_x*0.054}] [expr {$width*0.054}]]
    set horizontal [seam_intervals $y0 $y1 [expr {$pitch_y*0.270}] [expr {$height*0.270}]]
    set vw 0.0; set hh 0.0; set boxes {}; set left $x0; set gaps {}
    foreach span $vertical {
        lassign $span a b; set vw [expr {$vw+$b-$a}]; lappend boxes [list $a $y0 $b $y1]
        if {$a > $left} { lappend gaps [list $left $a] }; set left $b
    }
    if {$left < $x1} { lappend gaps [list $left $x1] }
    foreach span $horizontal {
        lassign $span a b; set hh [expr {$hh+$b-$a}]
        foreach gap $gaps { lassign $gap l r; lappend boxes [list $l $a $r $b] }
    }
    set fraction [expr {1-(1-$vw/($x1-$x0))*(1-$hh/($y1-$y0))}]
    if {$fraction <= 0} { error "No seams inside core" }
    set density [expr {($util-(1-$fraction)*($util+$delta))/$fraction}]
    if {$density > 1} { error "Infeasible seam utilization" }
    set options [expr {$density < 0.05 ? {} : [list -max_density [expr {round(100*$density)}]]}]
    foreach box $boxes { create_blockage -region $box {*}$options }
}
proc rsc::remove_partial_seams {} {
    foreach b [[ord::get_db_block] getBlockages] { if {[$b getMaxDensity] > 0} { odb::dbBlockage_destroy $b } }
}
