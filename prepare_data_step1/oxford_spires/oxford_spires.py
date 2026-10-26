#!/usr/bin/env python3
"""Oxford Spires helpers for the benchmark's Oxford-Spires branch.

  calibration   <cam-lidar-imu.yaml>
      Prints R_lidar_imu as "qx qy qz qw", the rotation bag_to_laz --imu-rotation
      applies to bring the Alphasense IMU into the Hesai lidar frame.
  ground-truth  <gt-tum.txt> <out.tum>
      Moves the official ground truth (base frame, ICP to the TLS map) to the lidar
      frame: T_world_lidar = T_world_base * T_base_lidar, T_base_lidar from the dataset
      wiki (Sensors page): [0, 0, 0.124, 0, 0, 1, 0] (x y z qx qy qz qw).
  gt-session    <session_dir> <ground_truth.tum> <out_dir> [--chunk-s 5] [--every 3]
      Builds the HDMapping ground-truth session steps 4, 7 and 8 align to: the raw scans
      of the HDMapping session, deskewed with the ground-truth poses (interpolated per
      point) and cut into --chunk-s chunks, each in its own chunk frame. In the TLS frame,
      like the ground truth.
  tls-reference <merged-cloud-1cm.pcd> <ground_truth.tum> <out.laz> [--margin 20]
      Writes the step 8 reference: the site's TLS map cropped to the walked path plus
      --margin metres, as LAZ (point format 1, 0.1 mm scale).

Quaternions in cam-lidar-imu.yaml are [x, y, z, w]: C_q_CL reproduces T_cam_lidar only in
that order, which `calibration` asserts.
"""
import argparse
import glob
import json
import os
import sys

import numpy as np

# ---------------------------------------------------------------------------
# rotations
# ---------------------------------------------------------------------------


def rot_xyzw(q):
    x, y, z, w = q
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def quat_xyzw(r):
    # Shepperd's method, branch on the largest diagonal term for stability.
    t = np.trace(r)
    if t > 0:
        s = 2 * np.sqrt(t + 1)
        q = [(r[2, 1] - r[1, 2]) / s, (r[0, 2] - r[2, 0]) / s, (r[1, 0] - r[0, 1]) / s, s / 4]
    else:
        i = int(np.argmax(np.diag(r)))
        j, k = (i + 1) % 3, (i + 2) % 3
        s = 2 * np.sqrt(1 + r[i, i] - r[j, j] - r[k, k])
        q = [0.0] * 4
        q[i] = s / 4
        q[j] = (r[j, i] + r[i, j]) / s
        q[k] = (r[k, i] + r[i, k]) / s
        q[3] = (r[k, j] - r[j, k]) / s
    q = np.array(q)
    return q / np.linalg.norm(q)


def log_so3(r):
    """Rotation matrices (n,3,3) -> rotation vectors (n,3)."""
    cos = np.clip((np.trace(r, axis1=1, axis2=2) - 1) / 2, -1, 1)
    ang = np.arccos(cos)
    w = np.stack([r[:, 2, 1] - r[:, 1, 2], r[:, 0, 2] - r[:, 2, 0], r[:, 1, 0] - r[:, 0, 1]], 1)
    s = np.sin(ang)
    k = np.where(s > 1e-9, ang / (2 * np.where(s > 1e-9, s, 1)), 0.5)
    return w * k[:, None]


def exp_so3(v):
    """Rotation vectors (n,3) -> rotation matrices (n,3,3) (Rodrigues)."""
    ang = np.linalg.norm(v, axis=1)
    a = np.where(ang > 1e-12, ang, 1)
    k = v / a[:, None]
    kx = np.zeros((len(v), 3, 3))
    kx[:, 0, 1], kx[:, 0, 2], kx[:, 1, 2] = -k[:, 2], k[:, 1], -k[:, 0]
    kx[:, 1, 0], kx[:, 2, 0], kx[:, 2, 1] = k[:, 2], -k[:, 1], k[:, 0]
    s, c = np.sin(ang)[:, None, None], np.cos(ang)[:, None, None]
    return np.eye(3)[None] + s * kx + (1 - c) * kx @ kx


