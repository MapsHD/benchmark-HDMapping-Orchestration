# benchmark-HDMapping-Orchestration

# branch HUMANOID-LIO-DATASET

### dataset source:
https://zenodo.org/records/21318128

![calibration-room](dataset_photos/calibration-room.jpeg)
![flat-room](dataset_photos/flat-room.jpeg)
![long-corridor](dataset_photos/long-corridor.jpeg)
![outdoor-urk](dataset_photos/outdoor-urk.jpeg)
![underground-garage](dataset_photos/underground-garage.jpeg)


# Step 1 (download data)
Download first trial https://zenodo.org/records/21318128/files/calibration-room.7z?download=1 (You can do similar step for all other trials) 

# Step 2 (prepare data)
Unpack calibration-room.7z (later on You can do similar for flat-room.7z, long-corridor.7z, outdoor-urk.7z, underground-garage.7z)

You should see following data structure for calibration-room data collection:

```HUMANOID-LIO-DATASET (single scenario) data structure
<calibration-room>/
├── TLS-ground-truth
│   ├── Leica_ScanStation_P30-P40_Civil_DS.pdf  (documentation for Terrestrial Laser Scanner)
│   └── TLS.laz (ground truth point cloud from Terrestrial Laser Scanner)
├── trial-1
│   ├──ground-truth
│   │  ├──ground_truth.tum (ground truth trajectory)
│   │  ├──ground_truth.txt (ground truth trajectory)
│   │  └──perspective_view.png (perspective view of trajectory)
│   └──hdmapping-raw (raw data in format of data https://github.com/MapsHD/HDMapping)
│      ├──imu0000.csv
│      ├──imu0001.csv
│      ├──imu0002.csv
│      ├──...
│      ├──imu0038.csv
│      ├──lidar0000.laz
│      ├──lidar0000.sn
│      ├──lidar0001.laz
│      ├──lidar0002.sn
│      ├──...
│      ├──lidar0038.laz
│      ├──lidar0038.sn
│      ├──status0000.json
│      ├──status0001.json
│      ├──status0002.json
│      ├──...
│      └──status0038.json
├── trial-2
│   ├──ground-truth
│   │  ├──ground_truth.tum (ground truth trajectory)
│   │  ├──ground_truth.txt (ground truth trajectory)
│   │  └──perspective_view.png (perspective view of trajectory)
│   └──hdmapping-raw (raw data in format of data https://github.com/MapsHD/HDMapping)
│      ├──imu0000.csv
│      ├──imu0001.csv
│      ├──imu0002.csv
│      ├──...
│      ├──imu0022.csv
│      ├──lidar0000.laz
│      ├──lidar0000.sn
│      ├──lidar0001.laz
│      ├──lidar0002.sn
│      ├──...
│      ├──lidar0022.laz
│      ├──lidar0022.sn
│      ├──status0000.json
│      ├──status0001.json
│      ├──status0002.json
│      ├──...
│      └──status0022.json
└── image.jpeg (situation view)
```
## Create worskpace folder and copy raw data (in HDMapping format)
open new terminal
```shell
mkdir -p ~/hdmapping-benchmark/data/raw
cd ~/hdmapping-benchmark/data/raw
cp ~/Downloads/calibration-room/trial-1/hdmapping-raw/* .
```

## Convert data to ROS1 format
open new terminal
```shell
cd ~/hdmapping-benchmark
git clone https://github.com/MapsHD/mandeye_to_bag.git --recursive
cd ~/hdmapping-benchmark/mandeye_to_bag
docker build -t mandeye-ws_noetic --target ros1 .
docker build -t mandeye-ws_humble --target ros2 .
./mandeye-convert.sh '/home/janusz/hdmapping-benchmark/data/raw' '/home/janusz/hdmapping-benchmark/data/raw/ros1' hdmapping-to-ros1
mv ~/hdmapping-benchmark/data/raw/ros1/raw ../data/reg-1.bag 
```

You should see following folders
```
<~hdmapping-benchmark/data>/
├── raw (folder with raw hdmapping data)
└── reg-1.bag (bugfile for ROS1 - Robot Operating System 1)
```

