"""Reproduce the SeamGain results of the paper from the measurement tables in data/.

    python3 seamgain/evaluate.py [--write-parameters]

Sections of the output:
  1. parameters fitted on each pair of training designs and on all three (Section IV-C)
  2. accuracy with whole designs held out, with the ridge-regression reference (Table V)
  3. unseen designs (Section IV-C)
  4. configuration selection with one RSC run (Table VI), and the best swept configurations re-scored
     on the placement seeds that were not used to pick them
  5. decision of whether to apply RSC, per case (Section IV-D)

tpu, ethmac and jpeg are held out in turn (the parameters are fitted on the other two); cva6, swerv
and mempool are never used to fit the parameters. All numbers are reductions of global-routing
wirelength against the median of the uniform baseline seeds, in percent.

--write-parameters stores the parameters fitted on the three training designs, the packing limit
and the thresholds in seamgain/parameters.json, which select_config.py reads.
"""
import argparse
import json
import os

import numpy as np
import pandas as pd

import seamgain as sg

FEASIBLE_DENSITY = 0.945        # "packing-feasible" configurations in the accuracy tables
RIDGE_LAMBDA = 10.0


def show(title, table, digits=2):
    print('\n--- ' + title)
    print(table.to_string(float_format=lambda v: ('%%.%df' % digits) % v))


def accuracy(df, predicted):
    error = predicted - df.y.values
    return dict(configs=len(df), mae=np.abs(error).mean(), pearson=np.corrcoef(predicted, df.y.values)[0, 1])


# --------------------------------------------------------------------------- reference: ridge regression on geometry only
def ridge_features(df):
    u, delta = df.util_pct.values / 100.0, df.block_delta.values
    fx, fy = df.width_sites.values / df.pitch_sites.values, df.height_rows.values / df.pitch_rows.values
    f = fx + fy - fx * fy
    q = delta / (1.0 - u)
    return np.c_[1.0 - np.sqrt(u / (u + delta)), q, q * q, fx, fy, f, f * f,
                 df.pitch_sites.values * sg.SITE_WIDTH_UM / df.core_width_um.values,
                 df.pitch_rows.values * sg.ROW_HEIGHT_UM / df.core_height_um.values, u]


