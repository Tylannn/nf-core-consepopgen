# nf-core/consepopgen: Output

## Introduction

This document describes the output produced by the pipeline. Most of the plots are taken from the MultiQC report, which summarises results at the end of the pipeline.

The directories listed below will be created in the results directory after the pipeline has finished. All paths are relative to the top-level results directory.

> [!NOTE]
> This pipeline is currently in active development (v0.1.0-dev). The outputs described below reflect the current implementation. Additional analyses (PCA, ADMIXTURE, Fis, ROH) are planned for future releases as described in the [project proposal](https://github.com/nf-core/proposals/issues/57).

## Pipeline overview

The pipeline is built using [Nextflow](https://www.nextflow.io/) and processes data using the following steps:

- [Population VCF Splitting](#population-vcf-splitting) - Split VCF files by population
- [PIXY](#pixy) - Population genetic statistics (π, FST, Dxy)
- [VCFtools](#vcftools) - Individual heterozygosity and inbreeding coefficient (Fis)
- [MultiQC](#multiqc) - Workflow execution report with software versions
- [Pipeline information](#pipeline-information) - Report metrics generated during the workflow execution

### Population VCF Splitting

<details markdown="1">
<summary>Output files</summary>

- `populations/`
  - `*.vcf.gz`: VCF files split by population (one file per population)
  - `samples/`: Directory containing sample list files for each population

</details>

The pipeline automatically splits input VCF files by population using [bcftools view](http://samtools.github.io/bcftools/bcftools.html). This enables population-specific analyses such as individual heterozygosity calculations.

**Output files:**
- Each population gets its own compressed VCF file: `<vcf_name>_<population>.vcf.gz`
- Sample lists are stored in `samples/` for reproducibility

These population-specific VCF files are used downstream for calculating individual-level statistics.

### PIXY

<details markdown="1">
<summary>Output files</summary>

- `pixy/`
  - `*_pi.txt`: Nucleotide diversity (π) within each population
  - `*_fst.txt`: Population differentiation (FST) between population pairs
  - `*_dxy.txt`: Absolute divergence (Dxy) between population pairs
  - `populations.txt`: Population assignments file used by PIXY

</details>

[PIXY](https://pixy.readthedocs.io/) is a command-line tool for calculating population genetic statistics from VCF files. Unlike many tools, PIXY correctly handles invariant sites, making it particularly suitable for modern genomic datasets.

#### Nucleotide Diversity (π)

**File**: `*_pi.txt`

Nucleotide diversity (π) measures the average number of nucleotide differences per site between two randomly chosen sequences from a population. Higher values indicate greater genetic diversity.

**Key columns:**
- `pop`: Population identifier
- `chromosome`: Chromosome/scaffold name
- `window_pos_1`: First position of the genomic window
- `window_pos_2`: Last position of the genomic window
- `avg_pi`: **Average per site nucleotide diversity for the window**. This is the weighted average nucleotide diversity per site for all sites in the window, where weights are determined by the number of genotyped samples at each site.
- `no_sites`: Total number of sites in the window that have at least one valid genotype
- `count_diffs`: Raw number of pairwise differences between all genotypes in the window (numerator of avg_pi)
- `count_comparisons`: Raw number of non-missing pairwise comparisons between all genotypes (denominator of avg_pi)
- `count_missing`: Raw number of missing pairwise comparisons

**Interpretation:**
- π = 0: No genetic variation in the population (low diversity)
- π > 0.01: Generally considered high diversity
- Conservation concern: Low π may indicate small population size, bottlenecks, or inbreeding

> [!TIP]
> When aggregating across windows, sum `count_diffs` and `count_comparisons` separately, then compute the ratio. Do not average `avg_pi` values directly.

#### Population Differentiation (FST)

**File**: `*_fst.txt`

FST measures genetic differentiation between populations, ranging from 0 (no differentiation) to 1 (complete differentiation). PIXY calculates Weir & Cockerham's FST estimator.

**Key columns:**
- `pop1`: ID of the first population
- `pop2`: ID of the second population
- `chromosome`: Chromosome/scaffold name  
- `window_pos_1`: First position of the genomic window
- `window_pos_2`: Last position of the genomic window
- `avg_wc_fst`: **Average Weir & Cockerham's FST for the window** (per SNP, not per site)
- `no_snps`: Total number of variable sites (SNPs) in the window

**Interpretation:**
- FST < 0.05: Little genetic differentiation
- 0.05 < FST < 0.15: Moderate differentiation
- 0.15 < FST < 0.25: Great differentiation
- FST > 0.25: Very great differentiation
- Conservation implications: High FST may indicate isolated populations requiring separate management

> [!NOTE]
> FST is calculated **per SNP** (variable sites only), not per site. This differs from π and Dxy which are calculated per site.

#### Absolute Divergence (Dxy)

**File**: `*_dxy.txt`

Dxy measures the average per site nucleotide divergence between two populations. Unlike FST, Dxy is an absolute measure and is not affected by within-population diversity.

**Key columns:**
- `pop1`: ID of the first population
- `pop2`: ID of the second population
- `chromosome`: Chromosome/scaffold name
- `window_pos_1`: First position of the genomic window
- `window_pos_2`: Last position of the genomic window
- `avg_dxy`: **Average per site nucleotide divergence for the window**
- `no_sites`: Total number of sites in the window that have at least one valid genotype in both populations
- `count_diffs`: Raw number of pairwise, cross-population differences between all genotypes (numerator of avg_dxy)
- `count_comparisons`: Raw number of non-missing pairwise cross-population comparisons (denominator of avg_dxy)
- `count_missing`: Raw number of missing pairwise cross-population comparisons

**Interpretation:**
- Dxy is always positive and increases with divergence time
- Unlike FST, Dxy is not affected by within-population diversity
- Useful for estimating divergence times between populations
- Higher Dxy indicates longer separation between populations

> [!TIP]
> When aggregating across windows, sum `count_diffs` and `count_comparisons` separately, then compute the ratio. Do not average `avg_dxy` values directly.

#### Populations File

**File**: `populations.txt`

This file maps individual samples to their populations and is automatically generated from your samplesheet.

**Format:**
```
Individual_ID    Population_ID
Wolf_001         Yellowstone
Wolf_002         Yellowstone
...
```

### VCFtools

<details markdown="1">
<summary>Output files</summary>

- `vcftools/`
  - `*_<population>.het`: Individual heterozygosity statistics for each population

</details>

[VCFtools](https://vcftools.github.io/) is used to calculate individual-level heterozygosity statistics within each population. The pipeline runs VCFtools with the `--het` flag on population-specific VCF files, generating separate output files for each population.

#### Individual Heterozygosity

**File**: `*_<population>.het`

**Columns:**
- `INDV`: Individual sample ID
- `O(HOM)`: Observed number of homozygous sites
- `E(HOM)`: Expected number of homozygous sites under Hardy-Weinberg equilibrium
- `N_SITES`: Total number of sites analyzed
- `F`: Inbreeding coefficient (Fis)

For detailed information about the statistics and their interpretation, please refer to the [VCFtools documentation](https://vcftools.github.io/man_latest.html#OUTPUT%20OPTIONS).

### MultiQC

<details markdown="1">
<summary>Output files</summary>

- `multiqc/`
  - `multiqc_report.html`: a standalone HTML file that can be viewed in your web browser.
  - `multiqc_data/`: directory containing parsed statistics from the different tools used in the pipeline.
  - `multiqc_plots/`: directory containing static images from the report in various formats.

</details>

[MultiQC](http://multiqc.info) is a visualization tool that generates a single HTML report summarizing workflow execution information. 

In the current version (v0.1.0-dev), the MultiQC report includes:
- **Software versions**: All tools used in the pipeline for reproducibility tracking
- **Workflow summary**: Pipeline parameters and execution settings

> [!NOTE]
> **PIXY results are not yet integrated into the MultiQC report.** You need to analyze the PIXY output files (`*_pi.txt`, `*_fst.txt`, `*_dxy.txt`) directly. Integration of PIXY statistics visualization into MultiQC is planned for future releases.

For more information about MultiQC reports, see <http://multiqc.info>.

### Pipeline information

<details markdown="1">
<summary>Output files</summary>

- `pipeline_info/`
  - Reports generated by Nextflow: `execution_report.html`, `execution_timeline.html`, `execution_trace.txt` and `pipeline_dag.dot`/`pipeline_dag.svg`.
  - Reports generated by the pipeline: `pipeline_report.html`, `pipeline_report.txt` and `software_versions.yml`. The `pipeline_report*` files will only be present if the `--email` / `--email_on_fail` parameter's are used when running the pipeline.
  - Reformatted samplesheet files used as input to the pipeline: `samplesheet.valid.csv`.
  - Parameters used by the pipeline run: `params.json`.

</details>

[Nextflow](https://www.nextflow.io/docs/latest/tracing.html) provides excellent functionality for generating various reports relevant to the running and execution of the pipeline. This will allow you to troubleshoot errors with the running of the pipeline, and also provide you with other information such as launch commands, run times and resource usage.
