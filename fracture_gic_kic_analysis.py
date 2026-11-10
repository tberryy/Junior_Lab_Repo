"""
Fracture toughness (K_Ic) and critical strain energy release rate (G_Ic)
for every compact-tension (CT) fracture specimen in OrganizedData.

Python port of Fracture_GIc_KIc_Analysis.m (same classification, curve
processing, K and G_Ic formulas), so the results can be regenerated
without MATLAB.

  K_Ic = P_max / (B * sqrt(W)) * f(a/W)        ASTM E399 / D5045
  G_Ic = U / (B * (W - a))                      U = area under F-d to peak

Specimen dimensions are read from the sheet of SpecimenDimensions<year>.xlsx
that matches the specimen's batch (batch1 / batch2).

Run from inside Junior_Lab_Repo:  python3 fracture_gic_kic_analysis.py
"""

import glob
import os
import re

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd

ORGANIZED_FOLDER = "OrganizedData"
OUTPUT_FOLDER = "Fracture_GIc_KIc_Export"

DAYS = ["monday", "tuesday", "wednesday", "thursday", "friday"]
MATERIALS = ["CNT", "NEAT"]
YEARS = ["2023", "2024", "2025", "2026"]

# AP / epoxy weight percent for each test year
AP_PERCENT_BY_YEAR = {"2023": 60, "2024": 40, "2025": 50, "2026": 70}

NUM_CNT_PER_GROUP = 4          # highest-peak-force specimens in a group are CNT
FRACTURE_DISPLACEMENT_LIMIT = 3.5   # mm, same crop used for plotting
MAX_PEAK_DISPLACEMENT = 4.0         # mm, reject curves peaking later than this


# =========================================================================
# Reading
# =========================================================================

def read_curve(file_path):
    """Return an N x 3 array of [time_s, displacement_mm, force_N]."""
    with open(file_path, errors="ignore") as f:
        lines = f.read().splitlines()

    header = next((k for k, line in enumerate(lines)
                   if line.strip().startswith("Time")), None)
    if header is None:
        return np.empty((0, 3))

    rows = []
    for line in lines[header + 2:]:  # skip header and units rows
        parts = [p.strip().strip('"') for p in line.split(",")]
        if len(parts) < 3:
            continue
        try:
            rows.append([float(parts[0]), float(parts[1]), float(parts[2])])
        except ValueError:
            continue

    return np.array(rows) if rows else np.empty((0, 3))


def is_curve_file(file_path):
    """True for Time/Displacement/Force exports, False for results tables."""
    with open(file_path, errors="ignore") as f:
        head = f.read(300)
    return any(line.strip().startswith("Time") for line in head.splitlines())


# =========================================================================
# Classification: top NUM_CNT_PER_GROUP peak forces in a group are
# CNT_1..CNT_4, the rest NEAT_1, NEAT_2, ...
# =========================================================================

def classify_fracture_specimens():
    records = []

    for year in YEARS:
        year_folder = os.path.join(ORGANIZED_FOLDER, year + "_organized")

        for batch_folder in sorted(glob.glob(os.path.join(year_folder, "batch*"))):
            batch = os.path.basename(batch_folder)

            for day in DAYS:
                day_folder = os.path.join(batch_folder, day)
                if not os.path.isdir(day_folder):
                    continue

                for group in sorted(os.listdir(day_folder)):
                    group_path = os.path.join(day_folder, group)
                    if not os.path.isdir(group_path):
                        continue

                    files = sorted(p for p in glob.glob(
                                       os.path.join(group_path, "**", "*.csv"),
                                       recursive=True)
                                   if "FRACTURE" in os.path.basename(p).upper()
                                   and is_curve_file(p))

                    if not files:
                        continue

                    peaks = []
                    for p in files:
                        data = read_curve(p)
                        peaks.append(data[:, 2].max() if len(data) else -np.inf)

                    order = sorted(range(len(files)), key=lambda k: -peaks[k])

                    for rank, idx in enumerate(order):
                        if rank < NUM_CNT_PER_GROUP:
                            material, sample = "CNT", rank + 1
                        else:
                            material, sample = "NEAT", rank - NUM_CNT_PER_GROUP + 1

                        records.append(dict(
                            Year=year, Batch=batch, Day=day, Group=group,
                            Material=material, SampleName=f"{material}_{sample}",
                            SampleNumber=sample,
                            SectionNumber=int(re.sub(r"\D", "", group)),
                            OriginalFileName=os.path.basename(files[idx]),
                            FilePath=files[idx], MaxForce_N=peaks[idx]))

    return pd.DataFrame(records)


