-- ============================================================
-- WORKFORCE INTELLIGENCE DASHBOARD
-- Project by: [Your Name]
-- ============================================================
 
 
-- ============================================================
-- STEP 1: CREATE TABLE
-- ============================================================
 
CREATE TABLE employees (
    employee_id     INT PRIMARY KEY,
    name            VARCHAR(100),
    department      VARCHAR(50),
    gender          VARCHAR(10),
    hire_date       DATE,
    salary          NUMERIC(10, 2),
    performance_score INT,        -- 1 (low) to 5 (high)
    age             INT,
    left_company    INT           -- 0 = still here, 1 = left
);
 -- After creating the table, imported employees.csv


-- ============================================================
-- STEP 2: DATA QUALITY CHECK
-- Check for nulls, duplicates, salary outliers
-- ============================================================
 
-- Any nulls?
SELECT
    COUNT(*) - COUNT(employee_id)       AS missing_ids,
    COUNT(*) - COUNT(salary)            AS missing_salary,
    COUNT(*) - COUNT(performance_score) AS missing_scores,
    COUNT(*) - COUNT(hire_date)         AS missing_hire_dates
FROM employees


-- RESULT: All columns returned 0. No null values found. Data is clean.


-- Checking for duplicates


SELECT name, COUNT(*) AS occurrences
FROM employees
GROUP BY name
HAVING COUNT(*) > 1;


-- RESULT: No duplicates found. All 50 employee records are unique.


-- ============================================================
-- STEP 3: TENURE CALCULATION
-- How long has each person been at the company?
-- ============================================================
 
SELECT
    employee_id,
    name,
    department,
    hire_date,
    ROUND(
         (CURRENT_DATE - hire_date)/ 365.25,
        1
    ) AS tenure_years
FROM employees
ORDER BY tenure_years DESC;

-- RESULT: 50 employees. Tenure ranges from ~11 years (Suresh Babu, Engineering)
-- to under 3 year (recent hires in 2023).
-- Longest tenured employees are concentrated in Engineering and HR.
-- This column will be used in attrition risk scoring next.

-- ============================================================
-- ANALYSIS 1: ATTRITION RISK SCORE
-- Flags employees likely to leave based on:
-- low performance, below-average pay, long tenure with no raise
-- ============================================================
 
WITH dept_avg_salary AS (
    SELECT
        department,
        AVG(salary) AS avg_dept_salary
    FROM employees
    WHERE left_company = 0
    GROUP BY department
),
tenure_calc AS (
    SELECT
        e.*,
        ROUND(
             (CURRENT_DATE - hire_date)/ 365.25,
            1
        ) AS tenure_years,
        d.avg_dept_salary
    FROM employees e
    JOIN dept_avg_salary d ON e.department = d.department
    WHERE e.left_company = 0
)
SELECT
    employee_id,
    name,
    department,
    salary,
    ROUND(avg_dept_salary, 0) AS dept_avg_salary,
    performance_score,
    tenure_years,
    -- Risk score: higher = more likely to leave
    (
        CASE WHEN performance_score <= 2 THEN 3 ELSE 0 END
      + CASE WHEN salary < avg_dept_salary * 0.85 THEN 3 ELSE 0 END
      + CASE WHEN tenure_years > 5 AND performance_score <= 3 THEN 2 ELSE 0 END
      + CASE WHEN tenure_years < 1 THEN 1 ELSE 0 END
    ) AS attrition_risk_score,
    CASE
        WHEN (
            CASE WHEN performance_score <= 2 THEN 3 ELSE 0 END
          + CASE WHEN salary < avg_dept_salary * 0.85 THEN 3 ELSE 0 END
          + CASE WHEN tenure_years > 5 AND performance_score <= 3 THEN 2 ELSE 0 END
          + CASE WHEN tenure_years < 1 THEN 1 ELSE 0 END
        ) >= 5 THEN 'HIGH'
        WHEN (
            CASE WHEN performance_score <= 2 THEN 3 ELSE 0 END
          + CASE WHEN salary < avg_dept_salary * 0.85 THEN 3 ELSE 0 END
          + CASE WHEN tenure_years > 5 AND performance_score <= 3 THEN 2 ELSE 0 END
          + CASE WHEN tenure_years < 1 THEN 1 ELSE 0 END
        ) >= 3 THEN 'MEDIUM'
        ELSE 'LOW'
    END AS risk_level
