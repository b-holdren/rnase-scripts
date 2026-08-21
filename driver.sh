#!/bin/bash
# ==============================================================================
# Driver for RNase A Simulations
# Usage: ./driver.sh [--dryrun]
# ==============================================================================
set -e

DRY_RUN=false
if [[ "$1" == "--dryrun" ]] || [[ "$2" == "--dryrun" ]]; then
    DRY_RUN=true
fi

#GLOBAL CONFIG
# ==============================================================================
# System & Condition Settings
CONDITION="pH4-327K"
SYSTEM="urea-4M+sorbitol-1M"
TEMP="327"

# Cluster Settings
SLURM_PARTITION="batch"                 # CPU cluster partition (e.g. batch)
SLURM_NODES="1"                         # Number of nodes
SLURM_CPUS="40"                         # CPU cores / threads per task

# Walltimes 
TIME_EM="02:00:00"                      # Energy Minimization
TIME_EQUIB="12:00:00"                   # 1 ns NPT Equilibration
TIME_UNBIASED="96:00:00"                # 100 ns Unbiased MD
TIME_METAD_P1="96:00:00"                # Metadynamics Part 1
TIME_METAD_P2="96:00:00"                # Metadynamics Part 2 
TIME_METAD_P3="96:00:00"                # Metadynamics Part 3 

#Metadynamics Segments
METAD_P1_NS="150"                       
METAD_P2_EXTEND_NS="150"               
METAD_P3_EXTEND_NS="100"               

METAD_P2_EXTEND_PS=$((METAD_P2_EXTEND_NS * 1000))
METAD_P3_EXTEND_PS=$((METAD_P3_EXTEND_NS * 1000))

# Paths & Directory Setup

RUN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$RUN_DIR/.." && pwd)"
SCRIPTS_DIR="$RUN_DIR/scripts"

PREP_DIR="$BASE_DIR/prep/$CONDITION/$SYSTEM"
EM_DIR="$BASE_DIR/enermin/$CONDITION/$SYSTEM"
EQUIB_DIR="$BASE_DIR/equib/$CONDITION/$SYSTEM"
UNBIASED_DIR="$BASE_DIR/unbiased/$CONDITION/$SYSTEM"
METAD_DIR="$BASE_DIR/metadynamics/$CONDITION/$SYSTEM"
# ==============================================================================
if [ "$DRY_RUN" = true ]; then
    echo "RNase A Pipeline (DRY RUN MODE)"
else
    echo "RNase A Pipeline"
fi
echo "Condition:        $CONDITION"
echo "Target Temp:      ${TEMP} K"
echo "System:           $SYSTEM"
echo "Prep Directory:   $PREP_DIR"
echo ""

# Check prep files
if [ ! -f "$PREP_DIR/topol.top" ]; then
    echo "Error: Topology file not found at $PREP_DIR/topol.top" >&2
    exit 1
fi

GRO_FILE=$(find "$PREP_DIR" -name "protein_*_solv_ions.gro" -o -name "protein_box_solv_ions.gro" | head -n 1)
if [ -z "$GRO_FILE" ]; then
    echo "Error: Final.gro file not found in $PREP_DIR" >&2
    exit 1
fi
echo "Starting coordinates: $GRO_FILE"

# Create stage directories
mkdir -p "$EM_DIR" "$EQUIB_DIR" "$UNBIASED_DIR" "$METAD_DIR"

# ==============================================================================
# Helper Function to Populate Scripts
# ==============================================================================
apply_config() {
    local src="$1"
    local dst="$2"
    local job_name="$3"
    local time_limit="$4"
    local extend_ps="${5:-0}"

    sed \
        -e "s|__PARTITION__|$SLURM_PARTITION|g" \
        -e "s|__NODES__|$SLURM_NODES|g" \
        -e "s|__CPUS__|$SLURM_CPUS|g" \
        -e "s|__TIME__|$time_limit|g" \
        -e "s|__JOB_NAME__|$job_name|g" \
        -e "s|__CONDITION__|$CONDITION|g" \
        -e "s|__SYSTEM__|$SYSTEM|g" \
        -e "s|__EXTEND_PS__|$extend_ps|g" \
        "$src" > "$dst"
}

# ==============================================================================
# Populate Stage Directories
# ==============================================================================


echo "[1/4] Configuring Stage 1: Energy Minimization ($EM_DIR)..."
cp "$GRO_FILE" "$EM_DIR/conf.gro"
cp "$PREP_DIR/topol.top" "$EM_DIR/topol.top"
cp "$PREP_DIR/posre.itp" "$EM_DIR/posre.itp"
cp "$BASE_DIR/unbiased/enermin.mdp" "$EM_DIR/enermin.mdp"
apply_config "$SCRIPTS_DIR/01_em.sh" "$EM_DIR/01_em.sh" "01_em" "$TIME_EM"


