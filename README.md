# Reverse Seamcarving

Reverse seamcarving (RSC) redistributes placement density to create routing channels
between denser blocks of cells. This repository provides the OpenROAD flow,
the repaired mapped netlists used by that flow, and OpenROAD measurement data
for reviewing the experiments.

The baseline and seamcarved configurations use the same repaired netlist,
floorplan utilization, and placement/routing settings. Seam geometry and the
requested utilization increment within the blocks distinguish the carved cases.

## Repository contents

| Path | Contents |
| --- | --- |
| `flows/openroad/flow.tcl` | Seam generation, placement, CTS, global routing, and separate detailed routing |
| `flows/openroad/config.tcl` | Portable design, technology, and experiment configuration |
| `flows/openroad/build_handoff.tcl` | Import a released repaired netlist into OpenDB |
| `flows/openroad/preprocess.tcl` | Original constant-net mapping, tie-fanout repair, and pre-floorplan repair procedure |
| `flows/openroad/verify_netlist.py` | Structural checks for preserved cells, masters, connectivity, and CTS-only insertion |
| `flows/openroad/support/` | RC, track, and extraction support used in the experiments |
| `designs/` | Six repaired OpenROAD Verilog netlists, their SDCs, and preprocessing provenance |
| `genus/synthesize.tcl` | Genus synthesis driver used to create the mapped inputs |
| `data/` | OpenROAD DOE definitions, per-run measurements, and summary CSVs |

## Designs

| Identifier | Top module | Description |
| --- | --- | --- |
| `ethmac` | `ethmac` | Ethernet MAC |
| `jpeg` | `jpeg_encoder` | JPEG encoder |
| `cva6_no_sram` | `cva6` | Macro-free CVA6 variant |
| `swerv_no_macro` | `swerv_wrapper` | Macro-free SweRV variant |
| `mempool_tile_no_macro` | `mempool_tile_wrap` | Macro-free MemPool tile variant |
| `tpu` | `tpu` | TPU design |

Each `designs/<identifier>/` directory contains `netlist.v`, `constraints.sdc`,
and `provenance.json`. These Verilog files are the frozen OpenROAD handoffs
**after pre-floorplan repair and before placement or CTS**. The preprocessing
maps constant nets onto ASAP7 tie cells, repairs tie-cell fanout, and runs
`repair_design -pre_placement`, allowing signal buffering and cell resizing.
Baseline and RSC share this resulting netlist. Existing synthesis buffers remain.

The data contains OpenROAD results. The `genus/` directory contains the synthesis
driver only. No Genus-only mapped netlists or Innovus place-and-route flow are
included.

## OpenROAD flow

The flow performs the following stages.

1. Import the repaired netlist and create a floorplan from its cell area.
2. Generate vertical and horizontal seams on the legal site/row grid.
3. Run initial placement with `-skip_io`.
4. Assign IO pins and fix their locations.
5. Run fresh routability-driven placement with the seams applied.
6. Remove partial density screens for detailed legalization and legalize cells.
   Hard blockages remain.
7. Build the clock tree and legalize its buffers.
8. Run global routing and save its OpenDB checkpoint and routing guides.
9. Restore that checkpoint for detailed routing, followed by extraction and
   timing reports.

The placement-stage density screens shape the global placement. Their partial
constraints are removed by the existing legalization procedure, so the final
placement can fill part of the requested channels. This behavior matches the
saved experimental flow.

The signal netlist stays fixed after preprocessing. CTS uses
`BUFx2_ASAP7_75t_R` buffers and `-repair_clock_nets`. There is no post-CTS
`repair_timing` step. The structural checker verifies that original cells retain
their masters and logical connectivity, with clock-buffer insertion permitted.

Signals and clocks use M1--M6. Global routing applies a 25% layer-capacity
reduction, allows residual congestion, and uses a congestion-iteration budget
of 50. Detailed routing uses a limit of 32 and restores the saved global-route
guides. A clean DRT result requires the completed route to pass its routing and
DRC checks.

