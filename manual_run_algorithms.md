# Manual per-algorithm run commands

Equivalent of `run_benchmark_step3/run_benchmark_step3.sh`, expanded so each algorithm
can be run individually. Assumes step 1 (`prepare_data_step1`) and step 2
(`clone_github_repositories_step2`) have already completed, i.e. `reg-1.bag`,
`reg-1.bag-pc.bag`, `reg-1-ros2`, and `reg-1-ros2-lidar` exist under `$DATA_DIR`, and
each `benchmark-*-to-HDMapping` repo has been cloned with its `docker_session_run-*.sh`
scripts.

## Setup

```bash
export CLONE_DIR=~/hdmapping-benchmark
export DATA_DIR=~/hdmapping-benchmark/data
export OUTPUT_DIR=$DATA_DIR   # or wherever you want results written
```

## ROS1 algorithms

### Use `reg-1.bag-pc.bag` (converted point-cloud bag)

```bash
cd $CLONE_DIR/benchmark-DLIO-to-HDMapping        && ./docker_session_run-ros1-dlio.sh        "$DATA_DIR/reg-1.bag-pc.bag" "$OUTPUT_DIR/dlio"
cd $CLONE_DIR/benchmark-DLO-to-HDMapping         && ./docker_session_run-ros1-dlo.sh         "$DATA_DIR/reg-1.bag-pc.bag" "$OUTPUT_DIR/dlo"
cd $CLONE_DIR/benchmark-LOAM-Livox-to-HDMapping  && ./docker_session_run-ros1-loam.sh        "$DATA_DIR/reg-1.bag-pc.bag" "$OUTPUT_DIR/loam"
cd $CLONE_DIR/benchmark-CT-ICP-to-HDMapping      && ./docker_session_run-ros1-ct-icp.sh      "$DATA_DIR/reg-1.bag-pc.bag" "$OUTPUT_DIR/ct-icp"
cd $CLONE_DIR/benchmark-LeGO-LOAM-to-HDMapping   && ./docker_session_run-ros1-lego-loam.sh   "$DATA_DIR/reg-1.bag-pc.bag" "$OUTPUT_DIR/lego-loam"
cd $CLONE_DIR/benchmark-FORM-to-HDMapping        && ./docker_session_run-ros1-form.sh        "$DATA_DIR/reg-1.bag-pc.bag" "$OUTPUT_DIR/form"
cd $CLONE_DIR/benchmark-NV-LIOM-to-HDMapping     && ./docker_session_run-ros1-nv-liom.sh     "$DATA_DIR/reg-1.bag-pc.bag" "$OUTPUT_DIR/nv-liom"
cd $CLONE_DIR/benchmark-SE3-LIO-to-HDMapping     && ./docker_session_run-ros1-se3-lio.sh     "$DATA_DIR/reg-1.bag-pc.bag" "$OUTPUT_DIR/se3-lio"
cd $CLONE_DIR/benchmark-Voxel-SLAM-to-HDMapping  && ./docker_session_run-ros1-voxelslam.sh   "$DATA_DIR/reg-1.bag-pc.bag" "$OUTPUT_DIR/voxelslam"
cd $CLONE_DIR/benchmark-DALI_SLAM-to-HDMapping   && ./docker_session_run-ros1-dalislam.sh    "$DATA_DIR/reg-1.bag-pc.bag" "$OUTPUT_DIR/dalislam"
cd $CLONE_DIR/benchmark-LOG-LIO2-to-HDMapping    && ./docker_session_run-ros1-log-lio2.sh    "$DATA_DIR/reg-1.bag-pc.bag" "$OUTPUT_DIR/log-lio2"
cd $CLONE_DIR/benchmark-LIO-EKF-to-HDMapping     && ./docker_session_run-ros1-lio-ekf.sh     "$DATA_DIR/reg-1.bag-pc.bag" "$OUTPUT_DIR/lio-ekf"
```

### Use `reg-1.bag` (raw bag)

