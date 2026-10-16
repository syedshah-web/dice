# Portable Makefile for Dice 1.0 (Linux x86_64 / aarch64 incl. AWS, and macOS).
#
# Every path is auto-detected but can be overridden on the command line, e.g.
#   make -j                                   # system Boost/Eigen (apt/dnf/brew/conda)
#   make -j BOOST=/opt/boost_1_86_0            # Boost built from source (see scripts/build_boost.sh)
#   make -j EIGEN=/opt/eigen3 OPT="-march=native"
#   make -j USE_MPI=no                        # serial build
#
# Variables:
#   USE_MPI    yes|no    (default yes)
#   USE_INTEL  yes|no    (default no; uses mpiicpc/icpc)
#   EIGEN      directory containing Eigen/Dense
#   BOOST      Boost root (headers in $BOOST or $BOOST/include, libs in $BOOST/stage/lib or $BOOST/lib)
#   BOOST_LIB  override Boost library dir explicitly
#   OMP_PREFIX (macOS only) prefix holding include/omp.h and lib/libomp.dylib
#   OPT        extra optimisation flags, e.g. -march=native (not set by default so
#              binaries stay portable across instance types)

USE_MPI   ?= yes
USE_INTEL ?= no
OPT       ?=

UNAME_S := $(shell uname -s)

# ---------------------------------------------------------------- Eigen
ifeq ($(strip $(EIGEN)),)
EIGEN := $(patsubst %/Eigen/Dense,%,$(firstword $(wildcard \
	$(CONDA_PREFIX)/include/eigen3/Eigen/Dense \
	/usr/include/eigen3/Eigen/Dense \
	/usr/local/include/eigen3/Eigen/Dense \
	/opt/homebrew/include/eigen3/Eigen/Dense)))
endif
ifeq ($(strip $(EIGEN))$(filter clean,$(MAKECMDGOALS)),)
$(error Eigen not found. Install it (apt: libeigen3-dev, dnf: eigen3-devel, brew/conda: eigen) or pass EIGEN=/path/to/eigen3)
endif

# ---------------------------------------------------------------- Boost
BOOST_INC :=
ifneq ($(strip $(BOOST)),)
BOOST_INC := $(firstword $(patsubst %/boost/version.hpp,%,$(wildcard $(BOOST)/boost/version.hpp $(BOOST)/include/boost/version.hpp)))
ifeq ($(strip $(BOOST_LIB)),)
BOOST_LIB := $(firstword $(patsubst %/,%,$(dir $(wildcard $(BOOST)/stage/lib/libboost_serialization* $(BOOST)/lib/libboost_serialization* $(BOOST)/lib64/libboost_serialization*))))
endif
else ifneq ($(strip $(CONDA_PREFIX)),)
ifneq ($(wildcard $(CONDA_PREFIX)/include/boost/version.hpp),)
BOOST_INC := $(CONDA_PREFIX)/include
BOOST_LIB ?= $(CONDA_PREFIX)/lib
endif
endif

INCLUDES := -I$(EIGEN)
ifneq ($(strip $(BOOST_INC)),)
INCLUDES += -I$(BOOST_INC)
endif
BOOST_LFLAGS :=
ifneq ($(strip $(BOOST_LIB)),)
BOOST_LFLAGS += -L$(BOOST_LIB) -Wl,-rpath,$(BOOST_LIB)
endif

FLAGS  = -std=c++14 -g -O3 $(INCLUDES)
DFLAGS = -std=c++14 -g -O3 $(INCLUDES) -DComplex

# ---------------------------------------------------------------- OpenMP
ifeq ($(USE_INTEL), yes)
OMP_CFLAGS  := -qopenmp
OMP_LFLAGS  := -qopenmp
else ifeq ($(UNAME_S), Darwin)
# conda's OpenMPI wrapper otherwise looks for a non-existent cross compiler
OMPI_CXX ?= clang++
export OMPI_CXX
# Apple clang: preprocessor form + external libomp (conda llvm-openmp or brew libomp)
ifeq ($(strip $(OMP_PREFIX)),)
OMP_PREFIX := $(patsubst %/include/omp.h,%,$(firstword $(wildcard \
	$(CONDA_PREFIX)/include/omp.h /opt/homebrew/opt/libomp/include/omp.h /usr/local/opt/libomp/include/omp.h)))
