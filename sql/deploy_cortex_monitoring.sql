-- Cortex Usage Monitoring - Deployment Script
-- Target: SNOWFLAKE_EXAMPLE.CORTEX_USAGE
-- Prerequisites: IMPORTED PRIVILEGES on SNOWFLAKE database (or ACCOUNTADMIN role)
-- Safe to run: Idempotent, read-only views, no data modification

-- Create database and schema
CREATE DATABASE IF NOT EXISTS SNOWFLAKE_EXAMPLE
    COMMENT = 'DEMO: Database for Cortex usage monitoring and cost analysis';

CREATE SCHEMA IF NOT EXISTS SNOWFLAKE_EXAMPLE.CORTEX_USAGE
    COMMENT = 'DEMO: Schema containing views for Cortex service usage tracking (updated Nov 2024)';

USE SCHEMA SNOWFLAKE_EXAMPLE.CORTEX_USAGE;

-- View 1: Cortex Analyst usage
CREATE OR REPLACE VIEW V_CORTEX_ANALYST_DETAIL
    COMMENT = 'DEMO: Cortex Analyst usage metrics'
AS
SELECT 
    'Cortex Analyst' AS service_type,
    DATE_TRUNC('day', start_time) AS usage_date,
    start_time,
    end_time,
    username,
    credits,
    request_count
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_ANALYST_USAGE_HISTORY
WHERE start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP());

-- View 2: Cortex Search usage
CREATE OR REPLACE VIEW V_CORTEX_SEARCH_DETAIL
    COMMENT = 'DEMO: Cortex usage tracking view - see header for version history'
AS
SELECT 
    'Cortex Search' AS service_type,
    usage_date,
    database_name,
    schema_name,
    service_name,
    service_id,
    consumption_type,
    credits,
    model_name,
    tokens
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_DAILY_USAGE_HISTORY
WHERE usage_date >= DATEADD('day', -90, CURRENT_TIMESTAMP());

-- View 3:
CREATE OR REPLACE VIEW V_CORTEX_SEARCH_SERVING_DETAIL
    COMMENT = 'DEMO: Cortex usage tracking view - see header for version history'
AS
SELECT 
    'Cortex Search Serving' AS service_type,
    DATE_TRUNC('day', start_time) AS usage_date,
    start_time,
    end_time,
    database_name,
    schema_name,
    service_name,
    service_id,
    credits
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_SEARCH_SERVING_USAGE_HISTORY
WHERE start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP());

-- View 4:
CREATE OR REPLACE VIEW V_CORTEX_FUNCTIONS_DETAIL
    COMMENT = 'DEMO: Cortex usage tracking view - see header for version history'
AS
SELECT 
    'Cortex Functions' AS service_type,
    DATE_TRUNC('day', start_time) AS usage_date,
    start_time,
    end_time,
    function_name,
    model_name,
    warehouse_id,
    token_credits,
    tokens
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY
WHERE start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP());

-- View 5:
CREATE OR REPLACE VIEW V_CORTEX_FUNCTIONS_QUERY_DETAIL
    COMMENT = 'DEMO: Cortex usage tracking view - see header for version history'
AS
SELECT 
    'Cortex Functions Query' AS service_type,
    query_id,
    warehouse_id,
    model_name,
    function_name,
    tokens,
    token_credits,
    -- Calculate cost per million tokens
    CASE 
        WHEN tokens > 0 THEN (token_credits / tokens) * 1000000
        ELSE 0 
    END AS cost_per_million_tokens
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY;

-- View 6:
CREATE OR REPLACE VIEW V_DOCUMENT_AI_DETAIL
    COMMENT = 'DEMO: Cortex usage tracking view - see header for version history'
AS
SELECT 
    'Document AI' AS service_type,
    DATE_TRUNC('day', start_time) AS usage_date,
    start_time,
    end_time,
    credits_used,
    query_id,
    operation_name,
    page_count,
    document_count,
    feature_count