def ridge_fit_predict(train, test):
    x, y = ridge_features(train), train.y.values
    mean, std = x.mean(0), x.std(0)
    std[std < 1e-12] = 1.0
    z = (x - mean) / std
    beta = np.linalg.solve(z.T.dot(z) + RIDGE_LAMBDA * np.eye(z.shape[1]), z.T.dot(y - y.mean()))
    return ((ridge_features(test) - mean) / std).dot(beta) + y.mean()


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--write-parameters', action='store_true')
    args = ap.parse_args()

    runs, reference = sg.load_dataset()
    seed1 = runs[runs.placement_seed == 1].copy()
    fitset = sg.fitting_runs(runs)
    full, unseen = sg.TRAINING_DESIGNS, sg.UNSEEN_DESIGNS
    print('runs used to fit and to score: %d (%d on tpu, ethmac and jpeg)' % (len(fitset), fitset.design.isin(full).sum()))

    # geometry check: the seam-area fraction computed from the configuration equals the one applied by the flow
    g = seed1.dropna(subset=['seam_fraction'])
    computed = np.array([sg.seam_fraction(a, b, c, d, e, f) for a, b, c, d, e, f in
                         zip(g.core_width_um, g.core_height_um, g.width_sites, g.height_rows, g.pitch_sites, g.pitch_rows)])
    print('seam-area fraction, computed versus applied by the flow: largest difference %.2e over %d configurations'
          % (np.abs(computed - g.seam_fraction.values).max(), len(g)))

    # ---------------- 1. parameters
    params, rows, predictions = {}, [], []
    for held in full:
        train = fitset[fitset.design.isin(sg.training_designs(held))]
        test = fitset[fitset.design == held]
        params[held] = sg.fit(train)
        pred = sg.predict(params[held], sg.model_inputs(test))
        predictions.append(test.assign(predicted=pred))
        feasible = (test.packing_density <= FEASIBLE_DENSITY).values
        a, b = accuracy(test, pred), accuracy(test[feasible], pred[feasible])
        ridge = accuracy(test, ridge_fit_predict(train, test))
        rows.append(dict(held_out=held, training_configs=len(train), configs=a['configs'], mae=a['mae'], mae_feasible=b['mae'],
                         r=a['pearson'], ridge_mae=ridge['mae'], ridge_r=ridge['pearson']))
    params_all = sg.fit(fitset[fitset.design.isin(full)])
    table = pd.DataFrame(params, index=sg.PARAMETER_NAMES).T
    table.loc['all three'] = params_all
    show('1. Fitted parameters (row = held-out design; "all three" is used for the unseen designs)', table, 3)

    # ---------------- 2. accuracy with whole designs held out (Table V)
    allp = pd.concat(predictions)
    feasible = allp[allp.packing_density <= FEASIBLE_DENSITY]
    ridge_all = np.concatenate([ridge_fit_predict(fitset[fitset.design.isin(sg.training_designs(h))], fitset[fitset.design == h]) for h in full])
    ridge_y = np.concatenate([fitset[fitset.design == h].y.values for h in full])
    a = accuracy(allp, allp.predicted.values)
    rows.append(dict(held_out='all', training_configs=np.nan, configs=a['configs'], mae=a['mae'],
                     mae_feasible=np.abs(feasible.predicted - feasible.y).mean(), r=a['pearson'],
                     ridge_mae=np.abs(ridge_all - ridge_y).mean(), ridge_r=np.corrcoef(ridge_all, ridge_y)[0, 1]))
    show('2. Accuracy with whole designs held out (Table V): MAE in percentage points, r = Pearson correlation; '
         'feasible = packing density <= %.3f' % FEASIBLE_DENSITY, pd.DataFrame(rows).set_index('held_out'))
    other = runs[runs.ok & (runs.placement_seed > 1)].groupby(sg.CASE + ['config']).reduction.median().rename('others')
    both = seed1[seed1.ok].set_index(sg.CASE + ['config']).reduction.to_frame('seed1').join(other, how='inner')
    print('seed variation: |reduction with seed 1 - median of the other seeds| averages %.2f percentage points over %d configurations'
          % ((both.seed1 - both.others).abs().mean(), len(both)))

    # ---------------- 3. unseen designs
    un = fitset[fitset.design.isin(unseen)].copy()
    un['predicted'] = sg.predict(params_all, sg.model_inputs(un))
    un['ridge'] = ridge_fit_predict(fitset[fitset.design.isin(full)], un)
    f = un[un.packing_density <= FEASIBLE_DENSITY].groupby('design')
    show('3. Unseen designs: medians over the packing-feasible configurations', pd.DataFrame({
        'configs': f.size(), 'predicted': f.predicted.median(), 'measured': f.y.median(), 'ridge_predicted': f.ridge.median()}).loc[unseen])

    # ---------------- 4. and 5. configuration selection
    rows = []
    for design in full + unseen:
        train_designs = sg.training_designs(design)
        p = params[design] if design in full else params_all
        delta_max = sg.packing_limit(seed1[seed1.design.isin(train_designs)])
        scored = fitset[fitset.design == design].copy()
        if design in full:
            scored['ridge'] = ridge_fit_predict(fitset[fitset.design.isin(train_designs)], scored)
        for case, cand in seed1[seed1.design == design].groupby('case'):
            done = cand[cand.ok]
            chosen = sg.rank(cand, p, delta_max)
            row = dict(case=case, design=design, util_pct=int(cand.util_pct.iloc[0]), delta_max=delta_max,
                       best_of_sweep=done.reduction.max(), best_config=done.loc[done.reduction.idxmax(), 'config'],
                       median_config=done.reduction.median(),
                       random_1=np.mean([done.reduction.values[np.random.RandomState(k).choice(len(done), 1, replace=False)].max() for k in range(300)]),
                       random_best_of_5=np.mean([done.reduction.values[np.random.RandomState(k).choice(len(done), 5, replace=False)].max() for k in range(300)]))
            if len(chosen):
                first = chosen.iloc[0]
                row.update(selected=first.label, predicted=first.predicted, completed=bool(first.ok),
                           measured=first.reduction if first.ok else np.nan, apply=bool(first.predicted >= sg.TAU),
                           near_ties=int(chosen.near_tie.sum()))
            if design in full:
                sc = scored[scored.case == case]
                row['ridge'] = sc.sort_values('ridge', ascending=False).y.iloc[0]
            rows.append(row)
    sel = pd.DataFrame(rows).set_index('case')

    f3 = sel[sel.design.isin(full)]
    columns = ['measured', 'ridge', 'random_best_of_5', 'random_1', 'median_config', 'best_of_sweep']
    per = f3.groupby('design')[columns].mean().loc[full]
    per.loc['average (%d cases)' % len(f3)] = f3[columns].mean()
    per.columns = ['SeamGain (1)', 'Ridge (1)', 'Random best of 5', 'Random (1)', 'Median config.', 'Best of sweep (144)']
    show('4. Configuration selection (Table VI): reduction of the selected configuration, averages over utilizations; '
         'number of RSC runs in parentheses', per)
    print('the SeamGain-selected configuration obtains %.0f%% of the best-of-sweep reduction; |predicted - measured| averages %.1f percentage points'
          % (100 * f3.measured.mean() / f3.best_of_sweep.mean(), (f3.predicted - f3.measured).abs().mean()))

    # the best swept configuration is picked by its seed-1 measurement: re-score it on the other placement seeds
    others = runs[runs.ok & (runs.placement_seed != 1)].groupby(['case', 'config']).reduction.agg(['median', 'count'])
    rescored = [others['median'].get((case, cfg), np.nan) for case, cfg in zip(f3.index, f3.best_config)]
    n_other = [int(others['count'].get((case, cfg), 0)) for case, cfg in zip(f3.index, f3.best_config)]
    print('best swept configurations rerun with other placement seeds (%d to %d seeds per case): median reduction %.1f%% on average '
          '(%.1f%% with the seed used to pick them); the SeamGain-selected configuration obtains %.0f%% of it'
          % (min(n_other), max(n_other), np.nanmean(rescored), f3.best_of_sweep.mean(), 100 * f3.measured.mean() / np.nanmean(rescored)))

    decided = sel.dropna(subset=['predicted']).copy()
    decided['apply'] = decided['apply'].astype(bool)
    decided['near_ties'] = decided.near_ties.astype(int)
    show('5. Decision per case with a packing-feasible candidate (tau = %.0f%%): best predicted reduction, and measured '
         'reduction of the selected configuration' % sg.TAU,
         decided[['design', 'util_pct', 'selected', 'near_ties', 'predicted', 'apply', 'measured', 'best_of_sweep']])
    applied = decided[decided['apply']]
    kept = decided[~decided['apply']]
    print('RSC applied to %d of %d cases, measured reductions %.1f%% to %.1f%%; uniform flow kept for %d cases, where the selected '
          'configuration would have measured %.1f%% to %.1f%%'
          % (len(applied), len(decided), applied.measured.min(), applied.measured.max(), len(kept), kept.measured.min(), kept.measured.max()))
    print('thresholds that give the same decisions: %.1f%% < tau <= %.1f%%' % (kept.predicted.max(), applied.predicted.min()))

    if args.write_parameters:
        out = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'parameters.json')
        content = dict(parameters=dict(zip(sg.PARAMETER_NAMES, [float(v) for v in params_all])),
                       delta_max=sg.packing_limit(seed1[seed1.design.isin(full)]), tau=sg.TAU, epsilon=sg.EPSILON,
                       fitted_on=full)
        with open(out, 'w') as stream:
            json.dump(content, stream, indent=2)
            stream.write('\n')
        print('\nwrote seamgain/parameters.json')


if __name__ == '__main__':
    main()
