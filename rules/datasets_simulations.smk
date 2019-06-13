"""Rules for generating simulated HA sequences for validation of forecasting models.
"""
BUILD_PATH_SIMULATIONS = "results/builds/simulations/{percentage}/{start}--{end}/"
BUILD_LOG_STEM_SIMULATIONS = "{percentage}_{start}_{end}"
BUILD_TIMEPOINT_PATH_SIMULATIONS = BUILD_PATH_SIMULATIONS + "timepoints/{timepoint}/"
BUILD_SEGMENT_LOG_STEM_SIMULATIONS = "{percentage}_{start}_{end}_{timepoint}"

START_DATE_SIMULATIONS = "2010-10-01"
END_DATE_SIMULATIONS = "2030-10-01"
TIMEPOINTS_SIMULATIONS = _get_timepoints_for_build_interval(
    START_DATE_SIMULATIONS,
    END_DATE_SIMULATIONS,
    PIVOT_INTERVAL,
    MIN_YEARS_PER_BUILD
)
TRAIN_VALIDATE_TIMEPOINTS_SIMULATIONS = get_train_validate_timepoints(
    TIMEPOINTS_SIMULATIONS,
    config["fitness_model"]["delta_months"],
    config["fitness_model"]["training_window"]
)

#pprint.pprint(TRAIN_VALIDATE_TIMEPOINTS_SIMULATIONS)
#pprint.pprint(TIMEPOINTS_SIMULATIONS)

def float_to_datestring(time):
    """Convert a floating point date to a date string

    >>> float_to_datestring(2010.75)
    '2010-10-01'
    >>> float_to_datestring(2011.25)
    '2011-04-01'
    >>> float_to_datestring(2011.0)
    '2011-01-01'
    >>> float_to_datestring(2011.0 + 11.0 / 12)
    '2011-12-01'

    In some cases, the given float value can be truncated leading to unexpected
    conversion between floating point and integer values. This function should
    account for these errors by rounding months to the nearest integer.

    >>> float_to_datestring(2011.9166666666665)
    '2011-12-01'
    >>> float_to_datestring(2016.9609856262834)
    '2016-12-01'
    """
    year = int(time)

    # After accounting for the current year, extract the remainder and convert
    # it to a month using the inverse of the logic used to create the floating
    # point date. If the float date is sufficiently close to the end of the
    # year, rounding can produce a 13th month.
    month = min(int(np.rint(((time - year) * 12) + 1)), 12)

    # Floating point dates do not encode day information, so we always assume
    # they refer to the start of a given month.
    day = 1

    return "%s-%02d-%02d" % (year, month, day)


def _get_proportion_to_subsample_from_wildcards(wildcards):
    return round(int(wildcards.percentage) / 100.0, 2)


rule subsample_simulations:
    input:
       sequences = "data/simulations/HA_sequences_full.fasta"
       #sequences = "data/simulations/frequency_1.fasta"
    output:
       sequences = "results/datasets/h3_simulated_{percentage}pct/original_sequences.fasta"
    params:
        proportion = _get_proportion_to_subsample_from_wildcards
    conda: "../envs/anaconda.python3.yaml"
    shell:
        """
        seqtk sample {input.sequences} {params.proportion} > {output.sequences}
        """


rule parse_simulated_sequences:
    input:
        sequences = rules.subsample_simulations.output.sequences
    output:
        sequences = "results/datasets/h3_simulated_{percentage}pct/sequences.fasta",
        metadata = "results/datasets/h3_simulated_{percentage}pct/metadata.tsv"
    params:
        fasta_fields = "strain num_date"
    conda: "../envs/anaconda.python3.yaml"
    shell:
        """
        augur parse \
            --sequences {input.sequences} \
            --output-sequences {output.sequences} \
            --output-metadata {output.metadata} \
            --fields {params.fasta_fields}
        """


rule standardize_simulated_sequence_dates:
    input:
        metadata = rules.parse_simulated_sequences.output.metadata
    output:
        metadata = "results/datasets/h3_simulated_{percentage}pct/corrected_metadata.tsv"
    run:
        df = pd.read_csv(input.metadata, sep="\t")
        #df["num_date"] = 2000.0 + (df["generation"] / 100.0)
        df["num_date"] = df["num_date"] + 2000.0
        df["date"] = df["num_date"].apply(float_to_datestring)
        df.to_csv(output.metadata, header=True, index=False, sep="\t")


