import argparse
from concurrent.futures import ThreadPoolExecutor
from contextlib import contextmanager
import csv
from dataclasses import dataclass, field
from datetime import datetime
import fcntl
import hashlib
import json
import math
import os
from pathlib import Path
from queue import Empty, Queue
import re
import shutil
import signal
import struct
import subprocess
import sys
import tempfile
from threading import Event, Lock
from time import monotonic
from typing import Iterator, TextIO, TypedDict

from validate_registration import nonnegative_distance, positive_distance, validate_registration


THRESHOLD_M = 0.05
VOXEL_SIZE_M = 0.05
EVALUATION_BACKEND = "pointcloud_metrics_cli"
UPSTREAM_METRIC_MAP = {
    "chamfer_distance_m": "chamfer_distance",
    "chamfer_algorithm_to_faro_m": "chamfer_pc2_to_pc1",
    "chamfer_faro_to_algorithm_m": "chamfer_pc1_to_pc2",
    "hausdorff_distance_m": "hausdorff_distance",
    # The CLI is reference-first, but its precision helper treats pc1 as predictions.
    "precision": "recall",
    "recall": "precision",
    "fscore": "fscore",
    "rmse_m": "rmse",
}
METRIC_FIELDS = (
    "chamfer_distance_m",
    "chamfer_algorithm_to_faro_m",
    "chamfer_faro_to_algorithm_m",
    "hausdorff_distance_m",
    "precision",
    "recall",
    "fscore",
    "rmse_m",
)
SUMMARY_FIELDS = (
    "algorithm_id",
    "registration_status",
    "status",
    "registered_laz",
    "reference_laz",
    "algorithm_input_points",
    "reference_input_points",
    "algorithm_points",
    "reference_points",
    "voxel_size_m",
    "threshold_m",
    *METRIC_FIELDS,
    "message",
)
REGISTRATION_STATUSES = {"registered", "missing", "ambiguous", "existing", "failed"}
EVALUATION_ERRORS = (
    OSError, ValueError, RuntimeError, MemoryError, subprocess.SubprocessError, argparse.ArgumentTypeError,
)
CONSOLE = sys.stdout
PHASES = (
    "Hashing", "Conversion", "Loading FARO", "Loading algorithm",
    "Chamfer", "Hausdorff", "Precision/recall", "RMSE", "Saving",
)
UPSTREAM_PHASES = {
    "Loading reference point cloud from:": 3,
    "Loading distorted point cloud from:": 4,
    "Computing Chamfer Distance...": 5,
    "Computing Hausdorff Distance...": 6,
    "Computing Precision, Recall, F-score...": 7,
    "Computing RMSE...": 8,
}


class ReferenceProvenance(TypedDict):
    source_laz: str
    sha256: str
    points: int


