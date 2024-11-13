import os
configfile: "workflow/config/config.yaml"

query_path = config["query_path"]
samples_path = config["samples_path"]
FASTP_OUT_PATH = "fastp_out"
SPADES_OUT_PATH = "spades_out"
FILTERED_GENOME_OUT_PATH = "genome_upper_L1000C10"
BUSCO_OUT_PATH = "busco_output"
MEGAHIT_OUT_PATH = "megahit_out"
QUAST_OUT_PATH = "quast_out"
PROKKA_OUT_PATH = "prokka_out"
MMSEQ2_OUT_PATH = "mmseq2_out"
SEQTK_OUT_PATH_list = "seqtk_ls"
SEQTK_OUT_PATH_gene = "seqtk_gene"
DBCAN3_OUT_PATH = "dbcan_out"
METABAT_OUT_PATH = "metabat_out"
SAMPLES = os.listdir(samples_path)
QUERY_SAMPLES = os.listdir(query_path)

onerror:
    print("error!")

onsuccess:
    print("success!")

rule all:
    input:
        # expand(MEGAHIT_OUT_PATH + "/{sample}",sample = SAMPLES),
        # expand(PROKKA_OUT_PATH + "/{sample}",sample = SAMPLES),
        expand(QUAST_OUT_PATH + "/{sample}/{sample}.html", sample=SAMPLES),
        # expand(MMSEQ2_OUT_PATH + "/{sample}.n.m8",sample = SAMPLES),
        expand(DBCAN3_OUT_PATH + "/{sample}.fasta",sample = SAMPLES),
        expand(METABAT_OUT_PATH + "/{sample}", sample=SAMPLES),

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
        "base"
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
    

rule quast:
    input:
        rules.megahit.output.r2
    output:
        QUAST_OUT_PATH + "/{sample}/{sample}.html"
    shell:
        "quast.py -i {input} -o {output}"



rule prokka:
    input:
        rules.megahit.output.r2
    output:
         r1 = directory(PROKKA_OUT_PATH + "/{sample}"),
         r2 = PROKKA_OUT_PATH + "/{sample}/{sample}.ffn",
         r3 = PROKKA_OUT_PATH + "/{sample}/{sample}.faa",
    threads: 48
    params:
        prefix = "{sample}"
    conda:
        "Prokka"
    shell:
         "prokka --outdir {output} --prefix {params.prefix} --locustag {params.prefix} --centre P "
          "--addgenes --addmrna --metagenome --evalue 1e-10 --cpus {threads: 48} --metagenome {input}"

rule mmseq2:
    input:
        r1 = rules.prokka.output.r2
        # r2 = query_path + "/{query_sample}.fasta",
    output:
        MMSEQ2_OUT_PATH + "/{sample}.n.ls"
    shell:
        "mmseqs easy-search query_sequence/query.fasta {input.r1}"
        "{output} tmp --search-type 3;"

rule seqtk:
    input:
        r1 = rules.prokka.output.r2,
        # r2 = rules.prokka.output.r3,
        r2 = rules.mmseq2.output,
    output:
        # r1 = SEQTK_OUT_PATH_list + "/{sample}.n.ls",
        SEQTK_OUT_PATH_gene + "/{sample}.n.fa",
    shell:
        "seqtk subseq {input.r1} {input.r2} > {output}"


rule run_dbcan:
    input:
        rules.seqtk.output
    output:
        DBCAN3_OUT_PATH + "/{sample}.fasta",
    shell:
        "run_dbcan -i {input} -o {output}"

rule metabat:
    input:
        rules.megahit.output.r2
    output:
        directory( METABAT_OUT_PATH + "/{sample}")
    shell:
        "matebat -i {input} -o {output}"

