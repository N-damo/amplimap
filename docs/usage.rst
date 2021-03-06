.. _usage:

Input and the working directory
-------------------------------
For each experiment (for example each sequencing run), you need to create a working directory
inside which you run amplimap. All the input and output files will be kept in this directory.

Input overview
~~~~~~~~~~~~~~

Required input
^^^^^^^^^^^^^^^^

-  :ref:`reads-in`: subdirectory containing pairs of gzipped FASTQ files

   -  Alternative: :ref:`unmapped-bams`

-  :ref:`probes-csv`: probe design table in CSV format

   -  Alternative: :ref:`probes-mipgen-csv`

Optional input
^^^^^^^^^^^^^^^^

-  :ref:`targets-csv`: target regions in CSV format 
  
  - Alternative: :ref:`targets-bed`

-  ``config.yaml``: configuration file (see :doc:`configuration`)
-  :ref:`snps-txt`: list of known SNPs to genotype
-  :ref:`sample-info-csv`: sample annotation for variant and coverage
   tables

Input files
~~~~~~~~~~~~~~

.. _reads-in:

reads_in/
^^^^^^^^^^^^^^^^^^^^^^^^

This subdirectory should contain pairs of gzipped FASTQ files from
paired-end sequencing.
Filenames should follow standard Illumina naming conventions
(ending in ``_L001_R1_001.fastq.gz`` and
``_L001_R2_001.fastq.gz``, where ``L001`` is the lane).
Data from multiple lanes (e.g. ``L001`` and ``L002``) will be
merged, as long as all samples have a pair of files for each lane.

.. _unmapped-bams:

Unmapped BAM files (unmapped_bams_in/)
''''''''''''''''''''''''''''''''''''''''''''''''''''''''

Instead of the reads_in directory you can also provide your sequencing data
as unmapped BAM files inside a directory called ``unmapped_bams_in/``.
This is useful for running amplimap on data from capture-based protocols.

If your reads contained UMIs, these should have been trimmed off already and be
provided in the bam file using a BAM tag (e.g. ``RX``). You will need to
specify the name of this tag in the config file.

See also :ref:`running-capture` for more details and examples.

When running amplimap with capture-based data probes can no longer be identified
based on the primer arms. Thus, some of the output files can not be generated.

If your BAM files have already been mapped (aligned) you can also put
them into a directory called ``mapped_bams_in/`` instead, which will skip the
alignment step inside amplimap.

.. _probes-csv:

probes.csv
^^^^^^^^^^^^^^^^^^^^^^^^

This file contains information about the sequences of the primers and
their expected location on the reference genome. It can also be generated
directly from the output table created by *MIPGEN* - see below!

The columns are:

1. ``id``: a unique name for the probe
2. ``first_primer_5to3``: sequence of the forward primer, in 5’ to 3’
   orientation (needs to match start of read 1)
3. ``second_primer_5to3``: sequence of the reverse primer, in 5’ to 3’
   orientation (needs to match start of read 2)
4. ``chr``: chromosome (needs to match the naming scheme used for the reference genome, eg. ``1`` for Ensembl or ``chr1`` for UCSC)
5. ``target_start``: start of the target region (after the primer,
   1-based coordinate system)
6. ``target_end``: end of the target region
7. ``strand``: ``+`` or ``-``

The first row of the file should be the header listing these column names. Any
additional columns are ignored.

No two primers should be so similar to each other that a read could
match both of them. Otherwise, the read will be ambigous and may end up
being counted multiple times, once for each probe. This will skew any
downstream analysis.

If you have two probes for the same region to account for a SNP in the
primer sequence, you need to provide these as a single entry. To
make that merged entry match both primers, replace all ambiguous (SNP)
nucleotides in the primer sequences with a dot (``.``). This way, any
nucleotide will be allowed in this location and reads from either
version of the probe will be counted together.