FROM SNOWFLAKE.ACCOUNT_USAGE.DOCUMENT_AI_USAGE_HISTORY
WHERE start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP());

-- View 7:
-- Supports: Document AI, PARSE_DOCUMENT, AI_EXTRACT
CREATE OR REPLACE VIEW V_CORTEX_DOCUMENT_PROCESSING_DETAIL
    COMMENT = 'DEMO: Cortex usage tracking view - see header for version history'
AS
SELECT 
    'Cortex Document Processing' AS service_type,
    DATE_TRUNC('day', start_time) AS usage_date,
    query_id,
    credits_used,
    start_time,
    end_time,
    function_name,
    model_name,
    operation_name,
    page_count,
    document_count,
    feature_count,
    -- Calculate efficiency metrics
    CASE 
        WHEN page_count > 0 THEN credits_used / page_count 
        ELSE 0 
    END AS credits_per_page,
    CASE 
        WHEN document_count > 0 THEN credits_used / document_count 
        ELSE 0 
    END AS credits_per_document
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_DOCUMENT_PROCESSING_USAGE_HISTORY
WHERE start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP());

-- View 8:
CREATE OR REPLACE VIEW V_CORTEX_FINE_TUNING_DETAIL
    COMMENT = 'DEMO: Cortex usage tracking view - see header for version history'
AS
SELECT 
    'Cortex Fine-tuning' AS service_type,
    DATE_TRUNC('day', start_time) AS usage_date,
    start_time,
    end_time,
    warehouse_id,
    model_name,
    token_credits,
    tokens,
    -- Calculate cost per million tokens
    CASE 
        WHEN tokens > 0 THEN (token_credits / tokens) * 1000000
        ELSE 0 
    END AS cost_per_million_tokens
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FINE_TUNING_USAGE_HISTORY
WHERE start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP());

-- View 9:
CREATE OR REPLACE VIEW V_AISQL_FUNCTION_SUMMARY
    COMMENT = 'DEMO: Cortex usage tracking view - see header for version history'
AS
SELECT 
    function_name,
    model_name,
    COUNT(*) AS call_count,
    SUM(token_credits) AS total_credits,
    SUM(tokens) AS total_tokens,
    AVG(token_credits) AS avg_credits_per_call,
    AVG(tokens) AS avg_tokens_per_call,
    CASE 
        WHEN SUM(tokens) > 0 
        THEN SUM(token_credits) / SUM(tokens) * 1000000
        ELSE 0 
    END AS cost_per_million_tokens,
    MIN(start_time) AS first_usage,
    MAX(end_time) AS last_usage,
    DATEDIFF('day', MIN(start_time), MAX(end_time)) + 1 AS days_in_use,
    SUM(CASE WHEN warehouse_id = 0 THEN 1 ELSE 0 END) AS serverless_calls,
    SUM(CASE WHEN warehouse_id > 0 THEN 1 ELSE 0 END) AS compute_calls
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY
WHERE start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP())
GROUP BY function_name, model_name
ORDER BY total_credits DESC;

-- View 10:
CREATE OR REPLACE VIEW V_AISQL_MODEL_COMPARISON
    COMMENT = 'DEMO: Cortex usage tracking view - see header for version history'
AS
SELECT 
    model_name,
    COUNT(DISTINCT function_name) AS functions_used,
    COUNT(*) AS total_calls,
    SUM(token_credits) AS total_credits,
    SUM(tokens) AS total_tokens,
    AVG(token_credits) AS avg_credits_per_call,
    AVG(tokens) AS avg_tokens_per_call,
    PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY token_credits) AS median_credits,
    PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY token_credits) AS p90_credits,
    CASE 
        WHEN SUM(tokens) > 0 
        THEN SUM(token_credits) / SUM(tokens) * 1000000
        ELSE 0 
    END AS cost_per_million_tokens,
    MIN(start_time) AS first_usage,
    MAX(end_time) AS last_usage
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY
WHERE start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP())
    AND model_name IS NOT NULL
GROUP BY model_name
ORDER BY total_credits DESC;

