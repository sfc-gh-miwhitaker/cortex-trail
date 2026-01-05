/*******************************************************************************
 * DEMO PROJECT: Cortex Cost Calculator - Git-Integrated Deployment
 * 
 * AUTHOR: SE Community
 * CREATED: 2026-01-05
 * EXPIRES: 2026-02-04 (30 days)
 * 
 * DEMONSTRATION PROJECT - EXPIRES: 2026-02-04
 * NOT FOR PRODUCTION USE - REFERENCE IMPLEMENTATION ONLY
 * 
 * DEPLOYMENT METHOD: Copy/Paste into Snowsight
 *   1. Copy this ENTIRE script
 *   2. Open Snowsight -> New Worksheet
 *   3. Paste the script
 *   4. Click "Run All"
 *   5. Wait ~2 minutes for complete deployment
 * 
 * PURPOSE:
 *   Single-script deployment leveraging Snowflake native Git integration.
 *   Creates API Integration -> Git Repository -> Executes SQL from Git -> 
 *   Deploys Streamlit from Git.
 * 
 * OBJECTS CREATED:
 * 
 *   Account-Level:
 *   - API Integration: SFE_CORTEX_TRAIL_GIT_API
 *   
 *   Database-Level (SNOWFLAKE_EXAMPLE):
 *   - Database: SNOWFLAKE_EXAMPLE
 *   - Schema: GIT_REPOS (shared infrastructure)
 *   - Schema: CORTEX_USAGE
 *   - Git Repository: SFE_CORTEX_TRAIL_REPO
 *   - 21 views (monitoring + attribution + forecast)
 *   - 1 snapshot table (CORTEX_USAGE_SNAPSHOTS)
 *   - 1 serverless task (TASK_DAILY_CORTEX_SNAPSHOT)
 *   - 1 Streamlit app (CORTEX_COST_CALCULATOR)
 * 
 * GITHUB REPOSITORY:
 *   https://github.com/sfc-gh-miwhitaker/cortex-trail
 * 
 * PREREQUISITES:
 *   - ACCOUNTADMIN role OR role with:
 *     * CREATE DATABASE
 *     * CREATE API INTEGRATION  
 *     * CREATE GIT REPOSITORY
 *     * IMPORTED PRIVILEGES on SNOWFLAKE database
 *   - Active warehouse (XSMALL or larger)
 * 
 * DEPLOYMENT TIME: ~2 minutes
 * 
 * CLEANUP:
 *   Run sql/99_cleanup/cleanup_all.sql for complete removal
 * 
 * VERSION: 3.0 (Updated LLM model pricing, deprecation warnings)
 * LAST UPDATED: 2026-01-05
 ******************************************************************************/

-- ===========================================================================
-- EXPIRATION CHECK (MANDATORY)
-- ===========================================================================
-- This demo expires 30 days after creation.
-- If expired, deployment is halted. Fork the repository and refresh the dates and syntax.
-- Expiration date: 2026-02-04

-- Hard stop if expired (Snowflake Scripting)
DECLARE
    demo_expired EXCEPTION (-20001, 'DEMO EXPIRED: Do not deploy. Fork the repository and update expiration + syntax.');
    expiration_date DATE := '2026-02-04'::DATE;
BEGIN
    IF (CURRENT_DATE() > expiration_date) THEN
        RAISE demo_expired;
    END IF;
END;

-- Display expiration status (review result before proceeding)
SELECT 
    '2026-02-04'::DATE AS expiration_date,
    CURRENT_DATE() AS current_date,
    DATEDIFF('day', CURRENT_DATE(), '2026-02-04'::DATE) AS days_remaining,
    CASE 
        WHEN DATEDIFF('day', CURRENT_DATE(), '2026-02-04'::DATE) < 0 
        THEN 'EXPIRED - Do not deploy. Fork repository and update expiration date.'
        WHEN DATEDIFF('day', CURRENT_DATE(), '2026-02-04'::DATE) <= 7
        THEN 'EXPIRING SOON - ' || DATEDIFF('day', CURRENT_DATE(), '2026-02-04'::DATE) || ' days remaining'
        ELSE 'ACTIVE - ' || DATEDIFF('day', CURRENT_DATE(), '2026-02-04'::DATE) || ' days remaining'
    END AS demo_status;

-- This demo uses Snowflake features current as of December 2025.
-- To use after expiration:
--   1. Fork: https://github.com/sfc-gh-miwhitaker/cortex-trail
--   2. Update expiration_date in this file
--   3. Review/update for latest Snowflake syntax and features

-- ===========================================================================
-- STEP 1: CREATE API INTEGRATION (Account-level object for GitHub access)
-- ===========================================================================
-- Requires ACCOUNTADMIN or CREATE API INTEGRATION privilege
-- Creates: CORTEX_TRAIL_GIT_API

