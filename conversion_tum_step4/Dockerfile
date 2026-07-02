FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    g++ \
    cmake \
    git \
    wget \
    pkg-config \
    python3 \
    python3-pip \
    python3-dev \
    libeigen3-dev \
    libtbb-dev \
    liblaszip-dev \
    libproj-dev \
    proj-bin \
    libopencv-dev \
    libopencv-contrib-dev \
    libgl1-mesa-dev \
    libglu1-mesa-dev \
    mesa-common-dev \
    xorg-dev \
    libx11-dev \
    libxi-dev \
    libxrandr-dev \
    libxinerama-dev \
    libxcursor-dev \
    libxxf86vm-dev \
    libglx-dev \
    libopengl-dev \
    libgl-dev \
    libglut-dev \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --break-system-packages \
    numpy \
    pandas \
    pybind11

RUN wget https://github.com/Kitware/CMake/releases/download/v4.0.0/cmake-4.0.0-linux-x86_64.sh && \
    chmod +x cmake-4.0.0-linux-x86_64.sh && \
    ./cmake-4.0.0-linux-x86_64.sh --prefix=/usr/local --skip-license && \
    rm cmake-4.0.0-linux-x86_64.sh

WORKDIR /workspace

RUN git clone https://github.com/marcinmatecki/HDMapping.git --recursive

WORKDIR /workspace/HDMapping

RUN git checkout mma/save-tum-no-gui

RUN mkdir -p build && cd build && \
    cmake .. -DBUILD_WITH_PYBIND=ON && \
    cmake --build . --target multi_session_registration_py -j$(nproc)

COPY save_to_tum.py /workspace/

WORKDIR /workspace/HDMapping

CMD ["bash"]