FROM tenure_calc
ORDER BY attrition_risk_score DESC;

-- ATTRITION RISK RESULTS:
-- HIGH risk:   0 employees
-- MEDIUM risk: 1 employee (Arjun Verma, Engineering)
--              Reason: Salary 15% below dept average despite 4/5 performance
-- LOW risk:    49 employees
-- KEY INSIGHT: Workforce is stable overall, but Engineering has a
--              potential retention issue with underpaid mid-level performers.


-- ============================================================
-- ANALYSIS 2: SALARY EQUITY BY GENDER + DEPARTMENT
-- The one that always gets a reaction on LinkedIn
-- ============================================================

SELECT
    department,
    gender,
    COUNT(*)                       AS headcount,
    ROUND(AVG(salary), 0)          AS avg_salary,
    ROUND(MIN(salary), 0)          AS min_salary,
    ROUND(MAX(salary), 0)          AS max_salary,
    ROUND(STDDEV(salary), 0)       AS salary_stddev
FROM employees
WHERE left_company = 0
GROUP BY department, gender
ORDER BY department, gender;


-- Pay gap % within each department
WITH gender_avg AS (
    SELECT
        department,
        gender,
        ROUND(AVG(salary), 0) AS avg_salary
    FROM employees
    WHERE left_company = 0
    GROUP BY department, gender
),
dept_male AS (
    SELECT department, avg_salary AS male_avg
    FROM gender_avg WHERE gender = 'Male'
),
dept_female AS (
    SELECT department, avg_salary AS female_avg
    FROM gender_avg WHERE gender = 'Female'
)
SELECT
    m.department,
    m.male_avg,
    f.female_avg,
    ROUND(((m.male_avg - f.female_avg) / m.male_avg::NUMERIC) * 100, 1) AS pay_gap_pct
FROM dept_male m
JOIN dept_female f ON m.department = f.department
ORDER BY pay_gap_pct DESC;

-- PAY GAP RESULTS:
-- Engineering: 10.3% gap — males earn more on average (80,700 vs 72,375)
-- Sales: -1.5% — only 1 female employee, not statistically meaningful
-- NOTE: HR and Marketing excluded from pay gap calculation
-- Reason: All male employees in HR and Marketing have left the company
-- (left_company = 1), so no active males exist to compare against.
-- Pay gap analysis is only valid for Engineering and Sales
-- where both genders have active employees.
-- KEY INSIGHT: Engineering has the only statistically meaningful pay gap
--              at 10.3%. Worth investigating in a real company.


-- ============================================================
-- ANALYSIS 3: TOP PERFORMERS vs COMPENSATION
-- Are your best people being paid what they deserve?
-- ============================================================
 
WITH perf_quartile AS (
    SELECT
        employee_id,
        name,
        department,
        salary,
        performance_score,
        NTILE(4) OVER (ORDER BY performance_score DESC, salary DESC) AS perf_quartile,
        RANK() OVER (PARTITION BY department ORDER BY performance_score DESC) AS rank_in_dept,
        AVG(salary) OVER (PARTITION BY department) AS dept_avg_salary
    FROM employees
    WHERE left_company = 0
)
SELECT
    employee_id,
    name,
    department,
    salary,
    ROUND(dept_avg_salary, 0) AS dept_avg,
    performance_score,
    perf_quartile,
    rank_in_dept,
    ROUND(((salary - dept_avg_salary) / dept_avg_salary) * 100, 1) AS pct_vs_dept_avg,
    CASE
        WHEN performance_score = 5 AND salary < dept_avg_salary THEN 'Underpaid top performer'
        WHEN performance_score <= 2 AND salary > dept_avg_salary THEN 'Overpaid low performer'
        ELSE 'Fairly positioned'
    END AS compensation_flag
FROM perf_quartile
ORDER BY performance_score DESC, pct_vs_dept_avg ASC;


-- PERFORMANCE vs COMPENSATION RESULTS:
-- 5 employees flagged as 'Underpaid top performer' — all in Engineering
-- All 5 have performance score 5/5 and are female
-- Salary ranges from 11.7% to 3.9% below dept average
-- This directly explains the 10.3% gender pay gap found in Analysis 2
-- KEY INSIGHT: Engineering's pay gap is not random — it's concentrated
--              among the highest performing female employees.
-- 0 employees flagged as 'Overpaid low performer'



