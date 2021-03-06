from Bio import SeqIO
from Bio import Phylo

if config.get("outdir"):
    config["outdir"] = config["outdir"].rstrip("/")
else:
    config["outdir"] = "analysis"

config["query_sequences"]=[i for i in config["query_sequences"].split(',')]

rule all:
    input:
        expand(config["outdir"] + "/temp/expanded_query/{query}.fasta", query=config["query_sequences"]),
        config["outdir"] + "/lineage_report.csv"

rule expand_query_fasta:
    input:
        config["query_fasta"]
    params:
        config["query_sequences"]
    output:
        expand(config["outdir"] + '/temp/expanded_query/{query}.fasta',query=config["query_sequences"])
    run:
        for record in SeqIO.parse(input[0],"fasta"):
            with open(config["outdir"] + f'/temp/expanded_query/{record.id}.fasta',"w") as fw:
                fw.write(f">{record.id}\n{record.seq}\n")

rule profile_align_query:
    input:
        aln = config["representative_aln"],
        query = config["outdir"] + '/temp/expanded_query/{query}.fasta'
    output:
        config["outdir"] + "/temp/query_alignments/{query}.aln.fasta"
    shell:
        "mafft-profile {input.aln:q} {input.query:q} > {output:q}"

rule iqtree_with_guide_tree:
    input:
        profile_aln = rules.profile_align_query.output,
        guide_tree = config["guide_tree"]
    output:
        config["outdir"] + "/temp/query_alignments/{query}.aln.fasta.treefile"
    run:
        iqtree_check = output[0].rstrip("treefile") + "iqtree"
        if os.path.exists(iqtree_check):
            print("Tree exists, going to rerun", iqtree_check)
            shell("iqtree -s {input.profile_aln:q} -bb 1000 -m HKY -g {input.guide_tree:q} -o 'outgroup_A' -redo")
        else:
            print("Tree doesn't exist here", output[0])
            shell("iqtree -s {input.profile_aln:q} -bb 1000 -m HKY -g {input.guide_tree:q} -o 'outgroup_A'")

rule to_nexus:
    input:
        rules.iqtree_with_guide_tree.output
    output:
        config["outdir"] + "/temp/query_alignments/{query}.nexus.tree"
    run:
        Phylo.convert(input[0], 'newick', output[0], 'nexus')

rule assign_lineage:
    input:
        tree = rules.to_nexus.output,
    params:
        query = "{query}"
    output:
        config["outdir"] + "/temp/reports/{query}.txt"
    run:
        shell_start = f"clusterfunk subtype  --separator '_' --index 1 --collapse_to_polytomies --taxon '{params.query}'"
        shell(shell_start + " --input {input.tree:q} --output {output:q}")
        
rule gather_reports:
    input:
        reports = expand(config["outdir"] + "/temp/reports/{query}.txt", query=config["query_sequences"]),
        key=config["key"]
    output:
        config["outdir"] + "/lineage_report.csv"
    run:
        key_dict = {}
        with open(input.key, "r") as f:
            for l in f:
                l = l.rstrip('\n')
                taxon,key = l.split(",")
                key_dict[key] = taxon

        fw=open(output[0],"w")

        fw.write("taxon,lineage\n")
        for lineage_report in input.reports:
            
            with open(lineage_report, "r") as f:
                for l in f:
                    l=l.rstrip()
                    tokens = l.split(",")
                    lineage = tokens[1]
                    taxon = key_dict[tokens[0]]
                    fw.write(f"{taxon},{lineage}\n")
        fw.close()