class Trajectory:
    """A TUM trajectory with per-time pose interpolation (lerp + slerp)."""

    def __init__(self, tum_path):
        d = np.loadtxt(tum_path, ndmin=2)
        self.t = d[:, 0]
        self.p = d[:, 1:4]
        self.r = np.stack([rot_xyzw(q) for q in d[:, 4:8]])
        self.dlog = log_so3(np.einsum("nji,njk->nik", self.r[:-1], self.r[1:]))

    def interpolate(self, t):
        i = np.clip(np.searchsorted(self.t, t, side="right") - 1, 0, len(self.t) - 2)
        f = ((t - self.t[i]) / (self.t[i + 1] - self.t[i]))[:, None]
        return self.r[i] @ exp_so3(self.dlog[i] * f), self.p[i] * (1 - f) + self.p[i + 1] * f

    def matrix(self, t):
        r, p = self.interpolate(np.atleast_1d(t))
        m = np.tile(np.eye(4), (len(r), 1, 1))
        m[:, :3, :3], m[:, :3, 3] = r, p
        return m


# ---------------------------------------------------------------------------
# calibration
# ---------------------------------------------------------------------------


def cmd_calibration(args):
    import yaml

    cam = yaml.safe_load(open(args.calibration))["cam0"]
    t_cam_lidar = np.array(cam["T_cam_lidar"])
    if not np.allclose(rot_xyzw(cam["C_q_CL"]), t_cam_lidar[:3, :3], atol=1e-6):
        sys.exit("C_q_CL does not reproduce T_cam_lidar as [x, y, z, w]: unexpected calibration file")
    r_lidar_imu = t_cam_lidar[:3, :3].T @ rot_xyzw(cam["C_q_CI"])
    print(" ".join("%.9f" % v for v in quat_xyzw(r_lidar_imu)))


# ---------------------------------------------------------------------------
# ground truth in the lidar frame
# ---------------------------------------------------------------------------

T_BASE_LIDAR = np.eye(4)
T_BASE_LIDAR[:3, :3] = rot_xyzw([0.0, 0.0, 1.0, 0.0])
T_BASE_LIDAR[:3, 3] = [0.0, 0.0, 0.124]


def cmd_ground_truth(args):
    n = 0
    with open(args.gt) as f_in, open(args.out, "w") as f_out:
        for line in f_in:
            if not line.strip() or line.startswith("#"):
                continue
            stamp, *v = line.split()
            t_world_base = np.eye(4)
            t_world_base[:3, :3] = rot_xyzw([float(x) for x in v[3:7]])
            t_world_base[:3, 3] = [float(x) for x in v[:3]]
            t = t_world_base @ T_BASE_LIDAR
            f_out.write(f"{stamp} " + " ".join(f"{x:.9f}" for x in (*t[:3, 3], *quat_xyzw(t[:3, :3]))) + "\n")
            n += 1
    print(f"{n} poses -> {args.out}")


# ---------------------------------------------------------------------------
# HDMapping ground-truth session
# ---------------------------------------------------------------------------


def write_poses(path, poses):
    with open(path, "w") as f:
        f.write(f"{len(poses)}\n")
        for k, m in enumerate(poses):
            f.write(f"scan_lio_{k}.laz\n")
            for row in m:
                f.write(" ".join("%.9g" % x for x in row) + "\n")


