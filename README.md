# benchmark-HDMapping-Orchestration: Oxford Spires

Benchmark of LiDAR odometry algorithms on the
[Oxford Spires dataset](https://huggingface.co/datasets/ori-drs/oxford_spires_dataset)
(handheld, Hesai QT64 lidar, Alphasense IMU). The algorithms read a **canonical
bag** instead of the Livox bags of the other branches; each needs a
`hdmapping-benchmark-canonical` branch in its own repository, otherwise it is
skipped.

All data and results go to `~/hdmapping-benchmark/data`.

# Tutorial

Runs the pipeline step by step on `2024-03-12-keble-college-02` for two
algorithms. Use one terminal and run the blocks in order.

## Setup

Requirements: Linux, Git, Python 3, `curl`, `wget`, Docker without `sudo`, an X
session (some algorithms open windows), about 25 GB per sequence for the download
plus space for bags, images and results. A GPU is optional (PIN-SLAM only).

```shell
mkdir -p ~/hdmapping-benchmark
cd ~/hdmapping-benchmark
git clone https://github.com/MapsHD/benchmark-HDMapping-Orchestration.git
cd benchmark-HDMapping-Orchestration
git checkout Oxford-Spires
find . -name '*.sh' -exec chmod +x {} +
export ONLY_ALGOS="fast-lio pv-lio"   # IDs from algorithms.conf; unset = all
```

## Step 1. Download and convert

Builds the `hdmapping-tools` and `oxford-spires-tools` images, downloads the
sequence from Hugging Face and converts it. An interrupted run resumes.

```shell
cd ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration
prepare_data_step1/oxford_spires/prepare.sh
./validate.sh
```

**Check:** `validate.sh` reports `failed=0`, and the data folder has
`keble-college-02.bag`, `keble-college-02-ros2/`, `keble-college-02-hdmapping/`,
`ground_truth.tum`, `HDMappingGroundTruth/` and `TLS-FARO-Focus/map_gt_0.01.laz`
(the Oxford TLS map, under the Bunker name).

## Step 2. Clone and build the algorithms

```shell
cd ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration
./clone_github_repositories_step2/clone_github_repositories_step2.sh hdmapping-benchmark-canonical
```

**Check:** `~/hdmapping-benchmark/benchmark-FAST-LIO-to-HDMapping/` and
`benchmark-PV-LIO-to-HDMapping/` exist and no build failures are listed.

## Step 3. Run the algorithms

```shell
cd ~/hdmapping-benchmark/data
~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/run_benchmark_step3/run_benchmark_step3.sh \
    keble-college-02.bag keble-college-02-ros2 .
```

**Check:** `fast-lio/output_hdmapping-fast-lio/session.json` and
`pv-lio/output_hdmapping-pv-lio/session.json` exist in the data folder.

## Steps 4-6. Trajectories, APE/RPE and overlap

```shell
cd ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration
./conversion_tum_step4/run_tum_step4.sh
./evo_step5/tum-to-latex_step5.sh
python3 overlap_step6/overlap.py
```

**Check:** `tum/` has `ape_table_github.md`, `rpe_table_github.md`,
`overlap_results.md` and the plots `trajectories_xy_*.png`.

## Steps 7-8. Point-cloud registration and evaluation

```shell
cd ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration
./registration_step7/run_registration_step7.sh
./point_cloud_evaluation_step8/run_evaluation_step8.sh --timeout 900
```

**Check:** `step7_registration/registration_summary.csv` shows `registered` and
`step8_evaluation/evaluation_summary.md` shows `evaluated` with the metrics.

## Everything at once

```shell
unset ONLY_ALGOS
cd ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration
./start_benchmark.sh                     # all algorithms
./start_benchmark.sh fast-lio pv-lio     # a subset
```

Step 1 is skipped when its outputs exist. **Steps 7 and 8 replace existing
results**; add `--no-force` to keep them. For another core sequence (only those
have ground truth), move the previous results out of the data folder and run
`OXFORD_SPIRES_SEQUENCE=<sequence> ./start_benchmark.sh`.

**Do not use `clean.sh` on this branch**: it is written for the Bunker layout
and stops because `data/reg-1.bag` is missing.

# Options

| Option | Where | Default |
|---|---|---|
| `algo ...` / `ONLY_ALGOS` | `start_benchmark.sh` / Steps 2, 3, 4, 7, 8 | all |
| `OXFORD_SPIRES_SEQUENCE` | `start_benchmark.sh`, Step 1 | `2024-03-12-keble-college-02` |
| `OXFORD_SPIRES_DOWNLOAD_DIR` | `start_benchmark.sh`, Step 1 | `data/download` |
| `ALGO_BRANCH` | `start_benchmark.sh` | `hdmapping-benchmark-canonical` |
| `--bucket-size M` | Step 7 | `0.05` |
| `--voxel-size M` (`0` = off) | Step 8 | `0.05` |
| `--threshold M` | Step 8 precision/recall | `0.05` |
| `--jobs N` | Step 8 parallel evaluations | `1` |
| `--timeout S` / `STEP8_TIMEOUT` | Step 8 per map | `0` (`900` in `start_benchmark.sh`) |
| `--no-force` | Steps 7, 8: keep existing results | off |
| `--merge-only` | Step 8: rebuild summaries only | off |

`--bucket-size`, `--voxel-size`, `--threshold`, `--jobs` and `--no-force` also work
with `start_benchmark.sh`. `start_benchmark.sh` and the Step 2, 3, 4, 7 and 8
scripts print their options with `--help`.

# Oxford Spires details

## Step 1 in detail

The scripts are in `prepare_data_step1/oxford_spires/`, and `prepare.sh` is the only one to run. It builds the
two Docker images if they are missing (`build_images.sh`), downloads what is not there yet (`download.sh`), then
converts:

```bash
prepare_data_step1/oxford_spires/prepare.sh                                  # all defaults, as start_benchmark.sh
prepare_data_step1/oxford_spires/prepare.sh 2024-03-12-keble-college-02    # one sequence
```

Every argument is optional: `[sequence] [download_dir] [data_dir] [name]`. The defaults are those of
`start_benchmark.sh`, and its environment variables override them.

- `hdmapping-tools`: HDMapping's ROS-free converters `bag_to_laz`, `laz_to_bag`, `laz_to_mcap` and
  `mcap_to_laz`, from HDMapping branch `canonical-bag`. Set `HDMAPPING_SRC=<checkout>` when building to use a
  local checkout instead.
- `oxford-spires-tools`: `oxford_spires.py` and `rosbags-convert`.

`prepare.sh` writes, for `<name>` = the sequence without its date:

| Output                               | How                                                                                                                                                                                                                   |
|--------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------|
| `<name>-hdmapping/`                  | `bag_to_laz` of the raw bag(s). The IMU is rotated into the lidar frame (from `cam-lidar-imu.yaml`) and converted to g. The ring is kept as the LAS extra-bytes attribute `ring`. This is the input of HDMapping-LIO. |
| `<name>.bag`                         | `laz_to_bag --lidar-type canonical --msg_hz 10`: the canonical ROS1 bag                                                                                                                                               |
| `<name>-ros2/`                       | the same, as a ROS2 sqlite3 bag (`rosbags-convert`; the Humble images have no MCAP plugin)                                                                                                                            |
| `<name>.mcap`                        | the same as MCAP, only with `WRITE_MCAP=1`                                                                                                                                                                            |
| `ground_truth.tum`                   | `gt-tum.txt` (base frame, ICP to TLS) moved to the lidar frame; step 4 uses it                                                                                                                                        |
| `HDMappingGroundTruth/lio_result_0/` | ground-truth session for steps 4, 7 and 8: raw scans deskewed with the ground truth, in 5 s chunks                                                                                                                    |
| `TLS-FARO-Focus/map_gt_0.01.laz`     | step 8 reference: the site's TLS map cropped to the walk plus 20 m                                                                                                                                                    |

## Canonical bag

| Topic | Type | Content |
|---|---|---|
| `/lidar/pointcloud` | `sensor_msgs/PointCloud2` | One message per 100 ms, `frame_id: lidar`. Fields: `x y z intensity` (float32), `ring` (uint16, the laser 0–63), `time` (float32 s), `t` (uint32 ns). |
| `/lidar/imu` | `sensor_msgs/Imu` | `frame_id: lidar`. Rotated into the lidar frame, rad/s and m/s². |

- `time` and `t` are relative to `header.stamp`, which is the first point.
- Points are sorted by time, ties by ring.
- The layout matches the Velodyne point type of FAST-LIO (`lidar_type: 2`, `timestamp_unit: 0`), LIO-SAM
  (`sensor: velodyne`) and their derivatives. PCL matches fields by name *and* type, so use the Velodyne
  mode, not an Ouster one (`ring` as uint8).
- **Known issue, IMU lever arm:** the IMU is rotated into the lidar frame, but its accelerations are not
  transferred to the lidar origin. The missing term is `α × r + ω × (ω × r)` for the 8.6 cm lever arm: about
  0.09 m/s² at 1 rad/s, and about 0.4 m/s² in a 5 rad/s² turn. In the bag, the lidar–IMU extrinsic is identity
  (rotation and translation), so configs must say identity too.
- Hesai QT64 values for configs:
  - 64 rings, vertical field of view −52.5° to +52.1°, unevenly spaced;
  - up to about 1200 points per ring per sweep;
  - range 0.13–60 m;
  - IMU noise in `calibration/imu.yaml`.

## Adding an algorithm

Do it one algorithm at a time:

1. In `benchmark-<algo>-to-HDMapping`, create a branch `hdmapping-benchmark-canonical`. It is the same for every
   dataset converted to the canonical bag; step 2 checks it out (`ALGO_BRANCH` overrides the name).
2. Point the run script at `/lidar/pointcloud` and `/lidar/imu`.
3. Start from the algorithm's own spinning-lidar (Velodyne) config, and change only the sensor description:
   rings, time unit, ranges, field of view and IMU noise.
4. In `algorithms.conf` on this branch, set the algorithm's input to `canonical` (ROS1 bag) or
   `canonical-ros2` (ROS2 bag). HDMapping-LIO's input, `hdmapping` (the session), is already produced
   here and is the same for every dataset, so step 2 checks out that repo's `Bunker-DVI-Dataset-reg-1` branch
   (`BRANCH_OVERRIDE` in `clone_github_repositories_step2.sh`) until it has a `hdmapping-benchmark-canonical` branch.
5. Run `./start_benchmark.sh <algo>`.

Step 2 skips repos without that branch on GitHub, and step 3 skips algorithms whose input is still a
Livox one (`raw`, `pc`, `ros2`, `ros2-lidar`). Converted so far: fast-lio, lio-sam, kiss-icp, faster-lio, point-lio, ig-lio, pv-lio, r-voxelmap, dlio, dlo, ct-icp, lio-ekf, lego-loam, form, nv-liom, se3-lio, dalislam, voxelslam, log-lio2, sr-lio, floam, map-lio, super-lio, i2ekf-lo, voxel-map, slict, c3p-voxelmap, mm-lins, bievr-lio, d-lio, ellipselio, genz-icp, glim, lidar_odometry_ros_wrapper, mola, superOdom, pin-slam, resple, rko-lio.

**Exception, code patches:** where a config cannot describe the sensor, the branch patches the algorithm's code
in its Dockerfile, with a guard that fails the build if the patched line changes upstream. So far:
- **R-VoxelMap:** its Velodyne-with-time mode (`lidar_type: 5`) converts `time` to ms with a hard-coded `1e-3`, i.e. it assumes
  µs. Patched to `1e3` for the canonical seconds; without it deskew is off.
- **R-VoxelMap:** it stamps odometry and clouds with `ros::Time::now()`, the replay clock at publish time, 10–20 ms behind the
  scan. Patched to `lidar_end_time`, which its own TUM output uses. Without it evo pairs only 913 of 2996 poses
  with the ground truth. The Livox route has the same problem.
- **DLIO** keeps `t`, `time` and `timestamp` in one union, and PCL copies fields in offset order, so with the
  canonical `time` + `t` the union holds `t`; but its sensor detection stops at `time` (VELODYNE) and reads the
  ns bits as float seconds (~1e-37): deskew silently off. Patched to pick OUSTER (`t`) whenever `t` is present.
- **CT-ICP** publishes the pose at the end of the scan with the cloud's header stamp, the first point's time, so
  every pose is one sweep (0.1 s) early. Patched to stamp the odometry at the scan end (header stamp + the scan's
  point-time span). On keble-college-02 the unpatched run scored APE 0.131 m; shifting that trajectory by +0.1 s
  gives 0.091 m.
- **Voxel-SLAM** stamps its pose (TF `camera_init` -> `aft_mapped`) and `/map_scan` with `ros::Time::now()`,
  so consecutive stamps were 90-111 ms apart and evo paired only 2544 of 2995 poses. Patched to the state's time
  `x_curr.t` (scan end): 2980 poses, APE 0.035 m (unchanged), RPE 0.0063 -> 0.0034 m.
- **F-LOAM** ignores the `ring` field and derives the scan ID from the elevation angle with fixed Velodyne tables;
  the HDL-64 one (−24.3 to +2°) keeps only ~20 of the QT64's rings. Patched to take the scan ID from `ring` when the
  cloud has one.
- **MAP-LIO** never initialises `bool lidar_pushed`. With a garbage value its sync never loads the first scan, so
  it skips every scan and publishes nothing; whether it happens depends on memory contents. Patched to `false`, as
  in FAST-LIO. A bug fix, not a sensor description. The Livox route's empty MAP-LIO result is probably the same bug
  (not checked).
- **C3P-VoxelMap:** same `time * 1e-3` (µs) assumption as R-VoxelMap in its VELO32 handler (`lidar_type: 5`).
  Patched to `1e3`.

## Known issues

- **IMU lever arm:** see "Canonical bag". The accelerations are not transferred to the lidar origin.
- **Faster-LIO is worse on the canonical bag than on the Livox route** (keble-college-02: APE 0.103 m and map
  F-score 0.367, against 0.064 m and 0.552). Its canonical config is its upstream `velodyne.yaml` with only the
  sensor description changed, and everything else in that file was tuned for NCLT. A suspect was
  `extrinsic_est_en: true` (online IMU–lidar estimation), which is off in its `avia.yaml` and in FAST-LIO's
  `velodyne.yaml`. But PV-LIO's upstream `velodyne.yaml` has it on too and scores APE 0.043 m on the canonical
  bag, so that setting alone does not explain it; the cause is open. It is left as is by the
  sensor-description-only rule. The alternative, a written rule to turn off online extrinsic estimation for every
  algorithm when the bag's extrinsic is exact (as it is here), was considered and not taken.
- **Point-LIO is worse on the canonical bag than on the Livox route** (keble-college-02: APE 0.189 m and map
  F-score 0.359, against 0.099 m and 0.407), while its RPE is better (0.0086 m against 0.0166 m). Its config is
  upstream `velody16.yaml` with only the sensor description changed. Cause not identified; candidates are the
  uncorrected IMU lever arm (its IMU-as-output model leans on raw accelerations) and `point_filter_num 4` on 64
  rings.
- **DLO's map is keyframes only** (keble-college-02: map F-score 0.053, recall 0.03, the same as on the Livox
  route). Its run script records the keyframe clouds, which upstream spaces 5 m apart (`threshD`), not every
  scan. This predates the canonical bag. Its trajectory also covers only 278 s of the sequence: it starts 5 s
  late (IMU calibration) and ends 17 s early (not investigated; probably processing lag). DLO does not deskew.
