"""SeamGain: predicted routed-wirelength reduction of an RSC configuration.

The model follows Section III-C of the paper. For a configuration theta = (w, h, P_x, P_y, Delta):

    R_dp  = r_d (1 - g_d p) - k_d [delta - delta_0]+
    R_cts = r_c (1 - g_c p) min{1, W_s / a_cts} - k_c [delta - delta_0]+
    G     = 1 - kappa (1 + (1 - R_dp) e_dp) (1 + (1 - R_cts) e_cts) / ((1 + e_dp) (1 + e_cts))

with p = P_x / 300 - 1, the seam whitespace W_s and the packing density delta = U / (1 - W_s).
The design-dependent inputs (e_dp, e_cts, a_cts, U) come from a uniform reference run; the eight
parameters (r_d, g_d, k_d, r_c, g_c, k_c, delta_0, kappa) are shared by all designs.

This module contains the seam geometry, the model, its calibration, the configuration selection
(Algorithm 1 of the paper, extended to the k best-ranked configurations), and the loader of the
measurement tables in data/.
"""
import os

import numpy as np
import pandas as pd
from scipy.optimize import least_squares

SITE_WIDTH_UM = 0.054            # ASAP7 placement site width
ROW_HEIGHT_UM = 0.270            # ASAP7 placement row height
REFERENCE_PITCH_SITES = 300.0    # P_0
MIN_SEAM_UTILIZATION = 0.05      # below this the flow uses hard blockages; such configurations are not considered
TAU = 8.0                        # RSC is applied only if the best predicted reduction is at least TAU percent
EPSILON = 0.25                   # predictions within EPSILON percentage points of the best one count as ties
CLIP = -40.0                     # reductions below CLIP percent are clipped when fitting and scoring
PARAMETER_NAMES = ['r_d', 'g_d', 'k_d', 'r_c', 'g_c', 'k_c', 'delta_0', 'kappa']
TRAINING_DESIGNS = ['tpu', 'ethmac', 'jpeg']                                    # full sweeps (144 configurations)
UNSEEN_DESIGNS = ['cva6_no_sram', 'swerv_no_macro', 'mempool_tile_no_macro']    # coarse sweeps (36 configurations)
CASE = ['design', 'util_pct']
RUN = ['design', 'util_pct', 'config', 'placement_seed']


# --------------------------------------------------------------------------- seam geometry (Section II)
def _intervals(origin, limit, pitch, width):
    """Seam intervals along one axis, as in flow/openroad/seams.tcl: the first seam starts one pitch from the origin."""
    out = []
    if width <= 0:
        return out
    start = origin + pitch
    while start < limit - 1e-9:
        out.append((start, min(start + width, limit)))
        start += pitch
    return out


def seam_fraction(core_width_um, core_height_um, width_sites, height_rows, pitch_sites, pitch_rows):
    """Fraction f of the core area covered by the seams (intersections counted once)."""
    vertical = _intervals(0.0, core_width_um, pitch_sites * SITE_WIDTH_UM, width_sites * SITE_WIDTH_UM)
    horizontal = _intervals(0.0, core_height_um, pitch_rows * ROW_HEIGHT_UM, height_rows * ROW_HEIGHT_UM)
    vw = sum(b - a for a, b in vertical)
    hh = sum(b - a for a, b in horizontal)
    return (vw * core_height_um + hh * core_width_um - vw * hh) / (core_width_um * core_height_um)


def seam_utilization(utilization, f, delta):
    """Seam density target U_s = U - (1 - f) / f * Delta."""
    return utilization - (1.0 - f) / f * delta


def seam_whitespace(f, u_s):
    """Whitespace held by the seams, W_s = f (1 - U_s), as a fraction of the core area."""
    return f * (1.0 - np.maximum(u_s, 0.0))


def packing_density(utilization, w_s):
    """delta = U / (1 - W_s)."""
    return utilization / (1.0 - w_s)


# --------------------------------------------------------------------------- model (Section III-C)
def model_inputs(df):
    """Columns of a table of configurations that the model reads."""
    return {c: df[c].values for c in ['pitch_sites', 'packing_density', 'headroom', 'e_dp', 'e_cts']}


