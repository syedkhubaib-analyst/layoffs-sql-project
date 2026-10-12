/* =============================================================================
   PROJECT   : Global Layoffs Analysis
   SCRIPT    : 01_setup.sql
   PURPOSE   : Create the schema and load the raw CSV into the `layoffs` table.
   -----------------------------------------------------------------------------
   BEFORE RUNNING
     1. Replace <PATH_TO_REPO> below with the absolute path of this repository.
     2. Start the client with local infile enabled:
            mysql --local-infile=1 -u <user> -p
        (or enable it in MySQL Workbench: Connection > Advanced > OPT_LOCAL_INFILE=1)
     3. If the server blocks it:  SET GLOBAL local_infile = 1;

   Alternative: use MySQL Workbench > Table Data Import Wizard on data/layoffs_raw.csv.
   ============================================================================= */

CREATE DATABASE IF NOT EXISTS world_layoffs;
USE world_layoffs;

DROP TABLE IF EXISTS layoffs;

CREATE TABLE layoffs (
    company               TEXT,
    location              TEXT,
    industry              TEXT,
    total_laid_off        INT,
    percentage_laid_off   TEXT,
    `date`                TEXT,
    stage                 TEXT,
    country               TEXT,
    funds_raised_millions DECIMAL(12,4)
) DEFAULT CHARSET = utf8mb4;

-- The CSV uses the literal string 'NULL' for missing values; convert it to real NULLs.
-- Blank strings ('') in `industry` are deliberately kept: they are handled in 02_cleaning.sql.
LOAD DATA LOCAL INFILE '<PATH_TO_REPO>/data/layoffs_raw.csv'
INTO TABLE layoffs
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\r\n'
IGNORE 1 LINES
(company, location, industry, @total, @pct, @date, stage, country, @funds)
SET total_laid_off        = NULLIF(@total, 'NULL'),
    percentage_laid_off   = NULLIF(@pct, 'NULL'),
    `date`                = NULLIF(@date, 'NULL'),
    funds_raised_millions = NULLIF(@funds, 'NULL');

UPDATE layoffs SET industry = NULL WHERE industry = 'NULL';

-- Expect 2,361 rows
SELECT COUNT(*) AS raw_rows FROM layoffs;
