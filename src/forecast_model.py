"""Forecast given tip data into future using the given previously trained model.
"""
import argparse
import json
import numpy as np
import pandas as pd
import sys

from fit_model import DistanceExponentialGrowthModel
from weighted_distances import get_distances_by_sample_names


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--tip-attributes", required=True, help="tab-delimited file describing tip attributes at all timepoints with standardized predictors")
    parser.add_argument("--distances", help="tab-delimited file of distances between pairs of samples")
    parser.add_argument("--model", required=True, help="JSON representing the model fit with training and cross-validation results, beta coefficients for predictors, and summary statistics")
    parser.add_argument("--delta-months", required=True, type=int, nargs="+", help="number of months to project clade frequencies into the future")
    parser.add_argument("--output", required=True, help="table of forecasts for the given tips")

    args = parser.parse_args()

    # Load standardized tip attributes subsetting to tip name, clade, frequency,
    # and requested predictors.
    tips = pd.read_csv(
        args.tip_attributes,
        sep="\t",
        parse_dates=["timepoint"]
    )

    # Load distances.
    distances = pd.read_csv(args.distances, sep="\t")
    distances_by_sample_names = get_distances_by_sample_names(distances)

    # Load model details
    with open(args.model, "r") as fh:
        model_json = json.load(fh)

    predictors = model_json["predictors"]
    cost_function = model_json["cost_function"]
    l1_lambda = model_json["l1_lambda"]
    coefficients = np.array(model_json["coefficients_mean"])
    mean_stds = np.array(model_json["mean_stds_mean"])

    forecasts = []
    for delta_month in args.delta_months:
        # For each train/validate split, fit a model to the training data, and
        # evaluate the model with the validation data, storing the training results,
        # beta parameters, and validation results.
        delta_time = delta_month / 12.0
        delta_offset = pd.DateOffset(months=delta_month)

        model = DistanceExponentialGrowthModel(
            predictors=predictors,
            delta_time=delta_time,
            cost_function=cost_function,
            l1_lambda=l1_lambda,
            distances=distances_by_sample_names
        )
        model.coef_ = coefficients
        model.mean_stds_ = mean_stds

        # Forecast given tips.
        forecasts_df = model.predict(tips)
        forecasts_df["weighted_distance_to_future_by_%s" % "-".join(predictors)] = forecasts_df["y"]
        forecasts_df["future_timepoint"] = forecasts_df["timepoint"] + delta_offset

        forecasts.append(forecasts_df)

    all_forecasts = pd.concat(forecasts, ignore_index=True)
    all_forecasts.to_csv(args.output, sep="\t", index=False, header=True, na_rep="N/A")