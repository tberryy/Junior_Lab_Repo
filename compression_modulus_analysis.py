"""
Compressive modulus for every compression cylinder in OrganizedData.

Python port of Compression_Modulus_Analysis.m (same classification,
dimension lookup and fitting rules), so the results can be regenerated
without MATLAB.

Method (toe-compensated chord, ASTM D695 style)
  1. strain = (crosshead displacement - first reading) / specimen length
     stress = force / (pi * D^2 / 4)
  2. Keep the curve up to peak stress.
  3. Slide a window along the curve. Each window starts at a data point
     and extends until stress has risen by FIT_STRESS_SPAN * peak stress.
     Only windows lying between FIT_LOWER and FIT_UPPER of peak stress
     with at least MIN_FIT_POINTS points are considered.
  4. Fit stress = E*strain + b to each window. The compressive modulus
     is the steepest window whose R^2 >= MIN_R_SQUARED. Taking the
     steepest linear window skips the seating (toe) region automatically.

The modulus uses crosshead displacement, so it includes load-frame
compliance and is an apparent modulus, not a strain-gauge modulus.

Cross-check: Bluehill writes its own "Modulus (Automatic Young's)" to the
*_N_1.csv export, computed with placeholder geometry (20 mm diameter,
50 mm gauge length). That value is rescaled to the real geometry,
    E_rescaled = E_bluehill * (A_bluehill / A) * (L / L_bluehill),
and reported next to the fitted value.

Run from inside Junior_Lab_Repo:  python3 compression_modulus_analysis.py
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
RAW_DATA_FOLDER = "juniorlabdata"
OUTPUT_FOLDER = "Compression_Modulus_Export"

DAYS = ["monday", "tuesday", "wednesday", "thursday", "friday"]
MATERIALS = ["CNT", "NEAT"]
YEARS = ["2023", "2024", "2025", "2026"]

# AP / epoxy weight percent for each test year (same as the fracture analysis)
AP_PERCENT_BY_YEAR = {"2023": 60, "2024": 40, "2025": 50, "2026": 70}

# Fit settings
FIT_STRESS_SPAN = 0.20   # each window covers 20% of peak stress
FIT_LOWER = 0.02         # ignore the first 2% of peak stress (noise floor)
FIT_UPPER = 0.90         # ignore the last 10% before peak (yielding)
MIN_FIT_POINTS = 5
MIN_R_SQUARED = 0.995

# Flag specimens whose fit differs from Bluehill by more than this fraction
BLUEHILL_TOLERANCE = 0.25


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


def read_bluehill_results(file_path):
    """Return (modulus_MPa, diameter_mm, gauge_length_mm) or None."""
    with open(file_path, errors="ignore") as f:
        lines = f.read().splitlines()

    for k, line in enumerate(lines):
        if "Modulus (Automatic Young's)" not in line or k + 2 >= len(lines):
            continue

        header = [h.strip() for h in line.split(",")]
        values = [v.strip().strip('"') for v in lines[k + 2].split(",")]

        try:
            modulus = float(values[header.index("Modulus (Automatic Young's)")])
            diameter = float(values[header.index("Diameter")])
            gauge = float(values[header.index(
                "Compressive strain (Displacement) gauge length")])
        except (ValueError, IndexError):
            return None

        return modulus, diameter, gauge

    return None


def index_bluehill_results():
    """Map results-table file name -> path, searching raw and organized data."""
    index = {}
    patterns = [os.path.join(RAW_DATA_FOLDER, "**", "*.csv"),
                os.path.join(ORGANIZED_FOLDER, "*_organized", "**", "*.csv")]

    for pattern in patterns:
        for path in glob.glob(pattern, recursive=True):
            name = os.path.basename(path)
            if "COMPRESSION" in name.upper() and name.endswith("_1.csv"):
                index.setdefault(name, path)

    return index


# =========================================================================
# Classification (mirrors classifyFileListByMaxForce in
# data_process_and_plot2.m: highest peak force in a group is CNT_1,
# the rest are NEAT_1, NEAT_2, ...)
# =========================================================================

def classify_compression_specimens():
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

                    files = [p for p in glob.glob(
                                 os.path.join(group_path, "**", "*.csv"),
                                 recursive=True)
                             if "COMPRESSION" in os.path.basename(p).upper()
                             and is_curve_file(p)]

                    if not files:
                        continue

                    peaks = []
                    for p in files:
                        data = read_curve(p)
                        peaks.append(data[:, 2].max() if len(data) else np.nan)

                    order = np.argsort(-np.nan_to_num(np.array(peaks), nan=-np.inf))

                    for rank, idx in enumerate(order):
                        material = "CNT" if rank == 0 else "NEAT"
                        sample = 1 if rank == 0 else rank
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

def load_compression_dimensions(year):
    """Return {sheet_name: compression rows} for one year's dimension file."""
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
        for column in ["Section", "Sample", "Diameter_mm", "Length_mm"]:
            table[column] = pd.to_numeric(table[column], errors="coerce")
        sheets[sheet] = table[table["Test"] == "COMPRESSION"]

    return sheets


