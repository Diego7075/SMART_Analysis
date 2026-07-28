# SMART Analysis

MATLAB scripts for organizing, preprocessing, and analyzing data collected with the SMART experiment on Gorilla.

## Folder structure

The raw Gorilla exports should be organized as:

```
SMART/
│
├── ms0/
│   ├── AXBY/
│   ├── BAYX/
│   ├── XYAB/
│   └── YBXA/
│
├── ms250/
│   ├── AXBY/
│   ├── BAYX/
│   ├── XYAB/
│   └── YBXA/
│
├── ms500/
│   ├── AXBY/
│   ├── BAYX/
│   ├── XYAB/
│   └── YBXA/
│
├── ms1100/
│   ├── AXBY/
│   ├── BAYX/
│   ├── XYAB/
│   └── YBXA/
│
├── data/
└── results/
```

Each sequence folder should contain the Gorilla Excel files downloaded after data collection. The top-level folders (`ms0`, `ms250`, `ms500`, and `ms1100`) and their sequence subfolders must keep these names, as they are referenced directly by the MATLAB scripts.

**Note:** The response mappings used here correspond to the original Gorilla behavioral experiment (`AXBY`, `BAYX`, `XYAB`, and `YBXA`). The MATLAB/Psychtoolbox version of SMART uses a different set of mappings (`AXBY`, `BYAX`, `YBXA`, and `XAYB`) that was redesigned for EEG experiments to balance the temporal distribution of unidimensional (A/B) and multidimensional (X/Y) sequence elements.

## Workflow

### 1. Organize Gorilla data

Run:

```matlab
SMART_Data_Organizer
```

This script:

- Combines Gorilla files across all sequence mappings.
- Removes incomplete participants.
- Compresses the datasets into:
  - `SMART_Data_compressed.xlsx`
  - `Generalization_Data_compressed.xlsx`
  - `Demographics_Data_compressed.xlsx`

### 2. Analyze the dataset

Run:

```matlab
SMART_Data_Analyzer
```

The analysis pipeline automatically:

- Performs participant quality control.
- Applies preprocessing and exclusion criteria.
- Computes SMART reaction-time analyses.
- Computes Generalization performance.
- Produces statistical summaries.
- Generates figures.
- Saves all outputs in the `results` folder.

## Experimental conditions

### ISI conditions

- ms0
- ms250
- ms500
- ms1100

### Response mappings

- AXBY
- BYAX
- YBXA
- XAYB

## Output

The analysis generates:

- Preprocessed Excel files
- Text reports
- Summary statistics
- Publication-quality figures

All outputs are written to the `results` directory.