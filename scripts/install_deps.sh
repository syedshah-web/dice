#!/usr/bin/env bash
# Install Dice build/runtime dependencies on common Linux distros (incl. AWS) and macOS.
#
#   Ubuntu / Debian (AWS Ubuntu AMIs, Deep Learning AMIs):  apt  -> Boost.MPI comes from the distro
#   Amazon Linux 2023 / RHEL / Rocky:                         dnf  -> Boost is built from source
#   macOS:                                                    brew
#
# Usage: sudo is used automatically when not root.
#   ./scripts/install_deps.sh
set -euo pipefail

SUDO=""
[ "$(id -u)" -ne 0 ] && SUDO="sudo"
here="$(cd "$(dirname "$0")" && pwd)"

if command -v apt-get >/dev/null 2>&1; then
    $SUDO apt-get update
    DEBIAN_FRONTEND=noninteractive $SUDO apt-get install -y --no-install-recommends \
        build-essential make openmpi-bin libopenmpi-dev \
        libboost-serialization-dev libboost-mpi-dev libeigen3-dev \
        python3 python3-numpy
    echo
    echo "Dependencies installed. Build with:  make -j\$(nproc)"

elif command -v dnf >/dev/null 2>&1; then
    $SUDO dnf install -y gcc-c++ make tar gzip which findutils \
        openmpi-devel eigen3-devel python3 python3-numpy
    # Fedora-family OpenMPI lives under /usr/lib64/openmpi and is not on PATH by default.
    export PATH="/usr/lib64/openmpi/bin:$PATH"
    export LD_LIBRARY_PATH="/usr/lib64/openmpi/lib:${LD_LIBRARY_PATH:-}"
    PREFIX="${BOOST_PREFIX:-/opt/boost}"
    "$here/build_boost.sh" "$PREFIX"
    echo
    echo "Dependencies installed. Add OpenMPI to your environment (e.g. in ~/.bashrc):"
    echo "  export PATH=/usr/lib64/openmpi/bin:\$PATH"
    echo "  export LD_LIBRARY_PATH=/usr/lib64/openmpi/lib:\$LD_LIBRARY_PATH"
    echo "then build with:  make -j\$(nproc) BOOST=$PREFIX"

elif command -v brew >/dev/null 2>&1; then
    brew install open-mpi boost boost-mpi eigen libomp
    echo
    echo "Dependencies installed. Build with:  make -j BOOST=\$(brew --prefix)"

else
    echo "Unsupported system: install a C++14 compiler, OpenMPI, Eigen 3.3+ and Boost (serialization + mpi) manually." >&2
    exit 1
fi
