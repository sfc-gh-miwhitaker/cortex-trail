/*******************************************************************************
 * DEMO PROJECT: Cortex Cost Calculator - Complete Deployment
 * 
 * ⚠️  NOT FOR PRODUCTION USE - EXAMPLE IMPLEMENTATION ONLY
 * 
 * DEPLOYMENT METHOD: Copy/Paste into Snowsight
 *   1. Copy this ENTIRE script
 *   2. Open Snowsight → New Worksheet
 *   3. Paste the script
 *   4. Click "Run All"
 *   5. Wait ~1-2 minutes for complete deployment
 * 
 * PURPOSE:
 *   Single-script deployment for entire Cortex Cost Calculator toolkit:
 *   - Monitoring views (16 views tracking all Cortex services)
 *   - Snapshot table for historical tracking
 *   - Serverless task for daily snapshots
 *   - Streamlit calculator app (deployed from Git repository)
 * 
 * WHAT GETS CREATED:
 *   Account-Level Objects:
 *   - API Integration: CORTEX_TRAIL_GIT_API (GitHub access)
 * 
 *   Database Objects (SNOWFLAKE_EXAMPLE):
 *   - Git Repository: CORTEX_TRAIL_REPO
 *   - Schema: CORTEX_USAGE
 *   - 16 monitoring views
 *   - 1 snapshot table (CORTEX_USAGE_SNAPSHOTS)
 *   - 1 serverless task (TASK_DAILY_CORTEX_SNAPSHOT)
 *   - 1 Streamlit app (CORTEX_COST_CALCULATOR)
 * 
 * GITHUB REPOSITORY:
 *   https://github.com/sfc-gh-miwhitaker/cortex-trail
 * 
 * PREREQUISITES:
 *   - ACCOUNTADMIN role OR role with:
 *     * CREATE DATABASE privilege
 *     * CREATE API INTEGRATION privilege  
 *     * CREATE GIT REPOSITORY privilege
 *     * IMPORTED PRIVILEGES on SNOWFLAKE database
 *   - Active warehouse (any size, SMALL is fine)
 * 
 * DEPLOYMENT TIME: < 2 minutes
 * 
 * CLEANUP:
 *   See sql/99_cleanup/cleanup_all.sql for complete removal
 * 
 * VERSION: 2.7 (Git-integrated deployment)
 * LAST UPDATED: 2025-11-21
 ******************************************************************************/

-- ===========================================================================
-- STEP 1: GITHUB API INTEGRATION (Required for Git Repository access)
-- ===========================================================================

CREATE OR REPLACE API INTEGRATION CORTEX_TRAIL_GIT_API
  API_PROVIDER = git_https_api
  API_ALLOWED_PREFIXES = ('https://github.com/sfc-gh-miwhitaker')
  ENABLED = TRUE
  COMMENT = 'DEMO: cortex-trail - GitHub API integration for public repo access';

-- Verify API integration created
SHOW API INTEGRATIONS LIKE 'CORTEX_TRAIL_GIT_API';

-- ===========================================================================
-- STEP 2: DATABASE & SCHEMA SETUP
-- ===========================================================================

CREATE DATABASE IF NOT EXISTS SNOWFLAKE_EXAMPLE
    COMMENT = 'DEMO: Database for Cortex usage monitoring and cost analysis';

CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_EXAMPLE.GIT_REPOS
    COMMENT = 'DEMO: Schema for Git repository stages (shared across demos)';

USE SCHEMA SNOWFLAKE_EXAMPLE.GIT_REPOS;

-- ===========================================================================
-- STEP 3: GIT REPOSITORY SETUP
-- ===========================================================================

CREATE OR REPLACE GIT REPOSITORY SNOWFLAKE_EXAMPLE.GIT_REPOS.CORTEX_TRAIL_REPO
  API_INTEGRATION = CORTEX_TRAIL_GIT_API
  ORIGIN = 'https://github.com/sfc-gh-miwhitaker/cortex-trail.git'
  COMMENT = 'DEMO: cortex-trail - Cortex Cost Calculator toolkit repository';

-- Fetch latest code from GitHub
ALTER GIT REPOSITORY SNOWFLAKE_EXAMPLE.GIT_REPOS.CORTEX_TRAIL_REPO FETCH;

-- Verify repository setup
SHOW GIT REPOSITORIES LIKE 'CORTEX_TRAIL_REPO' IN SCHEMA SNOWFLAKE_EXAMPLE.GIT_REPOS;

-- ===========================================================================
-- STEP 4: EXECUTE MONITORING DEPLOYMENT FROM GIT
-- ===========================================================================

