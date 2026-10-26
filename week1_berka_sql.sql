/* =====================================================================
   Berka Bank Dataset - SQL Analysis, Week 1
   Author: Alejandro Barrios Noal
   Database: PostgreSQL

   Dataset: PKDD'99 Financial dataset (Berka), real anonymized data
   from a Czech retail bank (1993-1998).

   Tables used:
     client    - bank customers
     account   - bank accounts (district_id, frequency, opening date)
     loan      - loans (amount, duration, monthly payments, status)
     card      - credit cards (type)
     trans     - account transactions (~1M rows)
     district  - demographic data per district
                 (a1 = district code, a2 = district name, a3 = region)

   Loan status codes:
     A = finished, fully repaid
     B = finished, not repaid (default)
     C = running, payments up to date
     D = running, in arrears
   Transaction types:
     PRIJEM = credit (incoming)
     VYDAJ  = debit (outgoing)
     VYBER  = cash withdrawal
   ===================================================================== */


-- ---------------------------------------------------------------------
-- Q1. How many clients, accounts and loans does the bank have?
-- ---------------------------------------------------------------------
SELECT
    (SELECT COUNT(*) FROM client)  AS num_clients,
    (SELECT COUNT(*) FROM account) AS num_accounts,
    (SELECT COUNT(*) FROM loan)    AS num_loans;

-- Insight: 5,369 clients, 4,500 accounts and 682 loans.
-- Only ~15% of accounts have a loan.


-- ---------------------------------------------------------------------
-- Q2. Loans above 300,000, from largest to smallest
-- ---------------------------------------------------------------------
SELECT
    loan_id,
    account_id,
    amount,
    duration,
    payments,
    status
FROM loan
WHERE amount > 300000
ORDER BY amount DESC;

-- Insight: several of the largest loans are in status D (in arrears),
-- which suggests a link between loan size and credit risk.


-- ---------------------------------------------------------------------
-- Q3. Number of loans by status, with share of total
-- ---------------------------------------------------------------------
SELECT
    status,
    COUNT(*) AS num_loans,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM loan), 2) AS pct_of_total
FROM loan
GROUP BY status
ORDER BY status;

-- Insight: A = 203, B = 31, C = 403, D = 45.
-- Problem loans (B + D) = 76 out of 682, an 11.1% default rate,
-- well above current Spanish banking levels (~3-4%).


-- ---------------------------------------------------------------------
-- Q4. Average, minimum and maximum loan amount by duration (months)
-- ---------------------------------------------------------------------
SELECT
    duration,
    COUNT(*)              AS num_loans,
    ROUND(AVG(amount), 2) AS avg_amount,
    MIN(amount)           AS min_amount,
    MAX(amount)           AS max_amount
FROM loan
GROUP BY duration
ORDER BY duration;

-- Insight: the average amount rises steadily with duration,
-- from ~53,600 (12 months) to ~244,500 (60 months).
-- Larger loans need longer terms to keep monthly payments affordable.


-- ---------------------------------------------------------------------
-- Q5. Accounts opened per year
-- Dates are stored as integers in YYMMDD format (e.g. 940422).
-- Integer division by 10000 extracts the year (94); +1900 gives 1994.
-- ---------------------------------------------------------------------
SELECT
    date / 10000 + 1900 AS open_year,
    COUNT(*)            AS num_accounts
FROM account
GROUP BY date / 10000 + 1900
ORDER BY open_year;

-- Insight: 1993 = 1,139, 1994 = 439, 1995 = 661, 1996 = 1,363, 1997 = 898.
-- Strong acquisition in 1993 and 1996; a sharp drop in 1994.


-- ---------------------------------------------------------------------
-- Q6. Accounts by statement frequency
-- ---------------------------------------------------------------------
SELECT
    frequency,
    COUNT(*) AS num_accounts,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM account), 2) AS pct_of_total
FROM account
GROUP BY frequency
ORDER BY num_accounts DESC;

-- Insight: 93% of accounts receive a monthly statement
-- (POPLATEK MESICNE = 4,167). Weekly = 240, after each transaction = 93.