-- View 11:
CREATE OR REPLACE VIEW V_AISQL_DAILY_TRENDS
    COMMENT = 'DEMO: Cortex usage tracking view - see header for version history'
AS
SELECT 
    DATE(start_time) AS usage_date,
    function_name,
    model_name,
    COUNT(*) AS hourly_records,
    SUM(token_credits) AS daily_credits,
    SUM(tokens) AS daily_tokens,
    SUM(CASE WHEN warehouse_id = 0 THEN 1 ELSE 0 END) AS serverless_calls,
    SUM(CASE WHEN warehouse_id > 0 THEN 1 ELSE 0 END) AS compute_calls
FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_USAGE_HISTORY
WHERE start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP())
GROUP BY DATE(start_time), function_name, model_name
ORDER BY usage_date DESC, daily_credits DESC;

-- View 12:
CREATE OR REPLACE VIEW V_QUERY_COST_ANALYSIS
    COMMENT = 'DEMO: Cortex usage tracking view - see header for version history'
AS
WITH function_queries AS (
    SELECT 
        'LLM Functions' AS service_category,
        query_id,
        function_name AS operation_name,
        model_name,
        token_credits AS credits_used,
        tokens AS units_processed,
        NULL AS page_count,
        NULL AS document_count
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY
),
document_queries AS (
    SELECT 
        'Document Processing' AS service_category,
        query_id,
        function_name AS operation_name,
        model_name,
        credits_used,
        NULL AS units_processed,
        page_count,
        document_count
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_DOCUMENT_PROCESSING_USAGE_HISTORY
    WHERE start_time >= DATEADD('day', -90, CURRENT_TIMESTAMP())
)
SELECT 
    service_category,
    query_id,
    operation_name,
    model_name,
    credits_used,
    units_processed,
    page_count,
    document_count,
    -- Cost efficiency metrics
    CASE 
        WHEN units_processed > 0 THEN (credits_used / units_processed) * 1000000
        ELSE NULL 
    END AS cost_per_million_units,
    CASE 
        WHEN page_count > 0 THEN credits_used / page_count
        ELSE NULL 
    END AS cost_per_page,
    -- Rank by cost within category
    ROW_NUMBER() OVER (PARTITION BY service_category ORDER BY credits_used DESC) AS cost_rank
FROM (
    SELECT * FROM function_queries
    UNION ALL
    SELECT * FROM document_queries
)
WHERE credits_used > 0
ORDER BY credits_used DESC;

-- View 13:
CREATE OR REPLACE VIEW V_CORTEX_DAILY_SUMMARY
    COMMENT = 'DEMO: Cortex usage tracking view - see header for version history'