# =========================================================================
# Dimensions
# =========================================================================

NUMERIC_COLUMNS = ["Section", "Sample", "Width_mm", "Thickness_mm",
                   "NotchLength_mm", "PreCrackLength_mm"]


def load_fracture_dimensions(year):
    """Return {sheet_name: fracture rows} for one year's dimension file."""
    path = os.path.join(ORGANIZED_FOLDER, year + "_organized",
                        f"SpecimenDimensions{year}.xlsx")
    if not os.path.isfile(path):
        print(f"Warning: dimension file not found: {path}")
        return {}

    sheets = {}
    for sheet, table in pd.read_excel(path, sheet_name=None).items():
        if "Material" not in table.columns:
            table = table.rename(columns={table.columns[1]: "Material"})
        table["Material"] = table["Material"].astype(str).str.strip().str.upper()
        table["Test"] = table["Test"].astype(str).str.strip().str.upper()
        # Some sections are stored as text with a leading zero (e.g. '033016')
        for column in NUMERIC_COLUMNS:
            table[column] = pd.to_numeric(table[column], errors="coerce")
        sheets[sheet] = table[table["Test"] == "FRACTURE"]

    return sheets


def get_fracture_dimensions(sheets, batch, section, material, sample):
    """Return (W, B, a, sheet_used) in mm from the batch's own sheet."""
    sheet = batch if batch in sheets else next(iter(sheets), None)
    if sheet is None:
        return np.nan, np.nan, np.nan, ""

    table = sheets[sheet]
    row = table[(table["Section"] == section) & (table["Material"] == material)
                & (table["Sample"] == sample)]

    if row.empty:
        print(f"Warning: missing fracture dimensions: {batch} section {section} "
              f"{material} sample {sample}")
        return np.nan, np.nan, np.nan, sheet

    row = row.iloc[0]
    crack = row["NotchLength_mm"] + row["PreCrackLength_mm"]
    return row["Width_mm"], row["Thickness_mm"], crack, sheet


# =========================================================================
# Curve processing (mirrors processFractureCurve in the MATLAB script,
# including MATLAB's movmean / movsum / gradient conventions)
# =========================================================================

def matlab_movmean(x, window):
    """Centred moving mean with shrinking endpoints (MATLAB movmean)."""
    before = window // 2
    after = window - before - 1
    out = np.empty(len(x))
    for i in range(len(x)):
        out[i] = x[max(0, i - before):i + after + 1].mean()
    return out


def matlab_movsum(x, window):
    before = window // 2
    after = window - before - 1
    csum = np.concatenate([[0], np.cumsum(x)])
    lo = np.maximum(0, np.arange(len(x)) - before)
    hi = np.minimum(len(x), np.arange(len(x)) + after + 1)
    return csum[hi] - csum[lo]


def matlab_gradient(f, x):
    """MATLAB gradient(f, x): one-sided at the ends, central inside."""
    g = np.empty(len(f))
    with np.errstate(divide="ignore", invalid="ignore"):
        g[0] = (f[1] - f[0]) / (x[1] - x[0])
        g[-1] = (f[-1] - f[-2]) / (x[-1] - x[-2])
        g[1:-1] = (f[2:] - f[:-2]) / (x[2:] - x[:-2])
    return g


