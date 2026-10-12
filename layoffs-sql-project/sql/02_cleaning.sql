/* =============================================================================
   PROJECT   : Global Layoffs Analysis
   SCRIPT    : 02_cleaning.sql
   DATABASE  : MySQL 8.0+
   DATASET   : layoffs_raw.csv (2,361 rows | 9 columns)
   -----------------------------------------------------------------------------
   PURPOSE
     Clean the raw layoffs dataset so it is ready for analysis.

   STEPS
     0. Setup           - create database, stage the data (raw table is untouched)
     1. Duplicates      - detect with ROW_NUMBER() and remove
     2. Standardize     - fix whitespace, inconsistent labels, data types
     3. NULL / blanks   - convert blanks to NULL, populate from other rows
     4. Remove          - drop unusable rows and helper columns

   PREREQUISITE
     Run sql/01_setup.sql first (creates the schema and loads the
     raw `layoffs` table from data/layoffs_raw.csv).
   ============================================================================= */


/* -----------------------------------------------------------------------------
   0. SETUP
   ----------------------------------------------------------------------------- */

CREATE DATABASE IF NOT EXISTS world_layoffs;
USE world_layoffs;

-- Preview raw data
SELECT * FROM layoffs;

-- Work on a copy so the raw data is never modified
DROP TABLE IF EXISTS layoffs_staging;

CREATE TABLE layoffs_staging
LIKE layoffs;

INSERT INTO layoffs_staging
SELECT *
FROM layoffs;


/* -----------------------------------------------------------------------------
   1. REMOVE DUPLICATES
   MySQL has no unique id here, so ROW_NUMBER() is partitioned over every
   column. Any row with row_num > 1 is an exact duplicate.
   ----------------------------------------------------------------------------- */

-- 1.1 Identify duplicates
WITH duplicates_cte AS
(
    SELECT *,
           ROW_NUMBER() OVER (
               PARTITION BY company, location, industry, total_laid_off,
                            percentage_laid_off, `date`, stage, country,
                            funds_raised_millions
           ) AS row_num
    FROM layoffs_staging
)
SELECT *
FROM duplicates_cte
WHERE row_num > 1;

-- 1.2 Second staging table with the row_num column
--     (MySQL cannot DELETE directly from a CTE)
DROP TABLE IF EXISTS layoffs_staging2;

