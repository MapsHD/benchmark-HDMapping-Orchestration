FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y \
        python3 \
        python3-pip \
        python3-tk && \
    rm -rf /var/lib/apt/lists/*

RUN pip3 install --break-system-packages pandas numpy evo

WORKDIR /app

COPY tum-to-latex.py .