MIP names cannot contain characters other than alphanumeric characters
(``A-Z``, ``0-9``), or ``_:+-``. Avoid using multiple colons in a row
(e.g. ``::``) since this is used as a field separator internally.

The file needs to be in plain CSV format with UNIX/Windows (not Mac)
style line endings.

.. _probes-mipgen-csv:

MIPGEN probe design table (picked_mips.txt)
''''''''''''''''''''''''''''''''''''''''''''''''''''''''
Instead of the standard ``probes.csv`` file you can also provide a
*MIPGEN* probe design table. Copy the ``xxxxx.picked_mips.txt`` file
to the working directory and rename it to ``picked_mips.txt``.
When you run amplimap, this file will
automatically be converted into a ``probes.csv`` file in the right
format.

If *MIPGEN* generated two versions of the same probe to account for a
SNP, ``amplimap`` will detect this based on the identical value in the
``mip_name`` column (optionally followed by ``_SNP_a`` and ``_SNP_b``)
and merge them into a single entry, replacing any
differences in the primer sequences by a dot (see above). Probes
with the same name but not the same location, or probes
where the primers differ by more than 10 characters,
are not expected and will result in an error.

.. _targets-csv:

targets.csv
^^^^^^^^^^^^^^^^^^^^^^^^

List of target regions (e.g. exons, not the MIPs themselves) in CSV format.
This file should contain the following columns:

1. ``chr`` (needs to match the naming scheme used for the reference genome, eg. ``1`` for Ensembl or ``chr1`` for UCSC)
2. ``start`` (start position, 1-based coordinate system)
3. ``end`` (end position)
4. [optional] ``id`` (name of the target)

The first row of the file should be the header listing these column names. Any
additional columns are ignored.

Variants will only be called inside these target regions! If any of the
target regions overlap, they will be merged for variant calling and
cause an error when trying to calculate pileups.

.. _targets-bed:

targets.bed
''''''''''''''''''''''''''''''''''''''''''''''''''''''''

You can also provide this data in BED format. In that case, the file should be called
``targets.bed`` and use the standard BED columns (chromosome, 0-based start position,
end position, id). The score and strand columns may be included, but do not
have any effect on the pipeline.
Note that BED files do *not* contain column headers!

.. _snps-txt:

snps.txt (for allele counting pileup)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

If you have certain SNPs that you want to generate pileups for, you can
provide a list in tab-separated text format here. The columns are:

1. ``chr`` (needs to match the naming scheme used for the reference genome, eg. ``1`` for Ensembl or ``chr1`` for UCSC)
2. ``pos`` (1-based coordinate system)
3. ``id``
4. ``snp_ref``
5. ``snp_alt`` (only a single alt allele is supported)

This will generate the ``pileups_snps`` directory with
reference/alternate allele counts for each SNP. The filter column in the
pileup tables will reflect whether the observed alleles matched the SNP
alleles, or whether additional alleles were found.

Note: This file do *not* contain column headers!


.. _sample-info-csv:

sample_info.csv (for variant calling)
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

This file can be provided to add additional sample information columns
to the coverage and variant tables. If provided, it always needs to
start with these two columns:

1. ``Sample``: the sample id, including the ``_S123`` part

   -  needs to match the sample identifiers of the input fastq files
   -  example: ``Barcode-001_S1``

2. ``Targets``: a semicolon-separated list of target ids

   -  needs to match the ids provided in ``targets.csv``
   -  example: ``GENE1-Ex1.1;GENE1-Ex1.2;GENE1-Ex2;GENE3``

These should then be followed by one or more annotation columns, which
can contain information like the id of the corresponding individual or
other information about the samples. All of these columns will be copied
into the coverage and variant tables.

A single sample id (= barcode) can have multiple rows with different
annotation columns, as long as none of the targets are the same. In
other words, any combination of sample/target id may only occur once.

