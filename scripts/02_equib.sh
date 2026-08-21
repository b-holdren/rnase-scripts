#!/bin/bash -l
#SBATCH -p __PARTITION__
#SBATCH -N __NODES__
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=__CPUS__
#SBATCH -t __TIME__
#SBATCH --job-name=__JOB_NAME__
#SBATCH -o ./output_npt.%j.out
#SBATCH -e ./error_npt.%j.err

module load gromacs/2025.1
export OMP_NUM_THREADS=$SLURM_CPUS_PER_TASK

cd $SLURM_SUBMIT_DIR

# Copy EM output from enermin
cp ../../../enermin/__CONDITION__/__SYSTEM__/em.gro ./conf.gro

gmx grompp -f npt.mdp -c conf.gro -r conf.gro -p topol.top -o npt.tpr -maxwarn 2
gmx mdrun -deffnm npt -ntomp $SLURM_CPUS_PER_TASK -pin on
