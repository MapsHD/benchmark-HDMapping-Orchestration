#!/bin/bash

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [branch_name]"
    echo
    echo "Clones all ROS1, ROS2 and non-ROS (standalone) HDMapping benchmark repositories from MapsHD"
    echo "and switches them to the specified branch."
    echo
    exit 0
fi

CLONE_DIR="$HOME/hdmapping-benchmark"

if [ ! -d "$CLONE_DIR" ]; then
    echo "Creating directory $CLONE_DIR..."
    mkdir -p "$CLONE_DIR"
else
    echo "Directory $CLONE_DIR already exists, skipping creation."
fi

cd "$CLONE_DIR" || exit

if [ -n "$1" ]; then
    BRANCH_NAME="$1"
    echo "Using branch from CLI: $BRANCH_NAME"
else
    read -p "Enter the branch name to checkout for all repositories: " BRANCH_NAME
fi

# =======================
# ROS1 repositories
# =======================
ROS1_REPOS=(
"benchmark-Super-LIO-to-HDMapping"
"benchmark-DLIO-to-HDMapping"
"benchmark-DLO-to-HDMapping"
"benchmark-FAST-LIO-to-HDMapping"
"benchmark-Faster-LIO-to-HDMapping"
"benchmark-iG-LIO-to-HDMapping"
"benchmark-I2EKF-LO-to-HDMapping"
"benchmark-CT-ICP-to-HDMapping"
"benchmark-LOAM-Livox-to-HDMapping"
"benchmark-LIO-EKF-to-HDMapping"
"benchmark-LeGO-LOAM-to-HDMapping"
"benchmark-Point-LIO-to-HDMapping"
"benchmark-VoxelMap-to-HDMapping"
"benchmark-FORM-to-HDMapping"
"benchmark-C3P-VoxelMap-to-HDMapping"
"benchmark-SLICT-to-HDMapping"
"benchmark-NV-LIOM-to-HDMapping"
"benchmark-SE3-LIO-to-HDMapping"
"benchmark-DALI_SLAM-to-HDMapping"
"benchmark-Voxel-SLAM-to-HDMapping"
"benchmark-LOG-LIO2-to-HDMapping"
"benchmark-MM-LINS-to-HDMapping"
"benchmark-SR-LIO-to-HDMapping"
"benchmark-R-VoxelMap-to-HDMapping"
"benchmark-PV-LIO-to-HDMapping"
"benchmark-HDMapping_LIO-to-HDMapping"
)

# =======================
# ROS2 repositories
# =======================
ROS2_REPOS=(
"benchmark-SuperOdometry-to-HDMapping"
"benchmark-KISS-ICP-to-HDMapping"
"benchmark-GenZ-ICP-to-HDMapping"
"benchmark-GLIM-to-HDMapping"
"benchmark-lidar_odometry_ros_wrapper-to-HDMapping"
"benchmark-mola_lidar_odometry-to-HDMapping"
"benchmark-RESPLE-to-HDMapping"
"benchmark-EllipseLIO-to-HDMapping"
"benchmark-D-LIO-to-HDMapping"
"benchmark-BIEVR-LIO-to-HDMapping"
"benchmark-rko_lio-to-HDMapping"
)

# =======================
# Non-ROS repositories
# (standalone/offline algorithms: no roscore, no rosbag record — the algorithm
#  reads the bag file directly)
# =======================
NON_ROS_REPOS=(
"benchmark-PIN-SLAM-to-HDMapping"
)

