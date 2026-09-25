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
        method_name = os.path.basename(traj_file) \
                        .replace("output_hdmapping-", "") \
                        .replace("_trajectory_tum.txt", "")

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

def run_evo_traj_plot(ground_truth: str, traj_files: list[str]) -> None:
    valid_files = []

    for f in sorted(traj_files):
        if os.path.isfile(f) and os.path.getsize(f) > 0:
            valid_files.append(f)
        else:
            print(f"Skipping empty file: {f}")

    if not valid_files:
        print("No valid trajectory files found.")
        return

    cmd = [
        "evo_traj",
        "tum",
        *valid_files,
        "-a",
        "--ref", ground_truth,
        "--plot_mode", "xy",
        "-p",
    ]

    env = os.environ.copy()
    env["HOME"] = "/data"
    env["XDG_CONFIG_HOME"] = "/data/.config"

    result = subprocess.run(
        cmd,
        text=True,
        capture_output=True,
        cwd="/data",
        env=env
    )

    print("\n===== TRAJECTORY EVALUATION (evo_traj) =====")

    if result.returncode == 0:
        print("Status: SUCCESS (run completed without errors)")
    else:
        print("Status: FAILED (error occurred during execution)")
        print(f"Exit code: {result.returncode}")

    print("\n Program output:")
    print(result.stdout.strip() if result.stdout else "(no output)")

    if result.stderr:
        print("\n Error details:")
        print(result.stderr.strip())
    else:
        print("\n Error details:")
        print("(no error message)")

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
        caption="Quantitative evaluation (Absolute Pose Error \\cite{grupp2017evo}) of algorithms on bunker dataset. '-' corresponds to results we could not reach. First three rows: our method and ablation study.",
        table_label="table3"
    )
    df_to_latex_table(
        df=df_rpe,
        filename="table_rpe.tex",
        caption="Quantitative evaluation (Relative Pose Error\\cite{grupp2017evo}) of algorithms on bunker dataset. '-' corresponds to results we could not reach. First three rows: our method and ablation study.",
        table_label="table3"
    )

    csv_to_markdown_table("table_ape.csv", "APE (Absolute Pose Error)", "ape_table_github.md")
    csv_to_markdown_table("table_rpe.csv", "RPE (Relative Pose Error)", "rpe_table_github.md")
    
    run_evo_traj_plot(ground_truth, trajectory_files)