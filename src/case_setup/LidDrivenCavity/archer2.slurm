#!/bin/bash --login
#SBATCH --job-name=ccs
#SBATCH --nodes=1
#SBATCH --tasks-per-node=128
#SBATCH --cpus-per-task=1
#SBATCH --time=00:05:00
#SBATCH --account=e609
#SBATCH --partition=standard 
#SBATCH --qos=standard 

# set up environment  
module swap PrgEnv-cray PrgEnv-gnu
source /work/e609/e609/shared/ccs/gnu/setup_gnu.sh

# set up config and exe  
export EXE=../../../ccs_app
export CONFIG=$(SLURM_SUBMIT_DIR)/LidDrivenCavity_adios2_config.xml

# set striping and create directory 
export STRIPE_COUNT=-1 # max striping 
rm -rf ${RUNDIR}
mkdir -p ${RUNDIR}
lfs setstripe -c ${STRIPE_COUNT}  ${WORKING_DIR}
cd ${WORKING_DIR} 
cp ${CONFIG} . 

if (( ${DARSHAN} == 1 )); 
then 
  export DXT_ENABLE_IO_TRACE=1 # darshan DXT trace 
  module load darshan
fi 

srun  --hint=nomultithread  --distribution=block:block ${EXE} --ccs_m ${MESH_SIZE} --ccs_case LidDrivenCavity > ccs.out 

if (( ${DARSHAN} == 1 )); 
then 
  day=$( date +%-d )
  month=$( date +%-m )
  mv /mnt/lustre/a2fs-nvme/system/darshan/2024/${month}/${day}/shr203*.darshan .  
fi 

wait 

module list  2>&1 | tee -a ccs.out
echo "JOB ID"  $SLURM_JOBID >> ccs.out
echo "JOB NAME" ${SLURM_JOB_NAME} >> ccs.out

echo "Job ended " $(date +"%T") # end time 