class RunControl:
    def __init__(self) -> None:
        self.cancelled = Event()
        self.lock = Lock()
        self.processes: dict[int, subprocess.Popen[str]] = {}

    def check_cancelled(self) -> None:
        if self.cancelled.is_set():
            raise RuntimeError("evaluation cancelled")

    @staticmethod
    def signal_process(process: subprocess.Popen[str], signum: int) -> None:
        if process.poll() is None:
            try:
                os.killpg(process.pid, signum)
            except ProcessLookupError:
                pass  # The process exited between poll() and killpg().

    def cancel(self) -> None:
        self.cancelled.set()
        with self.lock:
            processes = list(self.processes.values())
        for process in processes:
            self.signal_process(process, signal.SIGTERM)
        deadline = monotonic() + 5
        for process in processes:
            try:
                process.wait(timeout=max(0, deadline - monotonic()))
            except subprocess.TimeoutExpired:
                self.signal_process(process, signal.SIGKILL)
                process.wait()

    @contextmanager
    def process(self, command: list[str], stdout: TextIO | int) -> Iterator[subprocess.Popen[str]]:
        process = None
        try:
            with self.lock:
                self.check_cancelled()
                process = subprocess.Popen(
                    command, stdout=stdout, stderr=subprocess.STDOUT, text=True,
                    bufsize=1, start_new_session=True,
                )
                self.processes[process.pid] = process
            yield process
        finally:
            if process is not None:
                self.signal_process(process, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    self.signal_process(process, signal.SIGKILL)
                    process.wait()
                finally:
                    if process.stdout is not None:
                        process.stdout.close()
                    with self.lock:
                        self.processes.pop(process.pid, None)


@dataclass
class ProgressEvent:
    worker_id: int
    algorithm_id: str
    message: str
    stage: int = 0
    result: dict[str, object] | None = None
    at: float = field(default_factory=monotonic)


@dataclass
class Worker:
    worker_id: int
    algorithm_id: str
    events: Queue[ProgressEvent]
    control: RunControl

    def emit(self, message: str, stage: int = 0, result: dict[str, object] | None = None) -> None:
        self.events.put(ProgressEvent(self.worker_id, self.algorithm_id, message, stage, result))


class ProgressDisplay:
    def __init__(self, workers: int, total: int) -> None:
        self.total = total
        self.completed = 0
        self.failed = 0
        self.states: dict[int, ProgressEvent] = {}
        self.started: dict[int, float] = {}
        self.phase_started: dict[int, float] = {}
        self.interactive = CONSOLE.isatty()
        self.last_refresh = 0.0
        self.bars = []
        if self.interactive:
            try:
                from tqdm import tqdm
            except ImportError as error:
                raise RuntimeError("interactive progress requires tqdm; rebuild the Step 8 image") from error

            self.overall = tqdm(total=total, desc="Overall", position=0, file=CONSOLE, leave=True)
            self.bars = [
                tqdm(
                    total=len(PHASES), desc=f"W{slot} idle", position=slot,
                    file=CONSOLE, leave=True,
                    bar_format="{desc} |{bar}| {n_fmt}/{total_fmt} stages {postfix}",
                )
                for slot in range(1, workers + 1)
            ]

    def handle(self, event: ProgressEvent) -> None:
        previous = self.states.get(event.worker_id)
        new_algorithm = previous is None or previous.algorithm_id != event.algorithm_id
        if new_algorithm:
            self.started[event.worker_id] = event.at
            if self.interactive:
                self.bars[event.worker_id - 1].reset(total=len(PHASES))
        if new_algorithm or (event.stage and (previous is None or event.stage != previous.stage)):
            self.phase_started[event.worker_id] = event.at
        if event.stage or event.result is not None or new_algorithm:
            self.states[event.worker_id] = event
        if event.result is not None:
            self.completed += 1
            failed = event.result["status"] != "evaluated"
            self.failed += int(failed)
            if self.interactive:
                self.overall.update(1)
                if failed:
                    self.overall.write(f"ERROR: W{event.worker_id} {event.algorithm_id}: {event.message}", file=CONSOLE)
            else:
                progress(
                    f"W{event.worker_id} {event.algorithm_id}: {event.message}; "
                    f"processed {self.completed}/{self.total}, failed={self.failed}"
                )
        elif not self.interactive:
            progress(f"W{event.worker_id} {event.algorithm_id}: {event.message}")

    def refresh(self, *, force: bool = False) -> None:
        now = monotonic()
        if not self.interactive or (not force and now - self.last_refresh < 0.5):
            return
        self.last_refresh = now
        self.overall.set_postfix_str(f"OK={self.completed - self.failed}, failed={self.failed}", refresh=False)
        self.overall.refresh()
        for slot, event in self.states.items():
            bar = self.bars[slot - 1]
            if event.result is not None:
                success = event.result["status"] == "evaluated"
                phase = "DONE" if success else "FAILED"
                elapsed = event.at - self.started[slot]
                if success:
                    bar.n = len(PHASES)
                bar.set_postfix_str(f"{phase}, elapsed={elapsed:.1f}s", refresh=False)
            else:
                bar.n = max(0, event.stage - 1)
                phase = PHASES[event.stage - 1] if event.stage else "Starting"
                bar.set_postfix_str(
                    f"{phase}, elapsed={now - self.started[slot]:.1f}s, "
                    f"phase={now - self.phase_started[slot]:.1f}s",
                    refresh=False,
                )
            bar.set_description_str(f"W{slot} {event.algorithm_id}", refresh=False)
            bar.refresh()

    def close(self) -> None:
        self.refresh(force=True)
        for bar in reversed(self.bars):
            bar.close()
        if self.interactive:
            self.overall.close()


def positive_jobs(value: str) -> int:
    if not re.fullmatch(r"[1-9][0-9]*", value):
        raise argparse.ArgumentTypeError("jobs must be a positive integer")
    return int(value)


@contextmanager
def output_lock(output: Path) -> Iterator[None]:
    with (output / ".evaluation.lock").open("a") as handle:
        try:
            fcntl.flock(handle, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise RuntimeError(f"another Step 8 run is using {output}; stop it or use a separate output directory") from error
        try:
            yield
        finally:
            fcntl.flock(handle, fcntl.LOCK_UN)


def progress(
    message: str, log: TextIO | None = None, *,
    worker: Worker | None = None, stage: int = 0,
) -> None:
    line = f"[{datetime.now().astimezone().isoformat(timespec='seconds')}] {message}"
    if worker is None:
        print(line, file=CONSOLE, flush=True)
    else:
        worker.emit(message, stage)
    if log is not None:
        print(line, file=log, flush=True)


@contextmanager
def timed_phase(
    label: str, log: TextIO | None = None, *,
    worker: Worker | None = None, stage: int = 0,
) -> Iterator[None]:
    started = monotonic()
    progress(f"START {label}", log, worker=worker, stage=stage)
    try:
        yield
    except (*EVALUATION_ERRORS, KeyboardInterrupt, SystemExit):
        progress(f"FAILED/INTERRUPTED {label} ({monotonic() - started:.1f}s)", log, worker=worker)
        raise
    else:
        progress(f"DONE {label} ({monotonic() - started:.1f}s)", log, worker=worker)


@contextmanager
def atomic_output(path: Path, *, newline: str | None = None) -> Iterator[TextIO]:
    with tempfile.NamedTemporaryFile(
        mode="w", dir=path.parent, prefix=f".{path.name}.", suffix=".tmp",
        newline=newline, delete=False,
    ) as handle:
        temporary = Path(handle.name)
        try:
            yield handle
            handle.close()
            temporary.replace(path)
        finally:
            temporary.unlink(missing_ok=True)


def write_json(path: Path, document: object) -> None:
    with atomic_output(path) as handle:
        json.dump(document, handle, indent=2, allow_nan=False)


def sha256(path: Path, control: RunControl | None = None) -> str:
    with path.open("rb") as handle:
        if control is not None:
            digest = hashlib.sha256()
            while chunk := handle.read(1024 * 1024):
                control.check_cancelled()
                digest.update(chunk)
            control.check_cancelled()
            return digest.hexdigest()
        return hashlib.file_digest(handle, "sha256").hexdigest()


def reference_provenance(source: Path) -> ReferenceProvenance:
    return {"source_laz": str(source), "sha256": sha256(source), "points": laz_point_count(source)}


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
        if not algo or algo in (".", "..", "reference", ".evaluation.lock") or Path(algo).name != algo or algo in algorithms:
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


def convert_laz(
    source: Path, destination: Path, log: TextIO, control: RunControl, *,
    worker: Worker | None = None,
) -> int:
    expected = laz_point_count(source)
    with timed_phase(
        f"Converting {source} -> {destination} ({expected:,} points)", log, worker=worker, stage=2,
    ):
        command = ["laz_to_ply", str(source), str(destination)]
        with control.process(command, log) as process:
            while process.poll() is None:
                control.check_cancelled()
                try:
                    process.wait(timeout=0.2)
                except subprocess.TimeoutExpired:
                    continue
            control.check_cancelled()
            returncode = process.wait()
            if returncode != 0:
                raise subprocess.CalledProcessError(returncode, command)
        converted = ply_point_count(destination)
        if converted != expected:
            raise ValueError(f"conversion point-count mismatch: expected {expected}, got {converted}")
    return expected


def remove_result_folder(folder: Path, output: Path, worker: Worker | None = None) -> None:
    if folder.parent != output or folder == output or folder.name in ("", ".", ".."):
        raise ValueError(f"refusing to remove a path outside the output's immediate children: {folder}")
    progress(f"Replacing results at {folder}", worker=worker)
    if folder.is_symlink():
        folder.unlink()
    elif folder.is_mount():
        raise ValueError(f"refusing to remove a mounted result directory: {folder}")
    elif folder.is_dir():
        shutil.rmtree(folder)
    elif folder.exists():
        folder.unlink()


def prepare_reference(
    source: Path, output: Path, provenance: ReferenceProvenance, control: RunControl, *,
    force: bool = True,
) -> Path:
    count = laz_point_count(source)
    folder = output / "reference"
    ply = folder / "faro.ply"
    metadata = folder / "source.json"
    if folder.exists() or folder.is_symlink():
        try:
            if folder.is_symlink() and force:
                raise ValueError("cannot reuse a symlinked FARO cache when replacement is enabled")
            if not metadata.is_file():
                raise ValueError(f"incomplete reference conversion at {folder}; rerun without --no-force or use a separate output directory")
            with metadata.open() as handle:
                if json.load(handle) != provenance:
                    raise ValueError(f"FARO reference has changed; rerun without --no-force or use a separate output directory instead of {folder}")
            if ply_point_count(ply) != count:
                raise ValueError(f"cached FARO PLY has an unexpected point count: {ply}")
        except (OSError, ValueError) as error:
            if not force:
                raise
            print(f"WARNING: rebuilding FARO cache: {error}", file=sys.stderr)
            remove_result_folder(folder, output)
        else:
            print(f"Reusing FARO conversion: {ply}")
            return ply

    folder.mkdir()
    print(f"Converting FARO once; see {folder / 'conversion.log'}")
    with (folder / "conversion.log").open("x") as log:
        convert_laz(source, ply, log, control)
    write_json(metadata, provenance)
    return ply


def validate_metrics(metrics: object, label: str) -> dict[str, float]:
    if not isinstance(metrics, dict) or set(metrics) != set(METRIC_FIELDS):
        raise ValueError(f"{label} lacks the expected metrics; reevaluate with default replacement or use a separate output directory")
    if any(
        type(value) not in (int, float) or not math.isfinite(value) or value < 0
        for value in metrics.values()
    ):
        raise ValueError(f"{label} contains nonnumeric, nonfinite or negative metrics")
    if any(metrics[key] > 1 for key in ("precision", "recall", "fscore")):
        raise ValueError(f"{label} has precision, recall or F-score outside [0, 1]")
    return {key: float(metrics[key]) for key in METRIC_FIELDS}


def validate_evaluated_count(value: object, expected: int, voxel_size: float, label: str) -> int:
    if type(value) is not int or not 0 < value <= expected:
        raise ValueError(f"unexpected {label}: {value}, input count: {expected}")
    if voxel_size == 0 and value != expected:
        raise ValueError(f"unsampled {label} differs from input count: {value} != {expected}")
    return value


def run_upstream_evaluation(
    algo: str, registered_ply: Path, reference_ply: Path, folder: Path,
    algorithm_input_points: int, reference_input_points: int, log: TextIO, worker: Worker, *,
    voxel_size: float, threshold: float,
) -> tuple[dict[str, float], int, int]:
    metrics_path = folder / "upstream_metrics.json"
    command = [
        sys.executable, "-u", "-m", "pointcloud_metrics",
        str(reference_ply), str(registered_ply),
        "--threshold", str(threshold), "--timings", "--output", str(metrics_path),
    ]
    if voxel_size > 0:
        command.extend(["--voxel-size", str(voxel_size)])
    counts = []
    with timed_phase(f"{algo}: upstream evaluation (shared NN cache enabled by default)", log, worker=worker):
        with worker.control.process(command, subprocess.PIPE) as process:
            if process.stdout is None:
                raise RuntimeError("upstream evaluator output pipe was not created")
            for line in process.stdout:
                worker.control.check_cancelled()
                log.write(line)
                log.flush()
                message = line.strip()
                if message:
                    stage = next((stage for marker, stage in UPSTREAM_PHASES.items() if message.startswith(marker)), 0)
                    worker.emit(message, stage)
                # The CLI JSON contains metrics only; point counts are printed once per input.
                match = re.fullmatch(r"  Points: ([0-9]+)\n?", line)
                if match:
                    counts.append(int(match[1]))
            returncode = process.wait()
            worker.control.check_cancelled()
        if returncode != 0:
            raise RuntimeError(f"upstream evaluator exited with code {returncode}; see {log.name}")
        if len(counts) != 2:
            raise ValueError(f"upstream evaluator did not report exactly two cloud point counts; see {log.name}")
        reference_points = validate_evaluated_count(
            counts[0], reference_input_points, voxel_size, "reference_points",
        )
        algorithm_points = validate_evaluated_count(
            counts[1], algorithm_input_points, voxel_size, "algorithm_points",
        )
        with metrics_path.open() as handle:
            upstream_metrics = json.load(handle)
        if not isinstance(upstream_metrics, dict) or set(upstream_metrics) != set(UPSTREAM_METRIC_MAP.values()):
            raise ValueError(f"upstream evaluator returned unexpected metric fields: {metrics_path}")
        metrics = validate_metrics(
            {key: upstream_metrics[source] for key, source in UPSTREAM_METRIC_MAP.items()},
            f"upstream result {metrics_path}",
        )
    return metrics, algorithm_points, reference_points


def evaluate_one(
    algo: str,
    source: Path,
    reference_source: Path,
    reference_ply: Path,
    folder: Path,
    reference_points: int,
    reference_sha256: str,
    worker: Worker,
    *,
    voxel_size: float,
    threshold: float,
) -> dict[str, object]:
    with (folder / "evaluation.log").open("x") as log:
        progress(f"{algo}: voxel size={voxel_size} m, threshold={threshold} m", log, worker=worker)
        with timed_phase(f"{algo}: hashing registered LAZ", log, worker=worker, stage=1):
            fingerprint = sha256(source, worker.control)
        expected = convert_laz(source, folder / "registered.ply", log, worker.control, worker=worker)
        metrics, algorithm_points, evaluated_reference_points = run_upstream_evaluation(
            algo, folder / "registered.ply", reference_ply, folder,
            expected, reference_points, log, worker, voxel_size=voxel_size, threshold=threshold,
        )
    document = {
        "algorithm_id": algo,
        "registered_laz": str(source),
        "reference_laz": str(reference_source),
        "evaluation_backend": EVALUATION_BACKEND,
        "algorithm_input_points": expected,
        "reference_input_points": reference_points,
        "algorithm_points": algorithm_points,
        "reference_points": evaluated_reference_points,
        "voxel_size_m": voxel_size,
        "threshold_m": threshold,
        "additional_downsampling": voxel_size > 0,
        "registered_laz_sha256": fingerprint,
        "reference_sha256": reference_sha256,
        "metrics": metrics,
    }
    with (folder / "evaluation.log").open("a") as log:
        with timed_phase(f"{algo}: saving metrics.json", log, worker=worker, stage=9):
            worker.control.check_cancelled()
            write_json(folder / "metrics.json", document)
    return {
        "algorithm_input_points": expected, "reference_input_points": reference_points,
        "algorithm_points": algorithm_points, "reference_points": evaluated_reference_points, **metrics,
    }


def evaluate_algorithm(
    algo: str,
    source: Path,
    reference_source: Path,
    folder: Path,
    reference_points: int,
    reference_sha256: str,
    reference_ply: Path,
    worker: Worker,
    force: bool = True,
    *,
    voxel_size: float,
    threshold: float,
) -> dict[str, object]:
    created = False
    try:
        worker.control.check_cancelled()
        if force and (folder.exists() or folder.is_symlink()):
            remove_result_folder(folder, folder.parent, worker)
        folder.mkdir()
        created = True
        values = evaluate_one(
            algo, source, reference_source, reference_ply, folder, reference_points, reference_sha256, worker,
            voxel_size=voxel_size, threshold=threshold,
        )
        return {**values, "status": "evaluated", "message": ""}
    except EVALUATION_ERRORS as error:
        message = str(error)
        if created:
            try:
                with (folder / "evaluation.log").open("a") as log:
                    print(f"ERROR: {error}", file=log)
                write_json(folder / "failure.json", {
                    "algorithm_id": algo,
                    "registered_laz": str(source),
                    "reference_laz": str(reference_source),
                    "reference_sha256": reference_sha256,
                    "voxel_size_m": voxel_size,
                    "threshold_m": threshold,
                    "additional_downsampling": voxel_size > 0,
                    "status": "failed",
                    "message": message,
                })
            except EVALUATION_ERRORS as persistence_error:
                message += f"; could not persist failure: {persistence_error}"
                progress(f"ERROR: {algo}: {message}", worker=worker)
        return {"status": "failed", "message": message}


def read_saved_result(
    folder: Path, algo: str, source: Path, reference_source: Path, provenance: ReferenceProvenance,
    *, voxel_size: float, threshold: float,
) -> dict[str, object]:
    metrics_path = folder / "metrics.json"
    failure_path = folder / "failure.json"
    if metrics_path.exists() and failure_path.exists():
        raise ValueError(f"conflicting completion and failure records at {folder}")
    path = metrics_path if metrics_path.is_file() else failure_path
    if not path.is_file():
        raise ValueError(f"no complete metrics or failure record at {folder}; evaluation is incomplete")
    with path.open() as handle:
        document = json.load(handle)
    if not isinstance(document, dict):
        raise ValueError(f"invalid saved result: {path}")
    expected = {
        "algorithm_id": algo, "registered_laz": str(source),
        "reference_laz": str(reference_source), "threshold_m": threshold,
        "additional_downsampling": voxel_size > 0,
    }
    if (
        any(document.get(key) != value for key, value in expected.items())
        or document.get("voxel_size_m", 0.0) != voxel_size
    ):
        raise ValueError(f"saved result has different inputs or settings: {path}")
    if document.get("reference_sha256", provenance["sha256"]) != provenance["sha256"]:
        raise ValueError(f"FARO reference has changed since evaluation: {path}")
    if path == failure_path:
        if document.get("status") != "failed" or not isinstance(document.get("message"), str) or not document["message"]:
            raise ValueError(f"invalid failure record: {path}")
        return {"status": "failed", "message": document["message"]}
    if document.get("evaluation_backend") != EVALUATION_BACKEND:
        raise ValueError(
            f"saved result is not from the upstream CLI: {path}; "
            "reevaluate with default replacement or use a separate output directory"
        )
    counts = {}
    for prefix, count in (("algorithm", laz_point_count(source)), ("reference", provenance["points"])):
        input_key = f"{prefix}_input_points"
        evaluated_key = f"{prefix}_points"
        input_count = document.get(input_key) if "voxel_size_m" in document else document.get(evaluated_key)
        evaluated_count = document.get(evaluated_key)
        if type(input_count) is not int or input_count != count:
            raise ValueError(f"saved result has an unexpected {input_key}: {path}")
        validate_evaluated_count(evaluated_count, input_count, voxel_size, f"{evaluated_key} in {path}")
        counts.update({input_key: input_count, evaluated_key: evaluated_count})
    if "registered_laz_sha256" in document and "reference_sha256" in document:
        if document["registered_laz_sha256"] != sha256(source):
            raise ValueError(f"registered LAZ has changed since evaluation: {path}")
    elif "registered_laz_sha256" in document or "reference_sha256" in document:
        raise ValueError(f"incomplete input fingerprints: {path}")
    else:
        print(
            f"WARNING: {algo}: legacy metrics lack input fingerprints; "
            "checking paths, point counts and cached FARO provenance only",
            file=sys.stderr,
        )
    metrics = validate_metrics(document.get("metrics"), f"saved result {path}")
    return {"status": "evaluated", "message": "", **counts, **metrics}


def write_reports(output: Path, records: list[dict[str, object]]) -> None:
    with atomic_output(output / "evaluation_summary.csv", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=SUMMARY_FIELDS)
        writer.writeheader()
        writer.writerows(records)
    columns = (
        "algorithm_id", "status", "algorithm_input_points", "reference_input_points",
        "algorithm_points", "reference_points", "voxel_size_m", "threshold_m",
        *METRIC_FIELDS, "message",
    )
    with atomic_output(output / "evaluation_summary.md") as handle:
        handle.write("# Step 8 point-cloud evaluation\n\n")
        handle.write("Distances in meters; precision/recall uses a strict less-than threshold.\n")
        handle.write("rmse_m uses upstream reference-to-algorithm NN RMSE for unequal counts, "
                     "or row-correspondence RMSE for equal counts.\n")
        handle.write("Input point counts are before voxel filtering; algorithm/reference points are evaluated counts.\n\n")
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


def run_workers(
    pending: list[str], records: dict[str, dict[str, object]],
    registration: Path, reference_source: Path, reference_ply: Path,
    output: Path, provenance: ReferenceProvenance, control: RunControl, *,
    jobs: int, force: bool, voxel_size: float, threshold: float,
) -> None:
    tasks: Queue[str] = Queue()
    events: Queue[ProgressEvent] = Queue()
    for algo in pending:
        tasks.put(algo)
    workers = min(jobs, len(pending))
    display = ProgressDisplay(workers, len(pending))
    pool = ThreadPoolExecutor(max_workers=workers, thread_name_prefix="step8")
    futures = []

    def run_worker(slot: int) -> None:
        while not control.cancelled.is_set():
            try:
                algo = tasks.get_nowait()
            except Empty:
                return
            worker = Worker(slot, algo, events, control)
            started = monotonic()
            worker.emit(f"START; log: {output / algo / 'evaluation.log'}", stage=1)
            values = evaluate_algorithm(
                algo, registration / algo / "registered.laz", reference_source,
                output / algo, provenance["points"], provenance["sha256"], reference_ply,
                worker, force, voxel_size=voxel_size, threshold=threshold,
            )
            elapsed = monotonic() - started
            message = (
                f"DONE in {elapsed:.1f}s" if values["status"] == "evaluated"
                else f"FAILED after {elapsed:.1f}s: {values['message']}"
            )
            worker.emit(message, result=values)

    def collect(event: ProgressEvent) -> None:
        if event.result is not None:
            records[event.algorithm_id].update(event.result)
        display.handle(event)

    try:
        for slot in range(1, workers + 1):
            futures.append(pool.submit(run_worker, slot))
        while True:
            try:
                collect(events.get(timeout=0.2))
            except Empty:
                pass
            for future in futures:
                if future.done():
                    future.result()
            display.refresh()
            if all(future.done() for future in futures):
                break
    finally:
        control.cancel()
        pool.shutdown(wait=True, cancel_futures=True)
        while True:
            try:
                collect(events.get_nowait())
            except Empty:
                break
        display.close()


def merge_worker_reports(
    pending: list[str], records: dict[str, dict[str, object]],
    registration: Path, reference_source: Path, output: Path,
    provenance: ReferenceProvenance, *, voxel_size: float, threshold: float,
) -> None:
    for algo in pending:
        record = records[algo]
        folder = output / algo
        if record["status"] == "evaluated" or (
            record["status"] == "failed"
            and (folder / "failure.json").is_file()
            and not (folder / "metrics.json").exists()
        ):
            for key in (*METRIC_FIELDS, "algorithm_input_points", "algorithm_points", "reference_points"):
                record.pop(key, None)
            try:
                record.update(read_saved_result(
                    folder, algo, registration / algo / "registered.laz", reference_source,
                    provenance, voxel_size=voxel_size, threshold=threshold,
                ))
            except EVALUATION_ERRORS as error:
                record.update(status="failed", message=f"cannot merge saved report: {error}")
        elif record["status"] == "pending":
            record.update(status="failed", message="evaluation interrupted before a report was saved")
        if record["status"] == "failed":
            print(f"ERROR: {algo}: {record['message']}", file=sys.stderr)


def main() -> int:
    parser = argparse.ArgumentParser(description="Evaluate Step 7 clouds against FARO ground truth.")
    parser.add_argument("--data-dir", type=Path, default=Path("/data"))
    parser.add_argument("--registration-dir", type=Path, default=Path("/registration"))
    parser.add_argument("--output-dir", type=Path, default=Path("/evaluation"))
    parser.add_argument(
        "--jobs", type=positive_jobs, default=1,
        help="simultaneous algorithm evaluations (default: 1)",
    )
    parser.add_argument(
        "--voxel-size", type=nonnegative_distance, default=VOXEL_SIZE_M,
        help="voxel size in meters for both clouds (default: 0.05; 0 disables downsampling)",
    )
    parser.add_argument(
        "--threshold", type=positive_distance, default=THRESHOLD_M,
        help="precision/recall distance threshold in meters (default: 0.05)",
    )
    parser.add_argument("--merge-only", action="store_true", help="rebuild summaries without replacing per-map results")
    parser.add_argument(
        "--no-force", dest="force", action="store_false",
        help="preserve existing evaluation folders instead of replacing them",
    )
    args = parser.parse_args()
    args.force = args.force and not args.merge_only
    progress(f"Step 8 {'merge' if args.merge_only else f'evaluation (jobs={args.jobs})'} started")
    data = args.data_dir.resolve(strict=True)
    registration = args.registration_dir.resolve(strict=True)
    output = args.output_dir.resolve()
    if any(output == path or output in path.parents for path in (data, registration)):
        raise ValueError("output directory must not be an input directory or its ancestor")
    if args.merge_only:
        if not output.is_dir():
            raise ValueError(f"evaluation output directory does not exist: {output}")
    else:
        output.mkdir(parents=True, exist_ok=True)
    control = RunControl()
    with output_lock(output):
        try:
            return run_locked(args, data, registration, output, control)
        finally:
            control.cancel()


def run_locked(
    args: argparse.Namespace, data: Path, registration: Path, output: Path, control: RunControl,
) -> int:
    run_started = monotonic()
    reference_source = data / "TLS-FARO-Focus/map_gt_0.01.laz"
    report = read_registration_report(registration / "registration_summary.csv")
    algorithms = selected_algorithms()
    if args.force:
        progress("WARNING: selected eligible evaluation results will be permanently replaced; use --no-force to preserve them")
    if args.merge_only:
        with timed_phase("Hashing FARO reference for merge validation"):
            provenance = reference_provenance(reference_source)
        with (output / "reference/source.json").open() as handle:
            if json.load(handle) != provenance:
                raise ValueError("FARO reference has changed; cannot merge saved results")
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
            "voxel_size_m": args.voxel_size,
            "threshold_m": args.threshold,
            "message": "",
        }
        eligible = bool(row and row["status"] == "registered")
        if row and row["status"] == "existing":
            try:
                validate_registration(source.parent)
                eligible = True
                print(f"Reusing completed Step 7 registration for {algo}", flush=True)
            except (OSError, ValueError, struct.error, argparse.ArgumentTypeError) as error:
                record.update(status="not_registered", message=f"existing Step 7 output is not reusable: {error}")
        if not eligible and record["status"] == "pending":
            record.update(status="not_registered", message=f"Step 7 status: {record['registration_status']}")
        elif eligible and (not source.is_file() or source.stat().st_size == 0):
            record.update(status="missing_input", message="registered LAZ is missing or empty")
        elif eligible and args.merge_only:
            record["reference_input_points"] = provenance["points"]
            try:
                with timed_phase(f"{algo}: merging saved results"):
                    record.update(read_saved_result(
                        output / algo, algo, source, reference_source, provenance,
                        voxel_size=args.voxel_size, threshold=args.threshold,
                    ))
            except EVALUATION_ERRORS as error:
                record.update(status="failed", message=str(error))
        elif eligible and not args.force and ((output / algo).exists() or (output / algo).is_symlink()):
            record.update(status="existing", message="existing evaluation folder; refusing to overwrite")
        if record["status"] == "not_registered":
            print(f"SKIP: {algo}: {record['message']}", flush=True)
        elif record["status"] not in ("pending", "evaluated"):
            print(f"ERROR: {algo}: {record['message']}", file=sys.stderr)
        records.append(record)
    if any(record["status"] == "pending" for record in records):
        try:
            with timed_phase("Hashing FARO reference"):
                provenance = reference_provenance(reference_source)
            with timed_phase("Preparing FARO PLY conversion once"):
                reference_ply = prepare_reference(
                    reference_source, output, provenance, control, force=args.force,
                )
        except EVALUATION_ERRORS as error:
            for record in records:
                if record["status"] == "pending":
                    record.update(status="failed", message=f"FARO preparation failed: {error}")
            write_reports(output, records)
            raise RuntimeError(f"FARO preparation failed: {error}") from error
        for record in records:
            record["reference_input_points"] = provenance["points"]
        records_by_id = dict(zip(algorithms, records, strict=True))
        pending = [algo for algo in algorithms if records_by_id[algo]["status"] == "pending"]
        progress(
            f"Evaluating {len(pending)} maps with up to {min(args.jobs, len(pending))} workers; "
            f"{len(records) - len(pending)} selected maps are not pending. "
            "Combined reports are replaced only after workers finish."
        )
        try:
            run_workers(
                pending, records_by_id, registration, reference_source, reference_ply,
                output, provenance, control, jobs=args.jobs, force=args.force,
                voxel_size=args.voxel_size, threshold=args.threshold,
            )
        except (*EVALUATION_ERRORS, KeyboardInterrupt, SystemExit):
            merge_worker_reports(
                pending, records_by_id, registration, reference_source, output,
                provenance, voxel_size=args.voxel_size, threshold=args.threshold,
            )
            write_reports(output, records)
            raise
        with timed_phase("Merging saved per-algorithm reports"):
            merge_worker_reports(
                pending, records_by_id, registration, reference_source, output,
                provenance, voxel_size=args.voxel_size, threshold=args.threshold,
            )

    write_reports(output, records)
    evaluated = sum(record["status"] == "evaluated" for record in records)
    skipped = sum(record["status"] == "not_registered" for record in records)
    unsuccessful = len(records) - evaluated - skipped
    print(f"Step 8 summary: selected={len(records)} evaluated={evaluated} skipped={skipped} unavailable_or_failed={unsuccessful}")
    print(f"Evaluation report: {output / 'evaluation_summary.csv'}")
    progress(f"Step 8 finished in {monotonic() - run_started:.1f}s")
    if evaluated == 0:
        print("ERROR: Step 8 did not evaluate any registered algorithm successfully", file=sys.stderr)
        return 1
    if unsuccessful:
        print("ERROR: Step 8 did not evaluate every eligible registered algorithm successfully", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    def interrupt(signum: int, frame: object) -> None:
        raise KeyboardInterrupt(f"received signal {signum}")

    signal.signal(signal.SIGTERM, interrupt)
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("ERROR: Step 8 interrupted; completed metrics are preserved and active maps may be incomplete", file=sys.stderr)
        sys.exit(130)
    except EVALUATION_ERRORS as error:
        print(f"ERROR: {error}", file=sys.stderr)
        sys.exit(1)