### Seam parameters

`U` is the floorplan utilization and `Delta` is an additive utilization increment
for the regions between seams. Both are fractions. For example, `U=0.90` and
`Delta=0.02` request 92% block utilization.

For seam-area fraction `f`, the requested density inside the seams is

```text
seam_density = [U - (1 - f) * (U + Delta)] / f
```

The implementation computes `f` from the actual clipped seam rectangles,
accounting for intersections once. It uses rounded percentage density screens,
or hard blockages when the requested seam density falls below 5%. Generated
rectangles and densities are recorded in `seams.txt`.

Widths and horizontal pitch are specified in sites, with 0.054 micrometers per
site. Heights and vertical pitch are specified in rows, with 0.270 micrometers
per row. A pitch of `240/60` therefore means 240 sites in X and 60 rows in Y.
Zero seam width and height select the baseline.

The seam procedure balances nominal cell area between blocks and seams, then
rounds the requested seam utilization to the native blockage-density setting.
A requested seam utilization below 5% uses a hard placement blockage. Partial
density screens guide global placement and are removed before detailed
placement. Hard placement blockages remain. The selected density, seam area,
and rectangles are written to `seams.txt`.

The flow performs initial skip-IO placement, places IO pins, restarts main
routability-driven placement, legalizes, inserts a clock tree, and legalizes
again. The signal netlist retains its original instances and cell masters through
these stages. CTS is the only permitted source of new cells after preprocessing.
GRT uses M1--M6 with a 25% capacity reduction and up to 50 congestion iterations.
DRT restores the saved guides and database and uses an end-iteration limit of
32. It runs pin access as part of native detailed routing. Placement and CTS
are completed before either routing stage.

## Running an individual configuration

The experiments use OpenROAD commit
`e2820c8efda9ccf9949ec439456f699615b0dc47`, built with the commands used in these
Tcl files. Python 3.10 or newer is used for structural verification. The PDK must provide
the ASAP7 RVT LEF and SS/FF Liberty files listed in `config.tcl`.

From the repository root, set the PDK location and the configuration file.

```bash
export ASAP7_ROOT=/path/to/ASAP7
export ORD_CONFIG="$PWD/flows/openroad/config.tcl"
export RSC_DESIGN=jpeg
```

Reconstruct the shared repaired-netlist handoff once for the chosen design.

```bash
openroad -exit flows/openroad/build_handoff.tcl
```

Run a seamcarved configuration through placement, CTS, and global routing.

```bash
export RSC_UTIL=0.90
export RSC_WIDTH_SITES=15
export RSC_HEIGHT_ROWS=2
export RSC_PITCH_SITES=260
export RSC_PITCH_ROWS=65
export RSC_DELTA=0.03
export RSC_SEED=1
export RSC_OVERFLOW=0.05
export RSC_OUT="$PWD/work/jpeg_example"
export RSC_STAGE=grt
openroad -exit flows/openroad/flow.tcl
python3 flows/openroad/verify_netlist.py "$RSC_OUT"
```

Continue that exact saved configuration through detailed routing.

```bash
export RSC_STAGE=detail
openroad -exit flows/openroad/flow.tcl
python3 flows/openroad/verify_netlist.py "$RSC_OUT" --stage detail
```

The DRT command uses `grt.odb` and `route.guide` in the same `RSC_OUT` directory.
Keep the design and configuration variables the same between these stages.
For the corresponding baseline, set both seam dimensions to zero and choose
another output directory. Use the same utilization, seed, and overflow target.

Continue the same configuration through detailed routing using its saved
GRT database and route guides. Keep `RSC_OUT` and all configuration settings
from the preceding command.

```bash
export RSC_STAGE=detail
openroad -exit flows/openroad/flow.tcl
python3 flows/openroad/verify_netlist.py "$RSC_OUT" --stage detail
```

After GRT alone, the structural check is available with
`python3 flows/openroad/verify_netlist.py "$RSC_OUT" --stage grt`.