-- Execute the monitoring deployment script directly from Git repository
EXECUTE IMMEDIATE FROM @SNOWFLAKE_EXAMPLE.GIT_REPOS.CORTEX_TRAIL_REPO/branches/main/sql/01_deployment/deploy_cortex_monitoring.sql;

-- ===========================================================================
-- STEP 5: STREAMLIT APP DEPLOYMENT FROM GIT
-- ===========================================================================

USE SCHEMA SNOWFLAKE_EXAMPLE.CORTEX_USAGE;

-- Create Streamlit app pointing to Git repository
CREATE OR REPLACE STREAMLIT SNOWFLAKE_EXAMPLE.CORTEX_USAGE.CORTEX_COST_CALCULATOR
  FROM @SNOWFLAKE_EXAMPLE.GIT_REPOS.CORTEX_TRAIL_REPO/branches/main/streamlit/cortex_cost_calculator/
  MAIN_FILE = 'streamlit_app.py'
  QUERY_WAREHOUSE = CURRENT_WAREHOUSE()
  TITLE = 'Cortex Cost Calculator'
  COMMENT = 'DEMO: cortex-trail - Interactive Cortex usage analysis and cost forecasting tool';

-- ===========================================================================
-- DEPLOYMENT COMPLETE
-- ===========================================================================

SELECT '✅ DEPLOYMENT COMPLETE!' AS status;

SELECT 'Created Objects:' AS summary
UNION ALL SELECT '  ✓ API Integration: CORTEX_TRAIL_GIT_API'
UNION ALL SELECT '  ✓ Git Repository: SNOWFLAKE_EXAMPLE.GIT_REPOS.CORTEX_TRAIL_REPO'
UNION ALL SELECT '  ✓ Database: SNOWFLAKE_EXAMPLE'
UNION ALL SELECT '  ✓ Schema: CORTEX_USAGE (16 views + 1 table + 1 task)'
UNION ALL SELECT '  ✓ Streamlit App: CORTEX_COST_CALCULATOR'
UNION ALL SELECT ''
UNION ALL SELECT '📊 Next Steps:'
UNION ALL SELECT '  1. Access Streamlit: Snowsight → Projects → Streamlit → CORTEX_COST_CALCULATOR'
UNION ALL SELECT '  2. Query views: SELECT * FROM V_CORTEX_DAILY_SUMMARY LIMIT 10'
UNION ALL SELECT '  3. Monitor snapshots: Task runs daily at 3:00 AM'
UNION ALL SELECT ''
UNION ALL SELECT '⏱️  Total deployment time: < 2 minutes'
UNION ALL SELECT '🧹 Cleanup: Run sql/cleanup_all.sql to remove everything';

-- ===========================================================================
-- VALIDATION QUERIES (Optional - verify everything works)
-- ===========================================================================

-- Verify Git repository accessible
LIST @SNOWFLAKE_EXAMPLE.GIT_REPOS.CORTEX_TRAIL_REPO/branches/main/ PATTERN='.*\.sql';

-- Verify monitoring views created
SHOW VIEWS IN SCHEMA SNOWFLAKE_EXAMPLE.CORTEX_USAGE;

-- Verify Streamlit app created
SHOW STREAMLITS IN SCHEMA SNOWFLAKE_EXAMPLE.CORTEX_USAGE;

-- Test data access (will be empty if no Cortex usage yet)
SELECT COUNT(*) AS row_count 
FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_CORTEX_DAILY_SUMMARY;

-- ===========================================================================
-- TROUBLESHOOTING
-- ===========================================================================

/*
ISSUE: "API integration not found"
FIX: Ensure you have ACCOUNTADMIN or CREATE API INTEGRATION privilege

ISSUE: "Git repository fetch failed"
FIX: Verify GitHub repo is public: https://github.com/sfc-gh-miwhitaker/cortex-trail

ISSUE: "EXECUTE IMMEDIATE FROM failed"
FIX: Verify warehouse is running and Git repo was fetched successfully

ISSUE: "Streamlit app creation failed"
FIX: Verify MAIN_FILE path exists in repo:
     LIST @SNOWFLAKE_EXAMPLE.GIT_REPOS.CORTEX_TRAIL_REPO/branches/main/streamlit/cortex_cost_calculator/;

ISSUE: "Views return no data"
SOLUTION: This is normal if account has no Cortex usage yet. Views will populate as you use Cortex services.

For detailed troubleshooting: See docs/03-TROUBLESHOOTING.md in the GitHub repository
*/