def cmd_gt_session(args):
    import laspy

    os.makedirs(args.out_dir, exist_ok=True)
    traj = Trajectory(args.gt)
    t0, t1 = traj.t[0], traj.t[-1]
    edges = np.arange(t0, t1, args.chunk_s)
    chunk_poses = traj.matrix(edges)
    chunk_inv = np.linalg.inv(chunk_poses)
    n_chunks = len(edges)
    print(f"ground truth {t0:.3f}..{t1:.3f} ({t1 - t0:.1f} s) -> {n_chunks} chunks of {args.chunk_s} s")

    # Points of a chunk can sit in two input files, so collect them per chunk first.
    buffers = {k: [] for k in range(n_chunks)}
    written = 0

    def flush(k):
        nonlocal written
        parts = buffers.pop(k)
        pts = np.concatenate([p[0] for p in parts]) if parts else np.zeros((0, 3))
        ts = np.concatenate([p[1] for p in parts]) if parts else np.zeros(0)
        inten = np.concatenate([p[2] for p in parts]) if parts else np.zeros(0)
        h = laspy.LasHeader(point_format=1, version="1.2")
        h.scales = np.array([1e-4, 1e-4, 1e-4])
        h.offsets = np.zeros(3)
        las = laspy.LasData(h)
        las.x, las.y, las.z = pts[:, 0], pts[:, 1], pts[:, 2]
        las.intensity = inten.astype(np.uint16)
        las.gps_time = ts * 1e9
        las.write(os.path.join(args.out_dir, f"scan_lio_{k}.laz"))
        written += len(pts)

        lo, hi = edges[k], edges[k + 1] if k + 1 < n_chunks else t1 + 1e-9
        sel = (traj.t >= lo) & (traj.t < hi)
        local = chunk_inv[k] @ traj.matrix(traj.t[sel])
        with open(os.path.join(args.out_dir, f"trajectory_lio_{k}.csv"), "w") as f:
            f.write("timestamp_nanoseconds pose00 pose01 pose02 pose03 pose10 pose11 pose12 pose13 "
                    "pose20 pose21 pose22 pose23 timestampUnix_nanoseconds\n")
            for t, m in zip(traj.t[sel], local):
                ns = int(round(t * 1e9))
                f.write(f"{ns} " + " ".join("%.10g" % x for x in m[:3].ravel()) + f" {ns}\n")

    next_flush = 0
    for fn in sorted(glob.glob(os.path.join(args.session_dir, "lidar*.laz"))):
        las = laspy.read(fn)
        t = np.asarray(las.gps_time)[:: args.every]
        xyz = np.stack([las.x, las.y, las.z], 1)[:: args.every]
        inten = np.asarray(las.intensity)[:: args.every]
        keep = (t >= t0) & (t <= t1) & (np.linalg.norm(xyz, axis=1) > 0.5)
        t, xyz, inten = t[keep], xyz[keep], inten[keep]
        k = np.clip(np.searchsorted(edges, t, side="right") - 1, 0, n_chunks - 1)
        for c in np.unique(k):
            m = k == c
            r, p = traj.interpolate(t[m])
            world = np.einsum("nij,nj->ni", r, xyz[m]) + p
            local = world @ chunk_inv[c][:3, :3].T + chunk_inv[c][:3, 3]
            buffers[c].append((local, t[m], inten[m]))
        # Input files are in time order: every chunk that ends before this file's last point is done.
        last = np.searchsorted(edges, t[-1], side="right") - 1 if len(t) else next_flush
        while next_flush < last:
            flush(next_flush)
            next_flush += 1
    while next_flush < n_chunks:
        flush(next_flush)
        next_flush += 1

    write_poses(os.path.join(args.out_dir, "session_poses.mrp"), chunk_poses)
    write_poses(os.path.join(args.out_dir, "session_ini_poses.mri"), chunk_poses)
    session = {
        "Session Settings": {
            "folder_name": ".",
            "out_folder_name": ".",
            "initial_poses_file_name": "session_ini_poses.mri",
            "poses_file_name": "session_poses.mrp",
            "out_poses_file_name": "session_poses.mrp",
            "lidar_odometry_version": "ground truth (gt-tum.txt, TLS frame)",
            "offset_x": 0.0,
            "offset_y": 0.0,
            "offset_z": 0.0,
        },
        "laz_file_names": [{"file_name": f"scan_lio_{k}.laz"} for k in range(n_chunks)],
    }
    with open(os.path.join(args.out_dir, "session.mjs"), "w") as f:
        json.dump(session, f, indent=2)
    print(f"{n_chunks} chunks, {written} points -> {args.out_dir}")


