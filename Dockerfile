# Portable Dice image (works on x86_64 and arm64 / AWS Graviton).
#   docker build -t dice .
#   docker run --rm -v "$PWD":/work -w /work dice mpirun -np 8 Dice input.dat > output.dat
FROM ubuntu:22.04

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        build-essential make openmpi-bin libopenmpi-dev \
        libboost-serialization-dev libboost-mpi-dev libeigen3-dev \
        python3 python3-numpy \
    && rm -rf /var/lib/apt/lists/*

COPY . /opt/dice
WORKDIR /opt/dice
RUN make clean && make -j"$(nproc)" && rm -rf obj obj_z

ENV PATH="/opt/dice:${PATH}" \
    OMPI_ALLOW_RUN_AS_ROOT=1 \
    OMPI_ALLOW_RUN_AS_ROOT_CONFIRM=1 \
    OMPI_MCA_btl_vader_single_copy_mechanism=none

WORKDIR /work
CMD ["Dice"]
