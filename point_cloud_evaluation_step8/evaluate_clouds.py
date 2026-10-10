import argparse
from contextlib import redirect_stderr, redirect_stdout
import csv
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import sys
from typing import TextIO

import numpy as np
import pointcloud_metrics
from scipy.spatial import cKDTree


THRESHOLD_M = 0.01
METRIC_FIELDS = (
    "chamfer_distance_m",
    "chamfer_algorithm_to_faro_m",
    "chamfer_faro_to_algorithm_m",
    "hausdorff_distance_m",
    "precision",
    "recall",
    "fscore",
    "rmse_algorithm_to_faro_m",
)
SUMMARY_FIELDS = (
    "algorithm_id",
    "registration_status",
    "status",
    "registered_laz",
    "reference_laz",
    "algorithm_points",
    "reference_points",
    "threshold_m",
    *METRIC_FIELDS,
    "message",
)
REGISTRATION_STATUSES = {"registered", "missing", "ambiguous", "existing", "failed"}


def selected_algorithms() -> list[str]:
    result = subprocess.run(
        [
            "bash", "-euc",
            'source /workspace/algos_lib.sh; check_only_algos >&2; '
            'for category in ROS1 ROS2 NON_ROS; do algo_rows "$category"; done',
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        raise ValueError(f"cannot select algorithms: {result.stderr.strip()}")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    algorithms = []
    for row in result.stdout.splitlines():
        fields = row.split("\t")
        if len(fields) != 4:
            raise ValueError(f"invalid algorithm configuration row: {row}")
        algo = fields[1]
        if not algo or algo in (".", "..") or Path(algo).name != algo or algo in algorithms:
            raise ValueError(f"invalid or duplicate algorithm ID: {algo}")
        algorithms.append(algo)
    if not algorithms:
        raise ValueError("no algorithms selected")
    return algorithms


def read_registration_report(path: Path) -> dict[str, dict[str, str]]:
    with path.open(newline="") as handle:
        reader = csv.DictReader(handle)
        required = {"algorithm_id", "status", "registered_laz"}
        if not required.issubset(reader.fieldnames or []):
            raise ValueError(f"registration report lacks required columns: {path}")
        rows = {}
        for row in reader:
            algo = row["algorithm_id"]
            if None in row or any(row[key] is None for key in required):
                raise ValueError(f"malformed registration report row in {path}")
            if not algo or algo in rows or row["status"] not in REGISTRATION_STATUSES:
                raise ValueError(f"invalid or duplicate registration report row for {algo}")
            if row["registered_laz"] != f"/results/{algo}/registered.laz":
                raise ValueError(f"unexpected registered LAZ path in report for {algo}")
            rows[algo] = row
    return rows


def laz_point_count(path: Path) -> int:
    with path.open("rb") as handle:
        header = handle.read(375)
    if len(header) < 227 or header[:4] != b"LASF":
        raise ValueError(f"invalid LAS header: {path}")
    count = struct.unpack_from("<I", header, 107)[0]
    if tuple(header[24:26]) == (1, 4):
        count = struct.unpack_from("<Q", header, 247)[0] or count
    if count == 0:
        raise ValueError(f"LAZ has no points: {path}")
    return count


def ply_point_count(path: Path) -> int:
    with path.open("rb") as handle:
        if handle.readline() != b"ply\n":
            raise ValueError(f"invalid PLY signature: {path}")
        count = None
        while handle.tell() < 65536:
            line = handle.readline(4096)
            if not line:
                break
            fields = line.decode("ascii").strip().split()
            if fields[:2] == ["element", "vertex"] and len(fields) == 3:
                count = int(fields[2])
            if fields == ["end_header"]:
                if count is None or count <= 0 or path.stat().st_size <= handle.tell():
                    raise ValueError(f"empty or invalid PLY: {path}")
                return count
    raise ValueError(f"missing or oversized PLY header: {path}")


def convert_laz(source: Path, destination: Path, log: TextIO) -> int:
    expected = laz_point_count(source)
    print(f"Converting {source} -> {destination} ({expected} points)", file=log, flush=True)
    subprocess.run(
        ["laz_to_ply", str(source), str(destination)],
        stdout=log,
        stderr=subprocess.STDOUT,
        check=True,
    )
    converted = ply_point_count(destination)
    if converted != expected:
        raise ValueError(f"conversion point-count mismatch: expected {expected}, got {converted}")
    return expected


def load_cloud(path: Path, expected: int) -> pointcloud_metrics.PointCloud:
    cloud = pointcloud_metrics.load_point_cloud(
        str(path), load_colors=False, load_normals=False,
        voxel_size=None, max_points=None,
    )
    if cloud.points.shape != (expected, 3):
        raise ValueError(f"decoded cloud has unexpected shape {cloud.points.shape}: {path}")
    if not np.isfinite(cloud.points).all():
        raise ValueError(f"cloud contains nonfinite coordinates: {path}")
    print(f"Loaded full cloud: {expected} points from {path}", flush=True)
    return cloud


def prepare_reference(source: Path, output: Path) -> pointcloud_metrics.PointCloud:
    count = laz_point_count(source)
    with source.open("rb") as handle:
        fingerprint = hashlib.file_digest(handle, "sha256").hexdigest()
    provenance = {"source_laz": str(source), "sha256": fingerprint, "points": count}
    folder = output / "reference"
    ply = folder / "faro.ply"
    metadata = folder / "source.json"
    if folder.exists() or folder.is_symlink():
        if not metadata.is_file():
            raise ValueError(f"incomplete reference conversion at {folder}; use a new output directory")
        with metadata.open() as handle:
            if json.load(handle) != provenance:
                raise ValueError(f"FARO reference has changed; use a new output directory instead of {folder}")
        if ply_point_count(ply) != count:
            raise ValueError(f"cached FARO PLY has an unexpected point count: {ply}")
        print(f"Reusing FARO conversion: {ply}")
        with (folder / "conversion.log").open("a") as log:
            with redirect_stdout(log), redirect_stderr(log):
                return load_cloud(ply, count)

    folder.mkdir()
    print(f"Converting FARO once; see {folder / 'conversion.log'}")
    with (folder / "conversion.log").open("x") as log:
        convert_laz(source, ply, log)
        with redirect_stdout(log), redirect_stderr(log):
            reference = load_cloud(ply, count)
    with metadata.open("x") as handle:
        json.dump(provenance, handle, indent=2, allow_nan=False)
    return reference


def compute_metrics(
    algorithm: pointcloud_metrics.PointCloud,
    reference: pointcloud_metrics.PointCloud,
) -> dict[str, float]:
    print("Computing full-cloud Chamfer distances...", flush=True)
    chamfer, to_faro, from_faro = pointcloud_metrics.chamfer_distance(
        algorithm.points, reference.points,
    )
    print("Computing full-cloud Hausdorff distance...", flush=True)
    hausdorff = pointcloud_metrics.hausdorff_distance(algorithm.points, reference.points)
    # The helper expects predictions first, unlike the upstream script's CLI.
    print("Computing precision, recall and F-score...", flush=True)
    prf = pointcloud_metrics.precision_recall_fscore(
        algorithm.points, reference.points, threshold=THRESHOLD_M,
    )
    # Independently sampled clouds have no row correspondence, even at equal sizes.
    print("Computing algorithm-to-FARO nearest-neighbor RMSE...", flush=True)
    distances, _ = cKDTree(reference.points).query(algorithm.points, k=1)
    metrics = {
        "chamfer_distance_m": float(chamfer),
        "chamfer_algorithm_to_faro_m": float(to_faro),
        "chamfer_faro_to_algorithm_m": float(from_faro),
        "hausdorff_distance_m": float(hausdorff),
        "precision": float(prf["precision"]),
        "recall": float(prf["recall"]),
        "fscore": float(prf["fscore"]),
        "rmse_algorithm_to_faro_m": float(np.sqrt(np.mean(distances ** 2))),
    }
    if any(not math.isfinite(value) or value < 0 for value in metrics.values()):
        raise ValueError("evaluation produced nonfinite or negative metrics")
    if any(metrics[key] > 1 for key in ("precision", "recall", "fscore")):
        raise ValueError("precision, recall or F-score is outside [0, 1]")
    return metrics


def evaluate_one(
    algo: str,
    source: Path,
    reference_source: Path,
    reference: pointcloud_metrics.PointCloud,
    folder: Path,
) -> dict[str, object]:
    with (folder / "evaluation.log").open("x") as log:
        expected = convert_laz(source, folder / "registered.ply", log)
        with redirect_stdout(log), redirect_stderr(log):
            cloud = load_cloud(folder / "registered.ply", expected)
            metrics = compute_metrics(cloud, reference)
            print(json.dumps(metrics, indent=2, allow_nan=False), flush=True)
    document = {
        "algorithm_id": algo,
        "registered_laz": str(source),
        "reference_laz": str(reference_source),
        "algorithm_points": expected,
        "reference_points": len(reference),
        "threshold_m": THRESHOLD_M,
        "additional_downsampling": False,
        "metrics": metrics,
    }
    with (folder / "metrics.json").open("x") as handle:
        json.dump(document, handle, indent=2, allow_nan=False)
    return {"algorithm_points": expected, **metrics}


def write_reports(output: Path, records: list[dict[str, object]]) -> None:
    with (output / "evaluation_summary.csv").open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=SUMMARY_FIELDS)
        writer.writeheader()
        writer.writerows(records)
    columns = (
        "algorithm_id", "status", "algorithm_points", "reference_points",
        *METRIC_FIELDS, "message",
    )
    with (output / "evaluation_summary.md").open("w") as handle:
        handle.write("# Step 8 point-cloud evaluation\n\n")
        handle.write("Full clouds; precision/recall distance threshold: < 0.01 m.\n\n")
        handle.write("| " + " | ".join(columns) + " |\n")
        handle.write("| " + " | ".join("---" for _ in columns) + " |\n")
        for record in records:
            values = []
            for column in columns:
                value = record.get(column)
                if value is None:
                    text = "-"
                elif isinstance(value, float):
                    text = f"{value:.6f}"
                else:
                    text = str(value).replace("|", "\\|").replace("\n", " ")
                values.append(text)
            handle.write("| " + " | ".join(values) + " |\n")


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate Step 7 clouds against FARO ground truth.")
    parser.add_argument("--data-dir", type=Path, default=Path("/data"))
    parser.add_argument("--registration-dir", type=Path, default=Path("/registration"))
    parser.add_argument("--output-dir", type=Path, default=Path("/evaluation"))
    args = parser.parse_args()
    data = args.data_dir.resolve(strict=True)
    registration = args.registration_dir.resolve(strict=True)
    output = args.output_dir.resolve()
    if any(output == path or output in path.parents for path in (data, registration)):
        raise ValueError("output directory must not be an input directory or its ancestor")
    reference_source = data / "TLS-FARO-Focus/map_gt_0.01.laz"
    report = read_registration_report(registration / "registration_summary.csv")
    algorithms = selected_algorithms()
    output.mkdir(parents=True, exist_ok=True)
    records = []
    for algo in algorithms:
        row = report.get(algo)
        source = registration / algo / "registered.laz"
        record = {
            "algorithm_id": algo,
            "registration_status": row["status"] if row else "unreported",
            "status": "pending",
            "registered_laz": str(source),
            "reference_laz": str(reference_source),
            "threshold_m": THRESHOLD_M,
            "message": "",
        }
        if not row or row["status"] != "registered":
            record.update(status="not_registered", message=f"Step 7 status: {record['registration_status']}")
        elif not source.is_file() or source.stat().st_size == 0:
            record.update(status="missing_input", message="registered LAZ is missing or empty")
        elif (output / algo).exists() or (output / algo).is_symlink():
            record.update(status="existing", message="existing evaluation folder; refusing to overwrite")
        if record["status"] != "pending":
            print(f"ERROR: {algo}: {record['message']}", file=sys.stderr)
        records.append(record)
    write_reports(output, records)

    if any(record["status"] == "pending" for record in records):
        try:
            reference = prepare_reference(reference_source, output)
        except (OSError, ValueError, RuntimeError, MemoryError, subprocess.SubprocessError) as error:
            for record in records:
                if record["status"] == "pending":
                    record.update(status="failed", message=f"FARO preparation failed: {error}")
            write_reports(output, records)
            raise RuntimeError(f"FARO preparation failed: {error}") from error
        for record in records:
            record["reference_points"] = len(reference)
            if record["status"] != "pending":
                continue
            algo = record["algorithm_id"]
            folder = output / algo
            print(f"Evaluating {algo}; see {folder / 'evaluation.log'}", flush=True)
            created = False
            try:
                folder.mkdir()
                created = True
                values = evaluate_one(algo, registration / algo / "registered.laz", reference_source, reference, folder)
                record.update(values, status="evaluated")
                print(f"Evaluated {algo}", flush=True)
            except (OSError, ValueError, RuntimeError, MemoryError, subprocess.SubprocessError) as error:
                record.update(status="failed", message=str(error))
                if created:
                    with (folder / "evaluation.log").open("a") as log:
                        print(f"ERROR: {error}", file=log)
                print(f"ERROR: {algo}: {error}", file=sys.stderr)
            write_reports(output, records)

    evaluated = sum(record["status"] == "evaluated" for record in records)
    print(f"Step 8 summary: selected={len(records)} evaluated={evaluated} unavailable_or_failed={len(records) - evaluated}")
    print(f"Evaluation report: {output / 'evaluation_summary.csv'}")
    if evaluated != len(records):
        print("ERROR: Step 8 did not evaluate every selected algorithm successfully", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, RuntimeError, MemoryError, subprocess.SubprocessError) as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