# Step 3 (run benchmark)
open new terminal
```shell
cd ~/hdmapping-benchmark
git clone https://github.com/MapsHD/benchmark-HDMapping-Orchestration.git
cd benchmark-HDMapping-Orchestration
git checkout Bunker-DVI-Dataset-reg-1
chmod +x ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/prepare_data_step1/prepare_data_step1.sh 
chmod +x ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/prepare_data_step1/mandeye-convert.sh 
chmod +x ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/prepare_data_step1/livox_bag.sh 
chmod +x ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/clone_github_repositories_step2/clone_github_repositories_step2.sh
chmod +x ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/run_benchmark_step3/run_benchmark_step3.sh
chmod +x ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/conversion_tum_step4/run_tum_step4.sh
chmod +x ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/evo_step5/tum-to-latex_step5.sh
chmod +x ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/start_benchmark.sh
cp ~/Downloads/calibration-room/trial-1/ground-truth/ground_truth.tum ./conversion_tum_step4
```
Check if You have following data
```
<~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/conversion_tum_step4>/
├──Dockerfile
├──ground_truth.tum (this one can be missing --> it should be copied from ~/Downloads/calibration-room/trial-1/ground-truth/)
├──run_tum_step4.sh
└──save_to_tum.py
```

open new terminal
```shell
cd ~/hdmapping-benchmark/benchmark-HDMapping-Orchestration
~/hdmapping-benchmark/benchmark-HDMapping-Orchestration/start_benchmark.sh
```

# Step 4 (results for qualitative and quantitative inetpretation)
You should expect following results
```
<~/hdmapping-benchmark/data/tum>/
├──ape_table_github.md (Absolute Pose Error for github readme)
├──ground_truth.tum (ground truth trajectory in TUM format, [ts x y z qx qy qz qw])
├──image.png (plot of all trajectories)
├──output_hdmapping-BIEVR-LIO_trajectory_tum.txt (trajectory BIEVR-LIO in TUM format)
├──output_hdmapping-c3p-voxelmap_trajectory_tum.txt (trajectory c3p-voxelmap in TUM format)
├──output_hdmapping-ct-icp_trajectory_tum.txt (trajectory ct-icp in TUM format)
├──output_hdmapping-DALI_SLAM_trajectory_tum.txt (...)
├──output_hdmapping-dlio_trajectory_tum.txt
├──output_hdmapping-D-LIO_trajectory_tum.txt
├──output_hdmapping-dlo_trajectory_tum.txt
├──output_hdmapping-EllipseLIO_trajectory_tum.txt
├──output_hdmapping-faster-lio_trajectory_tum.txt
├──output_hdmapping-fast-lio_trajectory_tum.txt
├──output_hdmapping-form_trajectory_tum.txt
├──output_hdmapping-genz_trajectory_tum.txt
├──output_hdmapping-glim_trajectory_tum.txt
├──output_hdmapping-i2ekf-lo_trajectory_tum.txt
├──output_hdmapping-ig-lio_trajectory_tum.txt
├──output_hdmapping-kiss_trajectory_tum.txt
├──output_hdmapping-lego-loam_trajectory_tum.txt
├──output_hdmapping-lidar-odometry-ros_trajectory_tum.txt
├──output_hdmapping-lio-ekf_trajectory_tum.txt
├──output_hdmapping-log-lio2_trajectory_tum.txt
├──output_hdmapping-mm-lins_trajectory_tum.txt
├──output_hdmapping-nv-liom_trajectory_tum.txt
├──output_hdmapping-point-lio_trajectory_tum.txt
├──output_hdmapping-SE3-LIO_trajectory_tum.txt
├──output_hdmapping-slict_trajectory_tum.txt
├──output_hdmapping-super-lio_trajectory_tum.txt
├──output_hdmapping-superOdom_trajectory_tum.txt
├──output_hdmapping-Voxel-SLAM_trajectory_tum.txt
├──overlap_results.md (trajectory completness for github readme)
├──overlap_results.tex (trajectory completness in latex)
├──rpe_table_github.md (Relative Pose Error for github readme)
├──table_ape.csv (Absolute Pose Error in csv table)
├──table_ape.tex (Absolute Pose Error for latex)
├──table_rpe.csv (Relative Pose Error in csv table)
└──table_rpe.tex (Relative Pose Error for latex)
```

