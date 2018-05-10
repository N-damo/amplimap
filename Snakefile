import os, shutil

#version and title
from amplimap.version import __title__, __version__

#list of rules that don't run on the cluster
localrules: all, \
    start_analysis, check_python_packages, check_test_variant, check_target_overlaps, check_sample_info, \
    copy_probes, copy_snps, copy_targets_bed, convert_targets_csv,
    link_tagged_bais_1, link_tagged_bais_2, link_tagged_bams, link_unmapped_bams, \
    convert_mipgen_probes, convert_heatseq_probes, \
    link_reads, merge_targets, stats_samples_agg, stats_reads_agg_new, stats_alignment_agg, coverage_agg, stats_replacements_agg, \
    variants_merge, variants_summary, variants_summary_excel

#find samples
if os.path.isdir('bams_in'):
    SAMPLES, = glob_wildcards("bams_in/{sample_full}.bam")
    config['general']['lanes_actual'] = 1
elif os.path.isdir('tagged_bams_in'):
    SAMPLES, = glob_wildcards("tagged_bams_in/{sample_full}.bam")
    config['general']['lanes_actual'] = 1
elif os.path.isdir('unmapped_bams_in'):
    SAMPLES, = glob_wildcards("unmapped_bams_in/{sample_full}.bam")
    config['general']['lanes_actual'] = 1
else:
    #check that samples for R1 and R2 agree
    samples_with_lane1, = glob_wildcards("reads_in/{sample_with_lane}_R1_001.fastq.gz") 
    samples_with_lane2, = glob_wildcards("reads_in/{sample_with_lane}_R1_001.fastq.gz") 
    samples_with_lane1.sort()
    samples_with_lane2.sort()
    assert samples_with_lane1 == samples_with_lane2, 'Did not find R1 and R2 fastq files for all samples!'

    #now get list of samples and lanes
    SAMPLES_FULL, LANES = glob_wildcards("reads_in/{sample_full}_L{lane}_R1_001.fastq.gz") 

    #make unique
    SAMPLES = list(set(SAMPLES_FULL))

    #auto-detect number of input lanes
    if config['general']['lanes'] == 0:
        config['general']['lanes_actual'] = max((int(l) for l in LANES))
    else:
        config['general']['lanes_actual'] = config['general']['lanes']

#sort and make sure we don't use "Undetermined" sample
SAMPLES.sort()
SAMPLES = [s for s in SAMPLES if s != 'Undetermined_S0']

#versions
VERSIONS = {}
VERSIONS['_amplimap'] = str(__version__)
VERSIONS['Snakefile'] = str(os.path.getmtime(os.path.join(config['general']['basedir'], 'Snakefile')))
VERSIONS['parse_reads'] = str(os.path.getmtime(os.path.join(config['general']['amplimap_dir'], 'parse_reads.py')))
VERSIONS['pileup'] = str(os.path.getmtime(os.path.join(config['general']['amplimap_dir'], 'pileup.py')))
VERSIONS['stats_alignment'] = str(os.path.getmtime(os.path.join(config['general']['amplimap_dir'], 'stats_alignment.py')))
VERSIONS['coverage'] = str(os.path.getmtime(os.path.join(config['general']['amplimap_dir'], 'coverage.py')))
VERSIONS['simulate'] = str(os.path.getmtime(os.path.join(config['general']['amplimap_dir'], 'simulate.py')))
VERSIONS['variants'] = str(os.path.getmtime(os.path.join(config['general']['amplimap_dir'], 'variants.py')))

#helper function to load module
def load_module_command(name, config):
    if 'modules' in config and name in config['modules'] and len(config['modules'][name]) > 0:
        return 'module load {};'.format(config['modules'][name])
    else:
        return ''

#helper to get paths for genome
def get_path(name, my_config = None, default = None):
    if my_config is None:
        my_config = config

    if not my_config['general']['genome_name'] in my_config['paths']:
        raise Exception('Could not find list of paths for genome_name: "{}".'.format(my_config['general']['genome_name']))

    if not name in my_config['paths'][my_config['general']['genome_name']]:
        if default is None:
            raise Exception('\nCould not find path for "%s"! Please specify this in your configuration file under \npaths:\n  %s:\n    %s: /my/path\n' % (
                name, my_config['general']['genome_name'], name))
        else:
            return default
    else:
        return my_config['paths'][my_config['general']['genome_name']][name]

#helper to figure out which index to use
#used with False to get actual parameter for tool call, and with True to get path for Snakemake
def get_alignment_index_filename(real_path):
    if config['align']['aligner'] == 'naive':
        my_path = get_path('fasta')
    else:
        my_path = get_path(config['align']['aligner'])

    #masked index name
    if config['general']['mask_bed'] and len(config['general']['mask_bed']) > 0:
        if config['align']['aligner'] in ['naive', 'bwa', 'bowtie2']:
            my_path = 'masked_reference/genome.fa'
        elif config['align']['aligner'] == 'star':    
            my_path = 'masked_reference/star/'
        else:
            raise Exception('unexpected aligner')

    #add extension to index name to get actual filename
    if real_path:
        if config['align']['aligner'] == 'naive':
            return my_path+'.fai'
        elif config['align']['aligner'] == 'bwa':    
            return my_path+'.bwt'
        elif config['align']['aligner'] == 'bowtie2':    
            return my_path+'.1.bt2'
        elif config['align']['aligner'] == 'star':    
            return my_path+'/Genome'
        else:
            raise Exception('unexpected aligner')
    else:
        return my_path

##### ALL-RULE (DEFAULT = FIRST RULE)
rule all:
    input:
        "analysis/reads_parsed/stats_samples.csv",
        "analysis/reads_parsed/stats_reads.csv" if not config['pileup']['no_probe_data'] else [],
        "analysis/stats_alignment/stats_alignment.csv" if not config['pileup']['no_probe_data'] else [],

##### CHECKING
rule start_analysis:
    output:
        #force this to be 'analysis' right now
        versions = "analysis/versions.yaml",
        samples = "analysis/samples.yaml",
        file_hashes = "analysis/file_hashes.yaml",
    run:
        import yaml

        with open(output['versions'], 'w') as f:
            yaml.dump(VERSIONS, f, default_flow_style=False)

        with open(output['samples'], 'w') as f:
            yaml.dump(SAMPLES, f, default_flow_style=False)

        import amplimap.reader
        with open(output['file_hashes'], 'w') as f:
            yaml.dump(amplimap.reader.get_file_hashes(), f, default_flow_style=False)