rule get_strains_for_simulated_sequences:
    input:
        metadata = rules.standardize_simulated_sequence_dates.output.metadata
    output:
        strains = "results/datasets/h3_simulated_{percentage}pct/strains.txt"
    run:
        df = pd.read_csv(input.metadata, sep="\t")
        df["strain"].to_csv(output.strains, header=False, index=False)


rule get_strains_by_timepoint:
    input:
        metadata = rules.standardize_simulated_sequence_dates.output.metadata
    output:
        strains = BUILD_TIMEPOINT_PATH_SIMULATIONS + "strains.txt"
    conda: "../envs/anaconda.python3.yaml"
    shell:
        """
        python3 scripts/partition_strains_by_timepoint.py \
            {input.metadata} \
            {wildcards.timepoint} \
            {output}
        """


rule extract_simulated:
    input:
        sequences = rules.parse_simulated_sequences.output.sequences,
        strains = rules.get_strains_by_timepoint.output.strains
    output:
        sequences = BUILD_TIMEPOINT_PATH_SIMULATIONS + "filtered_sequences.fasta"
    conda: "../envs/anaconda.python3.yaml"
    shell:
        """
        python3 scripts/extract_sequences.py \
            --sequences {input.sequences} \
            --samples {input.strains} \
            --output {output}
        """


rule align_simulated:
    message:
        """
        Aligning sequences for {wildcards}
          - filling gaps with N
        """
    input:
        sequences = rules.extract_simulated.output.sequences,
    output:
        alignment = BUILD_TIMEPOINT_PATH_SIMULATIONS + "aligned.fasta"
    conda: "../envs/anaconda.python3.yaml"
    benchmark: "benchmarks/align_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + ".txt"
    threads: 4
    shell:
        """
        augur align \
            --sequences {input.sequences} \
            --output {output.alignment} \
            --fill-gaps \
            --nthreads {threads}
        """


rule tree_simulated:
    message: "Building tree ({wildcards})"
    input:
        alignment = rules.align_simulated.output.alignment
    output:
        tree = BUILD_TIMEPOINT_PATH_SIMULATIONS + "tree_raw.nwk"
    conda: "../envs/anaconda.python3.yaml"
    shadow: "minimal"
    benchmark: "benchmarks/tree_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + ".txt"
    log: "logs/tree_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + ".log"
    threads: 4
    shell:
        """
        augur tree \
            --alignment {input.alignment} \
            --output {output.tree} \
            --method iqtree \
            --nthreads {threads} &> {log}
        """


rule refine_simulated:
    message:
        """
        Refining tree ({wildcards})
          - estimate timetree
          - use {params.coalescent} coalescent timescale
          - estimate {params.date_inference} node dates
          - filter tips more than {params.clock_filter_iqd} IQDs from clock expectation
        """
    input:
        tree = rules.tree_simulated.output.tree,
        alignment = rules.align_simulated.output.alignment,
        metadata = rules.standardize_simulated_sequence_dates.output.metadata
    output:
        tree = BUILD_TIMEPOINT_PATH_SIMULATIONS + "tree.nwk",
        node_data = BUILD_TIMEPOINT_PATH_SIMULATIONS + "branch_lengths.json"
    params:
        coalescent = "const",
        date_inference = "marginal",
        clock_filter_iqd = 4
    conda: "../envs/anaconda.python3.yaml"
    benchmark: "benchmarks/refine_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + ".txt"
    log: "logs/refine_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + ".log"
    shell:
        """
        augur refine \
            --tree {input.tree} \
            --alignment {input.alignment} \
            --metadata {input.metadata} \
            --output-tree {output.tree} \
            --output-node-data {output.node_data} \
            --timetree \
            --clock-filter-iqd {params.clock_filter_iqd} \
            --coalescent {params.coalescent} \
            --date-confidence \
            --date-inference {params.date_inference} &> {log}
        """