## Plot of trajectories from file ~/hdmapping-benchmark/data/tum/image.png
![plot](plots/image-HUMANOID-LIO-DATASET.png)

## ape_table_github.md from file ~/hdmapping-benchmark/data/tum/iape_table_github.md
### APE (Absolute Pose Error)

| method | max | mean | median | min | rmse | sse | std |
| ------------- | ------------- | ------------- | ------------- | ------------- | ------------- | ------------- | ------------- |
| BIEVR-LIO | 1.295810 | 0.437973 | 0.344530 | 0.191516 | 0.501890 | 921.677001 | 0.245098 |
| D-LIO | - | - | - | - | - | - | - |
| DALI_SLAM | 1.425146 | 0.178958 | 0.135757 | 0.002888 | 0.229556 | 196.029655 | 0.143771 |
| EllipseLIO | 165149.928959 | 58892.917620 | 59752.386023 | 2972.317504 | 68846.391474 | 68893365371338.921875 | 35657.395771 |
| SE3-LIO | 2.515389 | 0.952638 | 0.781955 | 0.391832 | 1.058902 | 4129.646946 | 0.462335 |
| Voxel-SLAM | 6.834422 | 5.266162 | 4.612183 | 3.023417 | 5.351871 | 104688.431005 | 0.953973 |
| c3p-voxelmap | - | - | - | - | - | - | - |
| ct-icp | - | - | - | - | - | - | - |
| dlio | 0.224790 | 0.080390 | 0.076097 | 0.001506 | 0.087394 | 79.684916 | 0.034283 |
| dlo | 5.239997 | 2.956491 | 2.960970 | 0.404420 | 3.203236 | 28863.400581 | 1.232834 |
| fast-lio | 0.105537 | 0.035022 | 0.032762 | 0.002900 | 0.037630 | 5.241959 | 0.013763 |
| faster-lio | 0.106694 | 0.044897 | 0.043127 | 0.013499 | 0.046719 | 7.298892 | 0.012920 |
| form | 38.675221 | 14.853316 | 12.390098 | 3.845874 | 16.894641 | 1061224.647555 | 8.050336 |
| genz | 30.103982 | 10.912156 | 9.185137 | 1.606307 | 12.783811 | 607290.324667 | 6.659629 |
| glim | 0.061297 | 0.019110 | 0.017502 | 0.001983 | 0.020933 | 0.457042 | 0.008545 |
| i2ekf-lo | 17.302267 | 3.968518 | 3.362465 | 0.393010 | 4.560662 | 79246.605266 | 2.247332 |
| ig-lio | 364200.703105 | 121149.032635 | 118116.940932 | 3593.956626 | 143164.462225 | 78069504897569.000000 | 76282.207203 |
| kiss | 31.668316 | 13.804573 | 12.497219 | 1.479975 | 15.506996 | 888284.865388 | 7.064043 |
| lego-loam | 36.920216 | 16.472985 | 16.152645 | 1.552135 | 18.044450 | 300856.406128 | 7.364980 |
| lidar-odometry-ros | 33.380597 | 11.743830 | 9.870537 | 3.313172 | 13.815165 | 708086.093195 | 7.276073 |
| lio-ekf | 198301.299576 | 57997.879448 | 50625.256468 | 1409.576805 | 70647.951078 | 18552041329636.250000 | 40340.785455 |
| log-lio2 | 308072.902979 | 53735.299102 | 21915.025556 | 21145.443896 | 79300.880873 | 21375052375038.101562 | 58319.356458 |
| mm-lins | 2523.161399 | 151.999058 | 70.800282 | 37.574071 | 323.288621 | 397368055.106695 | 285.327564 |
| nv-liom | - | - | - | - | - | - | - |
| point-lio | 2.680825 | 0.048077 | 0.044863 | 0.009051 | 0.066090 | 16.641460 | 0.045348 |
| slict | 1140.764856 | 560.379002 | 576.379189 | 88.289514 | 631.922091 | 494365004.312951 | 292.063183 |
| super-lio | 0.107757 | 0.035489 | 0.034076 | 0.012102 | 0.037201 | 5.272670 | 0.011156 |
| superOdom | 40.822669 | 16.851372 | 16.206119 | 1.852167 | 18.236804 | 5582704.804668 | 6.972249 |


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

