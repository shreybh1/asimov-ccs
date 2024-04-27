module swap PrgEnv-cray PrgEnv-gnu
module use /work/y07/shared/archer2-lmod/dev
source /work/e609/e609/shared/ccs/gnu/setup_gnu.sh

make CMP=gnu FC=ftn all