def get_compression_dimensions(sheets, batch, section, material, sample):
    """Return (diameter_mm, length_mm, source) for one specimen.

    Looks in the sheet that matches the batch, then falls back to the
    same section/material with any sample number, then to the median of
    all compression specimens measured that year (the median ignores
    typos such as a length typed into the diameter column)."""
    table = sheets.get(batch)
    if table is None and sheets:
        table = next(iter(sheets.values()))

    def valid(rows):
        rows = rows[(rows["Diameter_mm"] > 0) & (rows["Length_mm"] > 0)]
        return rows if len(rows) else None

    if table is not None:
        same = table[(table["Section"] == section) & (table["Material"] == material)]

        rows = valid(same[same["Sample"] == sample])
        if rows is not None:
            return rows["Diameter_mm"].iloc[0], rows["Length_mm"].iloc[0], "measured"

        rows = valid(same)
        if rows is not None:
            return rows["Diameter_mm"].iloc[0], rows["Length_mm"].iloc[0], "same section"

    all_rows = valid(pd.concat(sheets.values())) if sheets else None
    if all_rows is None:
        return np.nan, np.nan, "missing"

    return all_rows["Diameter_mm"].median(), all_rows["Length_mm"].median(), "year median"


# =========================================================================
# Modulus fit
# =========================================================================

def fit_compressive_modulus(strain, stress):
    """Steepest linear window on the pre-peak curve.

    Returns dict with Modulus_MPa, Intercept_MPa, RSquared, NumberFitPoints,
    FitStartStrain, FitEndStrain (NaN / 0 when no window qualifies)."""
    result = dict(Modulus_MPa=np.nan, Intercept_MPa=np.nan, RSquared=np.nan,
                  NumberFitPoints=0, FitStartStrain=np.nan, FitEndStrain=np.nan)

    if len(stress) < MIN_FIT_POINTS:
        return result

    peak_index = int(np.argmax(stress))
    strain = strain[:peak_index + 1]
    stress = stress[:peak_index + 1]
    peak = stress[-1]

    if not np.isfinite(peak) or peak <= 0:
        return result

    for i in range(len(stress)):
        if stress[i] < FIT_LOWER * peak:
            continue

        # extend the window until stress has risen by the span
        rise = stress[i:] - stress[i]
        reached = np.nonzero(rise >= FIT_STRESS_SPAN * peak)[0]
        if len(reached) == 0:
            break
        j = i + reached[0]

        x = strain[i:j + 1]
        y = stress[i:j + 1]

        if len(x) < MIN_FIT_POINTS or y.max() > FIT_UPPER * peak:
            continue

        slope, intercept = np.polyfit(x, y, 1)
        residual = y - (slope * x + intercept)
        total = np.sum((y - y.mean()) ** 2)
        r_squared = 1 - np.sum(residual ** 2) / total if total > 0 else np.nan

        if not np.isfinite(r_squared) or r_squared < MIN_R_SQUARED:
            continue

        if not np.isfinite(result["Modulus_MPa"]) or slope > result["Modulus_MPa"]:
            result = dict(Modulus_MPa=slope, Intercept_MPa=intercept,
                          RSquared=r_squared, NumberFitPoints=len(x),
                          FitStartStrain=x[0], FitEndStrain=x[-1])

    return result


# =========================================================================
# Plots
# =========================================================================

COLORS = {"CNT": "#2a6fdb", "NEAT": "#d9822b"}


