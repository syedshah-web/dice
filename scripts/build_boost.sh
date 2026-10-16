#!/usr/bin/env bash
# Build Boost (serialization + mpi only) from source against the mpicxx on PATH.
#
# Use this whenever the distro has no Boost.MPI package, or when you run with an MPI
# other than the distro's default (e.g. AWS ParallelCluster's /opt/amazon/openmpi with EFA,
# or Intel MPI). Boost.MPI must be built against the same MPI that Dice runs with.
#
#   ./scripts/build_boost.sh [PREFIX]          (default PREFIX=/opt/boost)
#   make -j BOOST=PREFIX
#
# Env: BOOST_VERSION (default 1.86.0), MPICXX (default: mpicxx on PATH), JOBS.
set -euo pipefail

PREFIX="${1:-/opt/boost}"
VER="${BOOST_VERSION:-1.86.0}"
VER_US="${VER//./_}"
MPICXX="${MPICXX:-$(command -v mpicxx || true)}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"

if [ -z "$MPICXX" ]; then
    echo "mpicxx not found on PATH; install OpenMPI (or set MPICXX=/path/to/mpicxx)." >&2
    exit 1
fi

SUDO=""
mkdir -p "$PREFIX" 2>/dev/null || true
if [ ! -w "$PREFIX" ]; then SUDO="sudo"; $SUDO mkdir -p "$PREFIX"; fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cd "$work"

# NB: the bintray URLs in the original Dice docs are dead; archives.boost.io is the live mirror.
curl -fL -o boost.tar.gz "https://archives.boost.io/release/${VER}/source/boost_${VER_US}.tar.gz"
tar -xzf boost.tar.gz
cd "boost_${VER_US}"

./bootstrap.sh --with-libraries=serialization,mpi --prefix="$PREFIX"
# bootstrap does not configure MPI; without this line Boost.MPI is silently skipped.
echo "using mpi : $MPICXX ;" >> project-config.jam

./b2 -j"$JOBS" link=shared threading=multi variant=release
$SUDO ./b2 install --prefix="$PREFIX" link=shared threading=multi variant=release

ls "$PREFIX"/lib*/libboost_mpi* >/dev/null
echo "Boost $VER installed to $PREFIX (built against $MPICXX)"