If there are two overlapping target regions and a variant call is made
in the overlapping part, it can get assigned to either of them. To avoid
errors due to this, overlapping target regions must always be listed in
pairs and never be split up. For example, if the targets ``GENE1-Ex1a``
and ``GENE1-Ex1b`` overlap, you should never have a row where you only
list ``GENE1-Ex1a`` or only list ``GENE1-Ex1b``. They should always be
listed together (``GENE1-Ex1a;GENE1-Ex1b``) or not at all.

This file needs to be in plain CSV format with UNIX/Windows (not Mac)
style line endings.


Running amplimap
----------------

The pipeline is based on Snakemake, which uses predefined rules to
figure out what it needs to do to generate a certain output file.

To run the most basic version of the pipeline, just enter ``amplimap`` in your terminal:

::

    amplimap

By default, this will only start a so-called dry run. This will not
actually run any of the code yet. However, it will make sure that the expected
input files are present and tell you which jobs it would be running.

If the output of this dry run looks as expected you can start the actual
pipeline by adding the ``--run`` parameter:

::

    amplimap --run

This will go through the first few steps of the pipeline but will not
run the more advanced analysis-specific parts.

To run these additional analyses, you need to add so-called *target
rules* to the ``amplimap`` command line. Some of these are listed below.


``bams`` (read parsing and alignment)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
This rule performs read parsing and read alignment, creating the
``bams/`` and ``reads_parsed/`` output directories.

::

    amplimap bams


``variants`` and ``variants_umi`` (germline variant calling/annotation)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
These rules perform germline variant calling and annotation on the alignments
generated by the ``bams`` rule. If that rule has not been called yet, it will be
called implicitly.

To call variants from raw reads, creating the
``variants_raw/`` directory:

::

    amplimap variants

To call variants from UMI-deduplicated (but not consensus) reads, creating the
``variants_umi/`` directory:

::

    amplimap variants_umi

Please note that this command simply selects a random representative read per UMI group.
It does not perform any consensus calling like the ``pileups`` command would.


``coverages`` (target coverage tables)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
This rule calculates the target region coverage of the alignments generated by the ``bams`` rule.
If that rule has not been called yet, it will be
called implicitly.
Its output will be available in the ``bams/coverages/`` directory.

::

    amplimap coverages


``pileups`` (allele counts and allele frequencies)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
This rule calculates per-basepair allele counts and allele frequencies
in the target regions, using the alignments generated by the ``bams`` rule.
If that rule has not been called yet, it will be
called implicitly.

Its output will be available in the ``pileups/`` directory (if a ``targets.csv`` file
has been provided) and/or the ``pileups_snps/`` directory (if a ``snps.csv`` file
has been provided).

::

    amplimap pileups

To only perform a pileup of the SNPs, even if a targets file is present, run:

::

    amplimap pileups_snps


``variants_low_frequency`` (low-frequency/somatic variant calling)
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
[EXPERIMENTAL!] To call low-frequency variants using Mutect2 use this command:

::

    amplimap variants_low_frequency

This function is still experimental and has not been thoroughly tested. 
Its output will be available in the ``variants_low_frequency/`` directory 


Multiple analyses
~~~~~~~~~~~~~~~~~~~

You can also group together multiple *target rules* to run several analyses at once:

::

    amplimap pileups variants coverages


Running on a cluster
~~~~~~~~~~~~~~~~~~~~~~

You can specify the additional parameter ``--cluster=qsub`` to run jobs
in parallel on a SGE cluster:

::

    amplimap --cluster=qsub

    amplimap --cluster=qsub variants

    amplimap --cluster=qsub pileups

This can speed up the processing by an order of magnitude, as commands
will be run in parallel instead of sequentially. However, this process
is a bit more complex and may lead to unexpected errors. If you get an
error message, try running the standard command without the
``--cluster`` parameter instead.

You can set the number of jobs to submit by setting the ``--njobs``
parameter:

::

    amplimap --cluster=qsub --njobs=5

To use other cluster environments (such as LSF), add an entry with the submission command
to the ``clusters:`` section of the config file.

