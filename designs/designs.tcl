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
