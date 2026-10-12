/* =============================================================================
   PROJECT   : Global Layoffs Analysis
   SCRIPT    : 04_validation.sql
   PURPOSE   : Automated quality checks on the cleaned table.
               Every row should show status = 'PASS'.
   ============================================================================= */

USE world_layoffs;

SELECT 'No exact duplicates' AS check_name,
       IF(COUNT(*) = 0, 'PASS', 'FAIL') AS status
FROM (
    SELECT 1
    FROM layoffs_staging2
    GROUP BY company, location, industry, total_laid_off, percentage_laid_off,
             `date`, stage, country, funds_raised_millions
    HAVING COUNT(*) > 1
) d

UNION ALL
SELECT 'No blank industry',
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM layoffs_staging2 WHERE industry = ''

UNION ALL
SELECT 'Industry labels standardized (Crypto / Fin-Tech)',
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM layoffs_staging2
WHERE industry IN ('Crypto Currency', 'CryptoCurrency', 'Fin-Tech')

UNION ALL
SELECT 'No trailing period in country',
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM layoffs_staging2 WHERE country LIKE '%.'

UNION ALL
SELECT 'No untrimmed company names',
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM layoffs_staging2 WHERE company <> TRIM(company)

UNION ALL
SELECT 'Every row has layoff info (total or percentage)',
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM layoffs_staging2
WHERE total_laid_off IS NULL AND percentage_laid_off IS NULL

UNION ALL
SELECT 'Percentage within 0-1',
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM layoffs_staging2
WHERE percentage_laid_off < 0 OR percentage_laid_off > 1

UNION ALL
SELECT 'No negative numbers',
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM layoffs_staging2
WHERE total_laid_off < 0 OR funds_raised_millions < 0

UNION ALL
SELECT 'Date column is DATE type',
       IF(COUNT(*) = 1, 'PASS', 'FAIL')
FROM information_schema.columns
WHERE table_schema = 'world_layoffs' AND table_name = 'layoffs_staging2'
  AND column_name = 'date' AND data_type = 'date'

UNION ALL
SELECT 'Helper column row_num removed',
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM information_schema.columns
WHERE table_schema = 'world_layoffs' AND table_name = 'layoffs_staging2'
  AND column_name = 'row_num'

UNION ALL
SELECT 'One spelling per company (no case variants)',
       IF(COUNT(*) = 0, 'PASS', 'FAIL')
FROM (
    SELECT LOWER(company)
    FROM layoffs_staging2
    GROUP BY LOWER(company)
    HAVING COUNT(DISTINCT CAST(company AS BINARY)) > 1
) v

UNION ALL
SELECT 'Row count = distinct raw rows that carry layoff info',
       IF(COUNT(*) = (
              SELECT COUNT(*)
              FROM (SELECT DISTINCT company, location, industry, total_laid_off,
                                    percentage_laid_off, `date`, stage, country,
                                    funds_raised_millions
                    FROM layoffs) r
              WHERE r.total_laid_off IS NOT NULL
                 OR r.percentage_laid_off IS NOT NULL
          ), 'PASS', 'FAIL')
FROM layoffs_staging2;
