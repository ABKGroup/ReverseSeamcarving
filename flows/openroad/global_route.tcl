proc rsc::global_route {} {
    ::global_route \
        -guide_file [output_path route.guide] \
        -congestion_iterations 50 \
        -congestion_report_file [output_path congestion.rpt] \
        -allow_congestion \
        -verbose
    report_wire_length \
        -net {*} \
        -global_route \
        -file [output_path grt_wirelength.csv]
    report_wire_length -global_route -summary
    write_global_route_segments [output_path route.segments]
    placement_timing grt -global_routing
    write_def [output_path grt.def]
    write_db [output_path grt.odb]
}