- **LIO-EKF drifts horizontally** (keble-college-02: APE 1.539 m, of which 1.53 m in xy and 0.16 m in z,
  growing to 3.8 m at the end), while its RPE is 0.050 m. Its config is upstream `m2dgr.yaml` (a ground robot:
  1 m voxels, one ICP iteration, IMU noise of M2DGR's handsfree IMU) with only the sensor description changed.
  Its upstream `newerCollege.yaml` (handheld Ouster) was not tried: choosing a config by its score is tuning.
  The Livox route gave no LIO-EKF result.
- **LIO-EKF's map is its local map** (map F-score 0.019, recall 0.012): the run script records `/local_map`, the
  downsampled voxel map, not every scan. This predates the canonical bag.
- **LeGO-LOAM's RPE is not comparable** with the other methods': its mapping (and so its odometry output) runs
  every 0.3 s (upstream `mappingProcessInterval`), so its poses come at ~2.5 Hz and RPE is taken over ~0.4 s
  steps instead of 0.1 s (keble-college-02: RPE 0.586 m, 744 matched poses). APE (0.179 m) and the map
  (F-score 0.285) are comparable.
- **NV-LIOM's RPE is not comparable** either, the other way round: its odometry is the 400 Hz IMU odometry,
  so evo pairs consecutive poses ~40 ms apart (keble-college-02: RPE 0.0062 m, 7607 matched poses). APE (0.147 m)
  and the map (F-score 0.377) are comparable. Its range image has evenly spaced rows (64 over 106.5 deg), so a few
  of the QT64's denser rings near the horizon (1.46 deg apart) share a row; NV-LIOM keeps the nearest point.
- **SE3-LIO's map scores low** (keble-college-02: map F-score 0.226, against APE 0.049 m; Livox route 0.261): the
  run script records `/local/cloud_registered_body`, probably the scan after SE3-LIO's 1 m downsampling (not
  checked). This predates the canonical bag.
