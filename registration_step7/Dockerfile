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
    && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/Kitware/CMake/releases/download/v4.0.0/cmake-4.0.0-linux-x86_64.sh && \
    chmod +x cmake-4.0.0-linux-x86_64.sh && \
    ./cmake-4.0.0-linux-x86_64.sh --prefix=/usr/local --skip-license && \
    rm cmake-4.0.0-linux-x86_64.sh

ARG BUILD_JOBS=2

WORKDIR /workspace

# Avoid HTTP/2 authentication errors when fetching public submodules in Docker.
RUN git config --global http.version HTTP/1.1 && \
    git clone https://github.com/MapsHD/HDMapping.git --recursive

WORKDIR /workspace/HDMapping

RUN mkdir -p build && cd build && \
    cmake .. -DCMAKE_BUILD_TYPE=RelWithDebInfo && \
    cmake --build . --target session_to_session_rigid_registration -j"$BUILD_JOBS" && \
    test -x bin/session_to_session_rigid_registration

COPY algos_lib.sh algorithms.conf /workspace/
COPY registration_step7/register_sessions.sh /workspace/registration_step7/

ENV PATH="/workspace/HDMapping/build/bin:${PATH}"

CMD ["bash", "/workspace/registration_step7/register_sessions.sh"]
