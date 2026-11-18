# Portable configuration for the released OpenROAD flow.
# ASAP7_ROOT can override the bundled pdk/ASAP7 directory.
proc setting {name default} {
    if {[info exists ::env($name)] && $::env($name) ne ""} {
        return $::env($name)
    }
    return $default
}
set flow_dir [file dirname [file normalize [info script]]]
set repo_root [file normalize [file join $flow_dir ../..]]
set pdk [file normalize [setting ASAP7_ROOT [file join $repo_root pdk ASAP7]]]
# Accept compressed bundled files and uncompressed external installations.
proc pdk_file {relative_path} {
    set path [file join $::pdk $relative_path]
    if {[file exists ${path}.gz]} {return ${path}.gz}
    return $path
}
set design [setting RSC_DESIGN jpeg]
set design_top(jpeg) {jpeg_encoder}
set design_clocks(jpeg) [list {clk}]
set design_top(ethmac) {ethmac}
set design_clocks(ethmac) [list {wb_clk_i} {mtx_clk_pad_i} {mrx_clk_pad_i}]
set design_top(cva6_no_sram) {cva6}
set design_clocks(cva6_no_sram) [list {clk_i}]
set design_top(mempool_tile_no_macro) {mempool_tile_wrap}
set design_clocks(mempool_tile_no_macro) [list {clk_i}]
set design_top(swerv_no_macro) {swerv_wrapper}
set design_clocks(swerv_no_macro) [list {clk}]
set design_top(tpu) {tpu}
set design_clocks(tpu) [list {clk}]
if {![info exists design_top($design)]} {error "Unknown design $design"}
set cfg(top) $design_top($design)
set cfg(clock_ports) $design_clocks($design)
set cfg(netlist) [setting RSC_NETLIST [file join $repo_root designs $design netlist.v]]
set cfg(tech_lef) [pdk_file lef/asap7_tech_1x_201209.lef]
set cfg(cell_lef) [pdk_file lef/asap7sc7p5t_28_R_1x_220121a.lef]
set cfg(lib_FF) [list \
    [pdk_file lib/asap7sc7p5t_AO_RVT_FF_nldm_211120.lib] \
    [pdk_file lib/asap7sc7p5t_DFFHQNH2V2X_RVT_FF_nldm_FAKE.lib] \
    [pdk_file lib/asap7sc7p5t_DFFHQNV2X_RVT_FF_nldm_FAKE.lib] \
    [pdk_file lib/asap7sc7p5t_DFFHQNV4X_RVT_FF_nldm_FAKE.lib] \
    [pdk_file lib/asap7sc7p5t_INVBUF_RVT_FF_nldm_220122.lib] \
    [pdk_file lib/asap7sc7p5t_OA_RVT_FF_nldm_211120.lib] \
    [pdk_file lib/asap7sc7p5t_SEQ_RVT_FF_nldm_220123.lib] \
    [pdk_file lib/asap7sc7p5t_SIMPLE_RVT_FF_nldm_250407.lib]]
set cfg(lib_SS) [list \
    [pdk_file lib/asap7sc7p5t_AO_RVT_SS_nldm_211120.lib] \
    [pdk_file lib/asap7sc7p5t_DFFHQNH2V2X_RVT_SS_nldm_FAKE.lib] \
    [pdk_file lib/asap7sc7p5t_DFFHQNV2X_RVT_SS_nldm_FAKE.lib] \
    [pdk_file lib/asap7sc7p5t_DFFHQNV4X_RVT_SS_nldm_FAKE.lib] \
    [pdk_file lib/asap7sc7p5t_INVBUF_RVT_SS_nldm_220122.lib] \
    [pdk_file lib/asap7sc7p5t_OA_RVT_SS_nldm_211120.lib] \
    [pdk_file lib/asap7sc7p5t_SEQ_RVT_SS_nldm_220123.lib] \
    [pdk_file lib/asap7sc7p5t_SIMPLE_RVT_SS_nldm_211120.lib]]
set cfg(rc) [file join $flow_dir support rc.tcl]
set cfg(tracks) [file join $flow_dir support tracks.tcl]
set cfg(rcx) [file join $flow_dir support rcx.rules]
set cfg(stage) [setting RSC_STAGE grt]
set cfg(threads) [setting RSC_THREADS 8]
set cfg(util) [setting RSC_UTIL 0.90]
set cfg(width) [setting RSC_WIDTH_SITES 0]
set cfg(height) [setting RSC_HEIGHT_ROWS 0]
set cfg(pitch_x) [setting RSC_PITCH_SITES 300]
set cfg(pitch_y) [setting RSC_PITCH_ROWS 75]
set cfg(delta) [setting RSC_DELTA 0.02]
set cfg(placement_seed) [setting RSC_SEED 1]
set cfg(placement_overflow) [setting RSC_OVERFLOW 0.05]
if {$cfg(stage) ni {grt detail}} {error "RSC_STAGE must be grt or detail"}
if {$cfg(util)<=0 || $cfg(util)>=1} {error "RSC_UTIL must be in (0,1)"}
if {$cfg(width)<0 || $cfg(height)<0 || $cfg(delta)<0} {error "Negative seam parameter"}
if {($cfg(width)>0 || $cfg(height)>0) && ($cfg(pitch_x)<=0 || $cfg(pitch_y)<=0)} {
    error "Seams require positive paired pitches"
}
set default_out [file join $repo_root work $design \
    u$cfg(util)_w$cfg(width)_h$cfg(height)_p$cfg(pitch_x)x$cfg(pitch_y)_d$cfg(delta)_s$cfg(placement_seed)_o$cfg(placement_overflow)]
set cfg(out) [file normalize [setting RSC_OUT $default_out]]
set cfg(handoff_odb) [file normalize [setting RSC_HANDOFF \
    [file join $repo_root work handoffs $design handoff.odb]]]
file mkdir $cfg(out)
set sdc [setting RSC_SDC [file join $repo_root designs $design constraints.sdc]]
if {[file normalize $sdc] ne [file join $cfg(out) input.sdc]} {
    file copy -force $sdc [file join $cfg(out) input.sdc]
}