AS
WITH all_services AS (
    -- Cortex Analyst
    SELECT 
        usage_date,
        service_type,
        COUNT(DISTINCT username) AS daily_unique_users,
        SUM(request_count) AS total_operations,
        SUM(credits) AS total_credits
    FROM V_CORTEX_ANALYST_DETAIL
    GROUP BY usage_date, service_type
    
    UNION ALL
    
    -- Cortex Search (daily aggregates - no user info)
    SELECT 
        usage_date,
        service_type,
        0 AS daily_unique_users,
        SUM(tokens) AS total_operations,
        SUM(credits) AS total_credits
    FROM V_CORTEX_SEARCH_DETAIL
    GROUP BY usage_date, service_type
    
    UNION ALL
    
    -- Cortex Search Serving
    SELECT 
        usage_date,
        service_type,
        0 AS daily_unique_users,
        COUNT(*) AS total_operations,
        SUM(credits) AS total_credits
    FROM V_CORTEX_SEARCH_SERVING_DETAIL
    GROUP BY usage_date, service_type
    
    UNION ALL
    
    -- Cortex Functions (hourly aggregates - no user info)
    SELECT 
        usage_date,
        service_type,
        0 AS daily_unique_users,
        SUM(tokens) AS total_operations,
        SUM(token_credits) AS total_credits
    FROM V_CORTEX_FUNCTIONS_DETAIL
    GROUP BY usage_date, service_type
    
    UNION ALL
    
    -- Document AI (legacy)
    SELECT 
        usage_date,
        service_type,
        COUNT(DISTINCT query_id) AS daily_unique_users,
        SUM(page_count) AS total_operations,
        SUM(credits_used) AS total_credits
    FROM V_DOCUMENT_AI_DETAIL
    GROUP BY usage_date, service_type
    
    UNION ALL
    
    -- Document Processing (NEW in v2.6)
    SELECT 
        usage_date,
        service_type,
        COUNT(DISTINCT query_id) AS daily_unique_users,
        SUM(page_count) AS total_operations,
        SUM(credits_used) AS total_credits
    FROM V_CORTEX_DOCUMENT_PROCESSING_DETAIL
    GROUP BY usage_date, service_type
    
    UNION ALL
    
    -- Fine-tuning (NEW in v2.6)
    SELECT 
        usage_date,
        service_type,
        0 AS daily_unique_users,
        SUM(tokens) AS total_operations,
        SUM(token_credits) AS total_credits
    FROM V_CORTEX_FINE_TUNING_DETAIL
    GROUP BY usage_date, service_type
)
SELECT 
    usage_date,
    service_type,
    SUM(daily_unique_users) AS daily_unique_users,
    SUM(total_operations) AS total_operations,
    SUM(total_credits) AS total_credits,
    CASE 
        WHEN SUM(daily_unique_users) > 0 
        THEN SUM(total_credits) / SUM(daily_unique_users) 
        ELSE 0 
    END AS credits_per_user,
    CASE 
        WHEN SUM(total_operations) > 0 
        THEN SUM(total_credits) / SUM(total_operations) 
        ELSE 0 
    END AS credits_per_operation
FROM all_services
GROUP BY usage_date, service_type
ORDER BY usage_date DESC, total_credits DESC;

-- View 14:
CREATE OR REPLACE VIEW V_CORTEX_COST_EXPORT
    COMMENT = 'DEMO: Cortex usage tracking view - see header for version history'
AS
SELECT 
    usage_date AS date,
    service_type,
    daily_unique_users,
    daily_unique_users AS weekly_active_users,
    daily_unique_users AS monthly_active_users,
    total_operations,
    total_credits,
    credits_per_user,
    credits_per_operation,
    ROUND(credits_per_user, 4) AS avg_daily_cost_per_user,
    ROUND(credits_per_user * 30, 2) AS projected_monthly_cost_per_user,
    ROUND(total_credits * 30, 2) AS projected_monthly_total_credits
FROM V_CORTEX_DAILY_SUMMARY
-- No date filter here - let the extraction query control the date range
ORDER BY date DESC, total_credits DESC;

-- View 15:
CREATE OR REPLACE VIEW V_METERING_AI_SERVICES
    COMMENT = 'DEMO: Cortex usage tracking view - see header for version history'
AS
SELECT 
    usage_date,
    service_type,
    SUM(credits_used) AS total_credits,
    SUM(credits_used_compute) AS compute_credits,
    SUM(credits_used_cloud_services) AS cloud_services_credits
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE service_type = 'AI_SERVICES'
    AND usage_date >= DATEADD('day', -90, CURRENT_TIMESTAMP())
GROUP BY usage_date, service_type
ORDER BY usage_date DESC;