rule ancestral_simulated:
    message: "Reconstructing ancestral sequences and mutations for {wildcards}"
    input:
        tree = rules.refine_simulated.output.tree,
        alignment = rules.align_simulated.output.alignment
    output:
        node_data = BUILD_TIMEPOINT_PATH_SIMULATIONS + "nt_muts.json",
        sequences = BUILD_TIMEPOINT_PATH_SIMULATIONS + "nt.fasta"
    params:
        inference = "joint"
    conda: "../envs/anaconda.python3.yaml"
    benchmark: "benchmarks/ancestral_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + ".txt"
    log: "logs/ancestral_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + ".txt"
    shell:
        """
        augur ancestral \
            --tree {input.tree} \
            --alignment {input.alignment} \
            --output-json {output.node_data} \
            --output-fasta {output.sequences} \
            --inference {params.inference} &> {log}
        """


rule distances_simulated:
    input:
        tree = rules.refine_simulated.output.tree,
        alignments = rules.ancestral_simulated.output.sequences,
        epitope_distance_map = "config/distance_maps/simulated_epitopes_map.json",
        nonepitope_distance_map = "config/distance_maps/simulated_nonepitopes_map.json"
    params:
        genes = "HA1",
        comparisons = "root root",
        attribute_names = "ep ne"
    output:
        distances = BUILD_TIMEPOINT_PATH_SIMULATIONS + "distances.json",
    conda: "../envs/anaconda.python3.yaml"
    shell:
        """
        augur distance \
            --tree {input.tree} \
            --alignment {input.alignments} \
            --gene-names {params.genes} \
            --compare-to {params.comparisons} \
            --attribute-name {params.attribute_names} \
            --map {input.epitope_distance_map} {input.nonepitope_distance_map} \
            --output {output}
        """


rule lbi_simulated:
    message: "Calculating LBI"
    input:
        tree = rules.refine_simulated.output.tree,
        branch_lengths = rules.refine_simulated.output.node_data
    params:
        tau = config["lbi"]["tau"],
        window = config["lbi"]["window"],
        names = "lbi"
    output:
        lbi = BUILD_TIMEPOINT_PATH_SIMULATIONS + "lbi.json"
    conda: "../envs/anaconda.python3.yaml"
    shell:
        """
        augur lbi \
            --tree {input.tree} \
            --branch-lengths {input.branch_lengths} \
            --output {output} \
            --attribute-names {params.names} \
            --tau {params.tau} \
            --window {params.window}
        """


rule tip_frequencies_simulated:
    message:
        """
        Estimating tip frequencies for {input.tree}
          - narrow bandwidth: {params.narrow_bandwidth}
          - wide bandwidth: {params.wide_bandwidth}
          - proportion wide: {params.proportion_wide}
        """
    input:
        tree=rules.refine_simulated.output.tree,
        metadata=rules.standardize_simulated_sequence_dates.output.metadata,
        weights="data/region_weights.json"
    output:
        frequencies = "results/auspice/simulated_flu_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + "_tip-frequencies.json"
    params:
        narrow_bandwidth=config["frequencies"]["narrow_bandwidth"],
        wide_bandwidth=config["frequencies"]["wide_bandwidth"],
        proportion_wide=config["frequencies"]["proportion_wide"],
        pivot_frequency=PIVOT_INTERVAL,
        min_date=_get_min_date_for_augur_frequencies,
        max_date=_get_max_date_for_augur_frequencies
    conda: "../envs/anaconda.python3.yaml"
    benchmark: "benchmarks/tip_frequencies_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + ".txt"
    log: "logs/tip_frequencies_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + ".log"
    shell:
        """
        augur frequencies \
            --method kde \
            --tree {input.tree} \
            --metadata {input.metadata} \
            --narrow-bandwidth {params.narrow_bandwidth} \
            --wide-bandwidth {params.wide_bandwidth} \
            --proportion-wide {params.proportion_wide} \
            --min-date {params.min_date} \
            --max-date {params.max_date} \
            --pivot-interval {params.pivot_frequency} \
            --output {output}
        """
#            --weights {input.weights} \
#            --weights-attribute region \


