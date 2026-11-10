import subprocess
import pandas as pd
import glob
import os
import numpy as np

bibtex_entry = r"""@misc{grupp2017evo,
  title={evo: Python package for the evaluation of odometry and SLAM},
  author={Grupp, Michael},
  howpublished={\url{https://github.com/MichaelGrupp/evo}},
  year={2017}
}
"""

METRIC_KEYS = ["max", "mean", "median", "min", "rmse", "sse", "std"]


def report_failure(tool: str, method_name: str, traj_file: str, result) -> None:
    """Explain why a method ends up as an empty row / '-' in the tables.

    Without this, a failing evo run silently yields a row holding only the
    method name, which pandas writes as ",,,,,,". The usual causes are an
    empty trajectory file and a trajectory whose timestamps do not overlap
    the ground truth (e.g. wall-clock stamps instead of sensor time).
    """
    print(f"\n!!! {tool} produced no metrics for '{method_name}' -> row will be empty ('-')")
    try:
        size = os.path.getsize(traj_file)
    except OSError:
        size = -1
    if size == 0:
        print(f"    reason: trajectory file is empty (0 bytes): {traj_file}")
    else:
        print(f"    trajectory file: {traj_file} ({size} bytes)")
    print(f"    exit code: {result.returncode}")
    detail = (result.stderr or result.stdout or "").strip().splitlines()
    for line in detail[-5:]:
        print(f"    | {line}")
    print()


# evo's -a (Umeyama SE(3) alignment) fits the estimate onto the ground truth
# using positions only. If an algorithm never moves (every position is the same
# point, e.g. LOAM-Livox only rotating in place), that fit is undefined and evo
# aborts with this message instead of computing any error. The trajectory is
# still a result, just a very bad one, so such rows fall back as follows:
#  - APE: align at the first pose instead (evo --align_origin). The error then
#    measures how far the robot really travelled from where the algorithm
#    stayed. The row is marked with FALLBACK_MARK because its alignment differs.
#  - RPE: rerun without alignment. RPE compares relative motion between poses,
#    which a global alignment does not change, so the value is directly
#    comparable and the row is not marked.
DEGENERATE_ALIGNMENT = "Degenerate covariance rank"
FALLBACK_MARK = " *"
FALLBACK_NOTE_MD = ("\\* never moved, so Umeyama (SE(3)) alignment is impossible; "
                    "aligned at the first pose instead (`evo_ape --align_origin`).")
FALLBACK_NOTE_TEX = ("* never moved, so Umeyama alignment is impossible; "
                     "aligned at the first pose instead.")

# The trajectory plot is saved here (data/tum, next to the tables) and also
# opened in a window when a display is available.
TRAJ_PLOT_FILE = "trajectories.png"
# The plot opens on the ground truth's bounding box, widened on every side by
# this fraction of its larger side. Diverged trajectories leave the view; zoom
# out in the window to see them.
TRAJ_PLOT_MARGIN = 0.1


def method_name_of(traj_file: str) -> str:
    return os.path.basename(traj_file) \
             .replace("output_hdmapping-", "") \
             .replace("_trajectory_tum.txt", "")


def evo_metrics(tool: str, ground_truth: str, traj_file: str, align_args: list[str]):
    cmd = [tool, "tum", ground_truth, traj_file] + align_args
    result = subprocess.run(cmd, capture_output=True, text=True)
    metrics = {}
    for line in result.stdout.split("\n"):
        parts = line.strip().split()
        if len(parts) == 2 and parts[0] in METRIC_KEYS:
            metrics[parts[0]] = float(parts[1])
    return metrics, result


