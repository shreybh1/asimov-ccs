# calls archer2 slurm submission script using the needed flags and arguments.
# test, darshan, and weak scaling are pre set options. 
set -e

submitSlurm() {
  export DARSHAN=${DARSHAN}
  export MESH=${MESH} 
  if [[ $WAITFLAG  == 1 ]]
  then
    WAIT_CMD="--wait"
  else
    WAIT_CMD=""
  fi 
  if [[ $DRY_RUN  == 0 ]]
  then 
  sbatch --export=ALL,DARSHAN=${DARSHAN},MESH=${MESH},RUNDIR=${RUNDIR} \
    --nodes=${NUM_NODES} --ntasks-per-node=${PPN} --time=${TIME} \
    --array=${ARRAY} --qos=${QOS} ${WAIT_CMD} \
    archer2.slurm 
  fi 
}  

weakScaling() {
  echo "Node start ${NODE_START} to Node end ${NODE_END} PPN ${PPN} time ${TIME}"
  echo "DARSHAN flag ${DARSHAN} wait flag ${WAITFLAG} job array ${ARRAY} dry run ${DRY_RUN} " 
  for i in $(seq ${NODE_START} ${NODE_END})
  do 
    NUM_NODES=$(( ${i} * 20 )) 
    submitSlurm 
  done
} 

# Default arguments 
export DARSHAN=0
export MESH=$(( 400**3 ))  
export PPN=128
export TIME="04:00:00"
export ARRAY="0"
export WAITFLAG=0 
export DRY_RUN=0
export CCS_CASE="TaylorGreenVortex"
# Command line arguments 
if  [[ $1 == 'test' ]]
then 
  export NUM_NODES=1
  export RUNDIR=$(pwd)/test
  submitSlurm
elif  [[ $1 == 'darshan' ]]
then 
  export DARSHAN=1
  export NODE_START=1
  export NODE_END=4
  export WAITFLAG=0
  export QOS="lowpriority"
  weakScaling
else 
  echo 'invalid argument'
fi 
