import argparse
import math
from pathlib import Path
import re
import struct
import sys


FAILURE_DIAGNOSTICS = re.compile(
    r"AtPA=AtPB FAILED|DLL ERROR|problem with saving file|Rigid registration failed|ERROR:|"
    r"(^|[^a-zA-Z0-9_])[-+]?(nan|inf|infinity)([^a-zA-Z0-9_]|$)",
    re.IGNORECASE,
)


def nonnegative_distance(value: str) -> float:
    if not re.fullmatch(r"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?", value):
        raise argparse.ArgumentTypeError("distance must be a decimal number in meters")
    try:
        distance = float(value)
    except ValueError as error:
        raise argparse.ArgumentTypeError("distance must be a finite number in meters") from error
    if not math.isfinite(distance) or distance < 0:
        raise argparse.ArgumentTypeError("distance must be finite and nonnegative")
    return distance


def positive_distance(value: str) -> float:
    distance = nonnegative_distance(value)
    if distance == 0:
        raise argparse.ArgumentTypeError("distance must be greater than zero")
    return distance


def validate_laz(path: Path) -> int:
    with path.open("rb") as handle:
        header = handle.read(375)
    if len(header) < 227 or header[:4] != b"LASF":
        raise ValueError("missing or truncated LAS header")
    version = tuple(header[24:26])
    minimum_header_size = {(1, 2): 227, (1, 3): 235, (1, 4): 375}.get(version)
    if minimum_header_size is None:
        raise ValueError(f"unsupported LAS version {version}")
    if len(header) < minimum_header_size:
        raise ValueError("truncated LAS header")
    header_size, data_offset = struct.unpack_from("<HI", header, 94)
    if header_size < minimum_header_size or data_offset < header_size:
        raise ValueError("invalid header size or point-data offset")
    if path.stat().st_size <= data_offset:
        raise ValueError("no point data follows the header")
    points = struct.unpack_from("<I", header, 107)[0]
    if version == (1, 4):
        points = struct.unpack_from("<Q", header, 247)[0] or points
    if points == 0:
        raise ValueError("registered point cloud contains no points")
    scales_and_offsets = struct.unpack_from("<6d", header, 131)
    bounds = struct.unpack_from("<6d", header, 179)
    if not all(math.isfinite(value) for value in scales_and_offsets + bounds):
        raise ValueError("nonfinite coordinate metadata")
    if any(scale <= 0 for scale in scales_and_offsets[:3]):
        raise ValueError("invalid coordinate scales")
    if any(bounds[i] < bounds[i + 1] for i in (0, 2, 4)):
        raise ValueError("invalid coordinate bounds")
    return points


def validate_registration(
    folder: Path, *, require_record: bool = True, bucket_size: float | None = None,
) -> int:
    for name in ("sanity_check_trg.txt", "sanity_check_src.txt"):
        path = folder / name
        if not path.is_file() or path.stat().st_size == 0:
            raise ValueError(f"missing or empty sanity-check trajectory: {path}")
    points = validate_laz(folder / "registered.laz")
    completed = False
    validated = False
    recorded_bucket = None
    with (folder / "registration.log").open() as log:
        for line in log:
            if FAILURE_DIAGNOSTICS.search(line):
                raise ValueError(f"registration log contains failure diagnostics: {line.strip()}")
            if line.startswith("Rigid registration completed successfully. Output saved to: "):
                completed = line.strip().endswith(f"/{folder.name}/registered.laz")
            if line.startswith(f"Validated LAZ header: {points} points in "):
                validated = line.strip().endswith(f"/{folder.name}/registered.laz")
            if line.startswith("Registration bucket size: "):
                recorded_bucket = positive_distance(line.split(": ", 1)[1].strip())
    if not completed:
        raise ValueError("registration log lacks a successful completion record for this algorithm")
    if require_record and not validated:
        raise ValueError("registration log lacks a matching output-validation record; output is incomplete")
    if bucket_size is not None and recorded_bucket != bucket_size:
        raise ValueError(
            f"saved bucket size is {recorded_bucket}, requested {bucket_size}; "
            "use --force or a separate output directory"
        )
    return points


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Validate completed Step 7 registration artifacts.")
    parser.add_argument("folder", type=Path, nargs="?")
    parser.add_argument("--new", action="store_true", help="validate a new output before recording header validation")
    parser.add_argument("--bucket-size", type=positive_distance, help="require this bucket size in meters")
    args = parser.parse_args()
    if args.folder is None:
        if args.bucket_size is None or args.new:
            parser.error("a folder or --bucket-size is required")
        print(f"Bucket size: {args.bucket_size} m")
        sys.exit(0)
    try:
        count = validate_registration(args.folder, require_record=not args.new, bucket_size=args.bucket_size)
    except (OSError, ValueError, struct.error, argparse.ArgumentTypeError) as error:
        print(f"ERROR: invalid registration at {args.folder}: {error}", file=sys.stderr)
        sys.exit(1)
    print(f"Validated LAZ header: {count} points in {args.folder / 'registered.laz'}")