- **LOG-LIO2 runs without its normal model** (keble-college-02: APE 0.033 m, RPE 0.0022 m, map F-score 0.573;
  Livox route 0.224 / 0.108 / 0.151): `compute_normal` is off, because the ring-based normals need a ring angle
  table LOG-LIO2 has only for its own lidars. The score is plain point-to-plane LIO, not the full method.
- **SR-LIO** (keble-college-02: APE 0.046 m, RPE 0.0031 m, map F-score 0.076; Livox route 0.040 / 0.012 / 0.138):
  it publishes a pose per half-sweep (20 Hz), so its RPE is over 50 ms steps. The map scores low (recall 0.042)
  probably because the run script records `/cloud_global_map`, only the points each sweep adds to the voxel map (not
  checked). This predates the canonical bag.
- **F-LOAM diverges** (keble-college-02: APE 5.75 m, RPE 0.085 m; Livox route 15.6 / 1.78): about 2-3 m for the
  first ~250 s, then 22 m at the end; the map evaluation hits step 8's 900 s limit. F-LOAM is lidar-only with no
  deskew. Its ring patch takes the scan ID from the cloud's `ring` field instead of the HDL-64 elevation table.
- **I2EKF-LO diverges** (keble-college-02: APE 20.97 m, RPE 0.133 m; Livox route 15.67 / 0.099 / F 0.029):
  within ~0.25 m for the first ~45 s, then it drifts (~13 m at 150 s, ~75 m at the end); the map evaluation hits
  step 8's 900 s limit. I2EKF-LO is lidar-only; config-only conversion, no code patch.