def run_evo(tool: str, ground_truth: str, traj_files: list[str],
            fallback_args: list[str], fallback_mark: str) -> pd.DataFrame:
    results = []

    for traj_file in traj_files:
        method_name = method_name_of(traj_file)

        metrics, result = evo_metrics(tool, ground_truth, traj_file, ["-a"])
        if not metrics and DEGENERATE_ALIGNMENT in (result.stdout + result.stderr):
            how = " ".join(fallback_args) or "no alignment"
            print(f"\n--- {tool}: '{method_name}' never moves, so SE(3) alignment is impossible; retrying with {how}")
            metrics, result = evo_metrics(tool, ground_truth, traj_file, fallback_args)
            if metrics:
                method_name += fallback_mark

        # evo can also "succeed" with nan metrics (e.g. nan poses); treat as failed.
        if not metrics or any(np.isnan(v) for v in metrics.values()):
            report_failure(tool, method_name, traj_file, result)
            metrics = {}
        results.append({"method": method_name, **metrics})

    df = pd.DataFrame(results, columns=["method"] + METRIC_KEYS)
    df = df.sort_values("method")
    return df


def run_evo_ape(ground_truth: str, traj_files: list[str]) -> pd.DataFrame:
    return run_evo("evo_ape", ground_truth, traj_files, ["--align_origin"], FALLBACK_MARK)


def run_evo_rpe(ground_truth: str, traj_files: list[str]) -> pd.DataFrame:
    return run_evo("evo_rpe", ground_truth, traj_files, [], "")

def display_available() -> bool:
    """True if a window can be opened (the X display is reachable)."""
    if not os.environ.get("DISPLAY"):
        return False
    try:
        import tkinter
        tkinter.Tk().destroy()
        return True
    except Exception:
        return False