# ---------------------------------------------------------------------------
# step 8 TLS reference
# ---------------------------------------------------------------------------


def read_pcd_xyz_intensity(path):
    """Binary PCD with float fields (the Oxford TLS maps: Intensity rgb x y z + padding)."""
    with open(path, "rb") as f:
        header = {}
        while True:
            line = f.readline().decode("ascii", "replace").strip()
            key, _, value = line.partition(" ")
            header[key] = value.split()
            if key == "DATA":
                break
        if header["DATA"] != ["binary"]:
            sys.exit(f"{path}: only binary PCD is supported, got DATA {header['DATA']}")
        names, sizes, types = header["FIELDS"], header["SIZE"], header["TYPE"]
        counts = header.get("COUNT", ["1"] * len(names))
        fmt = {("F", "4"): "f4", ("F", "8"): "f8", ("U", "1"): "u1", ("U", "2"): "u2", ("U", "4"): "u4",
               ("I", "1"): "i1", ("I", "2"): "i2", ("I", "4"): "i4"}
        dtype = np.dtype([(n if n != "_" else f"_pad{i}", fmt[(t, s)], (int(c),) if int(c) > 1 else ())
                          for i, (n, s, t, c) in enumerate(zip(names, sizes, types, counts))])
        data = np.frombuffer(f.read(), dtype=dtype, count=int(header["POINTS"][0]))
    xyz = np.stack([data["x"], data["y"], data["z"]], 1).astype(np.float64)
    name = next((n for n in ("intensity", "Intensity") if n in data.dtype.names), None)
    inten = data[name].astype(np.float64) if name else np.zeros(len(data))
    return xyz, inten


def cmd_tls_reference(args):
    import laspy

    gt = np.loadtxt(args.gt, ndmin=2)[:, 1:4]
    lo, hi = gt.min(0) - args.margin, gt.max(0) + args.margin
    xyz, inten = read_pcd_xyz_intensity(args.pcd)
    keep = np.all((xyz >= lo) & (xyz <= hi), 1)
    xyz, inten = xyz[keep], inten[keep]
    if inten.size and inten.max() <= 1.0:
        inten = inten * 65535  # normalized intensity -> LAS uint16
    h = laspy.LasHeader(point_format=1, version="1.2")
    h.scales = np.array([1e-4, 1e-4, 1e-4])
    h.offsets = np.zeros(3)
    las = laspy.LasData(h)
    las.x, las.y, las.z = xyz[:, 0], xyz[:, 1], xyz[:, 2]
    las.intensity = np.clip(inten, 0, 65535).astype(np.uint16)
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    las.write(args.out)
    print(f"{keep.sum()} of {len(keep)} TLS points in {np.round(lo, 1)} .. {np.round(hi, 1)} -> {args.out}")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("calibration")
    p.add_argument("calibration")
    p.set_defaults(fn=cmd_calibration)
    p = sub.add_parser("ground-truth")
    p.add_argument("gt")
    p.add_argument("out")
    p.set_defaults(fn=cmd_ground_truth)
    p = sub.add_parser("gt-session")
    p.add_argument("session_dir")
    p.add_argument("gt")
    p.add_argument("out_dir")
    p.add_argument("--chunk-s", type=float, default=5.0)
    p.add_argument("--every", type=int, default=3, help="keep every K-th point")
    p.set_defaults(fn=cmd_gt_session)
    p = sub.add_parser("tls-reference")
    p.add_argument("pcd")
    p.add_argument("gt")
    p.add_argument("out")
    p.add_argument("--margin", type=float, default=20.0)
    p.set_defaults(fn=cmd_tls_reference)
    args = ap.parse_args()
    args.fn(args)


if __name__ == "__main__":
    main()