def plot_modulus_vs_ap(accepted, summary, out_base):
    fig, ax = plt.subplots(figsize=(8, 5.5))
    ap_values = sorted(AP_PERCENT_BY_YEAR.values())
    offsets = {"CNT": -0.8, "NEAT": 0.8}

    for material in MATERIALS:
        s = summary[summary.Material == material].sort_values("AP_Percent")
        x = s.AP_Percent + offsets[material]
        ax.errorbar(x, s.MeanModulus_MPa, yerr=s.StdModulus_MPa, fmt="o-",
                    color=COLORS[material], capsize=5, lw=2, ms=8,
                    label=f"{material} mean ± 1 SD")

        pts = accepted[accepted.Material == material]
        jitter = np.random.default_rng(0).uniform(-0.4, 0.4, len(pts))
        ax.scatter(pts.AP_Percent + offsets[material] + jitter,
                   pts.Modulus_MPa, s=14, alpha=0.35,
                   color=COLORS[material], edgecolors="none")

        for _, row in s.iterrows():
            ax.annotate(f"n={row.NumberOfSpecimens}",
                        (row.AP_Percent + offsets[material], 30),
                        ha="center", fontsize=8, color=COLORS[material])

    ax.set_xticks(ap_values)
    ax.set_xticklabels([f"{ap}% AP\n({next(y for y, v in AP_PERCENT_BY_YEAR.items() if v == ap)})"
                        for ap in ap_values])
    ax.set_xlabel("AP content (wt%)")
    ax.set_ylabel("Compressive modulus (MPa)")
    ax.set_title("Compressive modulus vs. AP content")
    ax.set_ylim(bottom=0)
    ax.grid(alpha=0.3)
    ax.legend()
    fig.tight_layout()
    fig.savefig(out_base + ".png", dpi=200)
    fig.savefig(out_base + ".pdf")
    plt.close(fig)


def plot_fit_check(results, curves, year, out_path):
    """One small panel per specimen: stress-strain curve with fitted line."""
    rows = results[results.Year == year].reset_index(drop=True)
    if rows.empty:
        return

    ncols = 8
    nrows = int(np.ceil(len(rows) / ncols))
    fig, axes = plt.subplots(nrows, ncols, figsize=(2.6 * ncols, 2.2 * nrows))
    axes = np.atleast_1d(axes).ravel()

    for ax, (_, row) in zip(axes, rows.iterrows()):
        strain, stress = curves[row.FilePath]
        peak = int(np.argmax(stress)) if len(stress) else 0
        ax.plot(strain, stress, color="0.3", lw=0.8)
        if np.isfinite(row.Modulus_MPa):
            x = np.array([max(0, -row.Intercept_MPa / row.Modulus_MPa),
                          row.FitEndStrain * 1.3])
            ax.plot(x, row.Modulus_MPa * x + row.Intercept_MPa,
                    color=COLORS[row.Material], lw=1.4)
            ax.axvspan(row.FitStartStrain, row.FitEndStrain,
                       color=COLORS[row.Material], alpha=0.15)
        ax.set_xlim(0, strain[peak] * 1.3 if len(strain) else 1)
        ax.set_ylim(0, stress.max() * 1.1 if len(stress) else 1)
        flag = "" if row.FitAccepted else "  REJECTED"
        ax.set_title(f"{row.Group} {row.SampleName}\nE={row.Modulus_MPa:.0f} MPa{flag}",
                     fontsize=7)
        ax.tick_params(labelsize=6)

    for ax in axes[len(rows):]:
        ax.axis("off")

    fig.suptitle(f"{year} compression fits (shaded = fit window)", fontsize=11)
    fig.tight_layout(rect=[0, 0, 1, 0.97])
    fig.savefig(out_path, dpi=110)
    plt.close(fig)


# =========================================================================
# Main
# =========================================================================

