#!/bin/bash
# ==============================================================================
# Prepare RNase A in 4M Urea solution and 1M Sorbitol solution at pH 4, 327K
# ==============================================================================
set -e

# Use gmx or gmx_mpi
if [ -z "$GMX" ]; then
    if command -v gmx &>/dev/null; then
        GMX="gmx"
    elif command -v gmx_mpi &>/dev/null; then
        GMX="gmx_mpi"
    else
        echo "Error: GROMACS binary not found in PATH."
        echo "Please load your environment/modules before running."
        exit 1
    fi
fi
echo "Using GROMACS: $GMX"

# Paths
# ==============================================================================
WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$WORK_DIR/../../.." && pwd)"
FF_DIR="$ROOT_DIR/force_fields"
CLEAN_PDB="$ROOT_DIR/prep/1KF5_clean.pdb"
SORBITOL_GRO="$FF_DIR/sorbitol.gro"
SORBITOL_ITP="$FF_DIR/sorbitol.itp"
UREA_GRO="$FF_DIR/urea.gro"
UREA_ITP="$FF_DIR/Urea.itp"
# ==============================================================================
cd "$WORK_DIR"

echo "[1/7] Running pdb2gmx for pH 4 (Protonate Histidines)"

(
    cd "$FF_DIR"
    printf "2\n2\n2\n2\n" | $GMX pdb2gmx \
        -f "$CLEAN_PDB" \
        -o "$WORK_DIR/protein.gro" \
        -p "$WORK_DIR/topol.top" \
        -i "$WORK_DIR/posre.itp" \
        -q "$WORK_DIR/protein_clean.pdb" \
        -ff charmm36-modified-trout \
        -water tip3p \
        -his \
        >& "$WORK_DIR/pdb2gmx.log"
)

echo "[2/7] Defining 9.8 nm cubic box"
$GMX editconf \
    -f protein.gro \
    -o protein_box.gro \
    -box 9.8 9.8 9.8 \
    -c

echo "[3/7] Inserting 567 Sorbitol molecules"

$GMX insert-molecules \
    -f protein_box.gro \
    -ci "$SORBITOL_GRO" \
    -nmol 567 \
    -o protein_sorbitol.gro \
    -try 100 \
    -seed 20260821 \
    >& insert-molecules.log

echo "[4/7] Inserting 2267 Urea molecules"

$GMX insert-molecules \
    -f protein_sorbitol.gro \
    -ci "$UREA_GRO" \
    -nmol 2267 \
    -o protein_sorbitol_urea.gro \
    -try 100 \
    -seed 20260821 \
    >& insert-molecules.log

echo "[5/7] Solvating with TIP3P water"

$GMX solvate \
    -cp protein_sorbitol_urea.gro \
    -cs spc216.gro \
    -o protein_sorbitol_urea_solv.gro \
    -p topol.top

echo "[6/7] Updating topol.top with Urea and Sorbitol parameters & paths"

sed -i 's|#include "\./charmm36-modified-trout\.ff/|#include "../../../force_fields/charmm36-modified-trout.ff/|g' topol.top
sed -i 's|#include ".*/posre\.itp"|#include "posre.itp"|g' topol.top

# Insert sorbitol.itp and Urea.itp 
if ! grep -q "sorbitol.itp" topol.top; then
    sed -i '/tip3p.itp/i ; Include sorbitol topology\n#include "../../../force_fields/sorbitol.itp"\n' topol.top
fi

if ! grep -q "Urea.itp" topol.top; then
    sed -i '/tip3p.itp/i ; Include urea topology\n#include "../../../force_fields/Urea.itp"\n' topol.top
fi

# Ensure [ molecules ] lists sorbitol 567 and UR 2267
if ! grep -q "^sorbitol" topol.top; then
    sed -i '/^SOL/i sorbitol            567' topol.top
fi

if ! grep -q "^UR" topol.top; then      
    sed -i '/^SOL/i UR                  2267' topol.top
fi

# Add [atomtypes] for custom urea atomtypes
if ! grep -q "CUR" topol.top; then
    sed -i '/forcefield.itp/a \
\
[ atomtypes ]\
; name     mass        charge    ptype        sigma                  epsilon\
    CUR   12.0107      0.921       A       0.377    0.417\
    HUR   1.00800      0.285       A       0.158    0.088\
    OUR   15.99940    -0.675       A       0.310    0.560\
    NUR   14.0067     -0.693       A       0.311    0.500\
' topol.top
fi

echo "[7/7]: Adding ions"

$GMX grompp \
    -f ions.mdp \
    -c protein_sorbitol_urea_solv.gro \
    -p topol.top \
    -o ions.tpr \
    -maxwarn 2 \
    >& grompp_ions.log

printf "SOL\n" | $GMX genion \
    -s ions.tpr \
    -o protein_sorbitol_urea_solv_ions.gro \
    -p topol.top \
    -pname NA \
    -nname CL \
    -rmin 0.35 \
    -neutral \
    >& genion.log

if [ -f "$WORK_DIR/protein_sorbitol_urea_solv_ions.gro" ]; then
    echo "System preparation finished successfully for pH4-327K!"
    echo "Final coordinate file: $WORK_DIR/protein_sorbitol_urea_solv_ions.gro"
    echo "Final topology file:   $WORK_DIR/topol.top"
fi
