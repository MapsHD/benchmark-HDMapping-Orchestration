FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    cmake \
    git \
    wget \
    pkg-config \
    python3 \
    python3-venv \
    libproj-dev \
    libopencv-dev \
    libopencv-contrib-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    mesa-common-dev \
    xorg-dev \
    libglut-dev \
    libwayland-dev \
    libxkbcommon-dev \
    liblz4-dev \
    libgomp1 \
    libglib2.0-0t64 \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/Kitware/CMake/releases/download/v4.0.0/cmake-4.0.0-linux-x86_64.sh && \
    chmod +x cmake-4.0.0-linux-x86_64.sh && \
    ./cmake-4.0.0-linux-x86_64.sh --prefix=/usr/local --skip-license && \
    rm cmake-4.0.0-linux-x86_64.sh

ARG BUILD_JOBS=2

WORKDIR /workspace

# Avoid HTTP/2 authentication errors when fetching public submodules in Docker.
RUN git config --global http.version HTTP/1.1 && \
    git clone https://github.com/MapsHD/HDMapping.git --recursive && \
    git clone https://github.com/MapsHD/point_clouds_evaluation.git

WORKDIR /workspace/HDMapping

RUN mkdir -p build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo -DBUILD_WITH_CLI_TOOLS=ON && \
    cmake --build . --target laz_to_ply -j"$BUILD_JOBS"

RUN python3 -m venv /opt/uv && \
    /opt/uv/bin/pip install --no-cache-dir uv

WORKDIR /workspace/point_clouds_evaluation

RUN /opt/uv/bin/uv sync --locked --no-dev --python /usr/bin/python3 && \
    .venv/bin/python -c "from tqdm import tqdm"

COPY algos_lib.sh algorithms.conf /workspace/
COPY point_cloud_evaluation_step8/evaluate_clouds.py /workspace/point_cloud_evaluation_step8/
COPY registration_step7/validate_registration.py /workspace/point_cloud_evaluation_step8/

ENV PATH="/workspace/point_clouds_evaluation/.venv/bin:/workspace/HDMapping/build/bin:${PATH}" \
    PYTHONPATH="/workspace/point_clouds_evaluation" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    OMP_NUM_THREADS=1 \
    OPENBLAS_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1

CMD ["python", "/workspace/point_cloud_evaluation_step8/evaluate_clouds.py"]