echo "[2/4] Configuring Stage 2: 1 ns NPT Equilibration ($EQUIB_DIR)..."
cp "$PREP_DIR/topol.top" "$EQUIB_DIR/topol.top"
cp "$PREP_DIR/posre.itp" "$EQUIB_DIR/posre.itp"
cp "$BASE_DIR/unbiased/npt.mdp" "$EQUIB_DIR/npt.mdp"
sed -i "s/ref_t.*=.*/ref_t                    = $TEMP /g" "$EQUIB_DIR/npt.mdp"
sed -i "s/gen_temp.*=.*/gen_temp                 = $TEMP /g" "$EQUIB_DIR/npt.mdp"
apply_config "$SCRIPTS_DIR/02_equib.sh" "$EQUIB_DIR/02_equib.sh" "02_equib" "$TIME_EQUIB"

echo "[3/4] Configuring Stage 3: 100 ns Unbiased MD ($UNBIASED_DIR)..."
cp "$PREP_DIR/topol.top" "$UNBIASED_DIR/topol.top"
cp "$BASE_DIR/unbiased/md_100ns.mdp" "$UNBIASED_DIR/md_100ns.mdp"
sed -i "s/ref_t.*=.*/ref_t                    = $TEMP /g" "$UNBIASED_DIR/md_100ns.mdp"
apply_config "$SCRIPTS_DIR/03_unbiased_100ns.sh" "$UNBIASED_DIR/03_unbiased_100ns.sh" "03_unbiased" "$TIME_UNBIASED"

echo "[4/4] Configuring Stage 4: 400 ns Metadynamics ($METAD_DIR)..."
cp "$PREP_DIR/topol.top" "$METAD_DIR/topol.top"
cp "$BASE_DIR/unbiased/md_150ns.mdp" "$METAD_DIR/md_150ns.mdp"
sed -i "s/ref_t.*=.*/ref_t                    = $TEMP /g" "$METAD_DIR/md_150ns.mdp"

cp "$BASE_DIR/metadynamics/plumed.dat" "$METAD_DIR/plumed.dat"
sed -i "s/TEMP=[0-9.]*/TEMP=$TEMP.0/g" "$METAD_DIR/plumed.dat"

cp "$BASE_DIR/metadynamics/backbone.pdb" "$METAD_DIR/backbone.pdb"
cp "$BASE_DIR/metadynamics/RNaseA.pdb" "$METAD_DIR/RNaseA.pdb"

apply_config "$SCRIPTS_DIR/04_metad_part1_150ns.sh" "$METAD_DIR/04_metad_part1_150ns.sh" "04_metad_p1" "$TIME_METAD_P1"
apply_config "$SCRIPTS_DIR/05_metad_part2_150ns.sh" "$METAD_DIR/05_metad_part2_150ns.sh" "05_metad_p2" "$TIME_METAD_P2" "$METAD_P2_EXTEND_PS"
apply_config "$SCRIPTS_DIR/06_metad_part3_100ns.sh" "$METAD_DIR/06_metad_part3_100ns.sh" "06_metad_p3" "$TIME_METAD_P3" "$METAD_P3_EXTEND_PS"

if [ "$DRY_RUN" = true ]; then
    echo "Dry run complete: All files & directories successfully created"
    exit 0
fi

echo ""
echo "[5/5] Submitting Slurm Jobs"

# 1. Submit Energy Minimization
JOB_EM=$(cd "$EM_DIR" && sbatch --parsable 01_em.sh)
echo "   Energy Minimization:          Job ID: $JOB_EM"

# 2. Submit NPT Equilibration (queued after EM)
JOB_EQUIB=$(cd "$EQUIB_DIR" && sbatch --parsable --dependency=afterok:$JOB_EM 02_equib.sh)
echo "   1 ns NPT Equilibration:       Job ID: $JOB_EQUIB (queued after $JOB_EM)"

# 3. Submit 100 ns Unbiased MD (queued after NPT)
JOB_UNBIASED=$(cd "$UNBIASED_DIR" && sbatch --parsable --dependency=afterok:$JOB_EQUIB 03_unbiased_100ns.sh)
echo "   100 ns Unbiased MD:           Job ID: $JOB_UNBIASED (queued after $JOB_EQUIB)"

# # 4. Submit Metadynamics Part 1 (150 ns) (queued after NPT)
# JOB_METAD_P1=$(cd "$METAD_DIR" && sbatch --parsable --dependency=afterok:$JOB_EQUIB 04_metad_part1_150ns.sh)
# echo "   Metadynamics Part 1 (150 ns): Job ID: $JOB_METAD_P1 (queued after $JOB_EQUIB)"

# # 5. Submit Metadynamics Part 2 (150 ns) (queued after Part 1)
# JOB_METAD_P2=$(cd "$METAD_DIR" && sbatch --parsable --dependency=afterok:$JOB_METAD_P1 05_metad_part2_150ns.sh)
# echo "   Metadynamics Part 2 (150 ns): Job ID: $JOB_METAD_P2 (queued after $JOB_METAD_P1)"

# # 6. Submit Metadynamics Part 3 (100 ns -> 400 ns total) (queued after Part 2)
# JOB_METAD_P3=$(cd "$METAD_DIR" && sbatch --parsable --dependency=afterok:$JOB_METAD_P2 06_metad_part3_100ns.sh)
# echo "   Metadynamics Part 3 (100 ns): Job ID: $JOB_METAD_P3 (queued after $JOB_METAD_P2)"

echo ""
echo "All steps successfully scheduled!"
