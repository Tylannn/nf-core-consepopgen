/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    IMPORT MODULES / SUBWORKFLOWS / FUNCTIONS
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
include { MULTIQC                           } from '../modules/nf-core/multiqc/main'
include { PIXY                              } from '../modules/local/pixy/main'
include { BCFTOOLS_VIEW as BCFTOOLS_SPLIT   } from '../modules/nf-core/bcftools/view/main'
include { VCFTOOLS as VCFTOOLS_HET          } from '../modules/nf-core/vcftools/main'
include { paramsSummaryMap                  } from 'plugin/nf-schema'
include { paramsSummaryMultiqc              } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { softwareVersionsToYAML            } from '../subworkflows/nf-core/utils_nfcore_pipeline'
include { methodsDescriptionText            } from '../subworkflows/local/utils_nfcore_consepopgen_pipeline'

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    RUN MAIN WORKFLOW
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/

workflow CONSEPOPGEN {

    take:
    ch_samplesheet // channel: samplesheet read in from --input
    main:

    ch_versions = channel.empty()
    ch_multiqc_files = channel.empty()

    //
    // Prepare VCF channel for PIXY
    //
    ch_samplesheet
        .map { _meta, vcf, vcf_index -> 
            return [
                [id: vcf.baseName, vcf_file: vcf.name], 
                vcf, 
                vcf_index
            ]
        }
        .set { ch_vcf_for_pixy }

    //
    // Split VCF by population
    //
    ch_samplesheet
        .flatMap { meta, vcf, vcf_index ->
            meta.populations.collect { population, individuals ->
                def pop_meta = [
                    id: "${vcf.baseName}_${population}",
                    population: population
                ]
                def sample_ids = individuals.collect { individual -> individual.id }
                [pop_meta, vcf, vcf_index, sample_ids]
            }
        }
        .multiMap { pop_meta, vcf, vcf_index, sample_ids ->
            samples: [pop_meta.id, sample_ids]
            vcf_info: [pop_meta.id, pop_meta, vcf, vcf_index]
        }
        .set { ch_split }

    //
    // Create sample list files for each population
    //
    ch_split.samples
        .collectFile(storeDir: "${params.outdir}/populations/samples") { id, sample_ids ->
            ["${id}_samples.txt", sample_ids.join('\n') + '\n']
        }
        .map { file -> [file.baseName.replaceAll('_samples$', ''), file] }
        .set { ch_sample_files }

    //
    // Combine VCF info with corresponding sample files, then run BCFTOOLS_SPLIT
    //
    ch_split.vcf_info
        .combine(ch_sample_files, by: 0)
        .map { _id, pop_meta, vcf, vcf_index, samples_file ->
            [pop_meta, vcf, vcf_index, samples_file]
        }
        .multiMap { pop_meta, vcf, vcf_index, samples_file ->
            // Separate inputs for BCFTOOLS_SPLIT
            vcf: [pop_meta, vcf, vcf_index]
            samples: samples_file
        }
        .set { ch_bcftools_input }

    BCFTOOLS_SPLIT (
        ch_bcftools_input.vcf,
        [],  // regions
        [],  // targets
        ch_bcftools_input.samples
    )

    ch_versions = ch_versions.mix(BCFTOOLS_SPLIT.out.versions.first())

    //
    // Create populations file from samplesheet
    //
    ch_samplesheet
        .collectFile(
            name: "populations.txt",
            storeDir: "${params.outdir}/pixy"
        ) { meta, _vcf, _vcf_index ->
            // Flatten the populations map to create individual-population pairs
            def lines = ""
            meta.populations.each { population, individuals ->
                individuals.each { individual ->
                    lines += "${individual.id}\t${population}\n"
                }
            }
            return lines
        }
        .set { ch_populations_file }

    //
    // Run PIXY analysis
    //
    PIXY (
        ch_vcf_for_pixy,
        ch_populations_file,
        []  // bed_file optional
    )

    ch_versions = ch_versions.mix(PIXY.out.versions)

    //
    // Run VCFTOOLS_HET to calculate heterozygosity (Fis) for each population
    //
    VCFTOOLS_HET (
        BCFTOOLS_SPLIT.out.vcf,
        [],  // bed file optional
        []   // diff_variant_file optional
    )

    ch_versions = ch_versions.mix(VCFTOOLS_HET.out.versions.first())

    //
    // Collate and save software versions
    //
    softwareVersionsToYAML(ch_versions)
        .collectFile(
            storeDir: "${params.outdir}/pipeline_info",
            name: 'nf_core_'  +  'consepopgen_software_'  + 'mqc_'  + 'versions.yml',
            sort: true,
            newLine: true
        ).set { ch_collated_versions }


    //
    // MODULE: MultiQC
    //
    ch_multiqc_config        = channel.fromPath(
        "$projectDir/assets/multiqc_config.yml", checkIfExists: true)
    ch_multiqc_custom_config = params.multiqc_config ?
        channel.fromPath(params.multiqc_config, checkIfExists: true) :
        channel.empty()
    ch_multiqc_logo          = params.multiqc_logo ?
        channel.fromPath(params.multiqc_logo, checkIfExists: true) :
        channel.empty()

    summary_params      = paramsSummaryMap(
        workflow, parameters_schema: "nextflow_schema.json")
    ch_workflow_summary = channel.value(paramsSummaryMultiqc(summary_params))
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_workflow_summary.collectFile(name: 'workflow_summary_mqc.yaml'))
    ch_multiqc_custom_methods_description = params.multiqc_methods_description ?
        file(params.multiqc_methods_description, checkIfExists: true) :
        file("$projectDir/assets/methods_description_template.yml", checkIfExists: true)
    ch_methods_description                = channel.value(
        methodsDescriptionText(ch_multiqc_custom_methods_description))

    ch_multiqc_files = ch_multiqc_files.mix(ch_collated_versions)
    ch_multiqc_files = ch_multiqc_files.mix(
        ch_methods_description.collectFile(
            name: 'methods_description_mqc.yaml',
            sort: true
        )
    )

    MULTIQC (
        ch_multiqc_files.collect(),
        ch_multiqc_config.toList(),
        ch_multiqc_custom_config.toList(),
        ch_multiqc_logo.toList(),
        [],
        []
    )

    emit:multiqc_report = MULTIQC.out.report.toList() // channel: /path/to/multiqc_report.html
    versions       = ch_versions                 // channel: [ path(versions.yml) ]

}

/*
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
    THE END
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
*/
