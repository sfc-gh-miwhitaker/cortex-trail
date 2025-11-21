-- Extract Metrics for Cost Calculator v2.5
-- 
-- v2.5 NEW: Added OPTION 3 for AISQL function-level data export

-- INSTRUCTIONS FOR SOLUTION ENGINEERS:
-- 1. Run this query in the CUSTOMER'S Snowflake account
-- 2. Click "Download" and save as CSV
-- 3. Upload CSV to YOUR Streamlit calculator (in your Snowflake account)
-- 4. Calculator will analyze and generate credit projections
-- 5. Export summary for sales/pricing team

-- Main Extraction Query - OPTION 1 (Real-time data)
-- Use V_CORTEX_COST_EXPORT for most up-to-date data (queries ACCOUNT_USAGE live)
-- Note: ROUND() functions prevent scientific notation in CSV exports
--       This ensures consistent display between CSV and Streamlit UI

SELECT 
    date,
    service_type,
    daily_unique_users,
    total_operations,
    ROUND(total_credits, 8) AS total_credits,
    ROUND(credits_per_user, 8) AS credits_per_user,
    ROUND(credits_per_operation, 12) AS credits_per_operation
FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_CORTEX_COST_EXPORT
WHERE date >= DATEADD('day', -90, CURRENT_DATE())  -- Default 90 days, adjust as needed
ORDER BY date DESC, total_credits DESC;

-- Main Extraction Query - OPTION 2 (Snapshot data - faster)
-- Use V_CORTEX_USAGE_HISTORY for faster queries (pre-aggregated snapshots)
-- Note: Data is captured daily at 3 AM, so may be 1 day behind current usage
/*
SELECT 
    date,
    service_type,
    daily_unique_users,
    total_operations,
    ROUND(total_credits, 8) AS total_credits,
    ROUND(credits_per_user, 8) AS credits_per_user,
    ROUND(credits_per_operation, 12) AS credits_per_operation,
    ROUND(credits_7d_ago, 8) AS credits_7d_ago,
    credits_wow_growth_pct
FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_CORTEX_USAGE_HISTORY
WHERE date >= DATEADD('day', -90, CURRENT_DATE())
ORDER BY date DESC, total_credits DESC;
*/

-- Main Extraction Query - OPTION 3 (AISQL Functions - v2.5)
-- Use V_AISQL_FUNCTION_SUMMARY for detailed AISQL function and model analysis
-- Note: This is NEW in v2.5 and provides function-level granularity
/*
SELECT 
    function_name,
    model_name,
    call_count,
    ROUND(total_credits, 8) AS total_credits,
    total_tokens,
    ROUND(avg_credits_per_call, 8) AS avg_credits_per_call,
    ROUND(avg_tokens_per_call, 2) AS avg_tokens_per_call,
    ROUND(cost_per_million_tokens, 8) AS cost_per_million_tokens,
    serverless_calls,
    compute_calls,
    first_usage,
    last_usage
FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_AISQL_FUNCTION_SUMMARY
ORDER BY total_credits DESC;
*/

-- Expected Output Columns:
-- date                     - Usage date (YYYY-MM-DD)
-- service_type             - Cortex Analyst, Search, Functions, Document AI
-- daily_unique_users       - Number of unique users (where available)
-- total_operations         - Requests, tokens, messages, pages processed
-- total_credits            - Actual Snowflake credits consumed
-- credits_per_user         - Average credits per user per day
-- credits_per_operation    - Average credits per operation

-- Data Quality Checks (Optional - Run Before Extraction)

-- Check 1: Verify data exists
SELECT 
    COUNT(*) AS total_rows,
    MIN(date) AS earliest_date,
    MAX(date) AS latest_date,
    COUNT(DISTINCT service_type) AS service_count
FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_CORTEX_COST_EXPORT;
-- Expected: Rows > 0, service_count between 1-4

-- Check 2: Service breakdown
SELECT 
    service_type,
    COUNT(DISTINCT date) AS days_with_data,
    ROUND(SUM(total_credits), 8) AS total_credits,
    ROUND(AVG(daily_unique_users), 2) AS avg_daily_users
FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_CORTEX_COST_EXPORT
GROUP BY service_type
ORDER BY total_credits DESC;

-- Check 3: Recent activity (last 7 days)
SELECT 
    date,
    service_type,
    ROUND(total_credits, 8) AS total_credits
FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_CORTEX_COST_EXPORT
WHERE date >= DATEADD('day', -7, CURRENT_DATE())
ORDER BY date DESC, total_credits DESC;

-- Export Instructions for SE:
-- 
-- STEP 1: Run main extraction query (lines 21-31)
-- STEP 2: In Snowflake UI, click "Download" button → Choose CSV
-- STEP 3: Save file as: "customer_name_cortex_usage_YYYYMMDD.csv"
-- 
-- STEP 4: Go to YOUR Snowflake account
-- STEP 5: Open YOUR Streamlit calculator
-- STEP 6: Upload the CSV file
-- 
-- STEP 7: Calculator will show:
--         - Historical usage analysis
--         - Cost projections (multiple scenarios)
--         - Credit estimates by service
-- 
-- STEP 8: Export credit summary:
--         - Download "Credit Estimate Summary" spreadsheet
--         - Share with sales/pricing team for proposal creation
--
-- ============================================================================
-- Troubleshooting:
--
-- Q: No data returned?
-- A: Check if customer has used Cortex recently (needs 7-14 days minimum)
--    Try: SELECT usage_date, service_type, credits_used, credits_used_compute, credits_used_cloud_services
--         FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
--         WHERE service_type = 'AI_SERVICES' ORDER BY usage_date DESC LIMIT 10;
--
-- Q: View doesn't exist?
-- A: Deploy monitoring first: @sql/deploy_cortex_monitoring.sql
--
-- Q: Permission denied?
-- A: Need IMPORTED PRIVILEGES on SNOWFLAKE database
--    Run as ACCOUNTADMIN: GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE 
--                         TO ROLE <YOUR_ROLE>;
--
-- Q: Wrong date range?
-- A: Change line 28: DATEADD('day', -90, ...) to -14, -30, -60, -180, etc.
--
-- ============================================================================

