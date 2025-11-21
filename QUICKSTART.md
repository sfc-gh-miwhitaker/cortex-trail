# Cortex Cost Calculator - Quickstart

Get from zero to working cost calculator in 15 minutes.

---

## 👋 First Time Here?

**Follow these 3 steps in order:**

1. **Read:** [`docs/01-GETTING_STARTED.md`](docs/01-GETTING_STARTED.md) - Complete getting started guide (5 min read)
2. **Deploy Monitoring:** Run [`sql/deploy_cortex_monitoring.sql`](sql/deploy_cortex_monitoring.sql) - Deploy monitoring views (5 min)
3. **Deploy Calculator:** Follow [Streamlit deployment instructions](#deploy-streamlit-calculator) below (5 min)

**Total setup time: ~15 minutes**

---

## What You'll Build

By the end of this quickstart, you'll have:

- ✅ 16 monitoring views tracking all Cortex services
- ✅ Automated daily snapshots (serverless task)
- ✅ Interactive Streamlit cost calculator
- ✅ Historical trend analysis
- ✅ Multi-scenario cost projections
- ✅ Export-ready credit estimates

---

## Prerequisites

Before starting, ensure you have:

- **Snowflake Account** with Cortex usage (ideally 7-14 days of history)
- **Role Access:** ACCOUNTADMIN OR role with IMPORTED PRIVILEGES on SNOWFLAKE database
- **Active Warehouse** for running queries
- **5-10 minutes** of uninterrupted time

---

## Step-by-Step Setup

### Step 1: Deploy Monitoring (5 minutes)

1. **Open Snowsight** and log into your Snowflake account
2. **Select a role** with ACCOUNTADMIN or IMPORTED PRIVILEGES on SNOWFLAKE database
3. **Select a warehouse** (any size, SMALL is fine)
4. **Run deployment script:**

```sql
-- Copy and paste the entire contents of:
-- sql/deploy_cortex_monitoring.sql
```

5. **Verify deployment:**

The script automatically validates. You should see:

```
✓ Database created: SNOWFLAKE_EXAMPLE
✓ Schema created: CORTEX_USAGE
✓ Views created: 16 views
✓ Snapshot table created: CORTEX_USAGE_SNAPSHOTS
✓ Serverless task created: TASK_DAILY_CORTEX_SNAPSHOT
```

6. **Test a view:**

```sql
SELECT * 
FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_CORTEX_DAILY_SUMMARY
LIMIT 10;
```

**Expected result:** Rows showing your Cortex usage (empty if no usage yet).

---

### Step 2: Deploy Streamlit Calculator (5 minutes)

#### Method 1: Snowsight UI (Recommended)

1. **Navigate:** Snowsight → **Projects** → **Streamlit** → **+ Streamlit App**
2. **Configure:**
   - **App name:** `CORTEX_COST_CALCULATOR`
   - **Location:** `SNOWFLAKE_EXAMPLE.CORTEX_USAGE` (or your preferred database/schema)
   - **Warehouse:** Select warehouse (SMALL is fine)
3. **Copy code:**
   - Open `streamlit/cortex_cost_calculator/streamlit_app.py`
   - Copy entire file contents
   - Paste into Snowsight code editor
4. **Add packages:**
   - Open `streamlit/cortex_cost_calculator/environment.yml`
   - Copy package dependencies
   - Paste into Snowsight packages section
5. **Click "Create"**

**Time:** 2-3 minutes

#### Method 2: SnowSQL CLI (Advanced)

```bash
# 1. Create stage
snow sql -q "CREATE STAGE IF NOT EXISTS SNOWFLAKE_EXAMPLE.CORTEX_USAGE.STREAMLIT_STAGE;"

# 2. Upload files (run in your local terminal)
snow stage put file://streamlit/cortex_cost_calculator/streamlit_app.py @SNOWFLAKE_EXAMPLE.CORTEX_USAGE.STREAMLIT_STAGE
snow stage put file://streamlit/cortex_cost_calculator/environment.yml @SNOWFLAKE_EXAMPLE.CORTEX_USAGE.STREAMLIT_STAGE

# 3. Create Streamlit app
snow sql -q "CREATE STREAMLIT SNOWFLAKE_EXAMPLE.CORTEX_USAGE.CORTEX_COST_CALCULATOR \
  ROOT_LOCATION = '@SNOWFLAKE_EXAMPLE.CORTEX_USAGE.STREAMLIT_STAGE' \
  MAIN_FILE = '/streamlit_app.py' \
  QUERY_WAREHOUSE = 'YOUR_WAREHOUSE_NAME';"
```

**Time:** 3-5 minutes

---

### Step 3: Access & Use Calculator (5 minutes)

1. **Open Streamlit app:**
   - Snowsight → **Projects** → **Streamlit** → **Apps** → **CORTEX_COST_CALCULATOR**

2. **Select data source:**
   - **Option A:** "Query Views (Same Account)" - For ongoing monitoring
   - **Option B:** "Upload Customer CSV" - For SE workflow (analyze customer data)

3. **Explore features:**
   - **Historical Analysis:** View trends, service breakdown, user activity
   - **Cost Projections:** Generate 3, 6, 12, or 24-month forecasts
   - **Cost per User Calculator:** Estimate per-user costs
   - **Budget Capacity Planning:** Determine user capacity for given budget
   - **Summary Report:** Export credit estimates for proposals

---

## Two Common Workflows

### Workflow 1: Customer Self-Service (Single Account)

**Use Case:** Customer wants ongoing cost monitoring in their own account

```
1. Customer deploys monitoring (Step 1 above)
2. Customer deploys Streamlit app (Step 2 above)
3. Customer accesses app anytime for real-time analysis
4. Automated daily snapshots capture historical trends
```

**Benefits:**
- Real-time visibility into Cortex spend
- Historical trend analysis
- No data export required
- Self-service forecasting

---

### Workflow 2: SE Analyzing Customer Data (Two Accounts)

**Use Case:** Solutions Engineer analyzing customer Cortex usage

**In Customer Account:**
```
1. SE deploys monitoring (Step 1 above)
2. Wait 7-14 days for usage data to accumulate
3. Run export query:
   @sql/export_metrics.sql
4. Download CSV
```

**In SE Account:**
```
5. SE accesses their own Streamlit calculator
6. Select "Upload Customer CSV" as data source
7. Upload customer's CSV file
8. Generate cost analysis and projections
9. Export credit estimate for sales team
```

**Benefits:**
- Analyze multiple customers without storing data
- Generate proposals quickly
- Reusable calculator across customers
- No customer data stored permanently

---

## Verification Checklist

After setup, verify everything works:

- [ ] **Database created:** `SHOW DATABASES LIKE 'SNOWFLAKE_EXAMPLE'` returns 1 row
- [ ] **Schema created:** `SHOW SCHEMAS IN DATABASE SNOWFLAKE_EXAMPLE` includes CORTEX_USAGE
- [ ] **Views created:** `SHOW VIEWS IN SCHEMA SNOWFLAKE_EXAMPLE.CORTEX_USAGE` returns 16 rows
- [ ] **Table created:** `SHOW TABLES IN SCHEMA SNOWFLAKE_EXAMPLE.CORTEX_USAGE` includes CORTEX_USAGE_SNAPSHOTS
- [ ] **Task created:** `SHOW TASKS IN SCHEMA SNOWFLAKE_EXAMPLE.CORTEX_USAGE` includes TASK_DAILY_CORTEX_SNAPSHOT
- [ ] **Task running:** Task status is "started" (check with `SHOW TASKS`)
- [ ] **Views return data:** `SELECT * FROM V_CORTEX_DAILY_SUMMARY LIMIT 1` returns rows
- [ ] **Streamlit accessible:** App loads without errors
- [ ] **Charts render:** Historical analysis displays visualizations

---

## Next Steps

Now that you're set up, explore these capabilities:

1. **Set up alerts** - Configure resource monitors for budget tracking
2. **Grant access** - Share views/app with other users via GRANT statements
3. **Customize** - Modify views to match your organization's needs
4. **Automate** - Schedule exports or integrate with your BI tools
5. **Optimize** - Use query-level cost analysis to find expensive queries

**Full documentation:** See [`docs/01-GETTING_STARTED.md`](docs/01-GETTING_STARTED.md) and [`docs/02-DEPLOYMENT_WALKTHROUGH.md`](docs/02-DEPLOYMENT_WALKTHROUGH.md)

---

## Need Help?

- **Documentation:** [`docs/`](docs/) directory
- **Troubleshooting:** [`docs/03-TROUBLESHOOTING.md`](docs/03-TROUBLESHOOTING.md)
- **Architecture:** [`diagrams/`](diagrams/) directory
- **Snowflake Docs:** [https://docs.snowflake.com](https://docs.snowflake.com)

---

## Cleanup (Optional)

To remove all monitoring objects:

```sql
-- Run cleanup script
@sql/cleanup_cortex_monitoring.sql
```

**What's removed:**
- CORTEX_USAGE schema (all views, tables, tasks)

**What's preserved (per cleanup rule):**
- SNOWFLAKE_EXAMPLE database
- Source data in ACCOUNT_USAGE
- Customer data and applications

**Time:** < 1 minute

---

**Ready? Start with Step 1 above. You'll be analyzing Cortex costs in 15 minutes.**

