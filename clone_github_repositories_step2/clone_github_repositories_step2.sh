#!/bin/bash

# Clones every ROS1/ROS2 HDMapping benchmark repo from MapsHD, pins it to the
# exact commit listed below, and builds its Docker image. Branch shown in
# each comment is informational only — the commit is what actually gets
# checked out.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLONE_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$CLONE_DIR" || exit

# =======================
# ROS1 repositories
# =======================

[ -d benchmark-Super-LIO-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-Super-LIO-to-HDMapping.git
cd benchmark-Super-LIO-to-HDMapping && git fetch && git checkout af8896a2b255d640ef467153b3b2d1ff07f1edb1 && git submodule update --init --recursive && docker build -t super-lio_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-DLIO-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-DLIO-to-HDMapping.git
cd benchmark-DLIO-to-HDMapping && git fetch && git checkout bfc704925fbd1e9fda00fc2cfce65af08ef765b8 && git submodule update --init --recursive && docker build -t dlio_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-DLO-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-DLO-to-HDMapping.git
cd benchmark-DLO-to-HDMapping && git fetch && git checkout 1ef6ce51fad8dc47c7f4098a13d3cf6333c9b9d6 && git submodule update --init --recursive && docker build -t dlo_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-FAST-LIO-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-FAST-LIO-to-HDMapping.git
cd benchmark-FAST-LIO-to-HDMapping && git fetch && git checkout aefa51dbbfc48cf27e7fb2d1b6abf63853adaad0 && git submodule update --init --recursive && docker build -t fast-lio_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-Faster-LIO-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-Faster-LIO-to-HDMapping.git
cd benchmark-Faster-LIO-to-HDMapping && git fetch && git checkout 43b2e0dd3ed89d6ee1381c5a0c034f8a2b14cc94 && git submodule update --init --recursive && docker build -t faster-lio_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-iG-LIO-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-iG-LIO-to-HDMapping.git
cd benchmark-iG-LIO-to-HDMapping && git fetch && git checkout 35c90367983974517507cd7543b363ac31c6aba7 && git submodule update --init --recursive && docker build -t ig-lio_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-I2EKF-LO-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-I2EKF-LO-to-HDMapping.git
cd benchmark-I2EKF-LO-to-HDMapping && git fetch && git checkout a6ed87e9221cc5ca65751c915ed4cfb85726cf47 && git submodule update --init --recursive && docker build -t i2ekf-lo_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-CT-ICP-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-CT-ICP-to-HDMapping.git
cd benchmark-CT-ICP-to-HDMapping && git fetch && git checkout 6b9e27f1b6e879878443bd9555b4f96360845dca && git submodule update --init --recursive && docker build -t ct-icp_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-LOAM-Livox-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-LOAM-Livox-to-HDMapping.git
cd benchmark-LOAM-Livox-to-HDMapping && git fetch && git checkout 90b75849222153baec9332703a73a524df627c68 && git submodule update --init --recursive && docker build -t loam_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-LIO-EKF-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-LIO-EKF-to-HDMapping.git
cd benchmark-LIO-EKF-to-HDMapping && git fetch && git checkout 2c2d8f4bf35c46cd0f376aa3e320d70e3e82dca8 && git submodule update --init --recursive && docker build -t lio-ekf_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-LeGO-LOAM-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-LeGO-LOAM-to-HDMapping.git
cd benchmark-LeGO-LOAM-to-HDMapping && git fetch && git checkout 8ae23ced4dfc7206a0f4c7d8ba838b021a2a4ba4 && git submodule update --init --recursive && docker build -t lego-loam_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-Point-LIO-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-Point-LIO-to-HDMapping.git
cd benchmark-Point-LIO-to-HDMapping && git fetch && git checkout 3528a917703abee78ab55d02d1726f1b310a6444 && git submodule update --init --recursive && docker build -t point-lio_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-VoxelMap-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-VoxelMap-to-HDMapping.git
cd benchmark-VoxelMap-to-HDMapping && git fetch && git checkout 3b4aea40a5ce2f18a1bda428c8a7baa6b5116b24 && git submodule update --init --recursive && docker build -t voxel-map_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-FORM-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-FORM-to-HDMapping.git
cd benchmark-FORM-to-HDMapping && git fetch && git checkout b5d3345d93d3563b6a993eb2c3419abc750ec27e && git submodule update --init --recursive && docker build -t form_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-C3P-VoxelMap-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-C3P-VoxelMap-to-HDMapping.git
cd benchmark-C3P-VoxelMap-to-HDMapping && git fetch && git checkout d372163961bc874118a40bc3c968772f865ffc03 && git submodule update --init --recursive && docker build -t c3p-voxelmap_noetic . # HUMANOID-LIO-DATASET
cd "$CLONE_DIR"

[ -d benchmark-SLICT-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-SLICT-to-HDMapping.git
cd benchmark-SLICT-to-HDMapping && git fetch && git checkout 56ead7c09a5560f82ac6ce9454abb9c6240c253c && git submodule update --init --recursive && docker build -t slict_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-NV-LIOM-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-NV-LIOM-to-HDMapping.git
cd benchmark-NV-LIOM-to-HDMapping && git fetch && git checkout b8b1fb4ef2a494104932622f1a0baaf08e24a300 && git submodule update --init --recursive && docker build -t nv-liom_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-SE3-LIO-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-SE3-LIO-to-HDMapping.git
cd benchmark-SE3-LIO-to-HDMapping && git fetch && git checkout e3bb43962865788c753a713fca86354b09f37612 && git submodule update --init --recursive && docker build -t se3-lio_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-DALI_SLAM-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-DALI_SLAM-to-HDMapping.git
cd benchmark-DALI_SLAM-to-HDMapping && git fetch && git checkout 115572a58312fb538c8da38dc84626dcd71a14a8 && git submodule update --init --recursive && docker build -t dalislam_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-Voxel-SLAM-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-Voxel-SLAM-to-HDMapping.git
cd benchmark-Voxel-SLAM-to-HDMapping && git fetch && git checkout 0d4f164236fe183d8745d5ebafb60ab4bd1c5b10 && git submodule update --init --recursive && docker build -t voxelslam_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-LOG-LIO2-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-LOG-LIO2-to-HDMapping.git
cd benchmark-LOG-LIO2-to-HDMapping && git fetch && git checkout e89d2a9acd05a1da7997e20df39e70b6a1469324 && git submodule update --init --recursive && docker build -t log-lio2_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-MM-LINS-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-MM-LINS-to-HDMapping.git
cd benchmark-MM-LINS-to-HDMapping && git fetch && git checkout 549d7a2838d01c3e24e0851115eabcee13ecdaaf && git submodule update --init --recursive && docker build -t mm-lins_noetic . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

# =======================
# ROS2 repositories
# =======================

[ -d benchmark-SuperOdometry-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-SuperOdometry-to-HDMapping.git
cd benchmark-SuperOdometry-to-HDMapping && git fetch && git checkout c5aa48bcbc290501d94ff85c6fd7418f4bf3cb9c && git submodule update --init --recursive && docker build -t superodom_humble . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-KISS-ICP-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-KISS-ICP-to-HDMapping.git
cd benchmark-KISS-ICP-to-HDMapping && git fetch && git checkout a54480113c0900f968c9ba7d6de5b40e888fb738 && git submodule update --init --recursive && docker build -t kiss-icp_humble . # HUMANOID-LIO-DATASET
cd "$CLONE_DIR"

[ -d benchmark-GenZ-ICP-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-GenZ-ICP-to-HDMapping.git
cd benchmark-GenZ-ICP-to-HDMapping && git fetch && git checkout 07366ef870f25f82c16c884c714deb126336688a && git submodule update --init --recursive && docker build -t genz-icp_humble . # HUMANOID-LIO-DATASET
cd "$CLONE_DIR"

[ -d benchmark-GLIM-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-GLIM-to-HDMapping.git
cd benchmark-GLIM-to-HDMapping && git fetch && git checkout a83c866b9025bc560b8c7e0c49b3c4a8143df9f5 && git submodule update --init --recursive && docker build -t glim_humble . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-lidar_odometry_ros_wrapper-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-lidar_odometry_ros_wrapper-to-HDMapping.git
cd benchmark-lidar_odometry_ros_wrapper-to-HDMapping && git fetch && git checkout fa9499a3d3d42262f045e627081623d5f4c18e0f && git submodule update --init --recursive && docker build -t lidar_odometry_ros_wrapper_humble . # HUMANOID-LIO-DATASET
cd "$CLONE_DIR"

[ -d benchmark-mola_lidar_odometry-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-mola_lidar_odometry-to-HDMapping.git
cd benchmark-mola_lidar_odometry-to-HDMapping && git fetch && git checkout 728755e870103c32a8269dab664459f31ea7c96c && git submodule update --init --recursive && docker build -t mola_humble . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-RESPLE-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-RESPLE-to-HDMapping.git
cd benchmark-RESPLE-to-HDMapping && git fetch && git checkout db68a67597d3e7dfac3eeb72b09465e57f2a0584 && git submodule update --init --recursive && docker build -t resple_humble . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-EllipseLIO-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-EllipseLIO-to-HDMapping.git
cd benchmark-EllipseLIO-to-HDMapping && git fetch && git checkout c2973d7886082fbe3d84b3ef1f338769a2db04fb && git submodule update --init --recursive && docker build -t ellipselio_humble . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

[ -d benchmark-D-LIO-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-D-LIO-to-HDMapping.git
cd benchmark-D-LIO-to-HDMapping && git fetch && git checkout 49ae6862077c892369a0aac45522a8d808e533dc && git submodule update --init --recursive && docker build -t d-lio_humble . # HUMANOID-LIO-DATASET
cd "$CLONE_DIR"

[ -d benchmark-BIEVR-LIO-to-HDMapping ] || git clone --recursive https://github.com/MapsHD/benchmark-BIEVR-LIO-to-HDMapping.git
cd benchmark-BIEVR-LIO-to-HDMapping && git fetch && git checkout f4512fe8e1f107637c5df95540eb694abe76461b && git submodule update --init --recursive && docker build -t bievr-lio_humble . # Bunker-DVI-Dataset-reg-1
cd "$CLONE_DIR"

echo "=== All repositories cloned, pinned, and Docker images built ==="