def main():
    os.makedirs(OUTPUT_FOLDER, exist_ok=True)

    specimens = classify_compression_specimens()
    if specimens.empty:
        raise SystemExit("No compression specimens found. Run from Junior_Lab_Repo.")

    bluehill_index = index_bluehill_results()
    dimension_sheets = {y: load_compression_dimensions(y) for y in YEARS}

    results = []
    curves = {}

    for _, s in specimens.iterrows():
        diameter, length, dim_source = get_compression_dimensions(
            dimension_sheets[s.Year], s.Batch, s.SectionNumber,
            s.Material, s.SampleNumber)

        data = read_curve(s.FilePath)
        area = np.pi * diameter ** 2 / 4
        strain = (data[:, 1] - data[0, 1]) / length
        stress = data[:, 2] / area
        curves[s.FilePath] = (strain, stress)

        fit = fit_compressive_modulus(strain, stress)

        # Bluehill cross-check
        e_bluehill = np.nan
        bh_name = s.OriginalFileName[:-len("2.csv")] + "1.csv"
        if bh_name in bluehill_index:
            bh = read_bluehill_results(bluehill_index[bh_name])
            if bh is not None:
                e_bh, d_bh, l_bh = bh
                e_bluehill = e_bh * (d_bh / diameter) ** 2 * (length / l_bh)

        accepted = (np.isfinite(fit["Modulus_MPa"]) and fit["Modulus_MPa"] > 0
                    and fit["RSquared"] >= MIN_R_SQUARED)

        ratio = fit["Modulus_MPa"] / e_bluehill if np.isfinite(e_bluehill) else np.nan

        results.append(dict(
            AP_Percent=AP_PERCENT_BY_YEAR[s.Year],
            Epoxy_Percent=100 - AP_PERCENT_BY_YEAR[s.Year],
            Year=s.Year, Material=s.Material, Batch=s.Batch, Day=s.Day,
            Group=s.Group, SampleName=s.SampleName,
            SectionNumber=s.SectionNumber, SampleNumber=s.SampleNumber,
            Diameter_mm=diameter, Length_mm=length, DimensionSource=dim_source,
            PeakForce_N=data[:, 2].max(),
            PeakStress_MPa=stress.max(),
            **fit,
            Bluehill_Modulus_Rescaled_MPa=e_bluehill,
            Ratio_Fit_to_Bluehill=ratio,
            DiffersFromBluehill=bool(np.isfinite(ratio)
                                     and abs(ratio - 1) > BLUEHILL_TOLERANCE),
            FitAccepted=accepted,
            OriginalFileName=s.OriginalFileName, FilePath=s.FilePath))

        print(f"{s.Year} {s.Group:>18} {s.SampleName:<7} "
              f"E = {fit['Modulus_MPa']:7.0f} MPa  R^2 = {fit['RSquared']:.4f}  "
              f"Bluehill = {e_bluehill:7.0f}")

    results = pd.DataFrame(results).sort_values(
        ["AP_Percent", "Material", "Batch", "Day", "Group", "SampleNumber"])
    accepted = results[results.FitAccepted]

    # Summary per composition and material
    summary_rows = []
    for year in YEARS:
        for material in MATERIALS:
            v = accepted[(accepted.Year == year) & (accepted.Material == material)].Modulus_MPa
            if v.empty:
                continue
            summary_rows.append(dict(
                AP_Percent=AP_PERCENT_BY_YEAR[year],
                Epoxy_Percent=100 - AP_PERCENT_BY_YEAR[year],
                Year=year, Material=material,
                MeanModulus_MPa=v.mean(),
                StdModulus_MPa=v.std(ddof=1) if len(v) > 1 else np.nan,
                StdErrModulus_MPa=v.std(ddof=1) / np.sqrt(len(v)) if len(v) > 1 else np.nan,
                MedianModulus_MPa=v.median(),
                MinModulus_MPa=v.min(), MaxModulus_MPa=v.max(),
                NumberOfSpecimens=len(v)))
    summary = pd.DataFrame(summary_rows).sort_values(["AP_Percent", "Material"])

    settings = pd.DataFrame({
        "Setting": ["Method", "FitStressSpan", "FitLower", "FitUpper",
                    "MinFitPoints", "MinRSquared", "BluehillTolerance", "Strain source"],
        "Value": ["Steepest linear window on pre-peak curve (toe-compensated)",
                  FIT_STRESS_SPAN, FIT_LOWER, FIT_UPPER, MIN_FIT_POINTS,
                  MIN_R_SQUARED, BLUEHILL_TOLERANCE,
                  "Crosshead displacement / specimen length (apparent modulus)"]})

    individual_file = os.path.join(OUTPUT_FOLDER, "Compression_Modulus_All_Specimens.xlsx")
    with pd.ExcelWriter(individual_file) as writer:
        results.to_excel(writer, sheet_name="All Specimens", index=False)
        accepted.to_excel(writer, sheet_name="Accepted Fits", index=False)
        settings.to_excel(writer, sheet_name="Fit Settings", index=False)

    summary_file = os.path.join(OUTPUT_FOLDER, "Compression_Modulus_Summary.xlsx")
    summary.to_excel(summary_file, sheet_name="Composition Summary", index=False)

    plot_modulus_vs_ap(accepted, summary,
                       os.path.join(OUTPUT_FOLDER, "Compression_Modulus_vs_AP_Content"))

    for year in YEARS:
        plot_fit_check(results, curves, year,
                       os.path.join(OUTPUT_FOLDER, f"Compression_Fit_Check_{year}.png"))

    print("\n" + summary.round(1).to_string(index=False))
    print(f"\nAccepted {len(accepted)} of {len(results)} specimens. "
          f"{int(results.DiffersFromBluehill.sum())} differ from Bluehill "
          f"by more than {BLUEHILL_TOLERANCE:.0%}.")
    print(f"Results saved to {OUTPUT_FOLDER}")


if __name__ == "__main__":
    main()