def process_fracture_curve(file_path):
    """Return (displacement_mm, force_N, peak_force_N, ok, reason)."""
    data = read_curve(file_path)
    if len(data) < 2:
        return None, None, np.nan, False, "no data"

    displacement = data[:, 1]
    force = data[:, 2]

    peak_original = force.max()
    if not np.isfinite(peak_original) or peak_original <= 0:
        return None, None, np.nan, False, "no positive force"

    # Loading start at 5% of the original peak
    start = np.nonzero(force >= 0.05 * peak_original)[0][0]
    displacement = displacement[start:]
    force = force[start:]

    if len(force) < 2:
        return None, None, np.nan, False, "too few points"

    # Sustained loading: smoothed slope >= 50 N/mm for 15 consecutive points
    slope = matlab_gradient(matlab_movmean(force, 25), displacement)
    with np.errstate(invalid="ignore"):
        loading = (slope >= 50).astype(float)
    sustained = np.nonzero(matlab_movsum(loading, 15) >= 15)[0]
    start = sustained[0] if len(sustained) else 0
    start = max(0, start - 3)

    displacement = displacement[start:] - displacement[start]
    force = force[start:] - force[start]
    displacement[displacement < 0] = 0
    force[force < 0] = 0

    peak_index = int(np.argmax(force))

    # Crop after force falls below 20% of peak
    drop = np.nonzero(force[peak_index:] <= 0.20 * force[peak_index])[0]
    if len(drop):
        end = peak_index + drop[0]
        displacement = displacement[:end + 1]
        force = force[:end + 1]

    if displacement[peak_index] > MAX_PEAK_DISPLACEMENT:
        return None, None, np.nan, False, "peak displacement outlier"

    keep = (displacement >= 0) & (displacement <= FRACTURE_DISPLACEMENT_LIMIT)
    displacement = displacement[keep]
    force = force[keep]

    if len(force) == 0:
        return None, None, np.nan, False, "empty after crop"

    peak_index = int(np.argmax(force))
    peak_force = force[peak_index]
    displacement = displacement[:peak_index + 1]
    force = force[:peak_index + 1]

    if len(displacement) < 2:
        return None, None, np.nan, False, "too few points before peak"

    return displacement, force, peak_force, True, ""


# =========================================================================
# K and G_Ic
# =========================================================================

def stress_intensity_factor(peak_force_N, W_mm, B_mm, a_mm):
    """ASTM E399 / D5045 CT geometry factor. Returns (K MPa*m^0.5, a/W)."""
    alpha = a_mm / W_mm
    if not np.isfinite(alpha) or alpha >= 1:
        return np.nan, alpha

    f = ((2 + alpha) * (0.886 + 4.64 * alpha - 13.32 * alpha ** 2
                        + 14.72 * alpha ** 3 - 5.6 * alpha ** 4)) / (1 - alpha) ** 1.5

    K = peak_force_N / ((B_mm / 1000) * np.sqrt(W_mm / 1000)) * f
    return K / 1e6, alpha


def energy_release_rate(displacement_mm, force_N, W_mm, B_mm, a_mm):
    """G_Ic = U / (B (W - a)). Returns (G_Ic kJ/m^2, U in J)."""
    energy_J = np.trapezoid(force_N, displacement_mm) / 1000
    ligament_m2 = (B_mm / 1000) * ((W_mm - a_mm) / 1000)
    return energy_J / ligament_m2 / 1000, energy_J


# =========================================================================
# Plots
# =========================================================================

COLORS = {"CNT": "#0072bd", "NEAT": "#d95319"}


