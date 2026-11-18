# SeamGain

SeamGain predicts the reduction of routed wirelength that an RSC configuration
obtains relative to the uniform flow, and selects the configuration of a design
from one uniform reference run (Sections III-C and III-D of the paper).

| File | Contents |
| --- | --- |
| `seamgain.py` | Seam geometry, the model, its calibration, the configuration selection (Algorithm 1), and the loader of `data/` |
| `evaluate.py` | Reproduces the SeamGain results of the paper: fitted parameters, accuracy with whole designs held out, unseen designs, configuration selection, and the apply-or-not decision per case |
| `topk.py` | Selection with `k` RSC runs instead of one (the best of the `k` first-ranked configurations is kept) |
| `select_config.py` | Applies SeamGain to a design: reads one uniform reference run and prints the decision and the selected configuration |
| `parameters.json` | Parameters fitted on `tpu`, `ethmac` and `jpeg`, the packing limit, and the thresholds |

The scripts need Python 3 with `numpy`, `pandas` and `scipy`. Run them from the
repository root.


## Reproducing the results

```bash
python3 seamgain/evaluate.py
python3 seamgain/topk.py
```

`evaluate.py` prints, in this order:

1. the fitted parameters per held-out design and for all three training designs;
2. the accuracy with whole designs held out, with the ridge-regression reference
   on geometric features;
3. predicted and measured reductions of the unseen designs;
4. the reduction of the SeamGain-selected configuration against the ridge
   reference, random configurations, the median configuration and the best of
   the sweep, and the best swept configurations re-scored on the placement
   seeds that were not used to pick them;
5. the decision of whether to apply RSC for every case with a packing-feasible
   candidate.


`topk.py` reports how the selected reduction changes when Algorithm 1 returns
its `k` first-ranked configurations and the best measured one is kept. 

`python3 seamgain/evaluate.py --write-parameters` regenerates
`parameters.json`.

## Selecting the configuration of a design

1. Run the uniform flow (`width 0` and `height 0` in
   `flow/openroad/config.tcl`) with OpenROAD's metrics output. SeamGain uses the
   stages up to the legalization that follows CTS.

   ```bash
   openroad -exit flow/openroad/build_handoff.tcl
   openroad -exit -metrics uniform_metrics.json flow/openroad/flow.tcl
   ```

2. Read the core width and height in micrometers, for example in OpenROAD after
   loading the placed design:

   ```tcl
   set block [ord::get_db_block]
   set core [$block getCoreArea]
   set dbu [$block getDbUnitsPerMicron]
   puts "[expr {[$core dx] / double($dbu)}] [expr {[$core dy] / double($dbu)}]"
   ```

3. Select the configuration.

   ```bash
   python3 seamgain/select_config.py --metrics uniform_metrics.json \
       --core-width-um 75.762 --core-height-um 75.6
   ```

   The script prints the inputs measured in the reference run, the decision
   (apply RSC, or keep the uniform flow), and the selected configuration as
   `width`, `height`, `pitch_x`, `pitch_y` and `delta` settings for
   `flow/openroad/config.tcl`. `--k N` lists the `N` first-ranked
   configurations. `--candidates FILE.csv` replaces the default candidates (the
   144 configurations of the sweep) by the rows of a CSV file with the columns
   `width_sites`, `height_rows`, `pitch_sites`, `pitch_rows` and `block_delta`.

The decision uses `parameters.json`: RSC is applied only if the best predicted
reduction among the packing-feasible candidates is at least `tau`; candidates
whose packing density exceeds `delta_max`, or whose seam density target is
below 5%, are not considered.
