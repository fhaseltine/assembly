"""Snakefile

Processes input fastq files to create consensus genomes and their associated summary statistics for the Seattle Flu Study.

To run:
    $ snakemake

Basic steps:
    1. Trim raw fastq's with Trimmomatic
    2. Map trimmed reads to each reference genomes in the reference panel using bowtie2 # This step may change with time
    3. Remove duplicate reads using Picard
    4. Call SNPs using varscan
    5. Use SNPs to generate full consensus genomes for each sample x reference virus combination
    6. Compute summary statistics for each sample x refernce virus combination

Adapted from Louise Moncla's illumina pipeline for influenza snp calling:
https://github.com/lmoncla/illumina_pipeline
"""
import glob
from config import CONFIG

all_sample_names = [ f.split('.')[0] for f in  glob.glob(CONFIG['fastq_directory']) ]
all_references = [ v for v in  glob.glob(CONFIG['reference_viruses']) ]

rule all:
    input:
        consensus_genome = expand("consensus_genomes/{reference}/{sample}.consensus.fasta",
               sample=all_sample_names,
               reference=all_references)
        # summary_statistics = ()

rule trim_fastqs:
    input:
        fastq = "test_data/{sample}.fastq.gz"
    output:
        trimmed_fastq = "{sample}.trimmed.fastq"
    params:
        paired_end = "SE",
        adapters = "path/to/adapters",
        illumina_clip = "1:30:10",
        window_size = "",
        trim_qscore = "",
        minimum_length = ""
    shell:
        """
        java \-jar /usr/local/bin/Trimmomatic-0.36/trimmomatic-0.36.jar \
            {params.paired_end} \
            {input.fastq} \
            {output.trimmed_fastq} \
            ILLUMINACLIP:{params.adapters}:{params.illumina_clip} \
            SLIDINGWINDOW:{params.window_size}:{params.trim_qscore} \
            MINLEN:{params.minimum_length}
        """

rule map:
    input:
        fastq = rules.trim_fastqs.output.trimmed_fastq,
        reference = ""
    output:
        sorted_sam_file = ""
    params:
    shell:
        """
        bowtie2 \
            -x {input.reference} \
            -U {input.fastq} \
            -S tmp/tmp.sam \
            --local
        samtools view \
            -bS tmp/tmp.sam | \
            samtools sort | \
            samtools view -h > {output.sorted_sam_file}
        """

rule remove_duplicate_reads:
    input:
        sorted_sam = rules.map.output.sorted_sam_file
    output:
        deduped = ""
    params:
        picard_params = "file.params.txt"
    shell:
        """
        java -jar /usr/local/bin/picard.jar \
            MarkDuplicates \
            I={params.input} \
            O={params.output} \
            REMOVE_DUPLICATES=true \
            M={params.picard_params}
        """

rule call_snps:
    input:
        deduped_sam = rules.remove_duplicate_reads.output.deduped,
        reference = ""
    output:
        vcf = ""
    params:
        depth = "1000000",
        min_cov = "",
        snp_qual_threshold = "",
        snp_frequency = "",
    shell:
        """
        samtools mpileup \
            -d {params.depth} \
            {input.deduped_sam} > process/tmp.pileup \
            -f {input.reference}
        java -jar /usr/local/bin/VarScan.v2.3.9.jar mpileup2snp \
            process/tmp.pileup \
            --min-coverage {params.min_coverage} \
            --min-avg-qual {params.snp_qual_threshold} \
            --min-var-freq {params.snp_frequency} \
            --strand-filter 1 \
            --output-vcf 1 > {output.vcf}
        """
