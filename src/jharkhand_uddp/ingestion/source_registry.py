# Central registry for all source datasets.

from dataclasses import dataclass


@dataclass(frozen=True)
class SourceDefinition:
    source_name: str
    filename: str
    table_name: str
    required_columns: tuple[str, ...]
    state_column: str
    district_name_column: str | None = None


SOURCE_REGISTRY = (
    SourceDefinition(
        source_name="Census District Demographics",
        filename="india-districts-census-2011.csv",
        table_name="census_demographics_raw",
        required_columns=(
            "District code",
            "State name",
            "District name",
            "Population",
            "Male",
            "Female",
            "Literate",
            "Workers",
            "SC",
            "ST",
            "Households",
        ),
        state_column="State name",
        district_name_column="District name",
    ),
    SourceDefinition(
        source_name="Census District Housing",
        filename="hlpca-total.csv",
        table_name="census_housing_raw",
        required_columns=(
            "State Code",
            "State Name",
            "District Code",
            "District Name",
            "Total Number of households",
        ),
        state_column="State Name",
        district_name_column="District Name",
    ),
    SourceDefinition(
        source_name="National Social Assistance Programme",
        filename="RS_Session_256_AU_3148_1.csv",
        table_name="nsap_pension_raw",
        required_columns=(
            "Category",
            "States/UTs",
            "Old Age Pension Scheme",
            "Widow Pension Scheme",
            "Divyangjan /Disability Pension Scheme",
        ),
        state_column="States/UTs",
    ),
)