def plot_metric_vs_ap(accepted, summary, mean_col, std_col, value_col,
                      title, ylabel, out_base):
    fig, ax = plt.subplots(figsize=(8, 5.5))
    ap_values = sorted(AP_PERCENT_BY_YEAR.values())
    offsets = {"CNT": -0.8, "NEAT": 0.8}
    rng = np.random.default_rng(0)

    for material in MATERIALS:
        pts = accepted[accepted.Material == material]
        ax.scatter(pts.AP_Percent + offsets[material]
                   + rng.uniform(-0.4, 0.4, len(pts)),
                   pts[value_col], s=12, alpha=0.3,
                   color=COLORS[material], edgecolors="none")

        s = summary[summary.Material == material].sort_values("AP_Percent")
        n_total = int(s.NumberOfSpecimens.sum())
        ax.errorbar(s.AP_Percent + offsets[material], s[mean_col], yerr=s[std_col],
                    fmt="o-", color=COLORS[material], capsize=5, lw=2, ms=8,
                    label=f"{material} mean ± 1 SD (n = {n_total})")

    labels = {v: y for y, v in AP_PERCENT_BY_YEAR.items()}
    ax.set_xticks(ap_values)
    ax.set_xticklabels([f"{ap}% AP\n({labels[ap]})" for ap in ap_values])
    ax.set_xlabel("AP content (wt%)")
    ax.set_ylabel(ylabel)
    ax.set_title(title)
    ax.set_ylim(bottom=0)
    ax.grid(alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(out_base + ".png", dpi=200)
    fig.savefig(out_base + ".pdf")
    plt.close(fig)


def plot_curve_check(results, curves, year, out_path):
    """Processed force-displacement curve (to peak) for every specimen."""
    rows = results[(results.Year == year) & results.CurveOK].reset_index(drop=True)
    if rows.empty:
        return

    fig, axes = plt.subplots(1, 2, figsize=(12, 4.5), sharey=True)
    for ax, material in zip(axes, MATERIALS):
        for _, row in rows[rows.Material == material].iterrows():
            d, f = curves[row.FilePath]
            ax.plot(d, f, color=COLORS[material], lw=0.6,
                    alpha=0.9 if row.ValidGeometry else 0.25)
        ax.set_title(f"{year} {material} (to peak load)")
        ax.set_xlabel("Displacement (mm)")
        ax.grid(alpha=0.3)
    axes[0].set_ylabel("Force (N)")
    fig.tight_layout()
    fig.savefig(out_path, dpi=130)
    plt.close(fig)


# =========================================================================
# Main
# =========================================================================

def main():
    os.makedirs(OUTPUT_FOLDER, exist_ok=True)

    specimens = classify_fracture_specimens()
    if specimens.empty:
        raise SystemExit("No fracture specimens found. Run from Junior_Lab_Repo.")

    dimension_sheets = {y: load_fracture_dimensions(y) for y in YEARS}

    results = []
    curves = {}

    for _, s in specimens.iterrows():
        W, B, a, sheet = get_fracture_dimensions(
            dimension_sheets[s.Year], s.Batch, s.SectionNumber,
            s.Material, s.SampleNumber)

        dims_ok = all(np.isfinite(v) and v > 0 for v in (W, B, a))

        d, f, peak, curve_ok, reason = process_fracture_curve(s.FilePath)
        if curve_ok:
            curves[s.FilePath] = (d, f)

        K = alpha = G = energy = np.nan
        if dims_ok and curve_ok:
            K, alpha = stress_intensity_factor(peak, W, B, a)
            G, energy = energy_release_rate(d, f, W, B, a)
        elif not dims_ok:
            reason = reason or "missing dimensions"

        # ASTM E399 / D5045: 0.2 < a/W < 0.8 for the geometry factor, and
        # D5045 requires 2 <= W/B <= 4. The W/B check also catches dimension
        # rows with swapped or shifted columns.
        w_over_b = W / B if dims_ok else np.nan
        valid = bool(np.isfinite(K) and np.isfinite(G) and 0.2 < alpha < 0.8
                     and 2 <= w_over_b <= 4)
        if not valid and not reason:
            reason = ("a/W outside 0.2-0.8" if not 0.2 < alpha < 0.8
                      else "W/B outside 2-4")

        results.append(dict(
            AP_Percent=AP_PERCENT_BY_YEAR[s.Year],
            Epoxy_Percent=100 - AP_PERCENT_BY_YEAR[s.Year],
            Year=s.Year, Material=s.Material, Batch=s.Batch, Day=s.Day,
            Group=s.Group, Sample=s.SampleName,
            SectionNumber=s.SectionNumber, SampleNumber=s.SampleNumber,
            DimensionSheet=sheet, Width_mm=W, Thickness_mm=B, CrackLength_mm=a,
            a_over_W=alpha, W_over_B=w_over_b, PeakForce_N=peak, Energy_J=energy,
            K_MPa_sqrtm=K, GIc_kJ_per_m2=G,
            CurveOK=curve_ok, ValidGeometry=valid, RejectReason=reason,
            OriginalFileName=s.OriginalFileName, FilePath=s.FilePath))

    results = pd.DataFrame(results).sort_values(
        ["AP_Percent", "Material", "SampleNumber", "Batch", "Day", "Group"])
    accepted = results[results.ValidGeometry]

    summary_rows = []
    for year in YEARS:
        for material in MATERIALS:
            v = accepted[(accepted.Year == year) & (accepted.Material == material)]
            if v.empty:
                continue
            n = len(v)
            summary_rows.append(dict(
                AP_Percent=AP_PERCENT_BY_YEAR[year],
                Epoxy_Percent=100 - AP_PERCENT_BY_YEAR[year],
                Year=year, Material=material,
                MeanK_MPa_sqrtm=v.K_MPa_sqrtm.mean(),
                StdK_MPa_sqrtm=v.K_MPa_sqrtm.std(ddof=1) if n > 1 else np.nan,
                MedianK_MPa_sqrtm=v.K_MPa_sqrtm.median(),
                MeanGIc_kJ_per_m2=v.GIc_kJ_per_m2.mean(),
                StdGIc_kJ_per_m2=v.GIc_kJ_per_m2.std(ddof=1) if n > 1 else np.nan,
                MedianGIc_kJ_per_m2=v.GIc_kJ_per_m2.median(),
                NumberOfSpecimens=n))
    summary = pd.DataFrame(summary_rows).sort_values(["AP_Percent", "Material"])

    individual_file = os.path.join(OUTPUT_FOLDER, "Fracture_GIc_KIc_All_Specimens.xlsx")
    with pd.ExcelWriter(individual_file) as writer:
        results.to_excel(writer, sheet_name="All Specimens", index=False)
        accepted.to_excel(writer, sheet_name="Valid Geometry", index=False)

    summary_file = os.path.join(OUTPUT_FOLDER, "Fracture_GIc_KIc_Composition_Summary.xlsx")
    summary.to_excel(summary_file, sheet_name="Composition Summary", index=False)

    plot_metric_vs_ap(accepted, summary, "MeanK_MPa_sqrtm", "StdK_MPa_sqrtm",
                      "K_MPa_sqrtm", "Fracture toughness vs. AP content",
                      "K$_{Ic}$ (MPa·m$^{0.5}$)",
                      os.path.join(OUTPUT_FOLDER, "Fracture_KIc_vs_AP_Content"))
    plot_metric_vs_ap(accepted, summary, "MeanGIc_kJ_per_m2", "StdGIc_kJ_per_m2",
                      "GIc_kJ_per_m2",
                      "Critical strain energy release rate vs. AP content",
                      "G$_{Ic}$ (kJ/m$^2$)",
                      os.path.join(OUTPUT_FOLDER, "Fracture_GIc_vs_AP_Content"))

    for year in YEARS:
        plot_curve_check(results, curves, year,
                         os.path.join(OUTPUT_FOLDER, f"Fracture_Curve_Check_{year}.png"))

    print(summary.round(3).to_string(index=False))
    print(f"\n{len(accepted)} of {len(results)} specimens have valid K and G_Ic.")
    print(results[~results.ValidGeometry].RejectReason.value_counts().to_string())
    print(f"Results saved to {OUTPUT_FOLDER}")


if __name__ == "__main__":
    main()
