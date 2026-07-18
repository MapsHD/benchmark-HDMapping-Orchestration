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