def _get_node_data_for_export_simulated(wildcards):
    """Return a list of node data files to include for a given build's wildcards.
    """
    # Define inputs shared by specific builds.
    inputs = [
        rules.refine_simulated.output.node_data,
        rules.ancestral_simulated.output.node_data,
        rules.distances_simulated.output.distances,
        rules.lbi_simulated.output.lbi
    ]

    # Convert input files from wildcard strings to real file names.
    inputs = [input_file.format(**wildcards) for input_file in inputs]
    return inputs


rule export_simulated:
    input:
        tree = rules.refine_simulated.output.tree,
        metadata = rules.standardize_simulated_sequence_dates.output.metadata,
        auspice_config = "config/auspice_config.json",
        node_data = _get_node_data_for_export_simulated,
        colors = "config/colors.tsv"
    output:
        auspice_tree = "results/auspice/simulated_flu_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + "_tree.json",
        auspice_metadata = "results/auspice/simulated_flu_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + "_meta.json"
#        auspice_sequence = "results/auspice/simulated_flu_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + "_seq.json",
    params:
        panels = "tree entropy"
    conda: "../envs/anaconda.python3.yaml"
    shell:
        """
        augur export \
            --tree {input.tree} \
            --metadata {input.metadata} \
            --node-data {input.node_data} \
            --colors {input.colors} \
            --auspice-config {input.auspice_config} \
            --output-tree {output.auspice_tree} \
            --output-meta {output.auspice_metadata} \
            --panels {params.panels} \
            --minify-json
        """


rule convert_node_data_to_table_simulated:
    input:
        tree = rules.refine_simulated.output.tree,
        node_data = _get_node_data_for_export_simulated
    output:
        table = BUILD_TIMEPOINT_PATH_SIMULATIONS + "node_data.tsv"
    params:
        excluded_fields_arg = _get_excluded_fields_arg
    conda: "../envs/anaconda.python3.yaml"
    shell:
        """
        python3 scripts/node_data_to_table.py \
            --tree {input.tree} \
            --jsons {input.node_data} \
            --output {output} \
            {params.excluded_fields_arg} \
            --annotations timepoint={wildcards.timepoint} \
                          lineage=simulated
        """


rule estimate_frequencies_simulated:
    message:
        """
        Estimating frequencies for {input.tree}
          - narrow bandwidth: {params.narrow_bandwidth}
          - wide bandwidth: {params.wide_bandwidth}
          - proportion wide: {params.proportion_wide}
        """
    input:
        tree=rules.refine_simulated.output.tree,
        metadata=rules.standardize_simulated_sequence_dates.output.metadata,
        weights="data/region_weights.json"
    output:
        frequencies = BUILD_TIMEPOINT_PATH_SIMULATIONS + "frequencies.json"
    params:
        narrow_bandwidth=config["frequencies"]["narrow_bandwidth"],
        wide_bandwidth=config["frequencies"]["wide_bandwidth"],
        proportion_wide=config["frequencies"]["proportion_wide"],
        pivot_frequency=PIVOT_INTERVAL
    conda: "../envs/anaconda.python3.yaml"
    benchmark: "benchmarks/estimate_frequencies_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + ".txt"
    log: "logs/estimate_frequencies_" + BUILD_SEGMENT_LOG_STEM_SIMULATIONS + ".log"
    shell: """python3 scripts/frequencies.py {input.tree} {input.metadata} {output} \
--narrow-bandwidth {params.narrow_bandwidth} \
--wide-bandwidth {params.wide_bandwidth} \
--proportion-wide {params.proportion_wide} \
--pivot-frequency {params.pivot_frequency} \
--start-date {wildcards.start} \
--end-date {wildcards.timepoint} \
--include-internal-nodes &> {log}"""


rule convert_frequencies_to_table_simulated:
    input:
        tree = rules.refine_simulated.output.tree,
        frequencies = rules.estimate_frequencies_simulated.output.frequencies
    output:
        table = BUILD_TIMEPOINT_PATH_SIMULATIONS + "frequencies.tsv"
    conda: "../envs/anaconda.python3.yaml"
    shell:
        """
        python3 scripts/frequencies_to_table.py \
            --tree {input.tree} \
            --frequencies {input.frequencies} \
            --output {output} \
            --annotations timepoint={wildcards.timepoint}
        """


