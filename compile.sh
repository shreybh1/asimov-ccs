export ADIOS2=$ADIOS2_DIR 
export PETSC_DIR=$PETSC 
export FYAMLC=$FYAMLC_DIR
export RCMF90=$RCMF90 
export PARHIP=$PARHIP_DIR 
export GKLIB_DIR=$GKLIB_DIR 
export METIS=$METIS_DIR
export CCS_DIR=$(pwd) 
echo ${CCS_DIR} 

make CMP=gnu all

# make CMP=gnu tests 