-- ---------------------------------------------------------------------
-- Q7. Number of cards by type
-- ---------------------------------------------------------------------
SELECT
    type,
    COUNT(*) AS num_cards,
    ROUND(COUNT(*) * 100.0 / (SELECT COUNT(*) FROM card), 2) AS pct_of_total
FROM card
GROUP BY type
ORDER BY num_cards DESC;

-- Insight: 892 cards for 4,500 accounts (~1 in 5 accounts).
-- Classic = 659, junior = 145, gold = 88. Low card penetration and a
-- small share of premium (gold) cards: a clear cross-selling opportunity.


-- ---------------------------------------------------------------------
-- Q8. Total amount at risk: loans in default or arrears (B + D)
-- ---------------------------------------------------------------------
SELECT
    SUM(amount) AS amount_at_risk,
    ROUND(SUM(amount) * 100.0 / (SELECT SUM(amount) FROM loan), 2) AS pct_of_portfolio
FROM loan
WHERE status IN ('B', 'D');

-- Insight: 15,580,152 is in loans that defaulted or are in arrears.


-- ---------------------------------------------------------------------
-- Q9. Average monthly payment by loan status
-- payments was imported as double precision, so it is cast to numeric
-- before rounding (ROUND with decimals only accepts numeric in PostgreSQL).
-- ---------------------------------------------------------------------
SELECT
    status,
    ROUND(AVG(payments)::numeric, 2) AS avg_monthly_payment
FROM loan
GROUP BY status
ORDER BY status;

-- Insight: A = 4,264.14 | B = 5,396.26 | C = 3,938.54 | D = 5,286.64.
-- Defaulted loans (B, D) have monthly payments 25-35% higher than
-- performing ones: payment burden is a key driver of default
-- (debt-to-income ratio).


-- ---------------------------------------------------------------------
-- Q10. Number of transactions and total volume by transaction type
-- ---------------------------------------------------------------------
SELECT
    type,
    COUNT(*)                       AS num_transactions,
    ROUND(SUM(amount)::numeric, 2) AS total_volume
FROM trans
GROUP BY type
ORDER BY total_volume DESC;

-- Insight: VYDAJ (debits) = 634,571, PRIJEM (credits) = 405,083,
-- VYBER (cash withdrawals) = 16,666. Total = 1,056,320 transactions.


-- ---------------------------------------------------------------------
-- Q11. Top 10 districts by number of accounts
-- ---------------------------------------------------------------------
SELECT
    d.a2     AS district_name,
    COUNT(*) AS num_accounts
FROM account a
JOIN district d ON a.district_id = d.a1
GROUP BY d.a2
ORDER BY num_accounts DESC
LIMIT 10;

-- Insight: Prague (Hl.m. Praha) concentrates far more accounts than any
-- other district, as expected for the capital.


-- ---------------------------------------------------------------------
-- Q12. Default rate by district (B + D over total loans), top 5 worst
-- Path: loan -> account (account_id) -> district (district_id = a1)
-- HAVING excludes districts with fewer than 10 loans, where a rate
-- based on 1-2 loans would be noise rather than signal.
-- ---------------------------------------------------------------------
SELECT
    d.a2     AS district_name,
    COUNT(*) AS total_loans,
    SUM(CASE WHEN l.status IN ('B', 'D') THEN 1 ELSE 0 END) AS bad_loans,
    ROUND(
        SUM(CASE WHEN l.status IN ('B', 'D') THEN 1 ELSE 0 END) * 100.0 / COUNT(*),
        2
    ) AS default_rate_pct
FROM loan l
JOIN account a  ON l.account_id = a.account_id
JOIN district d ON a.district_id = d.a1
GROUP BY d.a2
HAVING COUNT(*) >= 10
ORDER BY default_rate_pct DESC
LIMIT 5;

-- Insight: Svitavy (25.00%), Brno - mesto (20.83%), Ostrava - mesto (15.00%),
-- Olomouc (14.29%) and Karvina (12.50%) are above the 11.1% bank average.
-- Brno stands out: the country's second city, with 24 loans and
-- almost double the average default rate.
