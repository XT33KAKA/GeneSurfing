import os
configfile: "workflow/config/config.yaml"

samples_path = config["samples_path"]
FASTP_OUT_PATH = "fastp_out"
SPADES_OUT_PATH = "spades_out"
FILTERED_GENOME_OUT_PATH = "genome_upper_L1000C10"
BUSCO_OUT_PATH = "busco_output"
MEGAHIT_OUT_PATH = "megahit_out"

SAMPLES = os.listdir(samples_path)

onerror:
    print("error!")

onsuccess:
    print("success!")


# module fastp_m:
#     snakefile: "modules/fastp.smk"
#     config: config

# use rule fastp from fastp_m as my_fastp



rule all:
    input:
        expand(MEGAHIT_OUT_PATH + "/{sample}",sample = SAMPLES),


rule fastp:
    input:
        r1 = samples_path + "/{sample}/{sample}.R1.raw.fastq.gz",
        r2 = samples_path + "/{sample}/{sample}.R1.raw.fastq.gz",
    output:
        r1 = FASTP_OUT_PATH + "/{sample}/{sample}_paired_1.fq.gz",
        r2 = FASTP_OUT_PATH + "/{sample}/{sample}_paired_2.fq.gz",
        json= ensure(temp(FASTP_OUT_PATH + "/{sample}/{sample}_fastp.json"),non_empty=True),
        html = ensure(FASTP_OUT_PATH + "/{sample}/{sample}_fastp.html", non_empty=True), # Often, it is a good idea to combine ensure annotations with retry definitions, e.g. for retrying upon invalid checksums or empty files.
    log:
        "logs/fastp/{sample}.log"
    threads: 8
    params:
        unqualified=config['unqualified'],
        read_length=config['read_length']
    conda:
        "SG_assembly"
    shell:
        "fastp -i {input.r1} -I {input.r2} -o {output.r1} -O {output.r2} "
        "-j {output.json} -h {output.html} -w {threads} "
        "-q 20 " # the quality value that a base is qualified
        "-u {params.unqualified} " # how many percents of bases are allowed to be unqualified (0~100).
        "-n 3 " # number of N allowed
        "-l {params.read_length} " # reads shorter than length_required will be discarded, particularly those with adapter.
        "-5 " # enable trimming in 5' ends.
        "-3 " # enable trimming in 3' ends.
        "&> {log}"


rule megahit:
    input:
        r1 = rules.fastp.output.r1,
        r2 = rules.fastp.output.r2,
    output:
        r1 = directory(MEGAHIT_OUT_PATH + "/{sample}"),
        r2 = MEGAHIT_OUT_PATH+ "/{sample}/{sample}.contigs.fa",
    params:
        prefix = "{sample}"
    threads: 24
    shell:
        "megahit -1 {input.r1} {input.r2} -t {threads} -o {output.r1} --out-prefix {params.prefix}"
    


