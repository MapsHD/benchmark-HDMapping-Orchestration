# benchmark-HDMapping-Orchestration

# Step 1 Prepare data

## Create worskpace folder
```shell
mkdir -p ~/hdmapping-benchmark
```

## Go to your workspace folder:

```shell
cd ~/hdmapping-benchmark
```
## Clone the orchestration repository:
```shell
git clone https://github.com/MapsHD/benchmark-HDMapping-Orchestration.git
```
### Available sequences:

seq00 seq01 seq02 seq04 seq05 seq06 seq07 seq08 seq09 seq10

The dataset is available here: [KITTI dataset ROS](https://github.com/Jakubach/kitti_to_ros)

## Make the script executable (if not done yet):

```shell
chmod +x ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/prepare_data_step1/download_data.sh 
```
### Run the script with a sequence number:

```shell
~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/prepare_data_step1/download_data.sh seq00
```

## This will download the following into ~/hdmapping-benchmark/data:

kitti_seq00_ros1.bag

kitti_seq00_ros2.zip – ROS2 bag (automatically unzipped into kitti_seq00_ros2/)


# Step 2 Clone repositores

## Make the script executable (if not done yet):

```shell
chmod +x ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/clone_github_repositories_step2/clone_github_repositories_step2.sh
```

## Run the script:
```shell
~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/clone_github_repositories_step2/clone_github_repositories_step2.sh
```
After running the script, you will be prompted to enter the branch name you want to clone for the repositories.

## Result:

The repositories will be cloned into:

~/hdmapping-benchmark

The Docker images required for the benchmark will be built.

# Step 3 run benchmark

## Make the script executable (if not done yet):
```shell
chmod +x ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/run_benchmark_step3/run_benchmark_step3.sh
```

## Change directory to the data folder:

```shell
cd ~/hdmapping-benchmark/data
```

## Run the benchmark script with your ROS1 bag and ROS2 folder:
 
 ```shell
~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/run_benchmark_step3/run_benchmark_step3.sh kitti_seq00_ros1.bag kitti_seq00_ros2/2011_10_03_drive_0027_extract_ros2/ .
```

## Result:
 
### After running the script, you will get the following folder:

~/hdmapping-benchmark/data/output_hdmapping-ALGONAME/

You should see following data

lio_initial_poses.reg

poses.reg

scan_lio_*.laz

session.json

trajectory_lio_*.csv