- **VoxelMap diverges** (keble-college-02: APE 22.17 m, RPE 0.339 m; Livox route 17.9 / 0.750, map failed):
  ~1 m at 45-60 s, 13 m at 200 s, >60 m near the end; the map evaluation hits step 8's 900 s limit. Its upstream
  spinning-lidar config (KITTI) is lidar-only and reads no per-point time, so scans are not deskewed. Config-only:
  lidar_type 3 (the velodyne handler without its HDL-64 elevation window), calib_laser false.
- **C3P-VoxelMap runs with its IMU on**, beyond the sensor description (keble-college-02: APE 0.059 m, RPE
  0.037 m, map F-score 0.388; Livox route 24.7 / 1.26 / 0.005): its upstream spinning-lidar config (KITTI) is
  lidar-only, and like that it diverged (APE 22.3 m, F 0.009). With `imu_en: true` (identity extrinsic, default
  noise scales) it propagates and deskews with the IMU. The high RPE is probably its pose stamps,
  `ros::Time::now()` at publish time (not checked).
- **D-LIO diverges** (keble-college-02: APE 28.4 m, RPE 1.14 m; Livox route: no trajectory): with its own
  Newer College parameters (full-resolution cloud, up to 500 solver iterations) a scan takes ~0.5 s, so it
  publishes at ~2 Hz (1134 poses) and in real-time playback skips most scans; the map evaluation hits step 8's
  900 s limit. Config-only (run script parameters).
