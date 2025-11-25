/*******************************************************************************
 * DEMO PROJECT: Cortex Cost Calculator - Complete Cleanup
 * 
 * PURPOSE:
 *   Remove ALL objects created by deploy_all.sql
 * 
 * WHAT GETS REMOVED:
 *   - Streamlit app: CORTEX_COST_CALCULATOR
 *   - Git repository: SFE_CORTEX_TRAIL_REPO
 *   - API integration: SFE_CORTEX_TRAIL_GIT_API
 *   - Schema: CORTEX_USAGE (all views, tables, tasks)
 *   
 * WHAT STAYS (Protected shared infrastructure):
 *   - SNOWFLAKE_EXAMPLE database (may be used by other demos)
 *   - SNOWFLAKE_EXAMPLE.GIT_REPOS schema (shared across demos)
 *   - Source data in ACCOUNT_USAGE
 * 
 * DEPLOYMENT METHOD: Copy/Paste into Snowsight
 *   1. Copy this ENTIRE script
 *   2. Open Snowsight → New Worksheet
 *   3. Paste the script
 *   4. Click "Run All"
 *   5. Wait ~30 seconds for cleanup
 * 
 * ERROR HANDLING:
 *   - All DROP commands use IF EXISTS (safe to run multiple times)
 *   - Validation queries at end verify cleanup success
 *   - Clear error messages if permissions are insufficient
 * 
 * TIME: < 1 minute
 * 
 * VERSION: 2.9 (Standards-compliant: SFE_ prefixes, ASCII-only, comprehensive error handling)
 * LAST UPDATED: 2025-11-21
 ******************************************************************************/

-- ===========================================================================
-- CLEANUP INITIALIZATION
-- ===========================================================================

-- Set script behavior for error handling
-- This allows the script to continue even if individual objects don't exist

-- ===========================================================================
-- STEP 1: SUSPEND AND DROP TASKS (must be done before schema drop)
-- ===========================================================================
-- Tasks must be suspended before they can be dropped
-- This prevents "task is running" errors

BEGIN
    -- Try to suspend the task (may not exist)
    ALTER TASK IF EXISTS SNOWFLAKE_EXAMPLE.CORTEX_USAGE.TASK_DAILY_CORTEX_SNAPSHOT SUSPEND;
    RETURN 'Task suspended (if existed)';
EXCEPTION
    WHEN OTHER THEN
        RETURN 'WARNING: Task suspend skipped: ' || SQLERRM;
END;

-- ===========================================================================
-- STEP 2: DROP STREAMLIT APP
-- ===========================================================================
-- Must be dropped before schema since it references schema objects

BEGIN
    DROP STREAMLIT IF EXISTS SNOWFLAKE_EXAMPLE.CORTEX_USAGE.CORTEX_COST_CALCULATOR;
    RETURN 'Streamlit app removed';
EXCEPTION
    WHEN STATEMENT_ERROR THEN
        -- Schema might not exist, that's ok
        RETURN 'WARNING: Streamlit app skipped (schema may not exist)';
    WHEN OTHER THEN
        RETURN 'WARNING: Streamlit app removal error: ' || SQLERRM;
END;

-- ===========================================================================
-- STEP 3: DROP MONITORING SCHEMA (with all objects)
-- ===========================================================================
-- CASCADE automatically drops all objects in the schema:
--   - 16 views (V_CORTEX_*)
--   - 1 table (CORTEX_USAGE_SNAPSHOTS)
--   - 1 task (TASK_DAILY_CORTEX_SNAPSHOT)

BEGIN
    DROP SCHEMA IF EXISTS SNOWFLAKE_EXAMPLE.CORTEX_USAGE CASCADE;
    RETURN 'CORTEX_USAGE schema removed (16 views + table + task)';
EXCEPTION
    WHEN INSUFFICIENT_PRIVILEGES THEN
        RETURN 'ERROR: Insufficient privileges to drop schema. Need OWNERSHIP or higher role.';
    WHEN OTHER THEN
        RETURN 'WARNING: Schema drop error: ' || SQLERRM;
END;

-- ===========================================================================
-- STEP 4: DROP GIT REPOSITORY
-- ===========================================================================

BEGIN
    DROP GIT REPOSITORY IF EXISTS SNOWFLAKE_EXAMPLE.GIT_REPOS.SFE_CORTEX_TRAIL_REPO;
    RETURN 'Git repository removed';
EXCEPTION
    WHEN STATEMENT_ERROR THEN
        -- GIT_REPOS schema might not exist, that's ok
        RETURN 'WARNING: Git repository skipped (GIT_REPOS schema may not exist)';
    WHEN INSUFFICIENT_PRIVILEGES THEN
        RETURN 'ERROR: Insufficient privileges. Need OWNERSHIP on GIT_REPOS schema or ACCOUNTADMIN.';
    WHEN OTHER THEN
        RETURN 'WARNING: Git repository removal error: ' || SQLERRM;
