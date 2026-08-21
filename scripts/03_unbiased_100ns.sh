#!/bin/bash -l
#SBATCH -p gpu
#SBATCH -N __NODES__
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=__CPUS__
#SBATCH --gres=gpu:1
#SBATCH -t __TIME__
#SBATCH --mail-user=sheppard@ucsb.edu
#SBATCH --mail-type=all
#SBATCH --job-name=__JOB_NAME__
#SBATCH -o ./output_unbiased.%j.out
#SBATCH -e ./error_unbiased.%j.err

module purge
conda deactivate 2>/dev/null || true
module load gnu14/14.2.0 ucx/1.18.0 libfabric/1.18.0 hwloc/2.12.0 openmpi5/5.0.7 cuda/12.9
source $HOME/sw/gromacs-2025.1-cuda-mpi/bin/GMXRC

export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

cd $SLURM_SUBMIT_DIR
/bin/hostname

echo "JOBID=$SLURM_JOB_ID on $(hostname)"
echo "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
echo "SLURM_JOB_GPUS=$SLURM_JOB_GPUS"
echo "SLURM_STEP_GPUS=$SLURM_STEP_GPUS"
srun -n 1 bash -lc 'echo "STEP CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"; nvidia-smi -L'

# Copy NPT outputs from equib
cp ../../../equib/__CONDITION__/__SYSTEM__/npt.gro ./npt.gro
cp ../../../equib/__CONDITION__/__SYSTEM__/npt.cpt ./npt.cpt

srun --mpi=pmix -n 1 gmx_mpi grompp \
  -f md_100ns.mdp \
  -c npt.gro \
  -t npt.cpt \
  -p topol.top \
  -po mdout.mdp \
  -o unbiased_100ns.tpr \
  -maxwarn 2

srun --mpi=pmix -n $SLURM_NTASKS gmx_mpi mdrun -deffnm unbiased_100ns -ntomp $SLURM_CPUS_PER_TASK -nb gpu -pme gpu -pin on