Cluster log files
^^^^^^^^^^^^^^^^^^
When amplimap submits jobs to the cluster, it can no longer print their output to the screen.
Instead, it will create separate a log file for each job containing all of its output.
If one of your jobs fails because of an error, you may need to look for a
log file with the full error message in there.

The naming of the log files will depend on the cluster architecture used,
but they should usually be called "amplimap.RULENAME.JOBID.sh.oCLUSTERID"
where RULENAME is the name of the amplimap rule that failed, JOBID is its
ID and CLUSTERID is an additional ID that has been assigned by the cluster.
By default these log files will be placed in a folder called ``cluster_log``.

For example, if you see an error message like this:

::

    (...)
    Error in rule tool_version:
        jobid: 9
        (...)

Then you can find the error message in the log file that starts with
``cluster_log/amplimap.tool_version.9.sh.o`` followed by a number.


Output: the ``analysis`` directory
----------------------------------

All analysis results will be written to the subdirectory ``analysis`` inside
the working directory. These include:

-  ``reads_parsed/stats_samples.csv``: Sample statistics - number of
   read pairs matching expected primers per sample, etc.
-  ``reads_parsed/stats_reads.csv``: Read statistics - number of reads
   per probe per sample, number of UMIs per probe per sample, etc.
-  ``bams/``: BAM files with aligned reads
-  ``stats_alignment/stats_alignment.csv``: Alignment statistics for
   each sample - number of read pairs and unique UMI groups aligning in
   the expected location, etc.
-  ``reads_parsed/``: unknown primer arm files - sequences from the start of reads that didn’t
   match any of the expected primer sequences. Will only include data for the
   first 10,000 read pairs with unknown primer arms.
- ``versions/`` and ``versions.yaml``: a set of files providing the version numbers of various tools used for the analysis.

In addition, the ``analysis`` directory will contain
``config_used.yaml``, which is a copy of the configuration that was used
at the time the pipeline was first run. Note that this will not be
updated if you run the pipeline a second time, unless you delete the old
copy first.

Target-specific output
~~~~~~~~~~~~~~~~~~~~~~

The ``analysis`` directory will contain further subdirectories for the
different analyses that were performed by the pipeline:

Germline variant calling and annotation analysis: ``coverages`` and ``variants``
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

-  ``bams_umi_dedup/``: only generated if reads contained UMIs --
   deduplicated BAM files, with one read pair per UMI
   group chosen at *random* (no consensus calling, no minimum coverage
   per UMI)
-  ``bams/coverages/``: min/average/zero coverage of target regions based
   on raw reads (ignoring mapping quality)
-  ``bams_umi_dedup/coverages/``: min/average/zero coverage of target regions
   after UMI deduplication (ignoring mapping quality)
-  ``variants_raw/``: annotated variant calls (ignoring UMIs, if any)

   -  full summary table: ``variants_raw/variants_summary.csv`` includes
      summary of all variants in all samples, with deleteriousness
      score, etc.
   -  filtered summary table:
      ``variants_raw/variants_summary_filtered.csv`` all variants from
      summary table that pass variant quality filters and have a
      coverage of at least 10

-  ``variants_umi/``: only generated if reads contained UMIs --
   annotated variant calls based on UMI deduplicated reads (otherwise
   as above)

Low-frequency variation analysis: ``pileups``
^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

-  ``pileups/``: target region pileup tables

   -  per-basepair pileups for all positions and all samples:
      ``pileups/pileups_long.csv``
   -  coverage over target regions:
      ``pileups/target_coverage.csv``

-  ``pileups_snps/``: SNP pileup tables (optional, requires ``snps.txt``)

   -  per-SNP pileups:
      ``pileups_snps/target_snps_pileups_long.csv``

Additional output
~~~~~~~~~~~~~~~~~~~~~~

In addition to the ``analysis`` directory, these folders may be created:

-  ``cluster_log/``: directory with log files for each job submitted to
   the cluster (contain error messages if cluster submission fails)