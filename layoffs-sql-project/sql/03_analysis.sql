/* =============================================================================
   PROJECT   : Global Layoffs Analysis
   SCRIPT    : 03_analysis.sql
   DATABASE  : MySQL 8.0+
   REQUIRES  : Run 02_cleaning.sql first (uses table `layoffs_staging2`)
   -----------------------------------------------------------------------------
   PURPOSE
     Explore the cleaned layoffs data to find trends and patterns.

   SECTIONS
     1. Overview            - size and range of the data
     2. Extremes            - biggest layoffs, companies that shut down
     3. Totals by dimension - company, location, industry, stage, country, year
     4. Time series         - monthly layoffs, rolling total, year-over-year change
     5. Rankings            - top 5 companies per year
     6. Funding view        - did well-funded companies also cut deep?

   DATA CAVEATS
     - The data covers 2020-03-11 to 2023-03-06, so 2023 is a PARTIAL year.
     - 1 row has no date; it is excluded from time-based queries.
     - SUM() ignores NULL total_laid_off values, so totals are a lower bound.
   ============================================================================= */

USE world_layoffs;


/* -----------------------------------------------------------------------------
   1. OVERVIEW
   ----------------------------------------------------------------------------- */

SELECT COUNT(*)                          AS records,
       COUNT(DISTINCT company)           AS companies,
       COUNT(DISTINCT country)           AS countries,
       SUM(total_laid_off)               AS total_laid_off,
       MIN(`date`)                       AS first_date,
       MAX(`date`)                       AS last_date
FROM layoffs_staging2;


/* -----------------------------------------------------------------------------
   2. EXTREMES
   ----------------------------------------------------------------------------- */

-- Largest single layoff and highest percentage
SELECT MAX(total_laid_off)      AS max_laid_off,
       MAX(percentage_laid_off) AS max_percentage
FROM layoffs_staging2;

-- Top 5 single layoff events
SELECT company, `date`, total_laid_off
FROM layoffs_staging2
ORDER BY total_laid_off DESC
LIMIT 5;

-- Companies that laid off 100% of staff (shut down), biggest funding first (top 10)
SELECT company, industry, country, `date`, funds_raised_millions
FROM layoffs_staging2
WHERE percentage_laid_off = 1
ORDER BY funds_raised_millions DESC
LIMIT 10;

-- How many companies laid off 100% of staff?
SELECT COUNT(*) AS companies_shut_down
FROM layoffs_staging2
WHERE percentage_laid_off = 1;


/* -----------------------------------------------------------------------------
   3. TOTAL LAYOFFS BY DIMENSION
   ----------------------------------------------------------------------------- */

-- By company (top 10)
SELECT company, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY company
ORDER BY total_laid_off DESC
LIMIT 10;

-- By location (top 10)
SELECT location, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY location
ORDER BY total_laid_off DESC
LIMIT 10;

-- By industry
SELECT industry, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY industry
ORDER BY total_laid_off DESC;

-- By funding stage
SELECT stage, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY stage
ORDER BY total_laid_off DESC;

-- By country, with share of the global total
SELECT country,
       SUM(total_laid_off) AS total_laid_off,
       ROUND(100 * SUM(total_laid_off) / SUM(SUM(total_laid_off)) OVER (), 1) AS pct_of_total
FROM layoffs_staging2
GROUP BY country
ORDER BY total_laid_off DESC
LIMIT 10;

-- By year (NULL year = row without a date; 2023 = partial year)
SELECT YEAR(`date`) AS `year`, SUM(total_laid_off) AS total_laid_off
FROM layoffs_staging2
GROUP BY YEAR(`date`)
ORDER BY `year`;


/* -----------------------------------------------------------------------------
   4. TIME SERIES
   ----------------------------------------------------------------------------- */

-- Monthly layoffs
SELECT DATE_FORMAT(`date`, '%Y-%m') AS `year_month`,
       SUM(total_laid_off)          AS total_laid_off
FROM layoffs_staging2
WHERE `date` IS NOT NULL
GROUP BY `year_month`
ORDER BY `year_month`;

-- Cumulative (rolling) total by month
WITH monthly_totals AS
(
    SELECT DATE_FORMAT(`date`, '%Y-%m') AS `year_month`,
           SUM(total_laid_off)          AS total_laid_off
    FROM layoffs_staging2
    WHERE `date` IS NOT NULL
    GROUP BY `year_month`
)
SELECT `year_month`,
       total_laid_off,
       SUM(total_laid_off) OVER (ORDER BY `year_month`) AS rolling_total
FROM monthly_totals
ORDER BY `year_month`;

-- Year-over-year change (2023 is partial - do not read its change as a full-year drop)
WITH yearly AS
(
    SELECT YEAR(`date`) AS `year`, SUM(total_laid_off) AS total_laid_off
    FROM layoffs_staging2
    WHERE `date` IS NOT NULL
    GROUP BY YEAR(`date`)
)
SELECT `year`,
       total_laid_off,
       LAG(total_laid_off) OVER (ORDER BY `year`) AS previous_year,
       ROUND(100 * (total_laid_off - LAG(total_laid_off) OVER (ORDER BY `year`))
             / LAG(total_laid_off) OVER (ORDER BY `year`), 1) AS yoy_change_pct
FROM yearly
ORDER BY `year`;


/* -----------------------------------------------------------------------------
   5. TOP 5 COMPANIES BY LAYOFFS PER YEAR
   DENSE_RANK() keeps ties together and avoids gaps in the ranking.
   ----------------------------------------------------------------------------- */

WITH company_year AS
(
    SELECT company,
           YEAR(`date`)        AS `year`,
           SUM(total_laid_off) AS total_laid_off
    FROM layoffs_staging2
    WHERE `date` IS NOT NULL
    GROUP BY company, YEAR(`date`)
),
company_year_rank AS
(
    SELECT *,
           DENSE_RANK() OVER (PARTITION BY `year` ORDER BY total_laid_off DESC) AS ranking
    FROM company_year
    WHERE total_laid_off IS NOT NULL
)
SELECT *
FROM company_year_rank
WHERE ranking <= 5
ORDER BY `year`, ranking;


/* -----------------------------------------------------------------------------
   6. FUNDING VIEW
   ----------------------------------------------------------------------------- */

-- Shutdowns by funding stage: how many companies went under at each stage?
SELECT stage,
       COUNT(*)                           AS shutdowns,
       ROUND(AVG(funds_raised_millions))  AS avg_funds_raised_millions
FROM layoffs_staging2
WHERE percentage_laid_off = 1
GROUP BY stage
ORDER BY shutdowns DESC;

-- Average share of workforce cut, by industry (min. 10 records for a fair comparison)
SELECT industry,
       COUNT(*)                                  AS records,
       ROUND(100 * AVG(percentage_laid_off), 1)  AS avg_pct_laid_off
FROM layoffs_staging2
WHERE percentage_laid_off IS NOT NULL
GROUP BY industry
HAVING COUNT(*) >= 10
ORDER BY avg_pct_laid_off DESC;
