# https://github.com/MapsHD/HDMapping-benchmark-pointcloud-visual-inspection.git
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# pocl-opencl-icd is the CPU OpenCL fallback used when no NVIDIA runtime is available.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    git \
    pocl-opencl-icd \
    && rm -rf /var/lib/apt/lists/*

# The NVIDIA container runtime mounts libnvidia-opencl.so.1 but does not reliably
# add its ICD entry; without it the loader skips the GPU and falls back to PoCL.
RUN mkdir -p /etc/OpenCL/vendors && \
    echo "libnvidia-opencl.so.1" > /etc/OpenCL/vendors/nvidia.icd

ARG BUILD_JOBS=2
ARG CVC_REF=main

WORKDIR /workspace

# Avoid HTTP/2 authentication errors when fetching public submodules in Docker.
# Only the submodules used by the headless CMake build are fetched (no glfw).
RUN git config --global http.version HTTP/1.1 && \
    git clone https://github.com/MapsHD/HDMapping-benchmark-pointcloud-visual-inspection.git && \
    cd HDMapping-benchmark-pointcloud-visual-inspection && \
    git checkout "$CVC_REF" && \
    git submodule update --init \
        external/OpenCL-Headers \
        external/OpenCL-ICD-Loader \
        external/zlib-ng \
        external/happly \
        external/stb \
        external/glm \
        external/CLI11

WORKDIR /workspace/HDMapping-benchmark-pointcloud-visual-inspection

RUN cmake -S . -B build -DCMAKE_BUILD_TYPE=Release && \
    cmake --build build --target cloud_visual_compare -j"$BUILD_JOBS"

COPY algos_lib.sh algorithms.conf /workspace/
COPY point_cloud_compare_step9/compare_clouds.sh /workspace/point_cloud_compare_step9/

# HOME and the PoCL cache point to /tmp so OpenCL kernel caching works when the
# container runs as the invoking (non-root) user.
ENV PATH="/workspace/HDMapping-benchmark-pointcloud-visual-inspection/build/bin:${PATH}" \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    POCL_CACHE_DIR=/tmp/pocl-cache \
    HOME=/tmp

CMD ["bash", "/workspace/point_cloud_compare_step9/compare_clouds.sh"]