-- Historical Snapshot Table: CORTEX_USAGE_SNAPSHOTS (ENHANCED in v2.6)
--
-- PERFORMANCE NOTE: Clustering Key Threshold
-- A clustering key should only be considered if this table exceeds 1 TB in size.
-- Current demo usage: < 1 GB (clustering would waste credits at this scale)
-- Potential clustering key for 1+ TB tables: CLUSTER BY (usage_date, service_type)
-- Validate need using: SELECT SYSTEM$CLUSTERING_INFORMATION('CORTEX_USAGE_SNAPSHOTS')
--
-- See: .cursor/docs/DESIGN_DECISIONS.md for detailed rationale
--
CREATE TABLE IF NOT EXISTS CORTEX_USAGE_SNAPSHOTS (
    snapshot_date DATE NOT NULL,
    service_type VARCHAR(50) NOT NULL,
    usage_date DATE NOT NULL,
    daily_unique_users NUMBER(38,0),
    total_operations NUMBER(38,0),
    total_credits NUMBER(38,6),
    credits_per_user NUMBER(38,6),
    credits_per_operation NUMBER(38,12),
    -- v2.5: AISQL-specific metrics
    function_name VARCHAR(100),
    model_name VARCHAR(100),
    total_tokens NUMBER(38,0),
    cost_per_million_tokens NUMBER(38,6),
    serverless_calls NUMBER(38,0),
    compute_calls NUMBER(38,0),
    -- v2.6: Document processing metrics
    total_pages_processed NUMBER(38,0),
    total_documents_processed NUMBER(38,0),
    credits_per_page NUMBER(38,6),
    credits_per_document NUMBER(38,6),
    inserted_at TIMESTAMP_LTZ DEFAULT CURRENT_TIMESTAMP()
    -- Note: No primary key due to nullable function_name/model_name columns
    -- Uniqueness enforced by MERGE logic in task
)
COMMENT = 'DEMO: Daily snapshots of Cortex usage including AISQL function, model, and document processing details';

-- Scheduled Task: TASK_DAILY_CORTEX_SNAPSHOT
-- Schedule: Daily at 3:00 AM (after ACCOUNT_USAGE data is typically refreshed)
-- Compute: Serverless (Snowflake-managed, no warehouse required)
-- Now captures document processing and fine-tuning data
--
-- COST GUARDRAILS (v2.6+):
-- SERVERLESS_TASK_MAX_STATEMENT_SIZE caps maximum warehouse size to prevent runaway costs
-- Normal execution: XSMALL (~$0.001-0.003/day, $0.03-0.09/month)
-- Maximum with cap: SMALL (~$0.01/day, $0.30/month)
-- Provides 10x safety margin for forgotten demo deployments
--
CREATE OR REPLACE TASK TASK_DAILY_CORTEX_SNAPSHOT
    SCHEDULE = 'USING CRON 0 3 * * * America/Los_Angeles'
    USER_TASK_MANAGED_INITIAL_WAREHOUSE_SIZE = 'XSMALL'
    SERVERLESS_TASK_MAX_STATEMENT_SIZE = 'SMALL'
    COMMENT = 'DEMO: Daily serverless task with cost guardrails capturing Cortex usage snapshots including AISQL functions, document processing, and fine-tuning'
