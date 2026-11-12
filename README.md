# Jharkhand Mini-UDDP Data Pipeline

An end-to-end ETL/ELT pipeline built with Python, PostgreSQL and SQL to integrate public Census demographic, housing and social-security pension data into a district-level outreach prioritisation dataset for Jharkhand.

The project implements a Medallion Architecture with Bronze, Silver and Gold layers, a Data Quality framework, an AI-ready feature dataset and a Python-based orchestration layer.

## 1. Business Objective

The objective is to identify Jharkhand districts that may require greater attention for old-age and widow pension outreach.

The pipeline combines:

- District-level demographic indicators from Census 2011.
- District-level housing indicators from Census 2011.
- State/UT-level pension beneficiary statistics from the National Social Assistance Programme (NSAP).

It produces a district-level vulnerability-based outreach priority score and classifies districts into High, Medium and Low priority categories.

**Important:** The NSAP source contains State/UT-level pension counts, not district-level counts. Therefore, district-level pension coverage cannot be calculated from the available data. Missing district-level values remain NULL rather than being estimated or allocated.

## 2. Architecture

The solution follows a Medallion Architecture:

| Layer | Purpose |
|---|---|
| Bronze | Preserve source records and ingestion metadata |
| Silver | Clean, standardise and model demographic, housing and pension data |
| Gold | Produce the district-level pension outreach mart |
| ML | Store district-level features and a rule-derived target |
| DQ | Execute validations, record results and quarantine invalid source records |

The detailed architecture and data-flow diagrams are available in [docs/architecture.md](docs/architecture.md).

## 3. Technology Stack

| Component | Technology |
|---|---|
| Programming language | Python 3.12 |
| Database | PostgreSQL |
| Data processing | Pandas |
| Database connectivity | SQLAlchemy, Psycopg 3 |
| Transformations | SQL |
| Configuration | YAML, python-dotenv |
| Orchestration | Custom Python orchestrator |
| Logging | Python logging |
| Code quality | Ruff |
| Testing | Pytest and quarantine smoke test |

The pipeline uses PostgreSQL's `psql` command-line client to execute SQL transformation scripts.

## 4. Data Sources

### Source 1: Census 2011 District Dataset

