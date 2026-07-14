import os
import glob

def tum_info(path):

    if not os.path.exists(path):
        raise FileNotFoundError(f"Nie znaleziono pliku: {path}")

    with open(path, "r") as f:
        lines = [
            line.strip()
            for line in f
            if line.strip() and not line.startswith("#")
        ]

    if len(lines) == 0:
        raise ValueError(f"Plik {path} jest pusty.")

    timestamps = [float(line.split()[0]) for line in lines]

    return {
        "ts_begin": timestamps[0],
        "ts_end": timestamps[-1],
        "duration": timestamps[-1] - timestamps[0],
        "num_nodes": len(lines)
    }


gt = tum_info(os.path.expanduser(
    "~/hdmapping-benchmark/data/tum/ground_truth.tum"
))


lio_files = glob.glob(os.path.expanduser(
    "~/hdmapping-benchmark/data/tum/output_hdmapping-*_trajectory_tum.txt"
))


print("=" * 60)
print("GROUND TRUTH")
print("=" * 60)
print(f"Start timestamp : {gt['ts_begin']:.9f}")
print(f"End timestamp   : {gt['ts_end']:.9f}")
print(f"Duration        : {gt['duration']:.3f} s")
print(f"Nodes           : {gt['num_nodes']}")


print()


results = []

for lio_file in sorted(lio_files):

    try:
        lio = tum_info(lio_file)

        metric1 = (
            (lio["ts_end"] - lio["ts_begin"]) /
            (gt["ts_end"] - gt["ts_begin"])
        ) * 100


        metric2 = (
            lio["num_nodes"] /
            gt["num_nodes"]
        ) * 100


        lio_frequency = (
            lio["num_nodes"] /
            lio["duration"]
        )


        name = os.path.basename(lio_file)
        name = name.replace("output_hdmapping-", "")
        name = name.replace("_trajectory_tum.txt", "")

        print("=" * 60)
        print(name.upper())
        print("=" * 60)
        print(f"Start timestamp : {lio['ts_begin']:.9f}")
        print(f"End timestamp   : {lio['ts_end']:.9f}")
        print(f"Duration        : {lio['duration']:.3f} s")
        print(f"Nodes           : {lio['num_nodes']}")
        print(f"Frequency       : {lio_frequency:.2f} Hz")

        print()

        print("RESULTS")
        print("-" * 60)
        print(f"Metric 1 (time coverage): {metric1:.2f}%")
        print(f"Metric 2 (node ratio)   : {metric2:.2f}%")
        print()

        results.append({
            "name": name,
            "metric1": metric1,
            "metric2": metric2,
            "nodes": lio["num_nodes"]
        })


    except Exception as e:
        print(f"{lio_file}: ERROR -> {e}")

print()
print("=" * 90)
print("FINAL RESULTS TABLE")
print("=" * 90)

print(
    f"{'Algorithm':40s}"
    f"{'Metric1 [%]':>15s}"
    f"{'Metric2 [%]':>15s}"
    f"{'Nodes':>10s}"
)

print("-" * 90)

for r in results:
    print(
        f"{r['name']:40s}"
        f"{r['metric1']:15.2f}"
        f"{r['metric2']:15.2f}"
        f"{r['nodes']:10d}"
    )

md_file = os.path.expanduser(
    "~/hdmapping-benchmark/data/tum/overlap_results.md"
)

with open(md_file, "w") as f:

    f.write("# LIO overlap benchmark\n\n")

    f.write("| Algorithm | Metric1 [%] | Metric2 [%] | Nodes |\n")
    f.write("|-----------|-------------|-------------|-------|\n")

    for r in results:
        f.write(
            f"| {r['name']} "
            f"| {r['metric1']:.2f} "
            f"| {r['metric2']:.2f} "
            f"| {r['nodes']} |\n"
        )

print(f"Saved: {md_file}")

latex_file = os.path.expanduser(
    "~/hdmapping-benchmark/data/tum/overlap_results.tex"
)

caption = "LIO overlap benchmark."
table_label = "tab:lio_overlap"


latex_table = f"""\\begin{{table}}[]
\\centering
\\begin{{tabular}}{{lccc}}
\\rowcolor[HTML]{{C0C0C0}}
Algorithm & Metric1 [\\%] & Metric2 [\\%] & Nodes \\\\
"""


for r in results:
    latex_table += (
        f"{r['name']} & "
        f"{r['metric1']:.2f} & "
        f"{r['metric2']:.2f} & "
        f"{r['nodes']} \\\\\n"
    )


latex_table += f"""\\end{{tabular}}
\\caption{{{caption}}}
\\label{{{table_label}}}
\\end{{table}}"""


with open(latex_file, "w") as f:
    f.write(latex_table)

print(f"Saved: {latex_file}")