rule check_python_packages:
    input:
        rules.start_analysis.output
    output:
        touch("checks/check_python_packages.done")
    run:
        import six
        import numpy
        import pdb
        import Bio
        import pandas
        import argparse
        import interlap
        import pysam, pyfaidx, distance
        import umi_tools
        print('Python libraries checked.')

rule check_target_overlaps:
    input:
        targets = "{analysis_dir}/targets.bed"
    output:
        touch("{analysis_dir}/checks/check_target_overlaps.done")
    run:
        import amplimap.reader
        amplimap.reader.read_targets(input['targets'], check_overlaps=True, reference_type = config['general']['reference_type'], file_type = 'bed')
        print(input['targets'], 'checked for overlaps.')

rule check_sample_info:
    version: VERSIONS['parse_reads']
    input:
        rules.check_python_packages.output,
        sample_info = "sample_info.csv",
    output:
        touch("{analysis_dir}/checks/check_sample_info.done")
    run:
        import amplimap.reader
        amplimap.reader.read_sample_info(input['sample_info'])
    
##### target rules
rule coverages:
    input:
        rules.all.input,
        "analysis/bam/coverage/coverage_full.csv",
        "analysis/umi_dedup/coverage/coverage_full.csv" if not config['general']['ignore_umis'] else []

rule pileups_only:
    input:
        rules.check_python_packages.output, #enforce packages (and thus also config) check here
        "analysis/pileup/pileups_long.csv" if os.path.isfile("targets.bed") or os.path.isfile("targets.csv") else [],
        "analysis/pileup/target_coverage_long.csv" if os.path.isfile("targets.bed") or os.path.isfile("targets.csv") else [],
        "analysis/pileup_snps/target_snps_pileups_long.csv" if os.path.isfile("snps.txt") else []

rule pileups:
    input:
        rules.all.input,
        rules.pileups_only.input,

rule variants:
    input:
        rules.all.input,
        "analysis/variants_raw/variants_summary.csv",
        "analysis/variants_raw/variants_summary_filtered.csv",

rule variants_umi:
    input:
        rules.all.input,
        "analysis/variants_umi/variants_summary.csv",
        "analysis/variants_umi/variants_summary_filtered.csv"
        
rule variants_low_frequency:
    input:
        rules.all.input,
        "analysis/variants_low_frequency/variants_summary.csv",
        "analysis/variants_low_frequency/variants_summary_filtered.csv"

rule bams:
    input:
        rules.all.input,
        expand("analysis/bam/{sample_full}.bam", sample_full = SAMPLES),
        expand("analysis/bam/{sample_full}.bam.bai", sample_full = SAMPLES)

rule consensus_bams:
    input:
        rules.all.input,
        expand("analysis/bam_consensus/{sample_full}_CONSENSUS.bam", sample_full = SAMPLES),
        expand("analysis/bam_consensus/{sample_full}_CONSENSUS.bam.bai", sample_full = SAMPLES)

rule dedup_bams:
    input:
        rules.all.input,
        expand("analysis/umi_dedup/{sample_full}.bam", sample_full = SAMPLES),
        expand("analysis/umi_dedup/{sample_full}.bam.bai", sample_full = SAMPLES)

rule test_variants:
    input:
        "test__{search}_{replace}_{percentage}/stats_replacements/stats_replacements.csv",
        "test__{search}_{replace}_{percentage}/variants_raw/variants_summary_filtered.csv"
    output:
        touch("test__{search}_{replace}_{percentage}/test_variants.done")

rule test_pileups:
    input:
        "test__{search}_{replace}_{percentage}/stats_replacements/stats_replacements.csv",
        "test__{search}_{replace}_{percentage}/pileup/pileups_long.csv"
    output:
        touch("test__{search}_{replace}_{percentage}/test_pileups.done")

##### TARGET CONVERSION
rule copy_targets_bed:
    input:
        targets = "targets.bed"
    output:
        targets = "{analysis_dir}/targets.bed"
    run:
        print('Reading', input['targets'])

        import amplimap.reader
        targets = amplimap.reader.read_targets(input['targets'], reference_type = config['general']['reference_type'], file_type = 'bed')        
        print(input['targets'], 'checked.')

        amplimap.reader.write_targets_bed(output['targets'], targets)
        print(len(targets), 'written to', output['targets'])

rule convert_targets_csv:
    input:
        targets = "targets.csv"
    output:
        targets = "{analysis_dir}/targets.bed"
    run:
        print('Reading', input['targets'])

        import amplimap.reader
        targets = amplimap.reader.read_targets(input['targets'], reference_type = config['general']['reference_type'], file_type = 'csv')        
        print(input['targets'], 'checked.')

        amplimap.reader.write_targets_bed(output['targets'], targets)
        print(len(targets), 'written to', output['targets'])

##### PROBE CSV CONVERSION
rule copy_probes:
    version: VERSIONS['parse_reads']
    input:
        rules.check_python_packages.output,
        probes = "probes.csv"
    output:
        probes = "{analysis_dir}/probes.csv"
    run:
        import amplimap.reader
        design = amplimap.reader.read_new_probe_design(input['probes'], reference_type = config['general']['reference_type'])
        design.to_csv(output['probes'], index=False)

rule convert_mipgen_probes:
    version: VERSIONS['parse_reads']
    input:
        rules.check_python_packages.output,
        mipgen = "probes_mipgen.csv"
    output:
        probes = "{analysis_dir}/probes.csv"
    run:
        import amplimap.reader
        design = amplimap.reader.read_and_convert_mipgen_probes(input['mipgen'])
        design.to_csv(output['probes'], index=False)

rule convert_heatseq_probes:
    version: VERSIONS['parse_reads']
    input:
        rules.check_python_packages.output,
        heatseq = "probes_heatseq.tsv"
    output:
        probes = "{analysis_dir}/probes.csv"
    run:
        import amplimap.reader
        design = amplimap.reader.read_and_convert_heatseq_probes(input['heatseq'])
        design.to_csv(output['probes'], index=False)

##### SNPS CHECKING/COPYING
rule copy_snps:
    input:
        snps = "snps.txt"
    output:
        snps = "{analysis_dir}/snps.txt"
    run:
        import amplimap.reader
        amplimap.reader.read_snps_txt(input['snps'], reference_type = config['general']['reference_type'])
        print(input['snps'], 'checked.')

        #just copy the file over to the analysis directory
        shutil.copyfile(input['snps'], output['snps'])
    
##### MASKING
rule mask_genome:
    input:
        ref_fasta = get_path('fasta'),
        mask_bed = config['general']['mask_bed'],
    output:
        masked_fasta = 'masked_reference/genome.fa',
        masked_fasta_index = 'masked_reference/genome.fa.fai',
    shell:
        """
        %s
        bedtools maskfasta \
            -fi {input[ref_fasta]:q} \
            -bed {input[mask_bed]:q} \
            -fo {output[masked_fasta]:q} \
        ;

        %s
        samtools faidx {output[masked_fasta]:q};
        """ % (load_module_command('bedtools', config), load_module_command('samtools', config))

