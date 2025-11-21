/*******************************************************************************
 * DEMO PROJECT: Cortex Cost Calculator - Complete Cleanup
 * 
 * PURPOSE:
 *   Remove ALL objects created by deploy_all.sql
 * 
 * WHAT GETS REMOVED:
 *   - Streamlit app: CORTEX_COST_CALCULATOR
 *   - Git repository: CORTEX_TRAIL_REPO
 *   - API integration: CORTEX_TRAIL_GIT_API
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
 * TIME: < 1 minute
 * 
 * VERSION: 2.7
 * LAST UPDATED: 2025-11-21
 ******************************************************************************/

-- ===========================================================================
-- STEP 1: DROP STREAMLIT APP
-- ===========================================================================

DROP STREAMLIT IF EXISTS SNOWFLAKE_EXAMPLE.CORTEX_USAGE.CORTEX_COST_CALCULATOR;

SELECT '✓ Streamlit app removed' AS status;

-- ===========================================================================
-- STEP 2: DROP MONITORING OBJECTS (Schema with all views, tables, tasks)
-- ===========================================================================

DROP SCHEMA IF EXISTS SNOWFLAKE_EXAMPLE.CORTEX_USAGE CASCADE;

SELECT '✓ CORTEX_USAGE schema removed (16 views + table + task)' AS status;

-- ===========================================================================
-- STEP 3: DROP GIT REPOSITORY
-- ===========================================================================

DROP GIT REPOSITORY IF EXISTS SNOWFLAKE_EXAMPLE.GIT_REPOS.CORTEX_TRAIL_REPO;

SELECT '✓ Git repository removed' AS status;

-- ===========================================================================
-- STEP 4: DROP API INTEGRATION
-- ===========================================================================

DROP API INTEGRATION IF EXISTS CORTEX_TRAIL_GIT_API;

SELECT '✓ API integration removed' AS status;

-- ===========================================================================
-- CLEANUP COMPLETE
-- ===========================================================================

SELECT '✅ CLEANUP COMPLETE!' AS status;

SELECT 'Removed Objects:' AS summary
UNION ALL SELECT '  ✓ API Integration: CORTEX_TRAIL_GIT_API'
UNION ALL SELECT '  ✓ Git Repository: CORTEX_TRAIL_REPO'
UNION ALL SELECT '  ✓ Streamlit App: CORTEX_COST_CALCULATOR'
UNION ALL SELECT '  ✓ Schema: CORTEX_USAGE (all objects dropped)'
UNION ALL SELECT ''
UNION ALL SELECT 'Protected (Not Removed):'
UNION ALL SELECT '  ℹ️  Database: SNOWFLAKE_EXAMPLE (may contain other demos)'
UNION ALL SELECT '  ℹ️  Schema: SNOWFLAKE_EXAMPLE.GIT_REPOS (shared infrastructure)'
UNION ALL SELECT '  ℹ️  Source data: SNOWFLAKE.ACCOUNT_USAGE (unaffected)'
UNION ALL SELECT ''
UNION ALL SELECT '⏱️  Total cleanup time: < 1 minute';

-- ===========================================================================
-- VERIFICATION (Optional - confirm objects removed)
-- ===========================================================================

-- These should return no results:
SHOW API INTEGRATIONS LIKE 'CORTEX_TRAIL_GIT_API';
SHOW GIT REPOSITORIES LIKE 'CORTEX_TRAIL_REPO' IN SCHEMA SNOWFLAKE_EXAMPLE.GIT_REPOS;
SHOW SCHEMAS LIKE 'CORTEX_USAGE' IN DATABASE SNOWFLAKE_EXAMPLE;
SHOW STREAMLITS LIKE 'CORTEX_COST_CALCULATOR' IN SCHEMA SNOWFLAKE_EXAMPLE.CORTEX_USAGE;

