# Jharkhand Mini UDDP Data Pipeline

An ETL/ELT pipeline that integrates public Census demographic,
housing, and NSAP pension data to develop a district-level
pension outreach prioritization dataset for Jharkhand.

## Objective

Build a locally runnable, reliable and explainable data pipeline
using Python, PostgreSQL and SQL.

## Architecture

The pipeline follows a Medallion Architecture:

- Bronze: Raw source data and ingestion metadata.
- Silver: Cleaned and standardized datasets.
- Gold: District-level pension outreach mart.
- ML Features: AI-ready district feature dataset.

## Data Sources

1. India Census 2011 - District Dataset
2. India Census 2011 - Housing Dataset
3. National Social Assistance Programme - Pension Beneficiaries

## Technology Stack

- Python
- PostgreSQL
- Pandas
- SQLAlchemy
- Psycopg 3
- SQL
- Pytest

## Data Privacy

This project uses public aggregate data only.
No individual citizen or beneficiary-level information is used.

## Project Status

Under development.