CREATE TABLE `layoffs_staging2` (
  `company`               TEXT,
  `location`              TEXT,
  `industry`              TEXT,
  `total_laid_off`        INT  DEFAULT NULL,
  `percentage_laid_off`   TEXT,
  `date`                  TEXT,
  `stage`                 TEXT,
  `country`               TEXT,
  `funds_raised_millions` DECIMAL(12,4) DEFAULT NULL,
  `row_num`               INT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

INSERT INTO layoffs_staging2
SELECT *,
       ROW_NUMBER() OVER (
           PARTITION BY company, location, industry, total_laid_off,
                        percentage_laid_off, `date`, stage, country,
                        funds_raised_millions
       ) AS row_num
FROM layoffs_staging;

-- 1.3 Review, then delete
SELECT * FROM layoffs_staging2 WHERE row_num > 1;

DELETE FROM layoffs_staging2
WHERE row_num > 1;


/* -----------------------------------------------------------------------------
   2. STANDARDIZE DATA
   ----------------------------------------------------------------------------- */

-- 2.1 Company: trim leading/trailing whitespace
SELECT company, TRIM(company)
FROM layoffs_staging2;

UPDATE layoffs_staging2
SET company = TRIM(company);

-- 2.1b Company: one spelling per brand (the same company appears with different capitalisation).
--      LOWER() makes the match independent of the table collation.
UPDATE layoffs_staging2
SET company = CASE LOWER(company)
                  WHEN 'bytedance' THEN 'ByteDance'
                  WHEN 'appgate'   THEN 'Appgate'
                  WHEN 'clearco'   THEN 'Clearco'
                  WHEN 'curefit'   THEN 'Curefit'
                  WHEN 'salesloft' THEN 'Salesloft'
              END
WHERE LOWER(company) IN ('bytedance', 'appgate', 'clearco', 'curefit', 'salesloft');

-- 2.2 Industry: merge variants ('Crypto Currency', 'CryptoCurrency') into 'Crypto'
SELECT DISTINCT industry
FROM layoffs_staging2
ORDER BY 1;

UPDATE layoffs_staging2
SET industry = 'Crypto'
WHERE industry LIKE 'Crypto%';

-- 2.3 Industry: 'Fin-Tech' is a duplicate label of 'Finance'
UPDATE layoffs_staging2
SET industry = 'Finance'
WHERE industry = 'Fin-Tech';

-- 2.4 Country: remove trailing period ('United States.' -> 'United States')
SELECT DISTINCT country, TRIM(TRAILING '.' FROM country)
FROM layoffs_staging2
ORDER BY 1;

UPDATE layoffs_staging2
SET country = TRIM(TRAILING '.' FROM country)
WHERE country LIKE 'United States%';

-- 2.5 Date: convert text (m/d/Y) to a real DATE type
SELECT `date`, STR_TO_DATE(`date`, '%m/%d/%Y')
FROM layoffs_staging2;

UPDATE layoffs_staging2
SET `date` = STR_TO_DATE(`date`, '%m/%d/%Y');

ALTER TABLE layoffs_staging2
MODIFY COLUMN `date` DATE;

-- 2.6 Percentage: convert text to a numeric type so MAX/ORDER BY work correctly
--     (on TEXT, MAX('0.9') > MAX('1') because comparison is alphabetical).
--     DECIMAL(6,4) keeps values such as 0.0185 intact; DECIMAL(5,2) would round them.
UPDATE layoffs_staging2
SET percentage_laid_off = NULL
WHERE percentage_laid_off IN ('', 'NULL');

ALTER TABLE layoffs_staging2
MODIFY COLUMN percentage_laid_off DECIMAL(6,4);

-- Verify
SELECT * FROM layoffs_staging2;


/* -----------------------------------------------------------------------------
   3. NULL & BLANK VALUES
   ----------------------------------------------------------------------------- */

-- 3.0 Record the known limitation: rows with no date cannot be used in time analysis
SELECT COUNT(*) AS rows_without_date
FROM layoffs_staging2
WHERE `date` IS NULL;

-- 3.1 Rows with no layoff information at all
SELECT *
FROM layoffs_staging2
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;

-- 3.2 Industry: inspect missing values
SELECT *
FROM layoffs_staging2
WHERE industry IS NULL OR industry = '';

-- Example: Airbnb has a blank industry in one row, but a value in another
SELECT *
FROM layoffs_staging2
WHERE company = 'Airbnb';

-- 3.3 Convert blanks to NULL so one rule handles both cases
UPDATE layoffs_staging2
SET industry = NULL
WHERE industry = '';

-- 3.4 Preview the self-join that will populate missing industries
SELECT t1.company, t1.industry AS missing_industry, t2.industry AS known_industry
FROM layoffs_staging2 t1
JOIN layoffs_staging2 t2
  ON t1.company = t2.company
WHERE t1.industry IS NULL
  AND t2.industry IS NOT NULL;

-- 3.5 Populate from other rows of the same company
UPDATE layoffs_staging2 t1
JOIN layoffs_staging2 t2
  ON t1.company = t2.company
SET t1.industry = t2.industry
WHERE t1.industry IS NULL
  AND t2.industry IS NOT NULL;

-- 3.6 Remaining NULL industries (no other row to copy from, e.g. Bally's Interactive)
SELECT *
FROM layoffs_staging2
WHERE industry IS NULL;


/* -----------------------------------------------------------------------------
   4. REMOVE UNUSABLE ROWS & COLUMNS
   Rows with neither total_laid_off nor percentage_laid_off cannot support any
   layoff analysis, and the values cannot be reliably inferred, so they are removed.
   ----------------------------------------------------------------------------- */

SELECT *
FROM layoffs_staging2
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;

DELETE FROM layoffs_staging2
WHERE total_laid_off IS NULL
  AND percentage_laid_off IS NULL;

-- Drop helper column
ALTER TABLE layoffs_staging2
DROP COLUMN row_num;

-- Final cleaned dataset
SELECT * FROM layoffs_staging2;