def recoveries(params, x):
    """Recovered fractions (R_dp, R_cts) of the excess inflations of the uniform reference run."""
    r_d, g_d, k_d, r_c, g_c, k_c, delta_0, _ = params
    p = x['pitch_sites'] / REFERENCE_PITCH_SITES - 1.0
    penalty = np.maximum(0.0, x['packing_density'] - delta_0)
    return (r_d * (1.0 - g_d * p) - k_d * penalty,
            r_c * (1.0 - g_c * p) * np.minimum(1.0, x['headroom']) - k_c * penalty)


def predict(params, x):
    """Predicted reduction of routed wirelength, in percent."""
    r_dp, r_cts = recoveries(params, x)
    ratio = ((1.0 + (1.0 - r_dp) * x['e_dp']) * (1.0 + (1.0 - r_cts) * x['e_cts'])
             / ((1.0 + x['e_dp']) * (1.0 + x['e_cts'])))
    return 100.0 * (1.0 - params[7] * ratio)


def fit(train):
    """Calibrate the eight parameters on RSC runs of the training designs.

    The two recovery models are fitted to the measured recoveries of the two legalization steps by
    robust least squares; kappa is the median ratio of rho * L_gp between RSC and the uniform flow
    over the runs without packing penalty.
    """
    x = model_inputs(train)
    measured_dp = train.R_dp.clip(lower=-3).values
    measured_cts = train.R_cts.clip(lower=-3).values
    p = x['pitch_sites'] / REFERENCE_PITCH_SITES - 1.0

    def residual_dp(q):                         # q = r_d, g_d, k_d, delta_0
        return q[0] * (1.0 - q[1] * p) - q[2] * np.maximum(0.0, x['packing_density'] - q[3]) - measured_dp
    d = least_squares(residual_dp, [0.15, 0.5, 20.0, 0.945], bounds=([0, -3, 0, 0.92], [1, 3, 200, 0.97]),
                      loss='soft_l1', f_scale=0.1).x
    penalty = np.maximum(0.0, x['packing_density'] - d[3])

    def residual_cts(q):                        # q = r_c, g_c, k_c
        return q[0] * (1.0 - q[1] * p) * np.minimum(1.0, x['headroom']) - q[2] * penalty - measured_cts
    c = least_squares(residual_cts, [0.6, 0.5, 10.0], bounds=([0, -3, 0], [1, 3, 200]), loss='soft_l1', f_scale=0.1).x

    free = train[train.packing_density <= d[3]]
    kappa = float((free.gp_ratio * free.rho_ratio).median())
    return np.array([d[0], d[1], d[2], c[0], c[1], c[2], d[3], kappa])


def packing_limit(train):
    """delta_max: the largest packing density below which no configuration of the training designs fails."""
    first_failure = train[~train.ok].packing_density.min()
    return float(train[train.ok & (train.packing_density < first_failure)].packing_density.max())


# --------------------------------------------------------------------------- selection (Section III-D, Algorithm 1)
def rank(candidates, params, delta_max, epsilon=EPSILON):
    """Packing-feasible candidates of one case with their predictions, in the order in which Algorithm 1 prefers them.

    The near-tie set Theta_t (predictions within epsilon of the best) comes first, ordered by the distance of
    the seam whitespace to the middle of the feasible window [a_cts, 1 - U / delta_max]; the remaining
    candidates follow by decreasing prediction. Returns an empty table if there is no feasible candidate.
    """
    c = candidates[(candidates.seam_utilization >= MIN_SEAM_UTILIZATION) & (candidates.packing_density <= delta_max)].copy()
    if not len(c):
        return c.assign(predicted=[], offset=[], near_tie=[])
    c['predicted'] = predict(params, model_inputs(c))
    w_max = 1.0 - c.utilization.iloc[0] / delta_max
    middle = 0.5 * (min(c.a_cts.iloc[0], w_max) + w_max)
    c['offset'] = (c.seam_whitespace - middle).abs()
    c['near_tie'] = c.predicted >= c.predicted.max() - epsilon
    ties = c[c.near_tie].sort_values(['offset', 'predicted'], ascending=[True, False])
    rest = c[~c.near_tie].sort_values(['predicted', 'offset'], ascending=[False, True])
    return pd.concat([ties, rest])