END;

-- ===========================================================================
-- STEP 5: DROP API INTEGRATION
-- ===========================================================================
-- Requires ACCOUNTADMIN or role with CREATE INTEGRATION privilege

BEGIN
    DROP API INTEGRATION IF EXISTS SFE_CORTEX_TRAIL_GIT_API;
    RETURN 'API integration removed';
EXCEPTION
    WHEN INSUFFICIENT_PRIVILEGES THEN
        RETURN 'ERROR: Insufficient privileges. API integrations require ACCOUNTADMIN or CREATE INTEGRATION privilege.';
    WHEN OTHER THEN
        RETURN 'WARNING: API integration removal error: ' || SQLERRM;
END;

-- ===========================================================================
-- CLEANUP COMPLETE
-- ===========================================================================
-- Removed Objects:
--   - Task: TASK_DAILY_CORTEX_SNAPSHOT (suspended & dropped)
--   - Streamlit App: CORTEX_COST_CALCULATOR
--   - Schema: CORTEX_USAGE (16 views + table + task)
--   - Git Repository: SFE_CORTEX_TRAIL_REPO
--   - API Integration: SFE_CORTEX_TRAIL_GIT_API
--
-- Protected (Not Removed):
--   - Database: SNOWFLAKE_EXAMPLE (may contain other demos)
--   - Schema: SNOWFLAKE_EXAMPLE.GIT_REPOS (shared infrastructure)
--   - Source data: SNOWFLAKE.ACCOUNT_USAGE (unaffected)
--
-- Total cleanup time: < 1 minute

-- ===========================================================================
-- VERIFICATION - Confirm Cleanup Success
-- ===========================================================================
-- Run these queries to verify all objects were removed
-- All queries should return 0 rows or "no results"

-- Check 1: API Integration should NOT exist
SELECT 
    CASE 
        WHEN COUNT(*) = 0 THEN 'SUCCESS: API Integration removed'
        ELSE 'WARNING: API Integration still exists'
    END AS verification_status
FROM TABLE(RESULT_SCAN(LAST_QUERY_ID(-1)))
WHERE TRUE; -- Will be empty if previous SHOW returns nothing

SHOW API INTEGRATIONS LIKE 'SFE_CORTEX_TRAIL_GIT_API';

-- Check 2: Schema should NOT exist
SELECT 
    CASE 
        WHEN COUNT(*) = 0 THEN '✅ CORTEX_USAGE schema removed successfully'
        ELSE '❌ WARNING: CORTEX_USAGE schema still exists'
    END AS verification_status
FROM SNOWFLAKE.INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME = 'CORTEX_USAGE'
    AND CATALOG_NAME = 'SNOWFLAKE_EXAMPLE';

-- Check 3: Git Repository should NOT exist (only if GIT_REPOS schema exists)
BEGIN
    LET repo_count NUMBER;
    SELECT COUNT(*) INTO :repo_count
    FROM SNOWFLAKE.INFORMATION_SCHEMA.SCHEMATA
    WHERE SCHEMA_NAME = 'GIT_REPOS'
        AND CATALOG_NAME = 'SNOWFLAKE_EXAMPLE';
    
    IF (repo_count > 0) THEN
        -- GIT_REPOS schema exists, check for our repo
        SHOW GIT REPOSITORIES LIKE 'SFE_CORTEX_TRAIL_REPO' IN SCHEMA SNOWFLAKE_EXAMPLE.GIT_REPOS;
        RETURN 'Git repository verification complete';
    ELSE
        RETURN 'Git repository verification skipped (GIT_REPOS schema does not exist)';
    END IF;
EXCEPTION
    WHEN OTHER THEN
        RETURN 'WARNING: Git repository verification skipped: ' || SQLERRM;
END;

-- ===========================================================================
-- TROUBLESHOOTING GUIDE
-- ===========================================================================

-- If cleanup failed with permission errors:
--
-- 1. API Integration errors:
--    -> Switch to ACCOUNTADMIN role
--    -> USE ROLE ACCOUNTADMIN;
--    -> Re-run this cleanup script
--
-- 2. Schema/Object errors:
--    -> Verify you have OWNERSHIP on CORTEX_USAGE schema
--    -> GRANT OWNERSHIP ON SCHEMA SNOWFLAKE_EXAMPLE.CORTEX_USAGE TO ROLE <your_role>;
--
-- 3. Git Repository errors:
--    -> Verify you have OWNERSHIP on GIT_REPOS schema or ACCOUNTADMIN
--
-- 4. Partial cleanup (some objects remain):
--    -> Safe to re-run this script multiple times
--    -> Use SHOW commands above to identify remaining objects
--
-- For complete manual cleanup:
--    DROP DATABASE SNOWFLAKE_EXAMPLE CASCADE;  -- CAUTION: Removes ALL demos
--    DROP API INTEGRATION SFE_CORTEX_TRAIL_GIT_API;