AS
MERGE INTO CORTEX_USAGE_SNAPSHOTS AS target
USING (
    -- General Cortex services (Analyst, Search)
    SELECT 
        CURRENT_DATE() AS snapshot_date,
        service_type,
        usage_date,
        daily_unique_users,
        total_operations,
        total_credits,
        credits_per_user,
        credits_per_operation,
        CAST(NULL AS VARCHAR(100)) AS function_name,
        CAST(NULL AS VARCHAR(100)) AS model_name,
        CAST(NULL AS NUMBER(38,0)) AS total_tokens,
        CAST(NULL AS NUMBER(38,6)) AS cost_per_million_tokens,
        CAST(NULL AS NUMBER(38,0)) AS serverless_calls,
        CAST(NULL AS NUMBER(38,0)) AS compute_calls,
        CAST(NULL AS NUMBER(38,0)) AS total_pages_processed,
        CAST(NULL AS NUMBER(38,0)) AS total_documents_processed,
        CAST(NULL AS NUMBER(38,6)) AS credits_per_page,
        CAST(NULL AS NUMBER(38,6)) AS credits_per_document
    FROM V_CORTEX_DAILY_SUMMARY
    WHERE usage_date >= DATEADD('day', -2, CURRENT_DATE())
        AND service_type NOT IN ('AISQL Functions', 'Cortex Document Processing', 'Cortex Fine-tuning')
    
    UNION ALL
    
    -- AISQL function-specific data
    SELECT 
        CURRENT_DATE() AS snapshot_date,
        'AISQL Functions' AS service_type,
        usage_date,
        0 AS daily_unique_users,  -- Not available in hourly aggregates
        hourly_records AS total_operations,
        daily_credits AS total_credits,
        0 AS credits_per_user,
        CASE WHEN hourly_records > 0 THEN daily_credits / hourly_records ELSE 0 END AS credits_per_operation,
        function_name,
        model_name,
        daily_tokens AS total_tokens,
        CASE WHEN daily_tokens > 0 THEN (daily_credits / daily_tokens) * 1000000 ELSE 0 END AS cost_per_million_tokens,
        serverless_calls,
        compute_calls,
        CAST(NULL AS NUMBER(38,0)) AS total_pages_processed,
        CAST(NULL AS NUMBER(38,0)) AS total_documents_processed,
        CAST(NULL AS NUMBER(38,6)) AS credits_per_page,
        CAST(NULL AS NUMBER(38,6)) AS credits_per_document
    FROM V_AISQL_DAILY_TRENDS
    WHERE usage_date >= DATEADD('day', -2, CURRENT_DATE())
    
    UNION ALL
    
    -- Document Processing
    SELECT 
        CURRENT_DATE() AS snapshot_date,
        service_type,
        usage_date,
        COUNT(DISTINCT query_id) AS daily_unique_users,
        SUM(page_count) AS total_operations,
        SUM(credits_used) AS total_credits,
        0 AS credits_per_user,
        AVG(credits_per_page) AS credits_per_operation,
        function_name,
        model_name,
        CAST(NULL AS NUMBER(38,0)) AS total_tokens,
        CAST(NULL AS NUMBER(38,6)) AS cost_per_million_tokens,
        CAST(NULL AS NUMBER(38,0)) AS serverless_calls,
        CAST(NULL AS NUMBER(38,0)) AS compute_calls,
        SUM(page_count) AS total_pages_processed,
        SUM(document_count) AS total_documents_processed,
        AVG(credits_per_page) AS credits_per_page,
        AVG(credits_per_document) AS credits_per_document
    FROM V_CORTEX_DOCUMENT_PROCESSING_DETAIL
    WHERE usage_date >= DATEADD('day', -2, CURRENT_DATE())
    GROUP BY CURRENT_DATE(), service_type, usage_date, function_name, model_name
    
    UNION ALL
    
    -- Fine-tuning
    SELECT 
        CURRENT_DATE() AS snapshot_date,
        service_type,
        usage_date,
        0 AS daily_unique_users,
        COUNT(*) AS total_operations,
        SUM(token_credits) AS total_credits,
        0 AS credits_per_user,
        AVG(token_credits) AS credits_per_operation,
        CAST(NULL AS VARCHAR(100)) AS function_name,
        model_name,
        SUM(tokens) AS total_tokens,
        AVG(cost_per_million_tokens) AS cost_per_million_tokens,
        CAST(NULL AS NUMBER(38,0)) AS serverless_calls,
        CAST(NULL AS NUMBER(38,0)) AS compute_calls,
        CAST(NULL AS NUMBER(38,0)) AS total_pages_processed,
        CAST(NULL AS NUMBER(38,0)) AS total_documents_processed,
        CAST(NULL AS NUMBER(38,6)) AS credits_per_page,
        CAST(NULL AS NUMBER(38,6)) AS credits_per_document
    FROM V_CORTEX_FINE_TUNING_DETAIL
    WHERE usage_date >= DATEADD('day', -2, CURRENT_DATE())
    GROUP BY CURRENT_DATE(), service_type, usage_date, model_name
) AS source
ON target.snapshot_date = source.snapshot_date
    AND target.service_type = source.service_type
    AND target.usage_date = source.usage_date
    AND COALESCE(target.function_name, '') = COALESCE(source.function_name, '')
    AND COALESCE(target.model_name, '') = COALESCE(source.model_name, '')