- **GenZ-ICP jumps** (keble-college-02: APE 4.01 m, RPE 0.392 m, map F-score 0.030; Livox route 16.4 / 3.32, map
  timed out): within 0.15 m for the first 60 s, then a ~8 m jump between 60 and 90 s that stays until ~200 s. It
  runs at ~5.5 Hz in real-time playback, and is lidar-only without deskew (as upstream). Config-only.
- **ROS2 reruns after a crash:** step 3 does not clear `<data>/<algo>/`, and `ros2 bag record` refuses an existing
  `recorded-*` folder, so a rerun after an aborted run records nothing. Remove the stale folder first.
- **MOLA's APE is worse than on the Livox route** (keble-college-02: APE 0.273 m vs 0.091 m; RPE 0.059 vs 0.336 m;
  F-score 0.330 vs 0.254): with the first 20 s aligned it drifts to ~0.9 m at 120-200 s and returns at the end.
  Only the topics changed; not investigated.
- **SuperOdom is worse than on the Livox route** (keble-college-02: APE 0.202 m vs 0.051 m, F-score 0.297 vs
  0.538): with the first 20 s aligned it drifts to ~5.5 m at 120 s and returns at the end. Velodyne input (its own
  vlp_16 config, 64 lines, identity extrinsic); not investigated.