clone_repo() {
  local repo_name="$1"  
  local branch_name="$2"    
  local url="https://github.com/MapsHD/${repo_name}.git"
  local dir_name=$(basename "$repo_name")

  if [ ! -d "$dir_name" ]; then
    echo "Cloning $dir_name..."
    git clone --recursive "$url"
  else
    echo "$dir_name already exists, skipping clone."
  fi

  cd "$dir_name" || return
  echo "Switching $dir_name to branch $branch_name..."
  git fetch
  git checkout "$branch_name"
  # Fast-forward an existing clone to the remote branch — fetch+checkout alone
  # leaves a stale local branch ("Your branch is behind ..."). --ff-only never
  # rewrites local commits; it only advances to what origin already has.
  git pull --ff-only origin "$branch_name" || \
    echo "WARNING: $dir_name could not be fast-forwarded (local changes?) — using local state"
  # Pulled commits may bump submodule pointers; materialize them.
  git submodule update --init --recursive
  cd ..
}

echo "=== Cloning ROS1 repositories ==="
for repo in "${ROS1_REPOS[@]}"; do
  clone_repo "$repo" "$BRANCH_NAME"
done                 

echo "=== Cloning ROS2 repositories ==="
for repo in "${ROS2_REPOS[@]}"; do
  clone_repo "$repo" "$BRANCH_NAME"
done

echo "=== Cloning non-ROS repositories ==="
for repo in "${NON_ROS_REPOS[@]}"; do
  clone_repo "$repo" "$BRANCH_NAME"
done

echo "=== All repositories have been cloned and switched to branch '$BRANCH_NAME' ==="

ROS1_ALGOS=(
  "super-lio"
  "dlio"
  "dlo"
  "fast-lio"
  "faster-lio"
  "ig-lio"
  "i2ekf-lo"
  "ct-icp"
  "loam"
  "lio-ekf"
  "lego-loam"
  "point-lio"
  "voxel-map"
  "form"
  "c3p-voxelmap"
  "slict"
  "nv-liom"
  "se3-lio"
  "dalislam"
  "voxelslam"
  "log-lio2"
  "mm-lins"
  "sr-lio"
  "r-voxelmap"
  "pv-lio"
  "hdmapping-lio"
)

ROS2_ALGOS=(
  "superodom"
  "kiss-icp"
  "genz-icp"
  "glim"
  "lidar_odometry_ros_wrapper"
  "mola"
  "resple"
  "ellipselio"
  "d-lio"
  "bievr-lio"
  "rko-lio"
)

NON_ROS_ALGOS=(
  "pin-slam"
)

for i in "${!ROS1_ALGOS[@]}"; do
  algo="${ROS1_ALGOS[$i]}"
  dir="${ROS1_REPOS[$i]}"
  cd "$CLONE_DIR/$dir" || continue
  # Some repos (e.g. benchmark-HDMapping_LIO-to-HDMapping) ship only a README
  # describing a manual procedure — nothing to build for those.
  if [ ! -f Dockerfile ]; then
    echo "Skipping Docker build for $algo: $dir has no Dockerfile (manual procedure, see its README)."
    cd "$CLONE_DIR" || exit
    continue
  fi
  echo "Building Docker for $algo (ROS1 Noetic)..."
  docker build -t "${algo}_noetic" .
  cd "$CLONE_DIR" || exit
done

for i in "${!ROS2_ALGOS[@]}"; do
  algo="${ROS2_ALGOS[$i]}"
  dir="${ROS2_REPOS[$i]}"
  cd "$CLONE_DIR/$dir" || continue
  echo "Building Docker for $algo (ROS2 Humble)..."
  docker build -t "${algo}_humble" .
  cd "$CLONE_DIR" || exit
done

# Non-ROS images carry no ROS distro; the tag suffix is "_standalone".
# A GPU is recommended but not required: e.g. PIN-SLAM uses an NVIDIA GPU when
# the NVIDIA Container Toolkit is present and falls back to CPU otherwise.
for i in "${!NON_ROS_ALGOS[@]}"; do
  algo="${NON_ROS_ALGOS[$i]}"
  dir="${NON_ROS_REPOS[$i]}"
  cd "$CLONE_DIR/$dir" || continue
  echo "Building Docker for $algo (standalone, no ROS)..."
  docker build -t "${algo}_standalone" .
  cd "$CLONE_DIR" || exit
done

echo "=== All Docker images built ==="