The JPEG example above has been checked through GRT and DRT with zero final
DRC violations. Structural verification preserves all 48,276 original
instances and records 581 CTS buffers with zero added signal cells. The other
five design configurations pass input-path and Tcl configuration checks.
Verilog re-import can escape hierarchy separators in instance and net names;
the repaired JPEG topology matches after normalizing that naming convention.

### Configuration reference

| Variable | Default | Meaning |
| --- | --- | --- |
| `ASAP7_ROOT` | Required | External PDK root |
| `ORD_CONFIG` | Required | Path to `flows/openroad/config.tcl` |
| `RSC_DESIGN` | `jpeg` | Released design identifier |
| `RSC_UTIL` | `0.90` | Floorplan utilization |
| `RSC_WIDTH_SITES` | `0` | Vertical seam width |
| `RSC_HEIGHT_ROWS` | `0` | Horizontal seam height |
| `RSC_PITCH_SITES` | `300` | X seam pitch |
| `RSC_PITCH_ROWS` | `75` | Y seam pitch |
| `RSC_DELTA` | `0.02` | Additive block-utilization increment |
| `RSC_SEED` | `1` | Global placement random seed |
| `RSC_OVERFLOW` | `0.05` | Main-placement stopping overflow target |
| `RSC_THREADS` | `8` | Threads per OpenROAD process |
| `RSC_STAGE` | `grt` | `grt` or `detail` |
| `RSC_OUT` | Generated under `work/` | Outputs for this physical configuration |
| `RSC_HANDOFF` | `work/handoffs/<design>/handoff.odb` | Reconstructed repaired input |
| `RSC_NETLIST` | Released `netlist.v` | Optional alternate mapped Verilog input |
| `RSC_SDC` | Released `constraints.sdc` | Optional alternate constraints |

`preprocess.tcl` is provided for inspecting or applying the original preparation
procedure to an alternate, unrepaired mapped input. The released netlists have
already undergone this step. To use preprocessing on another mapped input,
set `RSC_NETLIST`, `RSC_SDC`, and `RSC_OUT` to that input and a dedicated handoff
output directory, then invoke `openroad -exit flows/openroad/preprocess.tcl`.
It writes `handoff.odb` and `netlist.v` to that directory. Use the resulting ODB
as `RSC_HANDOFF` for subsequent physical runs.

## Experimental coverage

Utilizations 90%, 91%, 92%, and 93% are evaluated separately. The widened grid
covers JPEG, ethmac, and TPU.

| Parameter | Original grid | Widened grid |
| --- | --- | --- |
| Block-utilization increment | +2%, +4%, +6% | +1%, +2%, +3%, +4%, +5%, +6% |
| Paired pitch, sites/rows | 280/70, 300/75, 320/80 | 240/60, 260/65, 280/70, 300/75, 320/80, 360/90 |
| Vertical width, sites | 10, 15 | 10, 15 |
| Horizontal height, rows | 2, 3 | 2, 3 |

Five global-placement seeds use the same nominal SDC. Selected configurations
receive detailed routing from their saved GRT handoffs. Single-axis controls
are retained in the data with their corresponding `kind`. The overflow
experiment repeats the widened grid at main-placement stopping targets 0.15
and 0.20. Its latest selection policy denoises five configurations and routes
three, each with five seeds, plus the baseline. That experiment remains a
partial snapshot as of the export date in `data/snapshot.json`.

## Results and CSV definitions

| File | Contents |
| --- | --- |
| `data/design_statistics.csv` | Repaired pre-CTS instance, logical-net, IO, and cell-area counts |
| `data/doe.csv` | Planned configurations for the original, widened, and overflow experiments |
| `data/openroad_measurements.csv` | Available per-configuration/per-seed GRT and DRT measurements and completion status |
| `data/openroad_summary.csv` | Best measured configurations per design, utilization, overflow, and routing stage |
| `data/snapshot.json` | Export date, tool version, row counts, and snapshot coverage |

