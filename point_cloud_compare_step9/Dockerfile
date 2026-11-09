# https://github.com/MapsHD/HDMapping-benchmark-pointcloud-visual-inspection.git
FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

# OpenCL drivers: PoCL (CPU), Intel compute runtime (Intel GPUs) and Mesa Rusticl
# (AMD GPUs). NVIDIA's driver library is mounted by the NVIDIA container runtime.
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    git \
    pocl-opencl-icd \
    intel-opencl-icd \
    mesa-opencl-icd \
    && rm -rf /var/lib/apt/lists/*

# The NVIDIA container runtime mounts libnvidia-opencl.so.1 but does not reliably
# add its ICD entry; without it the loader never sees the NVIDIA GPU.
# /etc/OpenCL/select/<mode> holds the drivers the OpenCL loader may use for each
# run_compare_step9.sh --opencl mode (selected through OCL_ICD_VENDORS). Mesa's
# legacy Clover driver (mesa.icd) is never selected. A missing optional driver
# leaves its mode empty, which compare_clouds.sh reports; PoCL is required.
RUN mkdir -p /etc/OpenCL/vendors && \
    echo "libnvidia-opencl.so.1" > /etc/OpenCL/vendors/nvidia.icd && \
    select_icds() { \
        dir="/etc/OpenCL/select/$1"; shift; mkdir -p "$dir"; \
        for icd in "$@"; do \
            if [ -f "/etc/OpenCL/vendors/$icd" ]; then cp "/etc/OpenCL/vendors/$icd" "$dir/"; fi; \
        done; \
    } && \
    select_icds auto nvidia.icd intel.icd rusticl.icd pocl.icd && \
    select_icds nvidia nvidia.icd && \
    select_icds intel intel.icd && \
    select_icds amd rusticl.icd && \
    select_icds cpu pocl.icd && \
    test -f /etc/OpenCL/select/cpu/pocl.icd

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
# container runs as the invoking (non-root) user. Rusticl exposes AMD GPUs only
# when enabled for radeonsi. run_compare_step9.sh overrides OCL_ICD_VENDORS.
ENV PATH="/workspace/HDMapping-benchmark-pointcloud-visual-inspection/build/bin:${PATH}" \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=compute,utility \
    OCL_ICD_VENDORS=/etc/OpenCL/select/auto \
    RUSTICL_ENABLE=radeonsi \
    POCL_CACHE_DIR=/tmp/pocl-cache \
    HOME=/tmp

CMD ["bash", "/workspace/point_cloud_compare_step9/compare_clouds.sh"]