rule mask_genome_index_bwa:
    input:
        masked_fasta = 'masked_reference/genome.fa',
    output:
        masked_index = 'masked_reference/genome.fa.bwt',
    shell:
        """        
        %s
        bwa index {input[masked_fasta]:q};
        """ % (load_module_command('bwa', config))

rule mask_genome_index_bowtie2:
    input:
        masked_fasta = 'masked_reference/genome.fa',
    output:
        masked_index = 'masked_reference/genome.fa.1.bt2',
    shell:
        """        
        %s
        bowtie2-build {input[masked_fasta]:q} {input[masked_fasta]:q};
        """ % (load_module_command('bowtie2', config))

rule mask_genome_index_star:
    input:
        masked_fasta = 'masked_reference/genome.fa',
        annotation_gff = get_path('annotation_gff', default = ''),
    output:
        masked_index_directory = 'masked_reference/star/',
        masked_index_file = 'masked_reference/star/Genome',
    threads: 4
    shell:
        """        
        %s
        STAR \
            --runThreadN {threads} \
            --runMode genomeGenerate \
            --genomeDir {output[masked_index_directory]:q} \
            --genomeFastaFiles {input[masked_fasta]:q} \
            --sjdbGTFfile {input[annotation_gff]:q} \
            --sjdbOverhang 100 \
        ;
        """ % (load_module_command('star', config))

##### RAW BAM CONVERSION
rule bam_to_fastq:
    input:
        "bams_in/{sample_full}.bam",
    output:
        r1 = "reads_in/{sample_full}_L001_R1_001.fastq.gz",
        r2 = "reads_in/{sample_full}_L001_R2_001.fastq.gz",
    run:
        shell("%s bedtools bamtofastq -i {input[0]:q} -fq {output[r1]:q} -fq2 {output[r2]:q}" % load_module_command('bedtools', config))    

##### TAGGED, ALIGNED BAMS
rule link_tagged_bams:
    input:
        "tagged_bams_in/{sample_full}.bam",
        config_check = rules.start_analysis.output
    output:
        "{analysis_dir}/bam/{sample_full}.bam",
    run:
        import os
        #could use os.path.abspath() here, but then we can't move working directory without breaking things
        os.symlink(os.path.join("..", "..", input[0]), output[0])

rule link_tagged_bais_1:
    input:
        "tagged_bams_in/{sample_full}.bam.bai",
    output:
        "{analysis_dir}/bam/{sample_full}.bam.bai",
    run:
        import os
        #could use os.path.abspath() here, but then we can't move working directory without breaking things
        os.symlink(os.path.join("..", "..", input[0]), output[0])

rule link_tagged_bais_2:
    input:
        "tagged_bams_in/{sample_full}.bai",
    output:
        "{analysis_dir}/bam/{sample_full}.bam.bai",
    run:
        import os
        #could use os.path.abspath() here, but then we can't move working directory without breaking things
        os.symlink(os.path.join("..", "..", input[0]), output[0])

##### IDT INPUT
rule link_unmapped_bams:
    input:
        "unmapped_bams_in/{sample_full}.bam",
        config_check = rules.start_analysis.output
    output:
        "{analysis_dir}/bam_unmapped/{sample_full}.bam",
    run:
        import os
        #could use os.path.abspath() here, but then we can't move working directory without breaking things
        os.symlink(os.path.join("..", "..", input[0]), output[0])

