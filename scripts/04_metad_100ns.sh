#!/bin/bash -l
#SBATCH -p gpu
#SBATCH -N __NODES__
#SBATCH --ntasks=4
#SBATCH --exclusive
#SBATCH --gres=gpu:4
#SBATCH -t __TIME__
#SBATCH --mail-user=bradyholdren@ucsb.edu
#SBATCH --mail-type=all
#SBATCH --job-name=__JOB_NAME__
#SBATCH -o ./output_metad.%j.out
#SBATCH -e ./error_metad.%j.err

module purge
conda deactivate 2>/dev/null || true
module load gnu14/14.2.0 ucx/1.18.0 libfabric/1.18.0 hwloc/2.12.0 openmpi5/5.0.7 cuda/12.9
source $HOME/sw/gromacs-2025.1-cuda-mpi/bin/GMXRC
source $HOME/src/plumed-2.9.0/sourceme.sh

cd $SLURM_SUBMIT_DIR
/bin/hostname

echo "JOBID=$SLURM_JOB_ID on $(hostname)"
echo "CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"
echo "SLURM_JOB_GPUS=$SLURM_JOB_GPUS"
echo "SLURM_STEP_GPUS=$SLURM_STEP_GPUS"
srun -n 1 bash -lc 'echo "STEP CUDA_VISIBLE_DEVICES=$CUDA_VISIBLE_DEVICES"; nvidia-smi -L'

WALKERS=(walker0 walker1 walker2 walker3)
TASKS=${#WALKERS[@]}

TOTAL_CPUS=${SLURM_CPUS_ON_NODE:-$(nproc)}
CPUS_PER_TASK=$(( TOTAL_CPUS / TASKS ))

export OMP_NUM_THREADS=$CPUS_PER_TASK
export PLUMED_NUM_THREADS=$CPUS_PER_TASK

[ ! -f npt.gro ] && cp ../../../equib/__CONDITION__/__SYSTEM__/npt.gro ./npt.gro

for w in "${WALKERS[@]}"; do
  mkdir -p "$w"
  ln -sf ../plumed.dat "$w/plumed.dat"
  [ -f RNaseA.pdb ] && ln -sf ../RNaseA.pdb "$w/RNaseA.pdb"
  [ -f backbone.pdb ] && ln -sf ../backbone.pdb "$w/backbone.pdb"

  srun --mpi=pmix -n 1 gmx_mpi grompp \
    -f md_100ns.mdp \
    -c npt.gro \
    -p topol.top \
    -po "$w/mdout.mdp" \
    -o "$w/metad_100ns.tpr" \
    -maxwarn 2
done

srun --mpi=pmix -n $TASKS -c $CPUS_PER_TASK gmx_mpi mdrun \
  -deffnm metad_100ns \
  -plumed plumed.dat \
  -multidir "${WALKERS[@]}" \
  -ntomp $CPUS_PER_TASK \
  -nb gpu -pme gpu -bonded gpu -pin on