-- ============================================================
-- ANALYSIS 4: HEADCOUNT TREND BY DEPARTMENT
-- Which teams are growing, which are shrinking?
-- ============================================================
 
SELECT
    department,
    COUNT(*) FILTER (WHERE left_company = 0)  AS current_headcount,
    COUNT(*) FILTER (WHERE left_company = 1)  AS total_attrition,
    COUNT(*)                                   AS ever_employed,
    ROUND(
        COUNT(*) FILTER (WHERE left_company = 1)::NUMERIC / COUNT(*) * 100,
        1
    ) AS attrition_rate_pct,
    ROUND(AVG(age) FILTER (WHERE left_company = 0), 1) AS avg_age_active,
    ROUND(AVG(salary) FILTER (WHERE left_company = 0), 0) AS avg_salary_active
FROM employees
GROUP BY department
ORDER BY attrition_rate_pct DESC;
 
-- HEADCOUNT RESULTS:
-- Sales:       41.7% attrition — highest in company (5 out of 12 left)
-- HR:          30.0% attrition — also concerning (3 out of 10 left)
-- Marketing:   22.2% attrition
-- Engineering:  5.3% attrition — most stable department
-- KEY INSIGHT: Sales is losing nearly half its people.
--              Engineering retains almost everyone — but underpays its
--              top performers (found in Analysis 3). Two very different problems.

-- ============================================================
-- ANALYSIS 5: TENURE RANKING WITH WINDOW FUNCTIONS
-- Shows RANK(), DENSE_RANK(), NTILE() in one query
-- Great for portfolio — shows you know window functions well
-- ============================================================
 
WITH tenure_data AS (
    SELECT
        employee_id,
        name,
        department,
        salary,
        hire_date,
        ROUND(
             (CURRENT_DATE - hire_date) / 365.25,
            1
        ) AS tenure_years
    FROM employees
    WHERE left_company = 0
)
SELECT
    employee_id,
    name,
    department,
    tenure_years,
    salary,
    RANK()       OVER (PARTITION BY department ORDER BY tenure_years DESC) AS tenure_rank_in_dept,
    DENSE_RANK() OVER (ORDER BY tenure_years DESC)                          AS overall_tenure_rank,
    NTILE(3)     OVER (ORDER BY tenure_years DESC)                          AS tenure_bucket,
    -- 1 = senior, 2 = mid, 3 = junior (by tenure)
    CASE NTILE(3) OVER (ORDER BY tenure_years DESC)
        WHEN 1 THEN 'Senior (top 33%)'
        WHEN 2 THEN 'Mid-level'
        WHEN 3 THEN 'Junior (bottom 33%)'
    END AS seniority_band
FROM tenure_data
ORDER BY tenure_years DESC;

-- TENURE RANKING RESULTS:
-- Senior band (top 33%): 13 employees, avg tenure 8.8 years
-- Mid-level band: 13 employees, avg tenure 5.1 years  
-- Junior band (bottom 33%): 13 employees, avg tenure 2.8 years
-- Suresh Babu leads overall at 11 years tenure
-- Engineering dominates the senior band — most stable, longest serving dept

-- ============================================================
-- ANALYSIS 6: ATTRITION SUMMARY — THE CLOSING INSIGHT
-- What percentage of each department quit, and who was at risk?
-- ============================================================
 
SELECT
    department,
    COUNT(*) FILTER (WHERE left_company = 1) AS employees_left,
    COUNT(*) FILTER (WHERE left_company = 1 AND performance_score >= 4) AS high_performers_lost,
    ROUND(
        COUNT(*) FILTER (WHERE left_company = 1 AND performance_score >= 4)::NUMERIC
        / NULLIF(COUNT(*) FILTER (WHERE left_company = 1), 0) * 100,
        1
    ) AS pct_lost_were_high_performers
FROM employees
GROUP BY department
ORDER BY pct_lost_were_high_performers DESC NULLS LAST;

-- ATTRITION SUMMARY RESULTS:
-- Sales lost 5 employees, HR lost 3, Marketing lost 2, Engineering lost 1
-- High performers lost: 0 across all departments
-- All attrition was among average or low performers (score 3 or below)


-- KEY INSIGHT: The company isn't losing its best people yet —
--              but Engineering's underpaid top performers are a warning sign.
--              If that pay gap isn't fixed, that 0 could change fast.
 
