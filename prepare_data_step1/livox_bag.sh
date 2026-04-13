DATASET_HOST_PATH="$1"
BAG_OUTPUT_HOST="$2"

IMAGE_NAME=livox_bag_aggregate_noetic

DATASET_HOST_PATH=$(realpath "$DATASET_HOST_PATH")
BAG_OUTPUT_HOST=$(realpath "$BAG_OUTPUT_HOST")

DATASET_CONTAINER_PATH=/ros_ws/dataset
BAG_OUTPUT_CONTAINER=/ros_ws/output

DATASET_NAME=$(basename "$DATASET_HOST_PATH")
BAG_NAME="${DATASET_NAME}-pc.bag"

xhost +local:docker >/dev/null

docker run -it --rm \
  --network host \
  -u 1000:1000 \
  -v "$DATASET_HOST_PATH":"$DATASET_CONTAINER_PATH":ro \
  -v "$BAG_OUTPUT_HOST":"$BAG_OUTPUT_CONTAINER" \
  "$IMAGE_NAME" \
  /bin/bash -c "
    source /opt/ros/noetic/setup.bash && \
    source /ros_ws/devel/setup.bash && \
    rosrun livox_bag_aggregate livox_bag_aggregate \
      $DATASET_CONTAINER_PATH \
      $BAG_OUTPUT_CONTAINER/$BAG_NAME \
      /livox/lidar \
      /livox/pointcloud
  "