endif
OMP_CFLAGS  := -Xpreprocessor -fopenmp -I$(OMP_PREFIX)/include
OMP_LFLAGS  := -L$(OMP_PREFIX)/lib -lomp -Wl,-rpath,$(OMP_PREFIX)/lib
else
OMP_CFLAGS  := -fopenmp
OMP_LFLAGS  := -fopenmp
endif

FLAGS  += $(OMP_CFLAGS)
DFLAGS += $(OMP_CFLAGS)

# ---------------------------------------------------------------- compilers
ifeq ($(USE_MPI), yes)
ifeq ($(USE_INTEL), yes)
CXX := mpiicpc
else
CXX := mpicxx
endif
LFLAGS = $(BOOST_LFLAGS) -lboost_serialization -lboost_mpi $(OMP_LFLAGS)
else
ifeq ($(USE_INTEL), yes)
CXX := icpc
else ifeq ($(UNAME_S), Darwin)
CXX := clang++
else
CXX := g++
endif
LFLAGS = $(BOOST_LFLAGS) -lboost_serialization $(OMP_LFLAGS)
FLAGS  += -DSERIAL
DFLAGS += -DSERIAL
endif
CC := $(CXX)

SRC_qdptsoc = QDPTSOC.cpp SHCIbasics.cpp Determinants.cpp integral.cpp input.cpp Davidson.cpp new_anglib.cpp SOChelper.cpp SHCIgetdeterminants.cpp SHCIsampledeterminants.cpp SHCIrdm.cpp SHCISortMpiUtils.cpp SHCImakeHamiltonian.cpp
SRC_GTensorFT = GTensorFT.cpp SHCIbasics.cpp Determinants.cpp integral.cpp input.cpp Davidson.cpp new_anglib.cpp SOChelper.cpp SHCIgetdeterminants.cpp SHCIsampledeterminants.cpp SHCIrdm.cpp SHCISortMpiUtils.cpp SHCImakeHamiltonian.cpp
SRC_GTensorFT2 = GTensorFT2.cpp SHCIbasics.cpp Determinants.cpp integral.cpp input.cpp Davidson.cpp new_anglib.cpp SOChelper.cpp SHCIgetdeterminants.cpp SHCIsampledeterminants.cpp SHCIrdm.cpp SHCISortMpiUtils.cpp SHCImakeHamiltonian.cpp
SRC_Dice = SHCI.cpp SHCIbasics.cpp Determinants.cpp integral.cpp input.cpp Davidson.cpp SHCIgetdeterminants.cpp SHCIsampledeterminants.cpp SHCIrdm.cpp SHCISortMpiUtils.cpp SHCImakeHamiltonian.cpp SHCIshm.cpp
SRC_ZDice2 = SHCI.cpp SHCIbasics.cpp Determinants.cpp integral.cpp input.cpp Davidson.cpp SOChelper.cpp new_anglib.cpp SHCIgetdeterminants.cpp SHCIsampledeterminants.cpp SHCIrdm.cpp SHCISortMpiUtils.cpp SHCImakeHamiltonian.cpp SHCIshm.cpp
SRC_forcyrus = forCyrus.cpp SHCIbasics.cpp Determinants.cpp integral.cpp input.cpp Davidson.cpp
SRC_Excitations = Excitations.cpp SHCIbasics.cpp Determinants.cpp integral.cpp input.cpp


