#!/bin/bash

if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: $0 [branch_name]"
    echo
    echo "Clones all ROS1 and ROS2 HDMapping benchmark repositories from MapsHD"
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

read -p "Enter the branch name to checkout for all repositories: " BRANCH_NAME

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
"benchmark-LIO-EKF-to-HDMapping"
"benchmark-LeGO-LOAM-to-HDMapping"
"benchmark-Point-LIO-to-HDMapping"
"benchmark-VoxelMap-to-HDMapping"
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
  "lio-ekf"
  "lego-loam"
  "point-lio"
  "voxel-map"
)

ROS2_ALGOS=(
  "superOdom"
  "kiss-icp"
  "genz-icp"
  "glim"
  "lidar_odometry_ros_wrapper"
)

for i in "${!ROS1_ALGOS[@]}"; do
  algo="${ROS1_ALGOS[$i]}"
  dir="${ROS1_REPOS[$i]}"
  cd "$CLONE_DIR/$dir" || continue
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

echo "=== All Docker images built ==="