rule unmapped_bam_to_fastqs:
    input:
        "{analysis_dir}/bam_unmapped/{sample_full}.bam",
    output:
        "{analysis_dir}/reads_parsed/fastq/{sample_full}.UNTAGGED__MIP_TRIMMED__R1_001.fastq.gz",
        "{analysis_dir}/reads_parsed/fastq/{sample_full}.UNTAGGED__MIP_TRIMMED__R2_001.fastq.gz",
        stats_samples = "{analysis_dir}/reads_parsed/stats_samples__sample_{sample_full}.csv",
    run:
        shell("""
            %s
            SamToFastq \
                INPUT={input:q} \
                FASTQ={output[0]:q} \
                SECOND_END_FASTQ={output[1]:q} \
                INCLUDE_NON_PF_READS=false \
                CLIPPING_ATTRIBUTE=XT \
                CLIPPING_ACTION=X \
                CLIPPING_MIN_LENGTH=10 \
            ;
        """ % load_module_command('picard', config))

        #count reads
        n_alignments = 0
        import pysam
        #need check_sq=False to handle unmapped file
        with pysam.AlignmentFile(input[0], "rb", check_sq=False) as bam:
            n_alignments = bam.count(until_eof=True)

        #align_pe rule expects stats_samples.csv, which is made from per-sample stats_samples.csv
        #we will just fake this for now
        import amplimap.parse_reads
        amplimap.parse_reads.output_stats_samples(output['stats_samples'], {
            'sample': [wildcards['sample_full']],
            'files': [1],
            'pairs_total': [n_alignments//2],
            'pairs_unknown_arms': [0],
            'pairs_good_arms': [n_alignments//2],
            'pairs_r1_too_short': [0],
            'pairs_r2_too_short': [0]
        })

rule attach_tags_from_unmapped:
    input:
        "{analysis_dir}/bam_unmapped/{sample_full}.bam",
        #TODO: this uses the normal align_pe rule for the alignment, which includes coordinate sorting
        #the merge scripts wants queryname sort, but detects and fixes that automatically.
        #just a bit of a waste...
        "{analysis_dir}/bam/{sample_full}.UNTAGGED.bam",
        "{analysis_dir}/bam/{sample_full}.UNTAGGED.bam.bai",
    output:
        "{analysis_dir}/bam/{sample_full}.bam",
        "{analysis_dir}/bam/{sample_full}.bam.bai",
        temp("{analysis_dir}/bam/{sample_full}.attach_tags_tmp.bam")
    run:
        shell("""
            %s%s

            #attach tags from unmapped bam
            MergeBamAlignment \
                ALIGNED={input[1]:q} \
                UNMAPPED={input[0]:q} \
                OUTPUT={output[2]:q} \
                REFERENCE_SEQUENCE="%s" \
                EXPECTED_ORIENTATIONS=FR \
                MAX_GAPS=-1 \
                SORT_ORDER=coordinate \
                ALIGNER_PROPER_PAIR_FLAGS=false \
                CLIP_OVERLAPPING_READS=false \
                VALIDATION_STRINGENCY=LENIENT \
            ;

            #fix the read groups, which will otherwise come from unmapped bam
            #note lenient stringency to deal with invalid read groups from before
            AddOrReplaceReadGroups \
                I={output[2]:q} \
                O={output[0]:q} \
                RGID={wildcards.sample_full:q} \
                RGLB={wildcards.sample_full:q} \
                RGPL=illumina \
                RGPU={wildcards.sample_full:q} \
                RGSM={wildcards.sample_full:q} \
                VALIDATION_STRINGENCY=LENIENT \
            ;

            samtools index {output[0]:q};
        """ % (load_module_command('picard', config), load_module_command('samtools', config), get_path('fasta')))

##### ACTUAL PIPELINE
rule link_reads:
    input:
        "reads_in/{sample_with_lane}_R{read}_001.fastq.gz",
        config_check = rules.start_analysis.output
    output:
        "analysis/reads_in/{sample_with_lane}_R{read}_001.fastq.gz",
    run:
        import os
        #could use os.path.abspath() here, but then we can't move working directory without breaking things
        os.symlink(os.path.join("..", "..", input[0]), output[0])

rule parse_reads_pe:
    version: VERSIONS['parse_reads']
    input:
        r1 = ["{analysis_dir}/reads_in/{sample_full}_L%03d_R1_001.fastq.gz" % (lane+1) for lane in range(config['general']['lanes_actual'])],
        r2 = ["{analysis_dir}/reads_in/{sample_full}_L%03d_R2_001.fastq.gz" % (lane+1) for lane in range(config['general']['lanes_actual'])],
        probes = "{analysis_dir}/probes.csv",
        config_check = rules.start_analysis.output #make sure we copied the config we used
    output:
        r1 = "{analysis_dir}/reads_parsed/fastq/{sample_full}__MIP_TRIMMED__R1_001.fastq.gz",
        r2 = "{analysis_dir}/reads_parsed/fastq/{sample_full}__MIP_TRIMMED__R2_001.fastq.gz",
        # consensus_fastqs = [
        #     "{analysis_dir}/reads_parsed/fastq/consensus/{sample_full}__MIP_TRIMMED_CONSENSUS__R1_001.fastq.gz",
        #     "{analysis_dir}/reads_parsed/fastq/consensus/{sample_full}__MIP_TRIMMED_CONSENSUS__R2_001.fastq.gz"
        # ] if not config['general']['ignore_umis'] else [],
        stats_samples = "{analysis_dir}/reads_parsed/stats_samples__sample_{sample_full}.csv",
        stats_reads = "{analysis_dir}/reads_parsed/stats_reads__sample_{sample_full}.csv"
    run:
        #prepare stats dicts
        import collections
        stats_samples = collections.OrderedDict()
        stats_reads = []

        #load probes
        import amplimap.reader
        #read new format
        probes = amplimap.reader.read_new_probe_design(input['probes'], reference_type = config['general']['reference_type'])
        #much faster to access than using DataFrame.loc every time
        probes_dict = probes.to_dict()

        #run
        import amplimap.parse_reads
        amplimap.parse_reads.parse_read_pairs(
            wildcards['sample_full'],
            input['r1'],
            input['r2'],
            output['r1'],
            output['r2'],
            probes_dict,
            stats_samples,
            stats_reads,
            unknown_arms_directory = os.path.join(wildcards['analysis_dir'], 'reads_parsed'),
            umi_one = config['parse_reads']['umi_one'], umi_two = config['parse_reads']['umi_two'],
            mismatches = config['parse_reads']['max_mismatches'],
            trim_primers = config['general']['trim_primers'],
            trim_min_length = config['general']['trim_min_length'],
            trim_primers_strict = False,
            trim_primers_smart = False,
            quality_trim_threshold = config['general']['quality_trim_threshold'] if config['general']['quality_trim_threshold'] != False else None,
            quality_trim_phred_base = config['general']['quality_trim_phred_base'],
            allow_multiple_probes = False,
            consensus_fastqs = None, #output['consensus_fastqs'],
            min_consensus_count = config['general']['umi_min_consensus_count']
        )

        #output stats files
        amplimap.parse_reads.output_stats_samples(output['stats_samples'], stats_samples)
        amplimap.parse_reads.output_stats_reads(output['stats_reads'], stats_reads, config['parse_reads']['umi_one'], config['parse_reads']['umi_two'])

rule merge_targets:
    input:
        "{analysis_dir}/targets.bed"
    output:
        "{analysis_dir}/targets_merged.bed"
    run:
        shell("%s bedtools merge -i <(sort -k1,1 -k2,2n {input[0]:q}) -c 4 -o collapse > {output[0]:q}" % load_module_command('bedtools', config))

rule stats_samples_agg:
    input:
        parsed_reads = expand("{{analysis_dir}}/reads_parsed/stats_samples__sample_{sample_full}.csv", sample_full = SAMPLES)
    output:
        "{analysis_dir}/reads_parsed/stats_samples.csv"
    run:
        import pandas as pd
        merged = None
        for file in input:
            print('Reading', file, '...')
            df = pd.read_csv(file, index_col = False)
            print('Data shape:', str(df.shape))

            if merged is None:
                merged = df
            else:
                merged = merged.append(df, ignore_index = True)

        print('Merged data shape:', str(merged.shape))
        merged.sort_values(['sample'], inplace=True)

        #should we ensure that we have at least X good reads?
        percentage_good = (100.0 * merged['pairs_good_arms'].sum() / merged['pairs_total'].sum())
        print('Overall good read percentage =', percentage_good)

        if not percentage_good > config['parse_reads']['min_percentage_good']: #in [0, 100] checked above
            merged.to_csv(output[0]+'.error.csv', index = False)
            print('Wrote sample stats to %s' % output[0]+'.error.csv')

        assert percentage_good > config['parse_reads']['min_percentage_good'], \
            '\n\nABORTED: Found too few pairs with good arms - overall percentage = %.1f%%. Check probe design file for mistakes or lower min_percentage_good in config.yaml to proceed\n\n' % (percentage_good)

        merged.to_csv(output[0], index = False)

rule stats_reads_agg_new:
    input:
        parsed_reads = expand("{{analysis_dir}}/reads_parsed/stats_reads__sample_{sample_full}.csv", sample_full = SAMPLES)
    output:
        "{analysis_dir}/reads_parsed/stats_reads.csv",
    run:
        import pandas as pd
        merged = None
        for file in input:
            print('Reading', file, '...')
            try:
                df = pd.read_csv(file, index_col = False)
                print('Data shape:', str(df.shape))

                if merged is None:
                    merged = df
                else:
                    merged = merged.append(df, ignore_index = True)
            except pd.io.common.EmptyDataError:
                print('No data for', file, ', skipping.')

        assert merged is not None and len(merged) > 0, \
            '\n\nABORTED: Did not find good reads for any sample. Please check configuration, probe design table and samples!\n\n'

        print('Merged data shape:', str(merged.shape))
        merged.sort_values(['sample', 'probe'], inplace=True)

        merged.to_csv(output[0], index = False)

rule align_pe:
    input:
        "{analysis_dir}/reads_parsed/fastq/{sample_full}__MIP_TRIMMED__R1_001.fastq.gz",
        "{analysis_dir}/reads_parsed/fastq/{sample_full}__MIP_TRIMMED__R2_001.fastq.gz",
        get_alignment_index_filename(real_path = True),
        "{analysis_dir}/reads_parsed/stats_samples.csv", #to make sure this gets generated and checked first
        probes = "{analysis_dir}/probes.csv" if config['align']['aligner'] == 'naive' else [] #the naive aligner also needs probes
    output:
        "{analysis_dir}/bam/{sample_full}.bam",
        "{analysis_dir}/bam/{sample_full}.bam.bai",
    threads: 4
    run:
        cmds = """
        %s
        %s
        %s
        samtools index {output[0]:q};
        """

        my_index = get_alignment_index_filename(real_path = False)
        if config['align']['aligner'] == 'naive':
            #load probes
            import amplimap.reader
            probes = amplimap.reader.read_new_probe_design(input['probes'], reference_type = config['general']['reference_type'])
            probes_dict = probes.to_dict()

            #just place the reads based on the probe location
            import amplimap.naive_mapper
            amplimap.naive_mapper.create_bam(
                wildcards['sample_full'],
                [input[0]],
                [input[1]],
                my_index,
                probes_dict,
                output[0]+"__unsorted",
                debug = False
            )

            #we still need to sort and index these            
            cmds = cmds % (
                load_module_command('samtools', config),
                '',
                """
                samtools sort \
                    -T "{output[0]}__sort_tmp" \
                    -o {output[0]:q} \
                    "{output[0]}__unsorted" \
                ;
                """
            )
        elif config['align']['aligner'] == 'bwa':
            cmds = cmds % (
                load_module_command('samtools', config),
                load_module_command('bwa', config),
                """
                bwa mem \
                    -t {threads} \
                    -R '@RG\\tID:{wildcards.sample_full}\\tSM:{wildcards.sample_full}' \
                    -C \
                    "%s" \
                    {input[0]:q} {input[1]:q} \
                | samtools fixmate -O bam - - \
                | samtools sort -T "{output[0]}__sort_tmp" \
                    -o {output[0]:q} - \
                ;
                """ % my_index
            )
        elif config['align']['aligner'] == 'bowtie2':
            extra = ''
            if config['align']['bowtie2']['report_n'] > 1:
                extra += '-k %d' % config['align']['bowtie2']['report_n']

            cmds = cmds % (
                load_module_command('samtools', config),
                load_module_command('bowtie2', config),
                """
                bowtie2 \
                    %s \
                    --rg-id {wildcards.sample_full:q} \
                    --threads {threads} \
                    -x "%s" \
                    -1 {input[0]:q} \
                    -2 {input[1]:q} \
                | samtools sort -T "{output[0]}__sort_tmp" \
                    -o {output[0]:q} - \
                ;
                """ % (extra, my_index)
            )
        elif config['align']['aligner'] == 'star':
            extra = ''
            if input[0].endswith('.gz'):
                extra += ' --readFilesCommand zcat'

            cmds = cmds % (
                load_module_command('samtools', config),
                load_module_command('star', config),
                """
                STAR \
                    %s \
                    --runMode alignReads \
                    --runThreadN {threads} \
                    --outSAMattrRGline ID:{wildcards.sample_full:q} SM:{wildcards.sample_full:q} \
                    --genomeDir "%s" \
                    --readFilesIn {input[0]:q} {input[1]:q} \
                    --outSAMtype BAM SortedByCoordinate \
                    --outFileNamePrefix "{output[0]}." \
                    --outSAMunmapped Within \
                    --outFilterType BySJout \
                    --outFilterMultimapNmax 5 \
                ;

                #fix names -- this will fail if no reads but should handle only unmapped thanks to --outSAMunmapped
                mv "{output[0]}.Aligned.sortedByCoord.out.bam" {output[0]:q};
                """ % (extra, my_index)
            )
        else:
            raise Exception("Invalid aligner specified in config!")

        shell(cmds)

rule align_pe_CONSENSUS:
    input:
        "{analysis_dir}/reads_parsed/fastq/consensus/{sample_full}__MIP_TRIMMED_CONSENSUS__R1_001.fastq.gz",
        "{analysis_dir}/reads_parsed/fastq/consensus/{sample_full}__MIP_TRIMMED_CONSENSUS__R2_001.fastq.gz",
        get_alignment_index_filename(real_path = True),
        "{analysis_dir}/reads_parsed/stats_samples.csv" #to make sure this gets generated and checked first
    output:
        #note the `,.*` to allow empty subdir
        "{analysis_dir}/bam_consensus/{sample_full}_CONSENSUS.bam",
        "{analysis_dir}/bam_consensus/{sample_full}_CONSENSUS.bam.bai",
    threads: 4
    run:
        cmds = """
        %s
        %s
        %s
        samtools index {output[0]:q};
        """

        my_index = get_alignment_index_filename(real_path = False)
        if config['align']['aligner'] == 'bwa':
            cmds = cmds % (
                load_module_command('samtools', config),
                load_module_command('bwa', config),
                """
                bwa mem \
                    -t {threads} \
                    -R '@RG\\tID:{wildcards.sample_full}\\tSM:{wildcards.sample_full}' \
                    -C \
                    "%s" \
                    {input[0]:q} {input[1]:q} \
                | samtools fixmate -O bam - - \
                | samtools sort -T "{output[0]}__sort_tmp" \
                    -o {output[0]:q} - \
                ;
                """ % my_index)
        elif config['align']['aligner'] == 'bowtie2':
            extra = ''
            if config['align']['bowtie2']['report_n'] > 1:
                extra += '-k %d' % config['align']['bowtie2']['report_n']

            cmds = cmds % (
                load_module_command('samtools', config),
                load_module_command('bowtie2', config),
                """
                bowtie2 \
                    %s \
                    --rg-id {wildcards.sample_full:q} \
                    --threads {threads} \
                    -x "%s" \
                    -1 {input[0]:q} \
                    -2 {input[1]:q} \
                | samtools sort -T "{output[0]}__sort_tmp" \
                    -o {output[0]:q} - \
                ;
                """ % (extra, my_index))
        elif config['align']['aligner'] == 'star':
            extra = ''
            if input[0].endswith('.gz'):
                extra += ' --readFilesCommand zcat'

            cmds = cmds % (
                load_module_command('samtools', config),
                load_module_command('star', config),
                """
                STAR \
                    %s \
                    --runMode alignReads \
                    --runThreadN {threads} \
                    --outSAMattrRGline ID:{wildcards.sample_full:q} SM:{wildcards.sample_full:q} \
                    --genomeDir "%s" \
                    --readFilesIn {input[0]:q} {input[1]:q} \
                    --outSAMtype BAM SortedByCoordinate \
                    --outFileNamePrefix "{output[0]}." \
                    --outSAMunmapped Within \
                    --outFilterType BySJout \
                    --outFilterMultimapNmax 5 \
                ;

                #fix names -- this will fail if no reads but should handle only unmapped thanks to --outSAMunmapped
                mv "{output[0]}.Aligned.sortedByCoord.out.bam" {output[0]:q};
                """ % (extra, my_index))
        else:
            raise Exception("Invalid aligner specified in config!")

        shell(cmds)

rule stats_alignment:
    version: VERSIONS['stats_alignment']
    input:
        "{analysis_dir}/bam/{sample_full}.bam",
        "{analysis_dir}/bam/{sample_full}.bam.bai",
        probes = "{analysis_dir}/probes.csv"
    output:
        "{analysis_dir}/stats_alignment/{sample_full}.stats_alignment.csv"
    run:
        import amplimap.stats_alignment
        amplimap.stats_alignment.process_file(
            design = input['probes'],
            input = input[0],
            output = "{}/stats_alignment/{}".format(wildcards['analysis_dir'], wildcards['sample_full']),
            min_mapq = config['pileup']['min_mapq'],
            min_consensus_count = config['general']['umi_min_consensus_count'],
            include_primers = not config['general']['trim_primers'],
            use_naive_groups = not config['general']['ignore_umis'],
            ignore_groups = config['general']['ignore_umis']
        )

rule stats_alignment_agg:
    input:
        csvs = expand("{{analysis_dir}}/stats_alignment/{sample_full}.stats_alignment.csv", sample_full = SAMPLES)
    output:
        "{analysis_dir}/stats_alignment/stats_alignment.csv"
    run:
        import amplimap.stats_alignment
        amplimap.stats_alignment.aggregate(folder = "{}/stats_alignment/".format(wildcards['analysis_dir']))

rule do_pileup:
    version: VERSIONS['pileup']
    input:
        "{analysis_dir}/bam/{sample_full}.bam", # if config['general']['ignore_umis'] else rules.umi_group.output,
        "{analysis_dir}/bam/{sample_full}.bam.bai",
        rules.check_target_overlaps.output,
        targets = "{analysis_dir}/targets.bed",
        probes = "{analysis_dir}/probes.csv" if config['pileup']['validate_probe_targets'] else []
    output:
        "{analysis_dir}/pileup/{sample_full}.pileup.csv",
        "{analysis_dir}/pileup/{sample_full}.targets.csv"
    run:
        import amplimap.pileup
        amplimap.pileup.process_file(
            input = input[0],
            output = "{}/pileup/{}".format(wildcards['analysis_dir'], wildcards['sample_full']),
            reference_type = config['general']['reference_type'],
            subsample_reads = config['pileup']['subsample_reads'],
            probes_file = input['probes'] if config['pileup']['validate_probe_targets'] else None,
            snps_file = None, #different from other pileup command
            targets_file = input['targets'], #different from other pileup command
            validate_probe_targets = config['pileup']['validate_probe_targets'],
            filter_softclipped = config['pileup']['filter_softclipped'],
            fasta_file = get_path('fasta'),
            min_mapq = config['pileup']['min_mapq'],
            min_baseq = config['pileup']['min_baseq'],
            ignore_groups = config['general']['ignore_umis'],
            group_with_mate_positions = config['pileup']['group_with_mate_positions'],
            min_consensus_count = config['general']['umi_min_consensus_count'],

            #to allow running straight from tagged bams:
            no_probe_data = config['pileup']['no_probe_data'],
            umi_tag_name = config['pileup']['umi_tag_name'],
        )

rule pileup_agg:
    input:
        csvs = expand("{{analysis_dir}}/pileup/{sample_full}.pileup.csv", sample_full = SAMPLES),
        targets = "{analysis_dir}/targets.bed"
    output:
        "{analysis_dir}/pileup/pileups_long.csv",
        "{analysis_dir}/pileup/pileups_long_detailed.csv",
        "{analysis_dir}/pileup/pileups_wide.csv",
        "{analysis_dir}/pileup/target_coverage.csv",
        "{analysis_dir}/pileup/target_coverage_long.csv"
    run:
        import amplimap.pileup
        amplimap.pileup.aggregate(
            folder = "{}/pileup/".format(wildcards['analysis_dir']),
            snps_file = None,
            ref = True,
            generate_calls = False
        )

rule do_pileup_snps:
    version: VERSIONS['pileup']
    input:
        "{analysis_dir}/bam/{sample_full}.bam", # if config['general']['ignore_umis'] else rules.umi_group.output,
        "{analysis_dir}/bam/{sample_full}.bam.bai",
        snps = "{analysis_dir}/snps.txt",
        probes = "{analysis_dir}/probes.csv" if config['pileup']['validate_probe_targets'] else []
    output:
        "{analysis_dir}/pileup_snps/{sample_full}.pileup.csv"
    run:
        import amplimap.pileup
        amplimap.pileup.process_file(
            input = input[0],
            output = "{}/pileup_snps/{}".format(wildcards['analysis_dir'], wildcards['sample_full']),
            reference_type = config['general']['reference_type'],
            subsample_reads = config['pileup']['subsample_reads'],
            probes_file = input['probes'] if config['pileup']['validate_probe_targets'] else None,
            snps_file = input['snps'], #different from other pileup command
            targets_file = None, #different from other pileup command
            validate_probe_targets = config['pileup']['validate_probe_targets'],
            filter_softclipped = config['pileup']['filter_softclipped'],
            fasta_file = get_path('fasta'),
            min_mapq = config['pileup']['min_mapq'],
            min_baseq = config['pileup']['min_baseq'],
            ignore_groups = config['general']['ignore_umis'],
            group_with_mate_positions = config['pileup']['group_with_mate_positions'],
            min_consensus_count = config['general']['umi_min_consensus_count'],

            #to allow running straight from tagged bams:
            no_probe_data = config['pileup']['no_probe_data'],
            umi_tag_name = config['pileup']['umi_tag_name'],
        )

rule pileup_snps_agg:
    input:
        csvs = expand("{{analysis_dir}}/pileup_snps/{sample_full}.pileup.csv", sample_full = SAMPLES),
        snps = "{analysis_dir}/snps.txt"
    output:
        "{analysis_dir}/pileup_snps/target_snps_pileups_long.csv",
        "{analysis_dir}/pileup_snps/target_snps_pileups_long_detailed.csv",
        "{analysis_dir}/pileup_snps/target_snps_pileups_wide.csv"
    run:
        import amplimap.pileup
        amplimap.pileup.aggregate(
            folder = "{}/pileup_snps/".format(wildcards['analysis_dir']),
            snps_file = input['snps'],
            ref = True,
            generate_calls = False
        )

rule umi_dedup:
    input:
        "{analysis_dir}/bam/{sample_full}.bam",
        "{analysis_dir}/bam/{sample_full}.bam.bai",
    output:
        "{analysis_dir}/umi_dedup/{sample_full}.bam",
        "{analysis_dir}/umi_dedup/{sample_full}.bam.bai",
        temp("{analysis_dir}/umi_dedup/{sample_full}.unsorted.bam")
    shell:
        """
        %s
        umi_tools dedup \
            --log2stderr \
            --method directional \
            --paired \
            -I {input[0]:q} \
            -S {output[2]:q} \
        ;
        samtools sort -o {output[0]:q} {output[2]:q};
        samtools index {output[0]:q};
        """ % load_module_command('samtools', config)

rule calc_coverage:
    input:
        "{analysis_dir}/{bamdir}/{file}.bam",
        "{analysis_dir}/{bamdir}/{file}.bam.bai",
        targets = "{analysis_dir}/targets.bed"
    output:
        "{analysis_dir}/{bamdir}/coverage/{file}.coverage_raw.txt",
    shell:        
        """
        %s
        bedtools coverage \
            -a {input.targets:q} \
            -b {input[0]:q} \
            -d \
        > {output[0]:q};
        """ % (load_module_command('bedtools', config))

rule calc_coverage_mapq:
    input:
        "{analysis_dir}/{bamdir}/{file}.bam",
        "{analysis_dir}/{bamdir}/{file}.bam.bai",
        targets = "{analysis_dir}/targets.bed"
    output:
        "{analysis_dir}/{bamdir}/coverage_mapq/{file}.coverage_raw.txt",
    shell:
        """
        %s
        %s
        samtools view -b \
            -q {config[pileup][min_mapq]:q} \
            {input[0]:q} \            
        | \
        bedtools coverage \
            -a {input.targets:q} \
            -b stdin \
            -d \
        > {output[0]:q};
        """ % (load_module_command('samtools', config), load_module_command('bedtools', config))

rule coverage_process:
    version: VERSIONS['coverage']
    input:
        "{prefix}.coverage_raw.txt"
    output:
        "{prefix}.coverage.csv"
    run:
        import amplimap.coverage
        amplimap.coverage.process_file(input[0], output[0])

rule coverage_agg:
    version: VERSIONS['coverage']
    input:
        csvs = expand("{{bamdir}}/coverage/{sample_full}.coverage.csv", sample_full = SAMPLES),
        sample_info = ["sample_info.csv"] if os.path.isfile("sample_info.csv") else []
    output:
        merged = "{bamdir}/coverage/coverage_full.csv",
        min_coverage = "{bamdir}/coverage/min_coverage.csv",
        cov_per_bp = "{bamdir}/coverage/cov_per_bp.csv",
        fraction_zero_coverage = "{bamdir}/coverage/fraction_zero_coverage.csv",
    run:
        import amplimap.coverage
        amplimap.coverage.aggregate(input, output)

rule call_variants_raw:
    input:
        "{analysis_dir}/bam/{sample_full}.bam",
        "{analysis_dir}/bam/{sample_full}.bam.bai",
        targets = "{analysis_dir}/targets_merged.bed"
    output:
        "{analysis_dir}/variants_raw/{sample_full}.vcf"
    run:
        #same as below
        if config['variants']['caller'] == 'platypus':
            shell("""
                %s
                platypus callVariants \
                    -o {output[0]:q} \
                    --refFile "%s" \
                    --bamFiles {input[0]:q} \
                    --regions {input.targets:q} \
                    {config[variants][platypus][parameters]} \
                ;
                """ % (load_module_command('platypus', config), get_path('fasta'))
            )
        elif config['variants']['caller'] == 'gatk':   
            #TODO: should we add https://software.broadinstitute.org/gatk/documentation/tooldocs/current/org_broadinstitute_hellbender_tools_walkers_bqsr_BaseRecalibrator.php
            #TODO: include Mutect2?    https://software.broadinstitute.org/gatk/documentation/tooldocs/current/org_broadinstitute_hellbender_tools_walkers_mutect_Mutect2.php
            shell("""
                %s
                gatk HaplotypeCaller \
                    {config[variants][gatk][parameters]} \
                    --reference "%s" \
                    --intervals {input.targets:q} \
                    --input {input[0]:q} \
                    --output {output[0]:q} \
                ;
                """ % (load_module_command('gatk', config), get_path('fasta'))
            )
        else:
            raise Exception('Invalid variant caller specified')

rule call_variants_umi:
    input:
        rules.umi_dedup.output,
        targets = "{analysis_dir}/targets_merged.bed"
    output:
        "{analysis_dir}/variants_umi/{sample_full}.vcf"
    run:
        #same as above
        if config['variants']['caller'] == 'platypus':
            shell("""
                %s
                platypus callVariants \
                    -o {output[0]:q} \
                    --refFile "%s" \
                    --bamFiles {input[0]:q} \
                    --regions {input.targets:q} \
                    {config[variants][platypus][parameters]} \
                ;
                """ % (load_module_command('platypus', config), get_path('fasta'))
            )
        elif config['variants']['caller'] == 'gatk':   
            #TODO: should we add https://software.broadinstitute.org/gatk/documentation/tooldocs/current/org_broadinstitute_hellbender_tools_walkers_bqsr_BaseRecalibrator.php
            #TODO: include Mutect2?    https://software.broadinstitute.org/gatk/documentation/tooldocs/current/org_broadinstitute_hellbender_tools_walkers_mutect_Mutect2.php
            shell("""
                %s
                gatk HaplotypeCaller \
                    {config[variants][gatk][parameters]} \
                    --reference "%s" \
                    --intervals {input.targets:q} \
                    --input {input[0]:q} \
                    --output {output[0]:q} \
                ;
                """ % (load_module_command('gatk', config), get_path('fasta'))
            )
        else:
            raise Exception('Invalid variant caller specified')

rule call_variants_low_frequency:
    input:
        "{analysis_dir}/bam/{sample_full}.bam",
        "{analysis_dir}/bam/{sample_full}.bam.bai",
        targets = "{analysis_dir}/targets_merged.bed"
    output:
        "{analysis_dir}/variants_low_frequency/{sample_full}.vcf",
        "{analysis_dir}/variants_low_frequency_unfiltered/{sample_full}.vcf"
    run:
        #same as below
        if config['variants']['caller_low_frequency'] == 'mutect2':
            shell("""
                %s
                gatk Mutect2 \
                    {config[variants][mutect2][parameters]} \
                    --reference "%s" \
                    --intervals {input.targets:q} \
                    --input {input[0]:q} \
                    --output {output[1]:q} \
                    --tumor-sample {wildcards.sample_full:q} \
                ;

                gatk FilterMutectCalls \
                    --variant {output[1]:q} \
                    --output {output[0]:q} \
                ;
                """ % (load_module_command('gatk', config), get_path('fasta'))
            )
        else:
            raise Exception('Invalid variant caller specified')

rule annotate_variants:
    input:
        "{analysis_dir}/{variants_dir}/{sample_full}.vcf",
    output:
        "{analysis_dir}/{variants_dir}/{sample_full}.vcf."+config['general']['genome_name']+"_multianno.csv",
        temp("{analysis_dir}/{variants_dir}/{sample_full}.for_annovar.vcf.gz"),
        temp("{analysis_dir}/{variants_dir}/{sample_full}.for_annovar.bed")
    run:
        with open(input[0], 'r') as f:
            found_variants = False
            for line in f:
                if not line.startswith('#'):
                    found_variants = True
                    break

        if not found_variants:
            print('No variants found, creating empty files!')
            open(output[0], 'a').close()
            open(output[1], 'a').close()
            open(output[2], 'a').close()
        else:
            shell("""
                %s
                %s

                lines_before="$(grep -v '^#' {input[0]:q} | wc -l)"
                bcftools norm \
                    --multiallelics=-both \
                    --fasta-ref="%s" \
                    --output={output[1]:q} \
                    --output-type=z \
                    {input[0]:q} \
                ;

                lines_after="$(zgrep -v '^#' {output[1]:q} | wc -l)"
                echo "Split $lines_before variants into $lines_after variants using bcftools";
                if [ $lines_after -lt $lines_before ]; then
                    echo "Lost lines?!"
                    exit 2
                fi

                convert2annovar.pl {output[1]:q} -format vcf4old --includeinfo > {output[2]:q};

                table_annovar.pl \
                    {output[2]:q} \
                    "%s" \
                    --buildver {config[general][genome_name]:q} \
                    --otherinfo -csvout -remove \
                    -protocol {config[annotate][annovar][protocols]:q} \
                    -operation {config[annotate][annovar][operations]:q} \
                    --outfile {input[0]:q} \
                ;

                lines_final="$(tail -n+2 {output[0]:q} | wc -l)"
                echo "Annotated $lines_after variants into $lines_final variants using annovar";
                if [ $lines_final -lt $lines_after ]; then
                    echo "Lost lines?!"
                    exit 2
                fi
            """ % (load_module_command('bcftools', config), load_module_command('annovar', config), get_path('fasta'), get_path('annovar')))

rule variants_merge:
    version: VERSIONS['variants']
    input:
        csvs = expand("{{analysis_dir}}/{{variants_dir}}/{sample_full}.vcf."+config['general']['genome_name']+"_multianno.csv", sample_full = SAMPLES)
    output:
        "{analysis_dir}/{variants_dir}/variants_merged.csv"
    run:
        import amplimap.variants
        amplimap.variants.merge_variants(input, output)

rule variants_summary:
    version: VERSIONS['variants']
    input:
        merged = rules.variants_merge.output,
        targets = "{analysis_dir}/targets.bed",
        sample_info = ["sample_info.csv"] if os.path.isfile("sample_info.csv") else []
    output:
        "{analysis_dir}/{variants_dir}/variants_summary.csv"
    run:
        import amplimap.variants
        amplimap.variants.make_summary(input, output, config,
            get_path('exon_table') if 'include_exon_distance' in config['annotate'] and config['annotate']['include_exon_distance'] else None)

rule variants_summary_condensed:
    version: VERSIONS['variants']
    input:
        summary = rules.variants_summary.output[0],
        sample_info = ["sample_info.csv"] if os.path.isfile("sample_info.csv") else []
    output:
        filtered = "{analysis_dir}/{variants_dir}/variants_summary_filtered.csv",
        unfiltered = "{analysis_dir}/{variants_dir}/variants_summary_UNfiltered.csv"
    run:
        import amplimap.variants
        amplimap.variants.make_summary_condensed(input, output)

rule variants_summary_excel:
    version: VERSIONS['variants']
    input:
        rules.variants_summary.output[0]
    output:
        "{analysis_dir}/{variants_dir}/variants_summary.xlsx"
    run:
        import amplimap.variants
        amplimap.variants.make_summary_excel(input, output)

rule check_test_variant:
    version: VERSIONS['simulate']
    output:
        touch("checks/check_test__{search}_{replace}_{percentage}.done")
    run:
        import amplimap.simulate
        amplimap.simulate.check_parameters(wildcards)

rule test_make_reads:
    version: VERSIONS['simulate']
    input:
        "analysis/reads_in/{sample_with_lane}_R1_001.fastq.gz",
        "analysis/reads_in/{sample_with_lane}_R2_001.fastq.gz",
        "checks/check_test__{search}_{replace}_{percentage}.done",
    output:
        "test__{search}_{replace}_{percentage}/reads_in/{sample_with_lane}_R1_001.fastq.gz",
        "test__{search}_{replace}_{percentage}/reads_in/{sample_with_lane}_R2_001.fastq.gz",
        stats = "test__{search}_{replace}_{percentage}/stats_replacements/stats_replacements__sample_{sample_with_lane}.csv"
    run:
        import amplimap.simulate
        amplimap.simulate.make_simulated_reads(input, output, wildcards, config)

rule stats_replacements_agg:
    version: VERSIONS['simulate']
    input:
        expand("test__{{params}}/stats_replacements/stats_replacements__sample_{sample_full}_L{lane}.csv", sample_full = SAMPLES, lane = ['%03d' % l for l in range(1, config['general']['lanes_actual']+1)])
    output:
        "test__{params}/stats_replacements/stats_replacements.csv",
    run:
        import amplimap.simulate
        amplimap.simulate.stats_replacements_agg(input, output)