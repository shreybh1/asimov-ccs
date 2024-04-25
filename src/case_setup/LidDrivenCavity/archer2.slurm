#!/bin/bash --login
#SBATCH --job-name=ccs
#SBATCH --nodes=1
#SBATCH --tasks-per-node=128
#SBATCH --cpus-per-task=1
#SBATCH --time=00:05:00
#SBATCH --account=e609
#SBATCH --partition=standard 
#SBATCH --qos=standard 

# GNU 
module swap PrgEnv-cray PrgEnv-gnu
source /work/e609/e609/shared/ccs/gnu/setup_gnu.sh

# EXE 
export EXE=../../../ccs_app

srun  --hint=nomultithread  --distribution=block:block ${EXE} --ccs_m 129 --ccs_case LidDrivenCavity

wait 

module list  2>&1 | tee -a test.out
echo "JOB ID"  $SLURM_JOBID >> test.out
echo "JOB NAME" ${SLURM_JOB_NAME} >> test.out

echo "Job ended " $(date +"%T") # end time 