def run_evo_traj_plot(ground_truth: str, traj_files: list[str]) -> None:
    """The plot of `evo_traj tum ... -a --ref ground_truth.tum --plot_mode xy -p`.

    Same tabbed window (trajectories, xyz, rpy, speeds), drawn with evo's own
    plotting functions. Each trajectory is synced to the ground truth and
    SE(3)-aligned exactly as evo_traj does it (nearest timestamps within
    0.01 s, then Umeyama). Differences from evo_traj:
      - evo_traj aborts the whole plot on a trajectory that never moves, so
        such a trajectory is aligned at its first pose instead, like its APE
        row, and plotted with the others;
      - the trajectories tab opens on the ground truth (TRAJ_PLOT_MARGIN) and
        is saved to TRAJ_PLOT_FILE, also without a display.
    """
    print("\n===== TRAJECTORY PLOT =====")
    show = display_available()

    # evo reads its settings and matplotlib its config from HOME, kept in
    # data/tum as before.
    os.environ["HOME"] = "/data"
    os.environ["XDG_CONFIG_HOME"] = "/data/.config"
    from evo.tools.settings import SETTINGS
    # Must be set before evo.tools.plot is imported, which applies it. Without
    # a display, TkAgg fails, and Agg still saves the picture.
    SETTINGS.plot_backend = "TkAgg" if show else "Agg"
    import itertools
    import matplotlib.cm as cm
    import matplotlib.pyplot as plt
    import seaborn as sns
    from evo.core import sync
    from evo.tools import file_interface, plot

    ref = file_interface.read_tum_trajectory_file(ground_truth)

    aligned = []
    for traj_file in sorted(traj_files):
        method_name = method_name_of(traj_file)
        if not (os.path.isfile(traj_file) and os.path.getsize(traj_file) > 0):
            print(f"Skipping '{method_name}': empty file {traj_file}")
            continue
        try:
            traj = file_interface.read_tum_trajectory_file(traj_file)
            ref_synced, traj = sync.associate_trajectories(ref, traj, max_diff=0.01)
            try:
                traj.align(ref_synced, correct_scale=False)
            except Exception as e:
                if DEGENERATE_ALIGNMENT not in str(e):
                    raise
                traj.align_origin(ref_synced)
                print(f"'{method_name}' never moves: aligned at the first pose")
        except Exception as e:
            print(f"Skipping '{method_name}': {e}")
            continue
        aligned.append((traj_file, method_name, traj))

    # Colors as evo_traj picks them.
    if SETTINGS.plot_multi_cmap.lower() != "none":
        cmap = getattr(cm, SETTINGS.plot_multi_cmap)
        colors = iter(cmap(np.linspace(0, 1, len(aligned))))
    else:
        colors = itertools.cycle(sns.color_palette())

    plot_collection = plot.PlotCollection("evo_traj - trajectory plot")
    fig_xyz, axarr_xyz = plt.subplots(3, sharex="col", figsize=tuple(SETTINGS.plot_figsize))
    fig_rpy, axarr_rpy = plt.subplots(3, sharex="col", figsize=tuple(SETTINGS.plot_figsize))
    fig_traj = plt.figure(figsize=(16, 10))
    fig_speed = plt.figure()
    ax_traj = plot.prepare_axis(fig_traj, plot.PlotMode.xy)

    def plot_over_time(traj, label: str, **style) -> None:
        """The xyz, rpy and speeds tabs, as evo_traj draws them."""
        plot.traj_xyz(axarr_xyz, traj, label=label, **style)
        plot.traj_rpy(axarr_rpy, traj, label=label, **style)
        try:
            plot.speeds(fig_speed.gca(), traj, label=label, **style)
        except Exception as e:
            print(f"Can't plot speeds of {label}: {e}")

    # zorder: on top of the trajectories, which would otherwise hide it.
    ax_traj.plot(ref.positions_xyz[:, 0], ref.positions_xyz[:, 1],
                 SETTINGS.plot_reference_linestyle, color=SETTINGS.plot_reference_color,
                 alpha=SETTINGS.plot_reference_alpha, label="ground truth", zorder=3)
    plot_over_time(ref, os.path.splitext(ground_truth)[0],
                   style=SETTINGS.plot_reference_linestyle,
                   color=SETTINGS.plot_reference_color,
                   alpha=SETTINGS.plot_reference_alpha)

    for traj_file, method_name, traj in aligned:
        color = next(colors)
        ax_traj.plot(traj.positions_xyz[:, 0], traj.positions_xyz[:, 1],
                     SETTINGS.plot_trajectory_linestyle, color=color,
                     alpha=SETTINGS.plot_trajectory_alpha, label=method_name)
        # evo_traj's labels in the other tabs: the file name without extension.
        plot_over_time(traj, os.path.splitext(os.path.basename(traj_file))[0],
                       style=SETTINGS.plot_trajectory_linestyle, color=color,
                       alpha=SETTINGS.plot_trajectory_alpha)
    if "euler_angle_sequence" in SETTINGS and not SETTINGS.plot_usetex:
        fig_rpy.text(0.0, 0.005, f"euler_angle_sequence: {SETTINGS.euler_angle_sequence}",
                     fontsize=6)

    gt_xy = ref.positions_xyz[:, :2]
    low, high = gt_xy.min(axis=0), gt_xy.max(axis=0)
    margin = TRAJ_PLOT_MARGIN * (high - low).max()
    ax_traj.set_xlim(low[0] - margin, high[0] + margin)
    ax_traj.set_ylim(low[1] - margin, high[1] + margin)
    ax_traj.set_aspect("equal")
    ax_traj.set_title(f"{len(aligned)} trajectories, SE(3)-aligned to the ground truth")
    ax_traj.legend(loc="upper center", bbox_to_anchor=(0.5, -0.08), ncol=4,
                   frameon=True, fontsize="small")

    fig_traj.savefig(TRAJ_PLOT_FILE, dpi=150)
    print(f"{len(aligned)} trajectories plotted, saved to data/tum/{TRAJ_PLOT_FILE}")

    plot_collection.add_figure("trajectories", fig_traj)
    plot_collection.add_figure("xyz", fig_xyz)
    plot_collection.add_figure("rpy", fig_rpy)
    plot_collection.add_figure("speeds", fig_speed)
    if show:
        print("Close the plot window to finish.")
        plot_collection.show()