CREATE OR REPLACE API INTEGRATION SFE_CORTEX_TRAIL_GIT_API
    API_PROVIDER = git_https_api
    API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-miwhitaker')
    ENABLED = TRUE
    COMMENT = 'DEMO: cortex-trail - GitHub API integration for public repository access | EXPIRES: 2026-02-04';

-- ===========================================================================
-- STEP 2: CREATE DATABASE & SCHEMAS
-- ===========================================================================
-- Creates: SNOWFLAKE_EXAMPLE database (demo container)
-- Creates: GIT_REPOS schema (shared infrastructure)
-- Creates: CORTEX_USAGE schema (will be created by monitoring script)

CREATE DATABASE IF NOT EXISTS SNOWFLAKE_EXAMPLE
    COMMENT = 'DEMO: Repository for example/demo projects - NOT FOR PRODUCTION | EXPIRES: 2026-02-04';

CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_EXAMPLE.GIT_REPOS
    COMMENT = 'DEMO: Shared schema for Git repository stages across demo projects | EXPIRES: 2026-02-04';

-- Set context for Git repository creation
USE SCHEMA SNOWFLAKE_EXAMPLE.GIT_REPOS;

-- ===========================================================================
-- STEP 3: CREATE GIT REPOSITORY
-- ===========================================================================
-- Creates: CORTEX_TRAIL_REPO in GIT_REPOS schema
-- Connects to: https://github.com/sfc-gh-miwhitaker/cortex-trail

CREATE OR REPLACE GIT REPOSITORY SNOWFLAKE_EXAMPLE.GIT_REPOS.SFE_CORTEX_TRAIL_REPO
    API_INTEGRATION = SFE_CORTEX_TRAIL_GIT_API
    ORIGIN = 'https://github.com/sfc-gh-miwhitaker/cortex-trail.git'
    COMMENT = 'DEMO: cortex-trail - Cortex Cost Calculator toolkit public repository | EXPIRES: 2026-02-04';

ALTER GIT REPOSITORY SNOWFLAKE_EXAMPLE.GIT_REPOS.SFE_CORTEX_TRAIL_REPO FETCH;

-- ===========================================================================
-- STEP 4: EXECUTE MONITORING DEPLOYMENT FROM GIT
-- ===========================================================================
-- Executes: sql/01_deployment/deploy_cortex_monitoring.sql from Git
-- Creates: CORTEX_USAGE schema, 21 views, 1 table, 1 task (forecast model optional)
-- Pattern: EXECUTE IMMEDIATE FROM Git stage (Snowflake native)

EXECUTE IMMEDIATE FROM @SNOWFLAKE_EXAMPLE.GIT_REPOS.SFE_CORTEX_TRAIL_REPO/branches/main/sql/01_deployment/deploy_cortex_monitoring.sql;

-- ===========================================================================
-- STEP 5: DEPLOY STREAMLIT APP FROM GIT
-- ===========================================================================
-- Creates: CORTEX_COST_CALCULATOR Streamlit app
-- Location: SNOWFLAKE_EXAMPLE.CORTEX_USAGE
-- Source: Git repository (copied at deploy time; update with ALTER STREAMLIT ... PULL after a FETCH)
-- Note: Uses COMPUTE_WH as default. Change to your warehouse if different.

USE SCHEMA SNOWFLAKE_EXAMPLE.CORTEX_USAGE;

-- Capture current warehouse for Streamlit deployment
SET streamlit_warehouse = (SELECT CURRENT_WAREHOUSE());

CREATE OR REPLACE STREAMLIT SNOWFLAKE_EXAMPLE.CORTEX_USAGE.CORTEX_COST_CALCULATOR
    FROM @SNOWFLAKE_EXAMPLE.GIT_REPOS.SFE_CORTEX_TRAIL_REPO/branches/main/streamlit/cortex_cost_calculator/
    MAIN_FILE = 'streamlit_app.py'
    QUERY_WAREHOUSE = $streamlit_warehouse
    TITLE = 'Cortex Cost Calculator'
    COMMENT = 'DEMO: cortex-trail - Interactive cost analysis and forecasting for Cortex services | EXPIRES: 2026-02-04';

-- Ensure the app has a live version (avoids requiring an owner to open the app once in Snowsight)
ALTER STREAMLIT SNOWFLAKE_EXAMPLE.CORTEX_USAGE.CORTEX_COST_CALCULATOR ADD LIVE VERSION FROM LAST;

