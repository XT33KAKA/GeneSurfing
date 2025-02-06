# Snakefile
import os

configfile: "workflow/config/config.yaml"
sample_path = config["samples_path"]
FASTP_OUT_PATH = "1.fastp_out"
MEGAHIT_OUT_PATH = "2.assembly"
QUAST_OUT_PATH = "3.assembly_assessment"
PROKKA_OUT_PATH = "4.Gene_annote"
MMSEQ2_OUT_PATH = "5.MMSEQS2_Align_file"
SAMPLES = os.listdir(sample_path)

onsuccess:
    print("Your pipeline has been completed successfully!")
    
onerror:
    print("Your process has encountered an error!")

rule all:
    input:
        expand(QUAST_OUT_PATH + "/{sample}", sample=SAMPLES),
        expand(PROKKA_OUT_PATH + "/{sample}", sample=SAMPLES),
        expand(MMSEQ2_OUT_PATH + "/{sample}.search_result.txt", sample=SAMPLES),
        expand("6.Sequence_get/Extracted_DNA_Sequences/{sample}.n.fa", sample=SAMPLES),
        expand("6.Sequence_get/Extracted_Protein_Sequences/{sample}.p.fa", sample=SAMPLES),
        expand("6.Sequence_get/Extracted_Sequence_IDs/{sample}.n.ls", sample=SAMPLES)

rule fastp:
    input:
        r1 = sample_path + "/{sample}/{sample}.R1.raw.fastq.gz",
        r2 = sample_path + "/{sample}/{sample}.R2.raw.fastq.gz",
    output:
        r1 = FASTP_OUT_PATH + "/{sample}/{sample}_paired_1.fq.gz",
        r2 = FASTP_OUT_PATH + "/{sample}/{sample}_paired_2.fq.gz",
        json = temp(FASTP_OUT_PATH + "/{sample}/{sample}_fastp.json"),
        html = FASTP_OUT_PATH + "/{sample}/{sample}_fastp.html",
    priority: 50
    threads: 10
    params:
        unqualified = config['unqualified'],
        read_length = config['read_length']
    log:
        "logs/fastp/{sample}.log"
    conda:
        "base"
    benchmark:
        "benchmarks/{sample}.fastp.benchmark.txt"
    shell:
        """
        fastp -i {input.r1} -I {input.r2} \
              -o {output.r1} -O {output.r2} \
              -j {output.json} -h {output.html} \
              -w {threads} -q 20 -u {params.unqualified} \
              -n 3 -l {params.read_length} -5 -3 &> {log}
        """

rule megahit:
    input:
        r1 = rules.fastp.output.r1,
        r2 = rules.fastp.output.r2,
    output:
        MEGAHIT_OUT_PATH + "/{sample}/{sample}.contigs.fa",
    priority: 40
    params:
        prefix = "{sample}"
    threads: 24
    conda:
        "base"
    benchmark:
        "benchmarks/{sample}.spades.benchmark.txt"
    shell:
        **"""
        megahit -1 {input.r1} -2 {input.r2} \
                -t {threads} \
                -o {MEGAHIT_OUT_PATH}/{wildcards.sample} \
                --out-prefix {params.prefix}
        """**

rule quast:
    input:
        rules.megahit.output
    output:
        directory(QUAST_OUT_PATH + "/{sample}")
    priority: 30
    params:
        contig = 500
    threads: 24
    conda:
        "quast_env"
    benchmark:
        "benchmarks/{sample}.quast.benchmark.txt"
    shell:
        """
        quast --threads {threads} \
              -o {output} \
              --min-contig {params.contig} \
              {input}
        """

rule prokka:
    input:
        rules.megahit.output
    output:
        ffn = PROKKA_OUT_PATH + "/{sample}/{sample}.ffn"
    priority: 30
    threads: 48
    params:
        prefix = "{sample}"
    conda:
        "Prokka"
    benchmark:
        "benchmarks/{sample}.prokka.benchmark.txt"
    shell:
        """
        prokka --outdir {PROKKA_OUT_PATH}/{wildcards.sample} \
               --prefix {params.prefix} \
               --locustag {params.prefix} \
               --centre P \
               --addgenes \
               --addmrna \
               --metagenome \
               --evalue 1e-10 \
               --cpus {threads} \
               {input}
        """

rule mmseqs2:
    input:
        r1 = "query_sequence/query.fasta",
        r2 = PROKKA_OUT_PATH + "/{sample}/{sample}.ffn",  # 显式声明输入路径
    output:
        MMSEQ2_OUT_PATH + "/{sample}.search_result.txt"
    priority: 10
    conda:
        "base"
    benchmark:
        "benchmarks/{sample}.mmseqs2.benchmark.txt"
    shell:
        """
        mmseqs easy-search {input.r1} {input.r2} \
               {output} tmp \
               --threads 4 \
               --search-type 3
        """

rule process_search_results:
    input:
        search_result = MMSEQ2_OUT_PATH + "/{sample}.search_result.txt",
    output:
        seq_n_fa = "6.Sequence_get/Extracted_DNA_Sequences/{sample}.n.fa",
        seq_p_fa = "6.Sequence_get/Extracted_Protein_Sequences/{sample}.p.fa",
        seq_n_ls = "6.Sequence_get/Extracted_Sequence_IDs/{sample}.n.ls",
    params:
        ffn = PROKKA_OUT_PATH + "/{sample}/{sample}.ffn",
        faa = PROKKA_OUT_PATH + "/{sample}/{sample}.faa"
    benchmark:
        "benchmarks/{sample}.seqtk.benchmark.txt"
    shell:
        """
        mkdir -p 6.Sequence_get/Extracted_DNA_Sequences \
                 6.Sequence_get/Extracted_Protein_Sequences \
                 6.Sequence_get/Extracted_Sequence_IDs

        # 提取序列ID
        awk '{{print $2}}' {input.search_result} | uniq > {output.seq_n_ls}

        # 提取DNA序列
        seqtk subseq {params.ffn} {output.seq_n_ls} > {output.seq_n_fa}

        # 提取蛋白序列
        seqtk subseq {params.faa} {output.seq_n_ls} > {output.seq_p_fa}
        """
