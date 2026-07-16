import multi_session_registration_py

sessions = [
    "/data/ground_truth/HDMappingGroundTruth/lio_result_0/session.mjs",
    "/data/c3p-voxelmap/output_hdmapping-c3p-voxelmap/session.json",
    "/data/ct-icp/output_hdmapping-ct-icp/session.json",
    "/data/dlio/output_hdmapping-dlio/session.json",
    "/data/dlo/output_hdmapping-dlo/session.json",
    "/data/faster-lio/output_hdmapping-faster-lio/session.json",
    "/data/fast-lio/output_hdmapping-fast-lio/session.json",
    "/data/form/output_hdmapping-form/session.json",
    "/data/genz-icp/output_hdmapping-genz/session.json",
    "/data/glim/output_hdmapping-glim/session.json",
    "/data/i2ekf-lo/output_hdmapping-i2ekf-lo/session.json",
    "/data/ig-lio/output_hdmapping-ig-lio/session.json",
    "/data/kiss-icp/output_hdmapping-kiss/session.json",
    "/data/lego-loam/output_hdmapping-lego-loam/session.json",
    "/data/lidar_odometry_ros_wrapper/output_hdmapping-lidar-odometry-ros/session.json",
    "/data/lio-ekf/output_hdmapping-lio-ekf/session.json",
    "/data/nv-liom/output_hdmapping-nv-liom/session.json",
    "/data/point-lio/output_hdmapping-point-lio/session.json",
    "/data/slict/output_hdmapping-slict/session.json",
    "/data/se3-lio/output_hdmapping-SE3-LIO/session.json",
    "/data/super-lio/output_hdmapping-super-lio/session.json",
    "/data/mm-lins/output_hdmapping-mm-lins/session.json",
    "/data/log-lio2/output_hdmapping-log-lio2/session.json",
    "/data/superOdom/output_hdmapping-superOdom/session.json",
    "/data/d-lio/output_hdmapping-D-LIO/session.json",
    "/data/ellipselio/output_hdmapping-EllipseLIO/session.json",
    "/data/dalislam/output_hdmapping-DALI_SLAM/session.json",
    "/data/voxelslam/output_hdmapping-Voxel-SLAM/session.json",
    "/data/bievr-lio/output_hdmapping-BIEVR-LIO/session.json",
]

result = multi_session_registration_py.run(sessions)

print(result)
