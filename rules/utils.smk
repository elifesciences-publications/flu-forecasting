#
# Define helper functions.
#
import datetime


def float_to_datestring(time):
    """Convert a floating point date from TreeTime `numeric_date` to a date string
    """
    # Extract the year and remainder from the floating point date.
    year = int(time)
    remainder = time - year

    # Calculate the day of the year (out of 365 + 0.25 for leap years).
    tm_yday = int(remainder * 365.25)
    if tm_yday == 0:
        tm_yday = 1

    # Construct a date object from the year and day of the year.
    date = datetime.datetime.strptime("%s-%s" % (year, tm_yday), "%Y-%j")

    # Build the date string with zero-padded months and days.
    date_string = "%s-%.2i-%.2i" % (date.year, date.month, date.day)

    return date_string

def _get_sequences_by_wildcards(wildcards):
    return config["builds"][wildcards.type][wildcards.sample]["sequences"]

def _get_metadata_by_wildcards(wildcards):
    return config["builds"][wildcards.type][wildcards.sample]["metadata"]

def _get_strains_by_wildcards(wildcards):
    return config["builds"][wildcards.type][wildcards.sample]["strains"]

def _get_titers_by_wildcards(wildcards):
    return config["builds"][wildcards.type][wildcards.sample]["titers"]

def _get_start_date_by_wildcards(wildcards):
    return config["builds"][wildcards.type][wildcards.sample]["start_date"]

def _get_end_date_by_wildcards(wildcards):
    return config["builds"][wildcards.type][wildcards.sample]["end_date"]

def _get_min_date_for_augur_frequencies_by_wildcards(wildcards):
    return timestamp_to_float(pd.to_datetime(_get_start_date_by_wildcards(wildcards)))

def _get_min_date_for_diffusion_frequencies_by_wildcards(wildcards):
    # Calculate min date for diffusion frequencies based on the current
    # timepoint minus the maximum number of years back allowed.
    years_back = config["frequencies"]["max_years_for_diffusion"]
    offset = pd.DateOffset(years=years_back)

    start_date = pd.to_datetime(_get_start_date_by_wildcards(wildcards))
    timepoint_date = pd.to_datetime(wildcards.timepoint)
    min_diffusion_date = max(start_date, timepoint_date - offset)

    return timestamp_to_float(min_diffusion_date)

def _get_max_date_for_augur_frequencies_by_wildcards(wildcards):
    return timestamp_to_float(pd.to_datetime(wildcards.timepoint))

def _get_viruses_per_month(wildcards):
    return config["datasets"][wildcards.sample]["viruses_per_month"]

def _get_simulation_seed(wildcards):
    return config["datasets"][wildcards.sample]["seed"]

def _get_fauna_fields(wildcards):
    return config["datasets"][wildcards.sample]["fauna_fields"]

def _get_fasta_fields(wildcards):
    return config["datasets"][wildcards.sample]["fasta_fields"]

def _get_lineage(wildcards):
    return config["datasets"][wildcards.sample]["lineage"]

def _get_segment(wildcards):
    return config["datasets"][wildcards.sample]["segment"]

def _get_titer_databases(wildcards):
    return config["datasets"][wildcards.sample]["titer_databases"]

def _get_titer_assay(wildcards):
    return config["datasets"][wildcards.sample]["titer_assay"]

def _get_titer_passage(wildcards):
    return config["datasets"][wildcards.sample]["titer_passage"]

def _get_min_sequence_length(wildcards):
    return config["datasets"][wildcards.sample]["min_sequence_length"]

def _get_outliers(wildcards):
    return config["datasets"][wildcards.sample]["outliers"]

def _get_required_strains(wildcards):
    return config["datasets"][wildcards.sample]["required_strains"]

def _get_start_date_for_dataset(wildcards):
    return config["datasets"][wildcards.sample]["start_date"]

def _get_end_date_for_dataset(wildcards):
    return config["datasets"][wildcards.sample]["end_date"]

def _get_reference(wildcards):
    return config["builds"][wildcards.type][wildcards.sample]["reference"]

def _get_pivot_interval(wildcards):
    return config["builds"][wildcards.type][wildcards.sample]["pivot_interval"]

def _get_min_date_for_translation_filter(wildcards):
    timepoint = pd.to_datetime(wildcards.timepoint)
    min_date = timepoint - pd.DateOffset(years=config["years_for_titer_alignments"])
    return min_date.strftime("%Y-%m-%d")

def _get_tip_attributes_by_wildcards(wildcards):
    build = config["builds"][wildcards.type][wildcards.sample]
    timepoints = _get_timepoints_for_build_interval(
        build["start_date"],
        build["end_date"],
        build["pivot_interval"],
        build["min_years_per_build"]
    )
    return expand(
        BUILD_PATH.replace("{", "{{").replace("}", "}}") + "timepoints/{timepoint}/tip_attributes.tsv",
        timepoint=timepoints
    )

def _get_tip_clades_by_wildcards(wildcards):
    build = config["builds"][wildcards.type][wildcards.sample]
    timepoints = _get_timepoints_for_build_interval(
        build["start_date"],
        build["end_date"],
        build["pivot_interval"],
        build["min_years_per_build"]
    )
    return expand(
        BUILD_PATH.replace("{", "{{").replace("}", "}}") + "timepoints/{timepoint}/tips_to_clades.tsv",
        timepoint=timepoints
    )

def _get_final_tree_for_wildcards(wildcards):
    end_date = _get_end_date_by_wildcards(wildcards)
    return BUILD_PATH.format(**wildcards) + "timepoints/%s/tree.nwk" % end_date