rule merge_node_data_and_frequencies_simulated:
    input:
        node_data = rules.convert_node_data_to_table_simulated.output.table,
        frequencies = rules.convert_frequencies_to_table_simulated.output.table
    output:
        table = BUILD_TIMEPOINT_PATH_SIMULATIONS + "tip_attributes.tsv"
    run:
        node_data = pd.read_table(input.node_data)
        frequencies = pd.read_table(input.frequencies)
        df = node_data.merge(
            frequencies,
            how="inner",
            on=["strain", "timepoint", "is_terminal"]
        )

        df.to_csv(output.table, sep="\t", index=False, header=True)


rule collect_tip_attributes_simulated:
    input:
        expand(BUILD_PATH_SIMULATIONS.replace("{", "{{").replace("}", "}}") + "timepoints/{timepoint}/tip_attributes.tsv", timepoint=TIMEPOINTS_SIMULATIONS)
    output:
        attributes = BUILD_PATH_SIMULATIONS + "tip_attributes.tsv"
    conda: "../envs/anaconda.python3.yaml"
    shell:
        """
        python3 scripts/collect_tables.py \
            --tables {input} \
            --output {output.attributes}
        """


rule target_distances_simulated:
    input:
        attributes = rules.collect_tip_attributes_simulated.output.attributes
    output:
        distances = BUILD_PATH_SIMULATIONS + "target_distances.tsv",
    params:
        delta_months = config["fitness_model"]["delta_months"]
    conda: "../envs/anaconda.python3.yaml"
    shell:
        """
        python3 scripts/calculate_target_distances.py \
            --tip-attributes {input.attributes} \
            --delta-months {params.delta_months} \
            --sequence-attribute-name sequence \
            --output {output}
        """


rule annotate_naive_tip_attribute_simulated:
    input:
        attributes = rules.collect_tip_attributes_simulated.output.attributes
    output:
        attributes = BUILD_PATH_SIMULATIONS + "tip_attributes_with_naive_predictor.tsv",
    run:
        # Annotate a predictor for a naive model with no growth.
        df = pd.read_csv(input.attributes, sep="\t")
        df["naive"] = 0.0
        df.to_csv(output.attributes, sep="\t", index=False)


rule annotate_weighted_distances_for_tip_attributes_simulated:
    input:
        attributes = rules.annotate_naive_tip_attribute_simulated.output.attributes,
        distances = rules.target_distances_simulated.output.distances
    output:
        attributes = BUILD_PATH_SIMULATIONS + "tip_attributes_with_weighted_distances.tsv"
    params:
        delta_months = config["fitness_model"]["delta_months"]
    shell:
        """
        python3 src/weighted_distances.py \
            --tip-attributes {input.attributes} \
            --distances {input.distances} \
            --delta-months {params.delta_months} \
            --output {output}
        """


rule fit_models_by_distances_simulated:
    input:
        attributes = rules.annotate_weighted_distances_for_tip_attributes_simulated.output.attributes,
        distances = rules.target_distances_simulated.output.distances
    output:
        model = BUILD_PATH_SIMULATIONS + "models_by_distances/{predictors}.json"
    params:
        predictors = _get_predictor_list,
        delta_months = config["fitness_model"]["delta_months"],
        training_window = config["fitness_model"]["training_window"],
        cost_function = config["fitness_model"]["distance_cost_function"],
        l1_lambda = config["fitness_model"]["l1_lambda"]
    conda: "../envs/anaconda.python3.yaml"
    benchmark: "benchmarks/fitness_model_distances_" + BUILD_LOG_STEM_SIMULATIONS + "_{predictors}.txt"
    log: "logs/fitness_model_distances_" + BUILD_LOG_STEM_SIMULATIONS + "_{predictors}.txt"
    shell:
        """
        python3 src/fit_model.py \
            --tip-attributes {input.attributes} \
            --training-window {params.training_window} \
            --delta-months {params.delta_months} \
            --predictors {params.predictors} \
            --cost-function {params.cost_function} \
            --l1-lambda {params.l1_lambda} \
            --target distances \
            --distances {input.distances} \
            --output {output} &> {log}
        """
