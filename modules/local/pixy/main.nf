// TODO nf-core: If in doubt look at other nf-core/modules to see how we are doing things! :)
//               https://github.com/nf-core/modules/tree/master/modules/nf-core/
//               You can also ask for help via your pull request or on the #modules channel on the nf-core Slack workspace:
//               https://nf-co.re/join
// TODO nf-core: A module file SHOULD only define input and output files as command-line parameters.
//               All other parameters MUST be provided using the "task.ext" directive, see here:
//               https://www.nextflow.io/docs/latest/process.html#ext
//               where "task.ext" is a string.
//               Any parameters that need to be evaluated in the context of a particular sample
//               e.g. single-end/paired-end data MUST also be defined and evaluated appropriately.
// TODO nf-core: Software that can be piped together SHOULD be added to separate module files
//               unless there is a run-time, storage advantage in implementing in this way
//               e.g. it's ok to have a single module for bwa to output BAM instead of SAM:
//                 bwa mem | samtools view -B -T ref.fasta
// TODO nf-core: Optional inputs are not currently supported by Nextflow. However, using an empty
//               list (`[]`) instead of a file can be used to work around this issue.

process PIXY {
    tag "$meta.id"
    label 'process_single'

    // TODO nf-core: See section in main README for further information regarding finding and adding container addresses to the section below.
    conda "${moduleDir}/environment.yml"
    container "${workflow.containerEngine == 'singularity' && !task.ext.singularity_pull_docker_container
        ? 'oras://community.wave.seqera.io/library/htslib_pixy:54543b385050f8cd'
        : 'community.wave.seqera.io/library/htslib_pixy:25b99ae8520fa852'}"

    input:
    tuple val(meta), path(vcf), path(vcf_index)
    path populations_file
    path bed_file

    output:
    tuple val(meta), path("*.txt"), emit: stats
    path "versions.yml", emit: versions

    when:
    task.ext.when == null || task.ext.when

    script:
    def args = task.ext.args ?: ''
    def prefix = task.ext.prefix ?: "${meta.id}"
    def populations = populations_file ? "--populations $populations_file" : ""
    def bed = bed_file ? "--bed_file $bed_file" : "--window_size 10000"
    """
    # Workaround for pixy issue with symlinked VCF files:
    # When index timestamp is older than VCF, pixy fail to read the file
    # Synchronizing timestamps prevents this issue
    touch ${vcf_index}

    pixy \\
        --stats pi fst dxy \\
        --vcf $vcf \\
        $populations \\
        $bed \\
        --n_cores $task.cpus \\
        --output_folder . \\
        --output_prefix $prefix \\
        $args

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        pixy: \$(pixy --version 2>&1 | tail -1 | sed 's/version //')
    END_VERSIONS
    """

    stub:
    """
    touch pi.txt
    touch dxy.txt
    touch fst.txt

    cat <<-END_VERSIONS > versions.yml
    "${task.process}":
        pixy: \$(echo "2.0.0.beta13")
    END_VERSIONS
    """
}
