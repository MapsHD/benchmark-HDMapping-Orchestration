import subprocess
import pandas as pd
import glob
import os
import numpy as np

def run_evo_ape(ground_truth: str, traj_files: list[str]) -> pd.DataFrame:
    results = []

    for traj_file in traj_files:
        method_name = os.path.basename(traj_file) \
                        .replace("output_hdmapping-", "") \
                        .replace("_trajectory_tum.txt", "")
        
        cmd = ["evo_ape", "tum", ground_truth, traj_file, "-a"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        output = result.stdout.split("\n")

        metrics = {"method": method_name}
        for line in output:
            parts = line.strip().split()
            if len(parts) == 2:
                key, value = parts
                if key in ["max", "mean", "median", "min", "rmse", "sse", "std"]:
                    metrics[key] = float(value)
        results.append(metrics)

    df = pd.DataFrame(results)
    df = df[["method", "max", "mean", "median", "min", "rmse", "sse", "std"]]
    df = df.sort_values("method")
    return df

def run_evo_rpe(ground_truth: str, traj_files: list[str]) -> pd.DataFrame:
    results = []

    for traj_file in traj_files:
        method_name = os.path.basename(traj_file) \
                        .replace("output_hdmapping-", "") \
                        .replace("_trajectory_tum.txt", "")
        
        cmd = ["evo_rpe", "tum", ground_truth, traj_file, "-a"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        output = result.stdout.split("\n")

        metrics = {"method": method_name}
        for line in output:
            parts = line.strip().split()
            if len(parts) == 2:
                key, value = parts
                if key in ["max", "mean", "median", "min", "rmse", "sse", "std"]:
                    metrics[key] = float(value)
        results.append(metrics)

    df = pd.DataFrame(results)
    df = df[["method", "max", "mean", "median", "min", "rmse", "sse", "std"]]
    df = df.sort_values("method")
    return df

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

    result = subprocess.run(
        cmd,
        text=True,
        capture_output=True
    )

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

    header = " & " + " & ".join(latex_df.columns[1:]) + " \\\\"

    rows = []
    for idx, row in latex_df.iterrows():
        method = row["method"]
        values = " & ".join([str(row[col]) for col in latex_df.columns[1:]])
        line = f"{method} & {values} \\\\"
        if idx % 2 == 1:
            line = "\t\t\\rowcolor[HTML]{EFEFEF} \n\t\t" + line
        else:
            line = "\t\t" + line
        rows.append(line)

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
    print(f"Wygenerowany {filename}")

if __name__ == "__main__":
    ground_truth = "ground_truth.tum"
    trajectory_files = glob.glob("output*_trajectory_tum.txt")

    df_ape = run_evo_ape(ground_truth, trajectory_files)
    df_ape.to_csv("tabela_ape.csv", index=False)
    print(df_ape)

    df_rpe = run_evo_rpe(ground_truth, trajectory_files)
    df_rpe.to_csv("tabela_rpe.csv", index=False)
    print(df_rpe)

    df_to_latex_table(
        df=df_ape,
        filename="tabela_ape.tex",
        caption="Quantitative evaluation (Absolute Pose Error \\cite{grupp2017evo}) of algorithms on bunker dataset. '-' corresponds to results we could not reach. First three rows: our method and ablation study.",
        table_label="table3"
    )
    df_to_latex_table(
        df=df_rpe,
        filename="tabela_rpe.tex",
        caption="Quantitative evaluation (Relative Pose Error\\cite{grupp2017evo}) of algorithms on bunker dataset. '-' corresponds to results we could not reach. First three rows: our method and ablation study.",
        table_label="table3"
    )

    run_evo_traj_plot(ground_truth, trajectory_files)