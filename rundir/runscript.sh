# calls archer2 slurm submission script using the needed flags and arguments.
# test, darshan, and weak scaling are pre set options. 
set -e

submitSlurm() {
  export DARSHAN=${DARSHAN}
  export MESH=${MESH} 
  export RUNDIR=$(pwd)/OUTPUT/LDC/${MESH}/${NUM_NODES}_${PPN} 
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
    --array=${ARRAY} ${WAIT_CMD} \
    archer2.slurm 
  fi 
}  

weakScaling() {
  echo "Entered weak scaling" 
  echo "Node start ${NODE_START} to Node end ${NODE_END} PPN ${PPN} time ${TIME}"
  echo "DARSHAN flag ${DARSHAN} wait flag ${WAITFLAG} job array ${ARRAY} dry run ${DRY_RUN} " 
  for i in $(seq ${NODE_START} ${NODE_END})
  do 
    NUM_NODES=$((2**${i}))
    submitSlurm 
  done
} 

# Default arguments 
export DARSHAN=0
export MESH=4096
export NUM_NODES=1
export PPN=128
export TIME="00:20:00"
export ARRAY="0"
export WAITFLAG=0 
export DRY_RUN=0
# Command line arguments 
if  [[ $1 == 'test' ]]
then 

  submitSlurm

elif  [[ $1 == 'darshan' ]]
then 

  export DARSHAN=1
  export NODE_START=1
  export NODE_END=4
  export WAITFLAG=1
  weakScaling

else 

  echo 'invalid argument'

fi 