```bash
cd $CLONE_DIR/benchmark-FAST-LIO-to-HDMapping     && ./docker_session_run-ros1-fast-lio.sh     "$DATA_DIR/reg-1.bag" "$OUTPUT_DIR/fast-lio"
cd $CLONE_DIR/benchmark-Super-LIO-to-HDMapping    && ./docker_session_run-ros1-super-lio.sh    "$DATA_DIR/reg-1.bag" "$OUTPUT_DIR/super-lio"
cd $CLONE_DIR/benchmark-Faster-LIO-to-HDMapping   && ./docker_session_run-ros1-faster-lio.sh   "$DATA_DIR/reg-1.bag" "$OUTPUT_DIR/faster-lio"
cd $CLONE_DIR/benchmark-iG-LIO-to-HDMapping       && ./docker_session_run-ros1-ig-lio.sh       "$DATA_DIR/reg-1.bag" "$OUTPUT_DIR/ig-lio"
cd $CLONE_DIR/benchmark-I2EKF-LO-to-HDMapping     && ./docker_session_run-ros1-i2ekf-lo.sh     "$DATA_DIR/reg-1.bag" "$OUTPUT_DIR/i2ekf-lo"
cd $CLONE_DIR/benchmark-Point-LIO-to-HDMapping    && ./docker_session_run-ros1-point-lio.sh    "$DATA_DIR/reg-1.bag" "$OUTPUT_DIR/point-lio"
cd $CLONE_DIR/benchmark-VoxelMap-to-HDMapping     && ./docker_session_run-ros1-voxel-map.sh    "$DATA_DIR/reg-1.bag" "$OUTPUT_DIR/voxel-map"
cd $CLONE_DIR/benchmark-SLICT-to-HDMapping        && ./docker_session_run-ros1-slict.sh        "$DATA_DIR/reg-1.bag" "$OUTPUT_DIR/slict"
cd $CLONE_DIR/benchmark-C3P-VoxelMap-to-HDMapping && ./docker_session_run-ros1-c3p-voxelmap.sh "$DATA_DIR/reg-1.bag" "$OUTPUT_DIR/c3p-voxelmap"
cd $CLONE_DIR/benchmark-MM-LINS-to-HDMapping      && ./docker_session_run-ros1-mm-lins.sh      "$DATA_DIR/reg-1.bag" "$OUTPUT_DIR/mm-lins"
```

## ROS2 algorithms

### Use `reg-1-ros2-lidar`

```bash
cd $CLONE_DIR/benchmark-SuperOdometry-to-HDMapping && ./docker_session_run-ros2-superOdom.sh "$DATA_DIR/reg-1-ros2-lidar" "$OUTPUT_DIR/superOdom"
```

### Use `reg-1-ros2`

```bash
cd $CLONE_DIR/benchmark-KISS-ICP-to-HDMapping                   && ./docker_session_run-ros2-kiss-icp.sh "$DATA_DIR/reg-1-ros2" "$OUTPUT_DIR/kiss-icp"
cd $CLONE_DIR/benchmark-GenZ-ICP-to-HDMapping                   && ./docker_session_run-ros2-genz-icp.sh "$DATA_DIR/reg-1-ros2" "$OUTPUT_DIR/genz-icp"
cd $CLONE_DIR/benchmark-lidar_odometry_ros_wrapper-to-HDMapping && ./docker_session_run-ros2-lidar_odometry_ros_wrapper.sh "$DATA_DIR/reg-1-ros2" "$OUTPUT_DIR/lidar_odometry_ros_wrapper"
cd $CLONE_DIR/benchmark-EllipseLIO-to-HDMapping                 && ./docker_session_run-ros2-ellipselio.sh "$DATA_DIR/reg-1-ros2" "$OUTPUT_DIR/ellipselio"
cd $CLONE_DIR/benchmark-D-LIO-to-HDMapping                      && ./docker_session_run-ros2-d-lio.sh "$DATA_DIR/reg-1-ros2" "$OUTPUT_DIR/d-lio"
cd $CLONE_DIR/benchmark-GLIM-to-HDMapping                       && ./docker_session_run-ros2-glim.sh "$DATA_DIR/reg-1-ros2" "$OUTPUT_DIR/glim"
cd $CLONE_DIR/benchmark-BIEVR-LIO-to-HDMapping                  && ./docker_session_run-ros2-bievr-lio.sh "$DATA_DIR/reg-1-ros2" "$OUTPUT_DIR/bievr-lio"
```

## Notes

- `cd $CLONE_DIR` back before running the next command (each block above assumes you start from `$CLONE_DIR`).
- Confirm the target script exists before running it manually:
  `ls $CLONE_DIR/<repo>/docker_session_run*`
- After running, continue with the remaining pipeline steps as needed:
  `conversion_tum_step4`, `evo_step5`, `overlap_step6`.
