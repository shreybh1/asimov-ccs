submitSlurm() {
  export DARSHAN=${DARSHAN}
  export MESH=${MESH} 
  export RUNDIR=$(pwd)/OUTPUT/${MESH}
  sbatch --export=ALL,DARSHAN=${DARSHAN},MESH=${MESH},RUNDIR=${RUNDIR} \
    --nodes=${NUM_NODES} --ntasks-per-node=${PPN} --time=${TIME} \
    --array=${ARRAY} \
    archer2.slurm 
}  

# Default arguments 
export DARSHAN=0
export MESH=129
export NUM_NODES=1
export PPN=128
export TIME="00:10:00"
export ARRAY="0"

# Command line arguments 
if  [[ $1 == 'run' ]]
then 
  submitSlurm
elif  [[ $1 == 'darshan' ]]
then 
  export DARSHAN=1
  submitSlurm
else 
  echo 'invalid argument'
fi 
