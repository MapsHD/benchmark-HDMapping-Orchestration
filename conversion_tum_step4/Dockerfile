FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    python3 \
    python3-pip \
    python3-dev \
    libeigen3-dev \
    liblaszip-dev \
    libtbb12 \
    && rm -rf /var/lib/apt/lists/*

# Python deps
RUN pip3 install --break-system-packages \
    numpy \
    pandas \
    pybind11

WORKDIR /workspace

RUN git clone https://github.com/marcinmatecki/HDMapping.git --recursive

WORKDIR /workspace/HDMapping

RUN git checkout mma/save-tum-no-gui

WORKDIR /workspace

RUN apt-get update && apt-get install -y \
    wget

RUN apt-get update && apt-get install -y \
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
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get install -y \
    libopencv-dev \
    && rm -rf /var/lib/apt/lists/*

RUN apt-get update && apt-get upgrade -y && apt-get install -y \
    g++ \
    libglx-dev \
    libopengl-dev \
    libgl-dev \
    libglut-dev \
    libopencv-contrib-dev \
    libproj-dev \
    proj-bin \
    pkg-config \
    && rm -rf /var/lib/apt/lists/*

RUN wget https://github.com/Kitware/CMake/releases/download/v4.0.0/cmake-4.0.0-linux-x86_64.sh && \
    chmod +x cmake-4.0.0-linux-x86_64.sh && \
    ./cmake-4.0.0-linux-x86_64.sh --prefix=/usr/local --skip-license && \
    rm cmake-4.0.0-linux-x86_64.sh

WORKDIR /workspace/HDMapping

RUN mkdir -p build && cd build && \
    cmake .. -DBUILD_WITH_PYBIND=ON && \
    cmake --build . --target multi_session_registration_py -j$(nproc)

COPY save_to_tum.py /workspace/

WORKDIR /workspace/HDMapping

CMD ["bash"]