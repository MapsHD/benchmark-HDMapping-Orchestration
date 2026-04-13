#!/bin/bash
set -e

DATASET_HOST_PATH="$1"          
BAG_OUTPUT_HOST="$2"             
ROS_VERSION="$3"                 # hdmapping-to-ros1| ros1-to-hdmapping | hdmapping-to-ros2| ros2-to-hdmapping | ros1-to-ros2

if [[ -z "$DATASET_HOST_PATH" || -z "$BAG_OUTPUT_HOST" || -z "$ROS_VERSION" ]]; then
  echo "Usage: $0 <dataset_path> <output_path> <hdmapping-to-ros1 | ros1-to-hdmapping | hdmapping-to-ros2 | ros2-to-hdmapping | ros1-to-ros2>"
  exit 1
fi

POINTCLOUD_TOPIC_ROS1="/livox/lidar"
IMU_TOPIC_ROS1="/livox/imu"

POINTCLOUD_TOPIC_ROS2="/livox/pointcloud"
IMU_TOPIC_ROS2="/livox/imu"

DATASET_HOST_PATH=$(realpath "$DATASET_HOST_PATH")
BAG_OUTPUT_HOST=$(realpath "$BAG_OUTPUT_HOST")

DATASET_DIR_HOST=$(dirname "$DATASET_HOST_PATH")
DATASET_FILE=$(basename "$DATASET_HOST_PATH")  
DATASET_FOLDER=$(basename "$DATASET_HOST_PATH")     

DATASET_CONTAINER_PATH=/mandeye_ws/dataset
BAG_OUTPUT_CONTAINER=/mandeye_ws/output

mkdir -p "$BAG_OUTPUT_HOST"
xhost +local:docker >/dev/null

IMAGE_NAME_ROS1="mandeye-ws_noetic"
IMAGE_NAME_ROS2="mandeye-ws_humble"

case "$ROS_VERSION" in
  ros1-to-hdmapping)
    echo "Running ROS1 → HDMapping conversion..."
    IMAGE_NAME="$IMAGE_NAME_ROS1"
    ROS_SETUP="source /opt/ros/noetic/setup.bash && source /mandeye_ws/devel/setup.bash"
    RUN_CMD="rosrun mandeye_to_rosbag1 rosbag_to_mandeye $DATASET_CONTAINER_PATH/$DATASET_FILE $BAG_OUTPUT_CONTAINER --pointcloud_topic $POINTCLOUD_TOPIC_ROS1 --imu_topic $IMU_TOPIC_ROS1"
    ;;

  hdmapping-to-ros1)
    echo "Running ROS1 → Bag conversion..."
    IMAGE_NAME="$IMAGE_NAME_ROS1"
    ROS_SETUP="source /opt/ros/noetic/setup.bash && source /mandeye_ws/devel/setup.bash"
    RUN_CMD="rosrun mandeye_to_rosbag1 mandeye_to_rosbag $DATASET_CONTAINER_PATH/$DATASET_FILE $BAG_OUTPUT_CONTAINER/$DATASET_FILE"
    ;;

  hdmapping-to-ros2)
    echo "Running ROS2 → Bag conversion..."
    IMAGE_NAME="$IMAGE_NAME_ROS2"
    ROS_SETUP="source /opt/ros/humble/setup.bash && source /mandeye_ws/install/setup.bash"
    RUN_CMD="ros2 run mandeye_to_rosbag2 mandeye_to_rosbag2_node $DATASET_CONTAINER_PATH/$DATASET_FOLDER $BAG_OUTPUT_CONTAINER/$DATASET_FOLDER-ros2/"
    ;;

  ros2-to-hdmapping)
    echo "Running ROS2 → HDMapping conversion..."
    IMAGE_NAME="$IMAGE_NAME_ROS2"
    ROS_SETUP="source /opt/ros/humble/setup.bash && source /mandeye_ws/install/setup.bash"
    RUN_CMD="ros2 run mandeye_to_rosbag2 rosbag2_to_mandeye_node $DATASET_CONTAINER_PATH/$DATASET_FILE $BAG_OUTPUT_CONTAINER/$DATASET_FOLDER --pointcloud_topic $POINTCLOUD_TOPIC_ROS2 --imu_topic $IMU_TOPIC_ROS2"
    ;;

ros1-to-ros2)
    echo "Running ROS1 → ROS2 conversion..."
    IMAGE_NAME="$IMAGE_NAME_ROS2"
    ROS_SETUP="source /opt/ros/humble/setup.bash && source /mandeye_ws/install/setup.bash"

    DATASET_NAME=$(basename "$DATASET_HOST_PATH" .bag)

    SRC_BAG="$DATASET_CONTAINER_PATH/${DATASET_NAME}.bag"
    DST_FOLDER="$BAG_OUTPUT_CONTAINER/${DATASET_NAME}-ros2-lidar"

    SRC_PC_BAG="$BAG_OUTPUT_CONTAINER/${DATASET_NAME}.bag-pc.bag"
    DST_PC_FOLDER="$BAG_OUTPUT_CONTAINER/${DATASET_NAME}-ros2"

    RUN_CMD="
    echo '[MAIN] converting...' &&
    rosbags-convert --src $SRC_BAG --dst $DST_FOLDER &&

    echo '[PC] converting...' &&
    if [ -f \"$SRC_PC_BAG\" ]; then
        rosbags-convert --src $SRC_PC_BAG --dst $DST_PC_FOLDER;
    fi
    "
    ;;
esac

docker run -it --rm \
  --network host \
  --user 1000:1000 \
  -v "$DATASET_DIR_HOST":"$DATASET_CONTAINER_PATH":ro \
  -v "$BAG_OUTPUT_HOST":"$BAG_OUTPUT_CONTAINER" \
  "$IMAGE_NAME" \
  /bin/bash -c "
    set -e &&
    $ROS_SETUP &&
    $RUN_CMD
  "

echo "Conversion finished successfully!"