def df_to_latex_table(df: pd.DataFrame, filename: str, caption: str, table_label: str) -> None:
    latex_df = df.copy()
    numeric_cols = ["max", "mean", "median", "min", "rmse", "sse", "std"]
    latex_df[numeric_cols] = latex_df[numeric_cols].fillna("-")

    for col in ["mean", "rmse"]:
        col_vals = pd.to_numeric(latex_df[col], errors="coerce")
        if col_vals.notna().any():
            min_val = col_vals.min()
            latex_df[col] = latex_df[col].apply(
                lambda x: f"\\textbf{{{x:.6f}}}" 
                          if str(x) != "-" and float(x) == min_val 
                          else f"{float(x):.6f}" if str(x) != "-" else "-"
            )

    for col in numeric_cols:
        if col not in ["mean", "rmse"]:
            latex_df[col] = latex_df[col].apply(lambda x: f"{float(x):.6f}" if str(x) != "-" else "-")

    if latex_df["method"].astype(str).str.endswith(FALLBACK_MARK).any():
        caption = f"{caption} {FALLBACK_NOTE_TEX}"

    header = " & " + " & ".join(latex_df.columns[1:]) + " \\\\"

    rows = []
    for _, row in latex_df.iterrows():
        method = row["method"]
        values = " & ".join([str(row[col]) for col in latex_df.columns[1:]])
        line = f"{method} & {values} \\\\"
        rows.append("\t\t" + line)

    latex_table = f"""\\begin{{table}}[]
        \t\\resizebox{{0.5\\textwidth}}{{!}}{{%
        \t\\begin{{tabular}}{{{'l' * len(latex_df.columns)}}}
        \t\t\\rowcolor[HTML]{{C0C0C0}} 
        \t\t{header}
        {chr(10).join(rows)}
        \t\\end{{tabular}}%
        }}
        \t\\caption{{{caption}}}
        \t\\label{{{table_label}}}
\\end{{table}}"""

    with open(filename, "w") as f:
        f.write(latex_table)
        f.write("\n\n")
        f.write(bibtex_entry)
    print(f"{filename}")

def csv_to_markdown_table(csv_file: str, title: str, output_md: str) -> None:
    df = pd.read_csv(csv_file)

    cols = ["method", "max", "mean", "median", "min", "rmse", "sse", "std"]

    df = df[cols]

    lines = []
    lines.append(f"# {title}\n")

    header = "| " + " | ".join(cols) + " |"
    sep = "| " + " | ".join(["-------------"] * len(cols)) + " |"

    lines.append(header)
    lines.append(sep)

    for _, row in df.iterrows():
        values = []
        for c in cols:
            v = row[c]
            if pd.isna(v) or str(v).strip() == "":
                values.append("-")
            else:
                try:
                    values.append(f"{float(v):.6f}")
                except:
                    values.append(str(v))

        lines.append("| " + " | ".join(values) + " |")

    if df["method"].astype(str).str.endswith(FALLBACK_MARK).any():
        lines.append("")
        lines.append(FALLBACK_NOTE_MD)

    with open(output_md, "w") as f:
        f.write("\n".join(lines))

    print(f"{output_md}")

if __name__ == "__main__":
    ground_truth = "ground_truth.tum"
    trajectory_files = glob.glob("output*_trajectory_tum.txt")

    df_ape = run_evo_ape(ground_truth, trajectory_files)
    df_ape.to_csv("table_ape.csv", index=False)
    print(df_ape)

    df_rpe = run_evo_rpe(ground_truth, trajectory_files)
    df_rpe.to_csv("table_rpe.csv", index=False)
    print(df_rpe)

    df_to_latex_table(
        df=df_ape,
        filename="table_ape.tex",
        caption="Quantitative evaluation (Absolute Pose Error \\cite{grupp2017evo}) of algorithms on bunker dataset.",
        table_label="table3"
    )
    df_to_latex_table(
        df=df_rpe,
        filename="table_rpe.tex",
        caption="Quantitative evaluation (Relative Pose Error\\cite{grupp2017evo}) of algorithms on bunker dataset.",
        table_label="table3"
    )

    csv_to_markdown_table("table_ape.csv", "APE (Absolute Pose Error)", "ape_table_github.md")
    csv_to_markdown_table("table_rpe.csv", "RPE (Relative Pose Error)", "rpe_table_github.md")
    
    run_evo_traj_plot(ground_truth, trajectory_files)
