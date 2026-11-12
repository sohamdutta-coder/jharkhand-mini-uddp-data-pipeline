# Assumptions and Data Limitations

This document records the assumptions used in the Jharkhand Mini-UDDP Data Pipeline.

The project uses public aggregate information only and does not attempt to identify individual citizens or beneficiaries.

## 1. Source Data

### Census Demographics

- Reference year: 2011.
- The district dataset contains demographic indicators for Indian districts.
- The pipeline selects the 24 Jharkhand districts represented in the source.
- District codes are used as the primary matching key.
- Census 2011 values are historical reference data, not current population estimates.

### Census Housing

- Reference year: 2011.
- The housing source contains district-level housing indicators.
- The pipeline selects Jharkhand records representing the total Rural/Urban aggregation.
- The housing dataset's `Total Number of households` field is a percentage-reference value, not an absolute household count.
- Absolute district household counts are taken from the demographic dataset's `Households` field.
- Housing condition and housing-type indicators are interpreted according to the source's published percentages.

### NSAP Pension Beneficiaries

- The supplied NSAP resource contains State/UT-level beneficiary counts.
- It does not provide district-level Jharkhand beneficiary counts.
- The Bronze layer preserves the original resource, including its Grand Total row.
- Silver transforms the 36 State/UT administrative units and three pension schemes into 108 rows.
- Grand Total is excluded from the Silver fact table to avoid treating it as an administrative unit.
- The Jharkhand State-level counts are retained at State level.

The Jharkhand State-level values in the supplied resource are:

| Scheme | Beneficiaries |
|---|---:|
| Old Age Pension | 993,567 |
| Widow Pension | 272,108 |
| Disability Pension | 31,286 |

These values must not be distributed across districts without a valid district-level source.

Consequently, the following Gold and ML district-level fields are NULL:

- Old-age pension beneficiary count.
- Widow pension beneficiary count.
- Old-age beneficiaries per 1,000 population.
- Widow beneficiaries per 1,000 population.
- Old-age beneficiaries per 1,000 households.
- Widow beneficiaries per 1,000 households.
- Total pension beneficiaries per 1,000 households.

The `district_pension_data_available` flag is FALSE for all 24 districts.

NULL means unavailable, not zero beneficiaries.

## 2. District Matching

- The demographic dataset provides the canonical Jharkhand district codes and names.
- District codes are the primary join key where available.
- District names are checked for consistency across sources.
- Only the relevant Jharkhand total housing records are used.
- Unmatched or invalid source records are reported or quarantined rather than silently discarded.
- The validated Census sources contain 24 matching Jharkhand districts.

District codes are preferred over district names because names may differ in spelling, punctuation or transliteration.

## 3. Population and Household Measures

- Total population is taken from the Census demographic dataset.
- Male and female population counts are retained separately.
- Literacy and work participation indicators use the available Census counts and population denominators as implemented in the Gold transformation.
- SC and ST population counts are retained separately.
- Total households are sourced from the demographic dataset.
- Population per household is calculated as a household-pressure proxy.

Population per household is not geographic population density. The pipeline does not contain district land-area measurements.

## 4. Age Indicator

The available demographic source provides an `Age_Group_50` field representing the population aged 50 and above.

The pipeline uses this as an age-vulnerability proxy.

It is not an exact count of persons aged 60 and above and must not be described as the official elderly population.

This limitation should be considered when interpreting district priorities for old-age pension outreach.

## 5. Priority Score

The priority score is a custom, explainable vulnerability proxy designed for the available data.

| Component | Weight |
|---|---:|
| Age 50+ population share | 25% |
| Dilapidated housing share | 20% |
| Combined SC/ST population share | 15% |
| Reverse literacy rate | 15% |
| Reverse work participation rate | 10% |
| Population per household | 10% |
| Female population share | 5% |

Each component is normalised to a range of 0 to 1 across the 24 districts.

For indicators where higher values represent greater vulnerability, min-max normalisation is used:

`(value - minimum) / (maximum - minimum)`

For literacy and work participation, the direction is reversed:

`(maximum - value) / (maximum - minimum)`

The weighted sum is multiplied by 100.

The formula does not include pension coverage because the available NSAP data is not district-level.

Female population share is a demographic context indicator only. It is not a proxy for widow prevalence.

The resulting score is a relative ranking within the 24-district dataset. It is not a validated measure of unmet pension demand or scheme eligibility.

### Priority categories

Districts are ranked by descending score and divided into three groups using `NTILE(3)`.

With 24 districts, each group contains eight districts.

- High: ranks 1–8.
- Medium: ranks 9–16.
- Low: ranks 17–24.

District code provides deterministic secondary ordering when scores are tied.

## 6. ML Target and Leakage

The ML table uses:

`target_high_priority = 1` for High priority districts, and `0` for Medium or Low priority districts.

This is a rule-derived demonstration label obtained from the Gold classification.

It is not an observed outcome such as successful enrolment, verified eligibility or outreach conversion.

Because the target is derived from the vulnerability indicators, training a supervised model using those same indicators would cause target leakage.

A future predictive model should:

1. Use independently measured outcomes.
2. Exclude the priority score, score components, rank and category from predictors.
3. Ensure predictor timestamps precede outcome timestamps.
4. Use temporal and geographic validation.
5. Evaluate against genuinely unseen observations.

The current dataset contains only 24 district observations and is intended for feature-engineering demonstration, not for claiming production predictive performance.

## 7. Data Quality

- Bronze preserves the original source row as JSONB.
- Ingestion metadata records source file hashes and row counts.
- Duplicate and unmatched district records are checked.
- Numeric and percentage values are validated.
- Population and household relationships are checked.
- Gender and age-group population totals are reconciled.
- Housing percentages are reconciled.
- NSAP administrative units, scheme categories and beneficiary counts are validated.
- Bronze-to-Silver record counts are checked.
- Invalid records are quarantined or included in exception reports.

The ingestion freshness check validates recent pipeline ingestion timestamps. It does not establish that the original public source was recently published or updated.

## 8. Scope and Privacy

This assessment is a simulated aggregate-data pipeline.

It does not include:

- Individual citizen or beneficiary records.
- Aadhaar numbers.
- Bank-account information.
- Mobile numbers.
- Ration-card identifiers.
- Person-level eligibility or enrolment decisions.

Any future UDDP extension involving such information would require appropriate legal, governance, privacy and security controls.
