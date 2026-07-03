# TRAJECTORY EVALUATION INSTRUCTIONS

## STEP 1 — Install required Python libraries
```shell
pip install pandas numpy evo
```
## STEP 2 — Prepare ground truth trajectory

## You must have a ground truth trajectory in TUM format named:

ground_truth.tum

## TUM format structure:
timestamp tx ty tz qx qy qz qw

## STEP 3 — Prepare algorithm trajectories

## All trajectories must also be in TUM format.
### File naming convention required by the script:

output_hdmapping-ALGORITHM_trajectory_tum.txt

### Example files:

output_hdmapping-fastlio_trajectory_tum.txt
output_hdmapping-liosam_trajectory_tum.txt
output_hdmapping-ours_trajectory_tum.txt

## STEP 4 — Check if trajectory files exist
```shell
ls output*_trajectory_tum.txt
```
## STEP 5 — Run evaluation script
```shell
python3 tum-to-latex.py
```
## STEP 6 — Output files

## The script will generate:

## CSV files with metrics
tabela_ape.csv

tabela_rpe.csv

##  LaTeX tables for papers
tabela_ape.tex

tabela_rpe.tex
