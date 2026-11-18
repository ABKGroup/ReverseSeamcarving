# Choose the placement target from cell area and blockage-adjusted capacity.
proc rsc::placement_density {} {
    set block [ord::get_db_block]
    set core [$block getCoreArea]
    set core_area [expr {double([$core dx]) * [$core dy]}]
    set cell_area 0.0
    foreach instance [$block getInsts] {
        set master [$instance getMaster]
        set cell_area [expr {
            $cell_area + double([$master getWidth]) * [$master getHeight]
        }]
    }

    set reserved_area 0.0
    foreach blockage [$block getBlockages] {
        set box [$blockage getBBox]
        set area [expr {
            double([$box xMax] - [$box xMin])
            * ([$box yMax] - [$box yMin])
        }]
        set reserved_area [expr {
            $reserved_area + $area * (1 - [$blockage getMaxDensity] / 100.0)
        }]
    }
    set minimum_density [expr {$cell_area / ($core_area - $reserved_area)}]
    set target_density [expr {max(0.95, $minimum_density + 0.005)}]
    if {$target_density >= 1} {
        error "Cell area and seam capacity leave no feasible placement target"
    }
    return $target_density
}