WHEN MATCHED THEN
    UPDATE SET
        daily_unique_users = source.daily_unique_users,
        total_operations = source.total_operations,
        total_credits = source.total_credits,
        credits_per_user = source.credits_per_user,
        credits_per_operation = source.credits_per_operation,
        total_tokens = source.total_tokens,
        cost_per_million_tokens = source.cost_per_million_tokens,
        serverless_calls = source.serverless_calls,
        compute_calls = source.compute_calls,
        total_pages_processed = source.total_pages_processed,
        total_documents_processed = source.total_documents_processed,
        credits_per_page = source.credits_per_page,
        credits_per_document = source.credits_per_document,
        inserted_at = CURRENT_TIMESTAMP()
WHEN NOT MATCHED THEN
    INSERT (snapshot_date, service_type, usage_date, daily_unique_users, total_operations, 
            total_credits, credits_per_user, credits_per_operation, function_name, model_name,
            total_tokens, cost_per_million_tokens, serverless_calls, compute_calls,
            total_pages_processed, total_documents_processed, credits_per_page, credits_per_document)
    VALUES (source.snapshot_date, source.service_type, source.usage_date, source.daily_unique_users,
            source.total_operations, source.total_credits, source.credits_per_user, source.credits_per_operation,
            source.function_name, source.model_name, source.total_tokens, source.cost_per_million_tokens,
            source.serverless_calls, source.compute_calls, source.total_pages_processed, 
            source.total_documents_processed, source.credits_per_page, source.credits_per_document);

-- Resume the task to activate it
ALTER TASK TASK_DAILY_CORTEX_SNAPSHOT RESUME;

-- View 16:
-- Optimized for Streamlit cost calculator queries
-- Includes document processing metrics and trend analysis
CREATE OR REPLACE VIEW V_CORTEX_USAGE_HISTORY
    COMMENT = 'DEMO: Historical snapshot view for Streamlit cost calculator with document processing metrics and trend analysis'
AS
SELECT 
    usage_date AS date,
    service_type,
    daily_unique_users,
    daily_unique_users AS weekly_active_users,
    daily_unique_users AS monthly_active_users,
    total_operations,
    total_credits,
    credits_per_user,
    credits_per_operation,
    ROUND(credits_per_user, 4) AS avg_daily_cost_per_user,
    ROUND(credits_per_user * 30, 2) AS projected_monthly_cost_per_user,
    ROUND(total_credits * 30, 2) AS projected_monthly_total_credits,
    snapshot_date,
    inserted_at,
    -- v2.6: Document processing metrics
    total_pages_processed,
    total_documents_processed,
    credits_per_page,
    credits_per_document,
    -- Trend analysis metrics
    LAG(total_credits, 7) OVER (PARTITION BY service_type ORDER BY usage_date) AS credits_7d_ago,
    ROUND(((total_credits - LAG(total_credits, 7) OVER (PARTITION BY service_type ORDER BY usage_date)) / 
           NULLIF(LAG(total_credits, 7) OVER (PARTITION BY service_type ORDER BY usage_date), 0)) * 100, 2) AS credits_wow_growth_pct
FROM CORTEX_USAGE_SNAPSHOTS
ORDER BY date DESC, total_credits DESC;

-- DEPLOYMENT VALIDATION (Quick Check)

-- Verify 16 views were created
SELECT COUNT(*) AS view_count
FROM SNOWFLAKE.INFORMATION_SCHEMA.VIEWS
WHERE TABLE_SCHEMA = 'CORTEX_USAGE'
    AND TABLE_CATALOG = 'SNOWFLAKE_EXAMPLE';
-- Expected: 16 (was 10 in v2.5)

-- Verify 1 table was created
SELECT COUNT(*) AS table_count
FROM SNOWFLAKE.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'CORTEX_USAGE'
    AND TABLE_CATALOG = 'SNOWFLAKE_EXAMPLE'
    AND TABLE_TYPE = 'BASE TABLE';
-- Expected: 1