- **RESPLE diverges** (keble-college-02: APE 11.7 m, RPE 1.28 m; Livox route 4.8 / 20.3, map timed out): within
  0.03-0.06 m for the first 120 s, then it drifts (3.5 m at 200 s, 40 m at the end); the map evaluation hits
  step 8's 900 s limit. Lidar-only, its own Ouster config; config-only.
- **rko-lio stops after 125 s** (keble-college-02: 1229 poses; over them APE 0.065 m, RPE 0.060 m, F-score 0.284;
  Livox route: no trajectory): it rejects a scan more than 1 s after the last accepted one
  (`rko_lio/core/lio.cpp:465`) and never resets that reference time, so after one late scan in real-time
  playback it drops every later scan. Reproduced in a second run. Fix options: a guarded patch resetting the
  reference on such a gap, or slower playback.

# More info
Our paper about benchmark
- https://www.sciencedirect.com/science/article/pii/S2352711026003146

To cite benchmark suite please use as follows:
```
@article{BEDKOWSKI2026102822,
title = {MapsHD: A benchmark suite for LiDAR odometry frameworks},
journal = {SoftwareX},
volume = {35},
pages = {102822},
year = {2026},
issn = {2352-7110},
doi = {https://doi.org/10.1016/j.softx.2026.102822},
url = {https://www.sciencedirect.com/science/article/pii/S2352711026003146},
author = {Janusz Bȩdkowski and Michał Pełka and Karol Majek and Marcin Matecki and Adrian Radulescu and Charles Hamesse and Ethan Decleyn and Przemysław Lekston and Tomasz Owerko and Przemysław Kuras and Michał Ciszewski and Jakub Kolecki and Karolina Tomaszkiewicz and Łukasz Ambroziński and Joanna Koszyk and Bartosz Hyla and Karolina Pargieła and Anna Malczewska and Tomasz Lipecki and Artur Adamek and Bartosz Mitka and Klapa Przemysław and Pelagia Gawronek and Martin Mokros and Jozef Výboštok and Juliána Chudá and Michal Skladan and Carlos Cabo and Kim André Anstensen and Craciun Daniel-Marian and Antun Jakopec and Michal Wlasiuk and Kornel Mrozowski and Maksymilian Kulicki and Krzysztof Stereńczak and Oskar Bartosz and Jakub Markiewicz and Sławomir Łapiński and Adam Kostrzewa and Mariana Campos and Machi Zawidzki and Jacek Szklarski and Rami Faraj and Loris Redovniković and Jurica Jagetić and Samer Karam and Răzvan Dumbravă and Milosz Mielcarek and Grzegorz Krok and Michal Laszkowski and Jaroslaw Wajs and Jakub Chudziński},
keywords = {LiDAR odometry, LiDAR-inertial odometry, Benchmarking},
abstract = {This paper describes a software toolbox for LiDAR (Light Detection and Ranging) and LiDAR-Inertial Odometry qualitative and quantitative evaluation. We provide software as https://github.com/MapsHD organization with all necessary information at https://github.com/MapsHD/HDMapping. Our software contributions are a) ground truth data processing tool, b) dockerized state-of-the-art LO and LIO algorithms, c) multi-session data registration to common coordinate system, d) Absolute Pose Error (APE) and Relative Pose Error (RPE) metrics, e) import/export tools for easier 3D data handling and visualizing, e.g., in Cloud Compare software. This software is compatible with ROS1 (Robot Operating System) and ROS2 data formats. We show an example benchmark of LeGO-LOAM, LIO-SAM, FAST-LIO, DLO, VoxelMap, Faster-LIO, KISS-ICP, CT-ICP, SLICT, DLIO, GLIM, iG-LIO, LIO-EKF, I2EKF-LO, GenZ-ICP, RESPLE, odometry_ros_wrapper, Point-LIO, and LOAM-Livox algorithms. For all experiments we provide movies. The contribution of the paper is software-oriented LO/LIO algorithm benchmark suite. The novelty lies in the integration of multiple benchmarking steps into a unified framework, thus overall effort needed for qualitative and quantitative evaluation is reduced.}
}
```