- Repository: [India Census 2011 Analysis](https://github.com/nishusharma1608/India-Census-2011-Analysis)
- Raw CSV: [india-districts-census-2011.csv](https://raw.githubusercontent.com/nishusharma1608/India-Census-2011-Analysis/master/india-districts-census-2011.csv)
- Purpose: Population, gender, literacy, workers, SC/ST population, age groups and household counts.

### Source 2: Census 2011 Housing Dataset

- Repository: [India Census 2011](https://github.com/pigshell/india-census-2011)
- Raw CSV: [hlpca-total.csv](https://raw.githubusercontent.com/pigshell/india-census-2011/master/hlpca-total.csv)
- Purpose: Housing conditions, housing types and serviceability indicators.

### Source 3: NSAP Pension Beneficiary Dataset

- Source: [Open Government Data India - State/UT-wise NSAP Pension Beneficiaries](https://www.data.gov.in/resource/stateneuts-wise-beneficiaries-under-pension-schemes-national-social-assistance-programme)
- Format: Downloadable tabular resource.
- Purpose: Old Age, Widow and Disability Pension beneficiary statistics at State/UT level.

The pipeline uses public aggregate information only. It does not access individual citizen or beneficiary records.

## 5. Repository Structure

```text
jharkhand-mini-uddp-data-pipeline/
│
├── config/
│   ├── config.yaml
│   └── pipeline.yaml
│
├── data/
│   └── raw/                        # Local source files; excluded from Git
│
├── docs/
│   ├── architecture.md
│   └── data_dictionary.md
│
├── outputs/
│   ├── mart_district_pension_outreach.csv
│   └── ml_district_features.csv
│
├── reports/
│   ├── data_quality_report.csv
│   └── unmatched_districts.csv
│
├── scripts/
│   ├── check_database.py
│   ├── export_gold_mart.py
│   ├── export_ml_features.py
│   ├── ingest_bronze.py
│   ├── inspect_source_files.py
│   ├── run_data_quality.py
│   ├── run_pipeline.py
│   └── test_quarantine.py
│
├── sql/
│   ├── setup/
│   ├── silver/
│   ├── quality/
│   ├── gold/
│   └── ml/
│
├── src/jharkhand_uddp/
│   ├── database/
│   ├── ingestion/
│   ├── quality/
│   ├── transformations/
│   ├── features/
│   ├── orchestration/
│   └── utils/
│
├── tests/
│
├── .env.example
├── .gitignore
├── requirements.in
├── requirements.txt
├── requirements-dev.in
├── requirements-dev.txt
├── ASSUMPTIONS.md
└── README.md
```

## 6. Database Design

The project uses five PostgreSQL schemas and 13 tables.

### Bronze

| Table | Grain |
|---|---|
| `bronze.ingestion_metadata` | One record per source-file ingestion version |
| `bronze.census_demographics_raw` | One record per original demographic CSV row and source version |
| `bronze.census_housing_raw` | One record per original housing CSV row and source version |
| `bronze.nsap_pension_raw` | One record per original NSAP CSV row and source version |

Original source records are stored as `JSONB`. Ingestion metadata includes source name, file name, SHA-256, file size, source row count, loaded row count, ingestion status and timestamps.

### Silver

| Table | Grain |
|---|---|
| `silver.dim_district` | One row per standardised Jharkhand district |
| `silver.fact_district_demographics` | One row per Jharkhand district |
| `silver.fact_district_housing` | One row per Jharkhand district |
| `silver.fact_pension_beneficiaries` | One row per administrative unit and pension scheme |

### Gold

| Table | Grain |
|---|---|
| `gold.mart_district_pension_outreach` | One row per Jharkhand district |

The Gold mart combines demographic and housing indicators, nullable district-level pension fields, vulnerability components, a priority score, rank and priority category.

### ML

| Table | Grain |
|---|---|
| `ml.ml_district_features` | One row per Jharkhand district |

This table contains district-level features, pension data availability indicators and a binary rule-derived priority target.

### Data Quality

| Table | Grain |
|---|---|
| `dq.data_quality_runs` | One row per data quality execution |
| `dq.data_quality_results` | One row per check execution within a DQ run |
| `dq.quarantined_records` | One row per quarantined source record and recorded reason |

See [data_dictionary.md](docs/data_dictionary.md) for the complete table inventory, keys and important columns.

## 7. Data Cleaning and Standardisation

The pipeline:

1. Reads and validates the required source columns.
2. Converts and validates numeric fields.
3. Standardises district identifiers and names.
4. Matches Jharkhand districts across Census datasets.
5. Detects missing, duplicate and unmatched records.
6. Quarantines invalid source records or reports them separately.
7. Preserves original Bronze records.

District codes are used as the primary matching key where available. Standardised district names are used for validation and reporting.

The demographic and housing sources contain 24 matching Jharkhand districts, with no missing districts or name mismatches in the validated execution.

## 8. Data Quality Framework

The pipeline implements 26 data quality checks.

These cover:

- Duplicate district codes.
- Missing district names and codes.
- Districts missing from source datasets.
- Unmatched demographic and housing records.
- Missing or invalid numeric values.
- Population less than or equal to zero.
- Households greater than population.
- Gender population reconciliation.
- Age-group population reconciliation.
- Housing percentage validation.
- Housing condition reconciliation.
- Negative pension beneficiary counts.
- Administrative-unit and scheme reconciliation.
- Bronze-to-Silver row-count reconciliation.
- Bronze ingestion metadata reconciliation.
- Ingestion timestamp freshness.

Bad records are quarantined or reported; they are not silently discarded.

Data quality results are persisted in PostgreSQL and exported to `reports/data_quality_report.csv`.

The latest complete pipeline execution recorded:

| Metric | Result |
|---|---|
| Total DQ checks | 26 |
| Passed | 26 |
| Failed | 0 |
| Newly quarantined records | 0 |

The quarantine smoke test can be executed using:

```bash
python scripts/test_quarantine.py
```

## 9. Priority Scoring Methodology

The Gold mart uses an explainable, weighted vulnerability score.

The score is:

```text
Priority Score = 100 × (
    0.25 × Age Vulnerability
  + 0.20 × Housing Vulnerability
  + 0.15 × Social Vulnerability
  + 0.15 × Literacy Vulnerability
  + 0.10 × Work Vulnerability
  + 0.10 × Household Pressure
  + 0.05 × Female Population Share
)
```

Each component is normalised between 0 and 1 across the 24 districts.

| Component | Weight | Interpretation |
|---|---|---|
| Age vulnerability | 25% | Higher 50+ population share |
| Housing vulnerability | 20% | Higher dilapidated housing share |
| Social vulnerability | 15% | Higher combined SC/ST population share |
| Literacy vulnerability | 15% | Lower literacy rate |
| Work vulnerability | 10% | Lower work participation rate |
| Household pressure | 10% | Higher population per household |
| Female population share | 5% | Higher female population share |

For literacy and work participation, the normalisation is reversed so that lower values result in higher vulnerability scores.

The final score ranges from 0 to 100.

Districts are ranked by descending score. District code is used as a deterministic secondary ordering key.

`NTILE(3)` divides the 24 districts into three equal groups:

- **High:** top 8 districts.
- **Medium:** middle 8 districts.
- **Low:** bottom 8 districts.

The resulting score is a vulnerability-based outreach priority proxy, not a measured pension coverage gap.

Female population share is used only as demographic context. It is not treated as widow prevalence.

The calculation is implemented in:

`sql/gold/001_build_mart_district_pension_outreach.sql`

## 10. AI-Ready Features

The ML feature table includes:

- Population per household.
- Female population share.
- Literacy rate.
- Work participation rate.
- SC and ST population shares.
- Age 50+ population share.
- Housing condition and housing type indicators.
- Pension beneficiary counts and coverage indicators, where available.
- District pension data availability flag.

The example target is:

```text
target_high_priority = 1 if priority_category = 'High'
target_high_priority = 0 otherwise
```

The target is derived from the rule-based Gold priority classification.

### Preventing target leakage

The target is derived from the same indicators used in the priority score. Therefore, training a supervised model on those same inputs to reproduce the target would introduce target leakage.

For a genuine predictive model:

1. Use independently observed future outcomes, such as outreach conversion or verified enrolment gaps.
2. Exclude the priority score, component scores, rank and category from predictors.
3. Avoid using variables measured after the outcome.
4. Use appropriate time-based and geographic validation.
5. Evaluate performance on genuinely unseen observations.

The current 24-district dataset is intended for feature engineering and demonstration. It is not sufficient evidence of a reliable predictive model.

## 11. Setup and Installation

### Prerequisites

- Python 3.12
- PostgreSQL
- PostgreSQL `psql` command-line client
- Git

Ensure `psql` is available in the system `PATH`.

### Clone the repository

```bash
git clone [https://github.com/sohamdutta-coder/jharkhand-mini-uddp-data-pipeline.git](https://github.com/sohamdutta-coder/jharkhand-mini-uddp-data-pipeline.git)
cd jharkhand-mini-uddp-data-pipeline
```

### Create a virtual environment

macOS/Linux:

```bash
python3.12 -m venv .venv
source .venv/bin/activate
```

Windows PowerShell:

```powershell
py -3.12 -m venv .venv
.venv\Scripts\Activate.ps1
```

### Install dependencies

```bash
python -m pip install --upgrade pip
pip install -r requirements-dev.txt
```

For runtime-only installation:

```bash
pip install -r requirements.txt
```

## 12. Database Configuration

Create a PostgreSQL role and database using a PostgreSQL administrator account.

Example:

```sql
CREATE USER uddp_app WITH PASSWORD 'replace_with_a_secure_password';
CREATE DATABASE jharkhand_uddp OWNER uddp_app;
```

Copy the environment template:

macOS/Linux:

```bash
cp .env.example .env
```

Windows PowerShell:

```powershell
Copy-Item .env.example .env
```

Update `.env`:

```env
APP_ENV=development
LOG_LEVEL=INFO

DB_HOST=localhost
DB_PORT=5432
DB_NAME=jharkhand_uddp
DB_USER=uddp_app
DB_PASSWORD=your_secure_password
```

Do not commit `.env` or database credentials.

### Initialise database schemas

Execute the SQL setup files in numerical order, once per new database:

```bash
psql -h localhost -U uddp_app -d jharkhand_uddp -v ON_ERROR_STOP=1 -f sql/setup/001_create_bronze_tables.sql
psql -h localhost -U uddp_app -d jharkhand_uddp -v ON_ERROR_STOP=1 -f sql/setup/002_create_silver_tables.sql
psql -h localhost -U uddp_app -d jharkhand_uddp -v ON_ERROR_STOP=1 -f sql/setup/003_create_data_quality_tables.sql
psql -h localhost -U uddp_app -d jharkhand_uddp -v ON_ERROR_STOP=1 -f sql/setup/004_create_gold_tables.sql
psql -h localhost -U uddp_app -d jharkhand_uddp -v ON_ERROR_STOP=1 -f sql/setup/005_create_ml_tables.sql
```

## 13. Source Data Setup

Create the local raw-data directory:

```bash
mkdir -p data/raw
```

Download the two Census sources:

```bash
curl -L "[https://raw.githubusercontent.com/nishusharma1608/India-Census-2011-Analysis/master/india-districts-census-2011.csv](https://raw.githubusercontent.com/nishusharma1608/India-Census-2011-Analysis/master/india-districts-census-2011.csv)" \
  -o data/raw/india-districts-census-2011.csv

curl -L "[https://raw.githubusercontent.com/pigshell/india-census-2011/master/hlpca-total.csv](https://raw.githubusercontent.com/pigshell/india-census-2011/master/hlpca-total.csv)" \
  -o data/raw/hlpca-total.csv
```

Download the NSAP resource from:
<https://www.data.gov.in/resource/stateneuts-wise-beneficiaries-under-pension-schemes-national-social-assistance-programme>

Place the downloaded resource in `data/raw/` using the expected filename:

`RS_Session_256_AU_3148_1.csv`

The three raw files are required before running Bronze ingestion.

Raw source files are excluded from Git. The project stores their ingested records in PostgreSQL Bronze tables.

## 14. Running the Pipeline

Check PostgreSQL connectivity:

```bash
python scripts/check_database.py
```

Run the complete pipeline:

```bash
python scripts/run_pipeline.py
```

The orchestrator executes:

1. Database connectivity validation.
2. Bronze ingestion.
3. Silver dimension and fact transformations.
4. Source alignment validation.
5. Data quality checks and quarantine.
6. Gold mart generation.
7. ML feature generation.
8. Gold and ML CSV exports.
9. Execution summary generation.

### Backfill and selective execution

Rebuild Silver onwards using existing Bronze records:

```bash
python scripts/run_pipeline.py --start-at silver
```

Rebuild Gold, ML and exports using existing Silver data:

```bash
python scripts/run_pipeline.py --start-at gold
```

Run source validation onwards:

```bash
python scripts/run_pipeline.py --start-at source_validation
```

These modes deliberately skip earlier stages. They should only be used when the upstream data already exists and is valid.

### Logging and execution summaries

The orchestrator generates:

```text
logs/
├── pipeline.log
└── pipeline_runs/
    └── <run-id>.json
```

Each execution summary records:

- Pipeline and run identifiers.
- Execution start and completion timestamps.
- Stage statuses.
- Retry attempts.
- Error information.
- Stage execution durations.
- Total pipeline duration.

Logs are local runtime artefacts and are excluded from Git.

## 15. Retry, Idempotency and Failure Handling

The orchestration configuration is maintained in `config/pipeline.yaml`.

Current retry settings:

| Setting | Value |
|---|---|
| Maximum retries | 3 |
| Total possible attempts | 4 |
| Initial retry delay | 2 seconds |
| Backoff multiplier | 2 |

Transient operational failures are retried with exponential backoff. Data quality execution is not automatically retried.

The pipeline stops when a critical stage fails.

Bronze ingestion uses source SHA-256 and source row identifiers to avoid duplicate ingestion of an unchanged source file.

Silver, Gold and ML transformations use deterministic district keys and repeatable database operations.

An optional failure webhook can be configured using:

```env
PIPELINE_ALERT_WEBHOOK=your_webhook_endpoint
```

Failure alerts are optional. Execution status is still recorded in the logs and JSON summary when no webhook is configured.

## 16. Sample Outputs

The repository includes:

| File | Description |
|---|---|
| `outputs/mart_district_pension_outreach.csv` | District-level Gold outreach mart |
| `outputs/ml_district_features.csv` | District-level ML feature dataset |
| `reports/data_quality_report.csv` | Individual DQ check results |
| `reports/unmatched_districts.csv` | Unmatched district report |

The validated output contains 24 Jharkhand districts.

The priority categories contain 8 High, 8 Medium and 8 Low districts.

## 17. Production Scheduling

The current implementation provides a manually executable Python orchestration entry point.

It can be scheduled through:

- Linux `cron`.
- Windows Task Scheduler.
- macOS `launchd`.

For a larger deployment, the same modular stages could be migrated into Apache Airflow, Prefect or Dagster.

A production scheduler should additionally include monitored execution, controlled backfills, alert routing, environment-specific configuration and operational ownership.

## 18. Extending the Design to an Actual UDDP

The current exercise uses public aggregate data only.

An actual UDDP implementation would need stronger governance and security controls before integrating individual citizen or beneficiary records.

Possible extensions include:

- Secure source-system connectors and controlled API ingestion.
- Data contracts and source-specific validation.
- Role-based access control and least-privilege permissions.
- Encryption in transit and at rest.
- Tokenisation or pseudonymisation of identifiers where appropriate.
- Purpose limitation and data minimisation.
- Consent and legal-basis governance where applicable.
- Auditable access, processing and retention policies.
- Separation of personally identifiable information from analytical datasets.
- Controlled sharing of aggregated reporting outputs.

Sensitive information such as Aadhaar, bank details, mobile numbers and individual beneficiary records is outside the scope of this assessment.

## 19. Assumptions and Limitations

See [ASSUMPTIONS.md](ASSUMPTIONS.md) for source-specific assumptions, pension-data limitations, age-group interpretation, scoring choices and ML limitations.

## 20. Project Status

The core implementation, database transformations, data quality framework, Gold mart, ML feature table and end-to-end Python orchestration have been implemented and successfully executed locally.

The pipeline has been rerun to verify that unchanged source files are not ingested twice and that district-level business tables retain their expected record counts.