-- ===========================================================================
-- DEPLOYMENT COMPLETE
-- ===========================================================================
-- Objects Created:
--
-- Account-Level:
--   - API Integration: SFE_CORTEX_TRAIL_GIT_API
--
-- Database-Level (SNOWFLAKE_EXAMPLE):
--   - Database: SNOWFLAKE_EXAMPLE
--   - Schema: GIT_REPOS (shared infrastructure)
--   - Schema: CORTEX_USAGE
--   - Git Repository: SFE_CORTEX_TRAIL_REPO
--   - Views: 21 views (monitoring + attribution + forecast)
--   - Table: CORTEX_USAGE_SNAPSHOTS
--   - Task: TASK_DAILY_CORTEX_SNAPSHOT (serverless)
--   - Streamlit App: CORTEX_COST_CALCULATOR
--
-- Next Steps:
--   1. Access app: Snowsight -> Projects -> Streamlit -> CORTEX_COST_CALCULATOR
--   2. Query views: SELECT usage_date, service_type, daily_unique_users, total_operations, total_credits FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_CORTEX_DAILY_SUMMARY ORDER BY usage_date DESC LIMIT 10
--   3. Monitor task: Task runs daily at 3:00 AM Pacific
--
-- Cleanup:
--   Run sql/99_cleanup/cleanup_all.sql to remove all objects
--
-- Total deployment time: ~2 minutes

-- ===========================================================================
-- VALIDATION - Verify Deployment Success
-- ===========================================================================

-- Check 1: Git repository accessible and contains SQL files
LIST @SNOWFLAKE_EXAMPLE.GIT_REPOS.SFE_CORTEX_TRAIL_REPO/branches/main/sql/ PATTERN='.*\.sql';

-- Check 2: Views created (should be 21)
SELECT 
    CASE 
        WHEN COUNT(*) = 21 THEN 'SUCCESS: All 21 views created'
        ELSE 'WARNING: Expected 21 views, found ' || COUNT(*) || ' views'
    END AS validation_status
FROM SNOWFLAKE.INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'CORTEX_USAGE'
    AND TABLE_CATALOG = 'SNOWFLAKE_EXAMPLE';

-- Check 3: Snapshot table exists
SELECT 
    CASE 
        WHEN COUNT(*) = 1 THEN 'SUCCESS: Snapshot table created'
        ELSE 'WARNING: Snapshot table not found'
    END AS validation_status
FROM SNOWFLAKE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'CORTEX_USAGE'
    AND TABLE_CATALOG = 'SNOWFLAKE_EXAMPLE'
    AND TABLE_NAME = 'CORTEX_USAGE_SNAPSHOTS';

-- Check 4: Serverless task created and running
SHOW TASKS LIKE 'TASK_DAILY_CORTEX_SNAPSHOT' IN SCHEMA SNOWFLAKE_EXAMPLE.CORTEX_USAGE;

-- Check 5: Streamlit app accessible
SHOW STREAMLITS LIKE 'CORTEX_COST_CALCULATOR' IN SCHEMA SNOWFLAKE_EXAMPLE.CORTEX_USAGE;

-- Check 6: Test data access (empty result is normal if no Cortex usage yet)
SELECT 
    COUNT(*) AS row_count,
    CASE 
        WHEN COUNT(*) > 0 THEN 'Data available - views are working'
        ELSE 'No data yet (normal if account has no Cortex usage)'
    END AS data_status
FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_CORTEX_DAILY_SUMMARY;

-- ===========================================================================
-- TROUBLESHOOTING GUIDE
-- ===========================================================================

-- Common Issues and Solutions:
--
-- 1. "API integration not found"
--    -> Requires ACCOUNTADMIN or CREATE API INTEGRATION privilege
--    -> Switch role: USE ROLE ACCOUNTADMIN;
--
-- 2. "Git repository fetch failed"
--    -> Verify repo is public: https://github.com/sfc-gh-miwhitaker/cortex-trail
--    -> Check network connectivity to GitHub
--
-- 3. "EXECUTE IMMEDIATE FROM failed"
--    -> Verify warehouse is running
--    -> Verify Git fetch completed successfully
--    -> Check file exists: LIST @SNOWFLAKE_EXAMPLE.GIT_REPOS.CORTEX_TRAIL_REPO/branches/main/sql/01_deployment/;
--
-- 4. "Streamlit app creation failed"
--    -> Verify streamlit_app.py exists in Git repo
--    -> Check path: LIST @...SFE_CORTEX_TRAIL_REPO/branches/main/streamlit/cortex_cost_calculator/;
--
-- 5. "Views return no data"
--    -> Normal if account has no Cortex usage yet
--    -> Views will populate after using Cortex services
--    -> Check permissions: GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE <your_role>;
--
-- Detailed docs: See docs/03-TROUBLESHOOTING.md in GitHub repository

