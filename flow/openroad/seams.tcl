# Generate a disjoint union of vertical and horizontal seam rectangles.
# Geometry is in micrometers. Pitches are measured from the core origin.
proc rsc::seam_intervals {origin limit pitch width} {
    set intervals {}
    if {$width <= 0} {
        return $intervals
    }
    for {set start [expr {$origin + $pitch}]} \
        {$start < $limit - 1e-9} \
        {set start [expr {$start + $pitch}]} {
        set end [expr {min($start + $width, $limit)}]
        lappend intervals [list $start $end]
    }
    return $intervals
}

proc rsc::interval_total_length {intervals} {
    set width 0.0
    foreach interval $intervals {
        lassign $interval start end
        set width [expr {$width + $end - $start}]
    }
    return $width
}

proc rsc::seam_rectangles {core_bounds vertical horizontal} {
    lassign $core_bounds x0 y0 x1 y1
    set rectangles {}
    foreach interval $vertical {
        lassign $interval left right
        lappend rectangles [list $left $y0 $right $y1]
    }

    # Split horizontal strips at vertical strips to avoid double blockage.
    foreach interval $horizontal {
        lassign $interval bottom top
        set left $x0
        foreach vertical_interval $vertical {
            lassign $vertical_interval seam_left seam_right
            if {$seam_left > $left} {
                lappend rectangles [list $left $bottom $seam_left $top]
            }
            set left $seam_right
        }
        if {$left < $x1} {
            lappend rectangles [list $left $bottom $x1 $top]
        }
    }
    return $rectangles
}

proc rsc::apply_seams {} {
    global cfg
    if {$cfg(width) == 0 && $cfg(height) == 0} {
        return
    }

    set block [ord::get_db_block]
    set core [$block getCoreArea]
    set dbu [$block getDbUnitsPerMicron]
    set x0 [expr {double([$core xMin]) / $dbu}]
    set y0 [expr {double([$core yMin]) / $dbu}]
    set x1 [expr {double([$core xMax]) / $dbu}]
    set y1 [expr {double([$core yMax]) / $dbu}]
    set core_width [expr {$x1 - $x0}]
    set core_height [expr {$y1 - $y0}]

    set seam_width [expr {$cfg(width) * 0.054}]
    set seam_height [expr {$cfg(height) * 0.270}]
    set pitch_x [expr {$cfg(pitch_x) * 0.054}]
    set pitch_y [expr {$cfg(pitch_y) * 0.270}]
    set vertical [seam_intervals $x0 $x1 $pitch_x $seam_width]
    set horizontal [seam_intervals $y0 $y1 $pitch_y $seam_height]
    set vertical_width [interval_total_length $vertical]
    set horizontal_height [interval_total_length $horizontal]

    set core_area [expr {$core_width * $core_height}]
    set seam_area [expr {
        $vertical_width * $core_height
        + $horizontal_height * $core_width
        - $vertical_width * $horizontal_height
    }]
    set seam_fraction [expr {$seam_area / $core_area}]
    if {$seam_fraction <= 0} {
        error "The requested pitches produce no seams inside the core"
    }

    # Preserve total nominal cell area while raising density outside seams.
    set block_utilization [expr {$cfg(util) + $cfg(delta)}]
    set seam_utilization [expr {
        ($cfg(util) - (1 - $seam_fraction) * $block_utilization)
        / $seam_fraction
    }]
    if {$seam_utilization > 1} {
        error "The requested block and seam utilizations are infeasible"
    }
    set hard_blockage [expr {$seam_utilization < 0.05}]
    set density_percent [expr {
        $hard_blockage ? 0 : round(100 * $seam_utilization)
    }]
    set rectangles [seam_rectangles \
        [list $x0 $y0 $x1 $y1] $vertical $horizontal]
    foreach rectangle $rectangles {
        if {$hard_blockage} {
            create_blockage -region $rectangle
        } else {
            create_blockage -region $rectangle -max_density $density_percent
        }
    }
    write_text seams.txt [list \
        fraction $seam_fraction \
        requested $seam_utilization \
        command_density_percent $density_percent \
        hard $hard_blockage \
        outside_target $block_utilization \
        boxes $rectangles]
}