OBJ_qdptsoc+=obj_z/QDPTSOC.o obj_z/SHCIbasics.o obj_z/Determinants.o obj_z/integral.o obj_z/input.o obj_z/Davidson.o obj_z/new_anglib.o obj_z/SOChelper.o obj_z/SHCIgetdeterminants.o obj_z/SHCIsampledeterminants.o obj_z/SHCIrdm.o obj_z/SHCISortMpiUtils.o obj_z/SHCImakeHamiltonian.o
OBJ_gtensorft+=obj_z/GTensorFT.o obj_z/SHCIbasics.o obj_z/Determinants.o obj_z/integral.o obj_z/input.o obj_z/Davidson.o obj_z/new_anglib.o obj_z/SOChelper.o obj_z/SHCIgetdeterminants.o obj_z/SHCIsampledeterminants.o obj_z/SHCIrdm.o obj_z/SHCISortMpiUtils.o obj_z/SHCImakeHamiltonian.o
OBJ_gtensorft2+=obj_z/GTensorFT2.o obj_z/SHCIbasics.o obj_z/Determinants.o obj_z/integral.o obj_z/input.o obj_z/Davidson.o obj_z/new_anglib.o obj_z/SOChelper.o obj_z/SHCIgetdeterminants.o obj_z/SHCIsampledeterminants.o obj_z/SHCIrdm.o obj_z/SHCISortMpiUtils.o obj_z/SHCImakeHamiltonian.o
OBJ_Dice+=obj/SHCI.o obj/SHCIbasics.o obj/Determinants.o obj/integral.o obj/input.o obj/Davidson.o obj/SHCIgetdeterminants.o  obj/SHCIsampledeterminants.o obj/SHCIrdm.o obj/SHCISortMpiUtils.o obj/SHCImakeHamiltonian.o obj/SHCIshm.o
OBJ_ZDice2+=obj_z/SHCI.o obj_z/SHCIbasics.o obj_z/Determinants.o obj_z/integral.o obj_z/input.o obj_z/Davidson.o obj_z/SOChelper.o obj_z/new_anglib.o obj_z/SHCIgetdeterminants.o  obj_z/SHCIsampledeterminants.o obj_z/SHCIrdm.o obj_z/SHCISortMpiUtils.o obj_z/SHCImakeHamiltonian.o obj_z/SHCIshm.o
OBJ_forcyrus+=obj/forCyrus.o obj/SHCIbasics.o obj/Determinants.o obj/integral.o obj/input.o obj/Davidson.o obj/SHCIgetdeterminants.o  obj/SHCIsampledeterminants.o obj/SHCIrdm.o obj/SHCISortMpiUtils.o obj/SHCImakeHamiltonian.o
OBJ_Excitations+=obj/Excitations.o obj/SHCIbasics.o obj/Determinants.o obj/integral.o obj/input.o

obj/%.o: %.cpp | obj
	$(CXX) $(FLAGS) $(OPT) -c $< -o $@
obj_z/%.o: %.cpp | obj_z
	$(CXX) $(DFLAGS) $(OPT) -c $< -o $@

obj obj_z:
	mkdir -p $@

all: Dice ZDice2 # stats QDPTSOC GTensorFT GTensorFT2
.DEFAULT_GOAL := all
.PHONY: all clean info

info:
	@echo "OS        = $(UNAME_S)"
	@echo "CXX       = $(CXX)"
	@echo "EIGEN     = $(EIGEN)"
	@echo "BOOST_INC = $(BOOST_INC)"
	@echo "BOOST_LIB = $(BOOST_LIB)"
	@echo "FLAGS     = $(FLAGS) $(OPT)"
	@echo "LFLAGS    = $(LFLAGS)"

stats: stats.cpp
	$(CXX) -O3 stats.cpp -o stats
Dice	: $(OBJ_Dice)
	$(CXX)   $(FLAGS) $(OPT) -o  Dice $(OBJ_Dice) $(LFLAGS)
ZDice2	: $(OBJ_ZDice2)
	$(CXX)   $(FLAGS) $(OPT) -o  ZDice2 $(OBJ_ZDice2) $(LFLAGS)
forcyrus	: $(OBJ_forcyrus)
	$(CXX)   $(FLAGS) $(OPT) -o  forcyrus $(OBJ_forcyrus) $(LFLAGS)
Excitations	: $(OBJ_Excitations)
	$(CXX)   $(FLAGS) $(OPT) -o  Excitations $(OBJ_Excitations) $(LFLAGS)
QDPTSOC	: $(OBJ_qdptsoc)
	$(CXX)   $(DFLAGS) $(OPT) -o  QDPTSOC $(OBJ_qdptsoc) $(LFLAGS)
GTensorFT	: $(OBJ_gtensorft)
	$(CXX)   $(DFLAGS) $(OPT) -o  GTensorFT $(OBJ_gtensorft) $(LFLAGS)
GTensorFT2	: $(OBJ_gtensorft2)
	$(CXX)   $(DFLAGS) $(OPT) -o  GTensorFT2 $(OBJ_gtensorft2) $(LFLAGS)

clean :
	rm -rf obj obj_z; rm -f CIST Dice ZDice2 QDPTSOC GTensorFT GTensorFT2 forcyrus Excitations stats