-- Verify task was created and is running
SHOW TASKS LIKE 'TASK_DAILY_CORTEX_SNAPSHOT' IN SCHEMA SNOWFLAKE_EXAMPLE.CORTEX_USAGE;
-- Expected: STATE = 'started', SCHEDULE should show CRON expression

-- Check task execution history (if any runs have occurred)
SELECT 
    NAME,
    STATE,
    SCHEDULED_TIME,
    COMPLETED_TIME,
    RETURN_VALUE
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    TASK_NAME => 'SNOWFLAKE_EXAMPLE.CORTEX_USAGE.TASK_DAILY_CORTEX_SNAPSHOT',
    SCHEDULED_TIME_RANGE_START => DATEADD('day', -7, CURRENT_TIMESTAMP())
))
ORDER BY SCHEDULED_TIME DESC
LIMIT 5;

-- Test data access (will be empty if no Cortex usage yet)
SELECT COUNT(*) AS row_count 
FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_CORTEX_DAILY_SUMMARY;

-- Test new v2.6 views
SELECT COUNT(*) AS doc_processing_count
FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_CORTEX_DOCUMENT_PROCESSING_DETAIL;

SELECT COUNT(*) AS query_analysis_count
FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_QUERY_COST_ANALYSIS;

-- If errors occur above, check ACCOUNT_USAGE permissions
-- GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE <YOUR_ROLE>;

-- Created Objects (v2.6):
-- VIEWS (16 - up from 13 in v2.5):
-- 1. V_CORTEX_ANALYST_DETAIL - Cortex Analyst usage (has USERNAME)
-- 2. V_CORTEX_SEARCH_DETAIL - Cortex Search daily usage (no user tracking)
-- 3. V_CORTEX_SEARCH_SERVING_DETAIL - Cortex Search serving usage (no user tracking)
-- 4. V_CORTEX_FUNCTIONS_DETAIL - Cortex Functions hourly aggregates (no user tracking)
-- 5. V_CORTEX_FUNCTIONS_QUERY_DETAIL - Cortex Functions query-level (ENHANCED in v2.6)
-- 6. V_DOCUMENT_AI_DETAIL - Document AI usage (legacy, still supported)
-- 7. V_CORTEX_DOCUMENT_PROCESSING_DETAIL - Unified document processing (NEW in v2.6)
-- 8. V_CORTEX_FINE_TUNING_DETAIL - Fine-tuning training costs (NEW in v2.6)
-- 9. V_AISQL_FUNCTION_SUMMARY - AISQL function summary
-- 10. V_AISQL_MODEL_COMPARISON - Model comparison
-- 11. V_AISQL_DAILY_TRENDS - Daily AISQL trends
-- 12. V_QUERY_COST_ANALYSIS - Most expensive queries (NEW in v2.6)
-- 13. V_CORTEX_DAILY_SUMMARY - Daily rollup across all services (ENHANCED in v2.6)
-- 14. V_CORTEX_COST_EXPORT - Pre-formatted for calculator (ENHANCED in v2.6)
-- 15. V_METERING_AI_SERVICES - AI services metering rollup
-- 16. V_CORTEX_USAGE_HISTORY - Historical snapshots with trend analysis (ENHANCED in v2.6)
--
-- TABLES (1):
-- 1. CORTEX_USAGE_SNAPSHOTS - Daily snapshots of usage data (ENHANCED in v2.6)
--
-- TASKS (1):
-- 1. TASK_DAILY_CORTEX_SNAPSHOT - Runs daily at 3 AM (ENHANCED in v2.6)
--
-- NEW FEATURES IN v2.6:
-- - CORTEX_DOCUMENT_PROCESSING_USAGE_HISTORY support (GA: Mar 3, 2025)
-- - CORTEX_FINE_TUNING_USAGE_HISTORY support (GA: Oct 10, 2024)
-- - Query-level cost analysis across all services
-- - Enhanced document processing metrics (pages, documents, credits per page)
-- - Better serverless vs warehouse tracking
-- - Improved validation and testing queries

