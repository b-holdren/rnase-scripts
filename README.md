# Simulation Pipeline & Automation Drivers

This repository contains the automation drivers and Slurm submission templates for running RNase A molecular dynamics simulations.



## Core Scripts

### 1. `driver.sh`
This file will generate Slurm scripts from templates, and schedule all jobs.

* **Usage**:
  ```bash
  # Test configuration & generate stage files without submitting:
  ./driver.sh --dryrun

  # Run and submit all stages with Slurm job dependencies:
  ./driver.sh
  ```

* **Driver Stages Submitted**:
  1. **Stage 1 (`01_em`)**: Energy minimization (`enermin.mdp`).
  2. **Stage 2 (`02_equib`)**: 1 ns NPT equilibration (`npt.mdp`) queued after EM (`afterok`).
  3. **Stage 3 (`03_unbiased`)**: 100 ns unbiased production MD (`md_100ns.mdp`) queued after NPT.
  4. **Stage 4 (`04_metad`)**: 100 ns Multiple-Walker Parallel-Bias Metadynamics (`md_100ns.mdp` + `plumed.dat`) queued after NPT.

---

### 2. `scripts/` (Slurm Templates)

Templates use placeholders that are substituted by `driver.sh`:

* **`01_em.sh`**: CPU energy minimization batch script.
* **`02_equib.sh`**: 1 ns NPT equilibration batch script.
* **`03_unbiased_100ns.sh`**: 100 ns unbiased MD on 1 GPU. Offloads non-bonded and bonded forces to the GPU (`-nb gpu -pme gpu -bonded gpu`), with thread binding localized to the GPU socket.
* **`04_metad_100ns.sh`**: 100 ns Multiple-Walker PBMetaD across 4 walkers (`walker0`–`walker3`).

---

### 3. `build_urea+sorbitol.sh`
Prepares, solvates, and neutralizes the system in 4M urea and 1M sorbitol solution prior to running the simulation pipeline. Designed to be configured for different systems, howewver will need to be changed if running only one solvent/different solvents then given. 