def select(candidates, params, delta_max, k=1, tau=TAU, epsilon=EPSILON):
    """Algorithm 1. Returns the k selected configurations (k = 1 in the paper), or None to keep the uniform flow."""
    ranked = rank(candidates, params, delta_max, epsilon)
    if not len(ranked) or ranked.predicted.max() < tau:
        return None
    return ranked.iloc[:k]


# --------------------------------------------------------------------------- measurement tables
def data_directory():
    return os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), 'data')


def load_dataset(directory=None):
    """Runs of the sweep with everything the model needs.

    Returns (runs, reference): `runs` holds the RSC runs (both seam directions) of every case that has a
    completed uniform baseline; `reference` holds, per case, the inputs measured in the uniform flow
    (medians over the baseline placement seeds).
    """
    directory = directory or data_directory()
    m = pd.read_csv(os.path.join(directory, 'openroad_measurements.csv'))
    m = m[m.experiment == 'control']
    s = pd.read_csv(os.path.join(directory, 'openroad_stage_metrics.csv'))
    d = m.merge(s, on=RUN, how='left')
    d['ok'] = d.grt_status == 'grt_complete'
    d['grt'] = d.grt_wl_um.where(d.ok)
    d['lambda_dp'] = d.dp_hpwl_um / d.gp_hpwl_um                        # HPWL after / before legalization
    d['lambda_cts'] = d.cts_hpwl_after_dp_um / d.cts_hpwl_before_dp_um  # same for the legalization that follows CTS
    d['rho'] = d.grt / d.cts_hpwl_after_dp_um                           # routed wirelength / final HPWL
    d['clock_buffer_area'] = (d.utilization_before_cts_dp_pct - d.utilization_before_dp_pct) / 100.0

    base = d[d.ok & (d.kind == 'baseline')].groupby(CASE)
    reference = pd.DataFrame({
        'ref_grt': base.grt.median(), 'ref_grt_best_seed': base.grt.min(),
        'e_dp': base.lambda_dp.median() - 1.0, 'e_cts': base.lambda_cts.median() - 1.0,
        'a_cts': base.clock_buffer_area.median(), 'utilization': base.utilization_before_dp_pct.median() / 100.0,
        'ref_gp_hpwl': base.gp_hpwl_um.median(), 'ref_rho': base.rho.median()})

    r = d[d.kind == 'combined'].join(reference, on=CASE).dropna(subset=['ref_grt']).copy()
    r['reduction'] = (1.0 - r.grt / r.ref_grt) * 100.0                  # percent; NaN for failed runs
    r['y'] = r.reduction.clip(lower=CLIP)
    r['seam_whitespace'] = seam_whitespace(r.seam_fraction, r.seam_utilization)
    r['packing_density'] = packing_density(r.utilization, r.seam_whitespace)
    r['headroom'] = r.seam_whitespace / r.a_cts
    r['R_dp'] = 1.0 - (r.lambda_dp - 1.0) / r.e_dp
    r['R_cts'] = 1.0 - (r.lambda_cts - 1.0) / r.e_cts
    r['gp_ratio'] = r.gp_hpwl_um / r.ref_gp_hpwl
    r['rho_ratio'] = r.rho / r.ref_rho
    r['case'] = r.design + '_' + r.util_pct.astype(str)
    r['label'] = r.config.str.split('__', n=1).str[1]
    return r, reference


def fitting_runs(runs):
    """Runs used to fit and to score the model: first placement seed, completed, seams realized as density screens."""
    s1 = runs[runs.placement_seed == 1]
    return s1[s1.ok & (s1.seam_utilization >= MIN_SEAM_UTILIZATION) & s1.y.notnull()]


def training_designs(design):
    """Designs whose runs calibrate the model when `design` is under test."""
    return [x for x in TRAINING_DESIGNS if x != design]