Planned configurations and measurement rows have different purposes. A row in
`doe.csv` identifies the intended experiment. A measurement row records an
observed saved result. Identical control configurations are reused across the
original and widened grids and appear once in the measurement data. Known interrupted ethmac baseline
attempts are marked `incomplete`.

The summary minimizes configuration-median wirelength over the eligible
completed samples. It compares the RSC median against the median available
baseline at the same design, utilization, overflow target, and routing stage.
An `rwl_ratio` below 1 indicates improvement. `improvement_pct` is
`100 * (1 - rwl_ratio)`. Baseline and RSC sample counts identify partial coverage.
Summary rows with RSC measurements but no baseline retain their absolute WL and
leave the ratio empty.

| Measurement column | Definition |
| --- | --- |
| `experiment` | `control` for overflow 0.05, or `overflow` for the weakening study |
| `design`, `config`, `placement_seed` | Portable identifiers for a measurement |
| `util_pct` | Floorplan utilization as a percentage |
| `kind` | Baseline, combined seams, or a single-axis control |
| `width_sites`, `height_rows` | Seam dimensions |
| `pitch_sites`, `pitch_rows` | Paired X/Y pitches |
| `block_delta` | Additive block-utilization increment as a fraction |
| `placement_overflow` | Main global-placement stopping target |
| `grt_status` | Saved global-route completion state |
| `grt_wl_um` | Native OpenROAD global-route wirelength in micrometers |
| `drt_status` | `completed_clean`, `failed`, `incomplete`, or `not_run` |
| `drt_wl_um` | Native detailed-route wirelength in micrometers, when available |
| `drt_drc` | Saved detailed-route violation count |

Wirelength columns use native router measurements, including routed clock
networks. They do not use the separately extracted non-clock WL metric from
some earlier working tables. DRT summary comparisons use clean completed
samples. A failed sample can still have a reported WL value, but contributes
no clean DRT summary measurement. Empty values represent unavailable results.
Machine-specific filesystem paths have been replaced with portable identifiers.

`design_statistics.csv` counts the repaired netlist before CTS. Logical-net
counts include connected clock nets and exclude power/ground connectivity.
Cell area is the sum of instantiated LEF master areas, in square micrometers.

## Genus synthesis driver

`genus/synthesize.tcl` records the upstream synthesis recipe. It runs
`syn_generic`, `syn_map`, and `syn_opt` with the low-effort settings used by the
source driver. It expects user-supplied RTL and the following environment
variables.

| Variable | Meaning |
| --- | --- |
| `CONTRA2_SYNTH_THREADS` | Synthesis CPU count |
| `CONTRA2_SYNTH_LIBS` | Space-separated timing-library paths |
| `CONTRA2_SYNTH_SDC` | Input SDC path |
| `CONTRA2_SYNTH_TOP` | RTL top module |
| `CONTRA2_SYNTH_RTL` | Space-separated RTL file paths |
| `CONTRA2_SYNTH_INCLUDES` | Include directories; may be empty |
| `CONTRA2_SYNTH_DEFINES` | Preprocessor definitions; may be empty |
| `CONTRA2_SYNTH_OUT` | Existing output directory |

The released OpenROAD inputs additionally contain the shared preprocessing
changes described above. Original macro-removal transformations for CVA6,
SweRV, and MemPool are reflected in those supplied inputs.

## Technology and provenance

The experiments use external ASAP7 RVT technology/cell LEFs and SS/FF Liberty
views. The exact filenames are listed in `flows/openroad/config.tcl`. The
technology files and tool installations must be supplied separately.

The small RC, track, and OpenRCX support files in `flows/openroad/support/`
originate from the ASAP7 platform support in
[OpenROAD-flow-scripts](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts/tree/master/flow/platforms/asap7).
They provide OpenROAD-compatible estimation and extraction support. The RC
model is distinct from the Cadence QRC model used in the separate Innovus study.

Per-design `provenance.json` files record the repaired handoff stage and
preprocessing counts. Generated OpenDB files and physical outputs are written
under the ignored `work/` directory when the flow is run.
