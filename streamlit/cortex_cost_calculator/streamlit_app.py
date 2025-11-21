import streamlit as st
import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from snowflake.snowpark.context import get_active_session
import plotly.graph_objects as go
import plotly.express as px

# Get Snowflake session
session = get_active_session()

st.set_page_config(
    page_title="Cortex Cost Calculator",
    page_icon="📊",
    layout="wide"
)

# ============================================================================
# Utility Functions
# ============================================================================

def fetch_data_from_views(lookback_days=30):
    """Fetch data from historical snapshot table (with fallback to live view)"""
    # Try snapshot table first (faster)
    snapshot_query = f"""
    SELECT 
        date,
        service_type,
        daily_unique_users,
        total_operations,
        total_credits,
        credits_per_user,
        credits_per_operation,
        avg_daily_cost_per_user,
        projected_monthly_cost_per_user,
        projected_monthly_total_credits,
        credits_7d_ago,
        credits_wow_growth_pct
    FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_CORTEX_USAGE_HISTORY
    WHERE date >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
    ORDER BY date DESC
    """
    
    try:
        df = session.sql(snapshot_query).to_pandas()
        if not df.empty:
            return df
    except:
        pass
    
    # Fallback to live view if snapshot is empty or doesn't exist
    live_query = f"""
    SELECT 
        date,
        service_type,
        daily_unique_users,
        total_operations,
        total_credits,
        credits_per_user,
        credits_per_operation,
        ROUND(credits_per_user, 4) AS avg_daily_cost_per_user,
        ROUND(credits_per_user * 30, 2) AS projected_monthly_cost_per_user,
        ROUND(total_credits * 30, 2) AS projected_monthly_total_credits,
        NULL AS credits_7d_ago,
        NULL AS credits_wow_growth_pct
    FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_CORTEX_COST_EXPORT
    WHERE date >= DATEADD('day', -{lookback_days}, CURRENT_DATE())
    ORDER BY date DESC
    """
    return session.sql(live_query).to_pandas()

def calculate_30day_totals(df):
    """Calculate rolling 30-day totals for cost estimation"""
    if df.empty:
        return pd.DataFrame()
    
    # Sort by date ascending for rolling calculations
    df_sorted = df.sort_values('DATE')
    
    # Calculate 30-day rolling totals by service type
    df_sorted['credits_30d_total'] = df_sorted.groupby('SERVICE_TYPE')['TOTAL_CREDITS'].transform(
        lambda x: x.rolling(window=30, min_periods=1).sum()
    )
    
    df_sorted['operations_30d_total'] = df_sorted.groupby('SERVICE_TYPE')['TOTAL_OPERATIONS'].transform(
        lambda x: x.rolling(window=30, min_periods=1).sum()
    )
    
    df_sorted['users_30d_avg'] = df_sorted.groupby('SERVICE_TYPE')['DAILY_UNIQUE_USERS'].transform(
        lambda x: x.rolling(window=30, min_periods=1).mean()
    )
    
    # Calculate 30-day average cost per user
    df_sorted['cost_per_user_30d'] = df_sorted['credits_30d_total'] / df_sorted['users_30d_avg']
    df_sorted['cost_per_user_30d'] = df_sorted['cost_per_user_30d'].fillna(0)
    
    return df_sorted.sort_values('DATE', ascending=False)

def calculate_growth_projection(df, growth_rate, projection_months=12, credit_cost=3.00):
    """Calculate cost projections based on growth rate"""
    baseline = df.groupby('SERVICE_TYPE').agg({
        'TOTAL_CREDITS': 'sum',
        'DAILY_UNIQUE_USERS': 'mean'
    }).reset_index()
    
    projections = []
    for month in range(1, projection_months + 1):
        for _, service in baseline.iterrows():
            growth_factor = (1 + growth_rate) ** month
            projected_credits = service['TOTAL_CREDITS'] * growth_factor
            projected_users = service['DAILY_UNIQUE_USERS'] * growth_factor
            projected_cost = projected_credits * credit_cost
            
            projections.append({
                'month': month,
                'service_type': service['SERVICE_TYPE'],
                'projected_credits': projected_credits,
                'projected_users': projected_users,
                'projected_cost_usd': projected_cost,
                'cost_per_user_usd': projected_cost / projected_users if projected_users > 0 else 0,
                'growth_rate': growth_rate
            })
    
    return pd.DataFrame(projections)

def format_currency(value):
    """Format value as currency"""
    return f"${value:,.2f}"

def format_number(value):
    """Format value as number with commas"""
    return f"{value:,.0f}"

# ============================================================================
# Main Application
# ============================================================================

def load_data_from_csv(uploaded_file):
    """Load and validate data from uploaded CSV file"""
    try:
        df = pd.read_csv(uploaded_file)
        
        # Expected columns from extract_metrics_for_calculator.sql
        required_cols = ['DATE', 'SERVICE_TYPE', 'TOTAL_CREDITS']
        missing_cols = [col for col in required_cols if col not in df.columns]
        
        if missing_cols:
            st.error(f"CSV missing required columns: {', '.join(missing_cols)}")
            return None
        
        # Standardize column names (handle case variations)
        df.columns = df.columns.str.upper()
        
        # Convert date column
        df['DATE'] = pd.to_datetime(df['DATE'])
        
        return df
    except Exception as e:
        st.error(f"Error loading CSV: {str(e)}")
        return None

def create_credit_summary(df, credit_cost=3.00):
    """Create credit estimate summary for sales team"""
    summary = df.groupby('SERVICE_TYPE').agg({
        'TOTAL_CREDITS': 'sum',
        'DAILY_UNIQUE_USERS': 'mean',
        'DATE': ['min', 'max']
    }).reset_index()
    
    summary.columns = ['Service', 'Total Credits', 'Avg Daily Users', 'Start Date', 'End Date']
    summary['Days of Data'] = (summary['End Date'] - summary['Start Date']).dt.days + 1
    summary['Avg Credits/Day'] = summary['Total Credits'] / summary['Days of Data']
    summary['Est. Credits/Month'] = summary['Avg Credits/Day'] * 30
    summary['Est. Cost/Month'] = summary['Est. Credits/Month'] * credit_cost
    
    return summary[['Service', 'Total Credits', 'Avg Credits/Day', 'Est. Credits/Month', 'Est. Cost/Month']]

def main():
    st.title("📊 Cortex Cost Calculator")
    st.markdown("""
    Estimate and project costs for Snowflake Cortex services based on actual usage data.
    **For Solution Engineers:** Upload customer CSV files or query your own account views.
    """)
    
    # Sidebar configuration
    with st.sidebar:
        st.header("⚙️ Configuration")
        
        # Data source selection
        data_source = st.radio(
            "Data Source",
            options=["Query Views (Same Account)", "Upload Customer CSV"],
            help="Query views for your own data, or upload CSV from customer account"
        )
        
        if data_source == "Query Views (Same Account)":
            lookback_days = st.slider(
                "Historical Data Period (days)",
                min_value=7,
                max_value=90,
                value=30,
                help="Number of days of historical data to analyze"
            )
        else:
            st.markdown("### 📁 Upload Customer Data")
            uploaded_file = st.file_uploader(
                "Upload CSV from extract_metrics_for_calculator.sql",
                type=['csv'],
                help="CSV file exported from customer's Snowflake account"
            )
        
        credit_cost = st.number_input(
            "Cost per Credit (USD)",
            value=3.00,
            min_value=0.01,
            step=0.10,
            help="Adjust based on your Snowflake pricing"
        )
        
        variance_pct = st.slider(
            "Projection Variance (%)",
            min_value=5,
            max_value=25,
            value=10,
            help="Variance range for cost estimates"
        ) / 100
        
        if st.button("🔄 Refresh Data"):
            st.cache_data.clear()
    
    # Load data based on source
    df = None
    if data_source == "Query Views (Same Account)":
        try:
            with st.spinner("Loading data from views..."):
                df = fetch_data_from_views(lookback_days)
        except Exception as e:
            st.error(f"Error querying views: {str(e)}")
            st.info("Make sure monitoring views are deployed in SNOWFLAKE_EXAMPLE.CORTEX_USAGE")
            return
    else:
        if 'uploaded_file' in locals() and uploaded_file is not None:
            with st.spinner("Loading CSV file..."):
                df = load_data_from_csv(uploaded_file)
        else:
            st.info("👆 Please upload a CSV file from the customer's account")
            st.markdown("""
            **To get customer data:**
            1. Run `@sql/extract_metrics_for_calculator.sql` in customer's Snowflake
            2. Download results as CSV
            3. Upload here
            """)
            return
    
    if df is None or df.empty:
        st.warning("No data available. Please check your data source.")
        return
    
    # Normalize column names
    df.columns = df.columns.str.upper()
    if 'DATE' not in df.columns:
        df['DATE'] = pd.to_datetime(df['USAGE_DATE']) if 'USAGE_DATE' in df.columns else pd.to_datetime(df.iloc[:, 0])
    
    # Create tabs
    tab1, tab2, tab3, tab4 = st.tabs([
        "📈 Historical Analysis",
        "🤖 AISQL Functions",
        "🔮 Cost Projections",
        "📋 Summary Report"
    ])
    
    with tab1:
        show_historical_analysis(df, credit_cost)
    
    with tab2:
        show_aisql_functions(credit_cost)
    
    with tab3:
        show_cost_projections(df, credit_cost, variance_pct)
    
    with tab4:
        show_summary_report(df, credit_cost, variance_pct)

def show_historical_analysis(df, credit_cost):
    """Display historical analysis tab"""
    st.header("Historical Usage Analysis")
    
    # Summary statistics
    total_credits = df['TOTAL_CREDITS'].sum()
    total_cost = total_credits * credit_cost
    avg_daily_credits = df.groupby('DATE')['TOTAL_CREDITS'].sum().mean()
    avg_daily_users = df['DAILY_UNIQUE_USERS'].mean()
    
    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        st.metric("Total Credits", format_number(total_credits))
    with col2:
        st.metric("Total Cost", format_currency(total_cost))
    with col3:
        st.metric("Avg Daily Credits", format_number(avg_daily_credits))
    with col4:
        st.metric("Avg Daily Users", format_number(avg_daily_users))
    
    st.divider()
    
    # 30-Day Rolling Totals
    st.subheader("📊 30-Day Rolling Totals (Most Recent)")
    st.caption("Rolling 30-day windows for cost estimation")
    
    # Calculate 30-day totals
    df_with_30d = calculate_30day_totals(df)
    
    if not df_with_30d.empty:
        # Get most recent 30-day totals by service
        latest_30d = df_with_30d.groupby('SERVICE_TYPE').last().reset_index()
        latest_30d['COST_30D_USD'] = latest_30d['credits_30d_total'] * credit_cost
        latest_30d['COST_PER_USER_30D_USD'] = latest_30d['cost_per_user_30d'] * credit_cost
        
        # Display metrics
        col1, col2, col3, col4 = st.columns(4)
        
        total_30d_credits = latest_30d['credits_30d_total'].sum()
        total_30d_cost = total_30d_credits * credit_cost
        avg_30d_users = latest_30d['users_30d_avg'].mean()
        avg_cost_per_user_30d = total_30d_cost / avg_30d_users if avg_30d_users > 0 else 0
        
        with col1:
            st.metric("30-Day Total Credits", format_number(total_30d_credits))
        with col2:
            st.metric("30-Day Total Cost", format_currency(total_30d_cost))
        with col3:
            st.metric("30-Day Avg Users", format_number(avg_30d_users))
        with col4:
            st.metric("Avg Cost/User (30d)", format_currency(avg_cost_per_user_30d))
        
        # Service-level 30-day breakdown
        st.caption("30-Day Totals by Service")
        service_30d_display = latest_30d[['SERVICE_TYPE', 'credits_30d_total', 'COST_30D_USD', 
                                           'operations_30d_total', 'users_30d_avg', 'COST_PER_USER_30D_USD']].copy()
        service_30d_display.columns = ['Service', '30d Credits', '30d Cost', '30d Operations', '30d Avg Users', 'Cost/User (30d)']
        
        st.dataframe(
            service_30d_display.style.format({
                '30d Credits': '{:,.0f}',
                '30d Cost': '${:,.2f}',
                '30d Operations': '{:,.0f}',
                '30d Avg Users': '{:.1f}',
                'Cost/User (30d)': '${:,.2f}'
            }),
            use_container_width=True,
            hide_index=True
        )
    
    st.divider()
    
    # Service breakdown
    st.subheader("Service Breakdown")
    service_agg = df.groupby('SERVICE_TYPE').agg({
        'TOTAL_CREDITS': 'sum',
        'DAILY_UNIQUE_USERS': 'mean',
        'TOTAL_OPERATIONS': 'sum'
    }).reset_index()
    service_agg['TOTAL_COST_USD'] = service_agg['TOTAL_CREDITS'] * credit_cost
    service_agg = service_agg.sort_values('TOTAL_CREDITS', ascending=False)
    
    col1, col2 = st.columns([2, 1])
    
    with col1:
        st.dataframe(
            service_agg.style.format({
                'TOTAL_CREDITS': '{:,.0f}',
                'TOTAL_COST_USD': '${:,.2f}',
                'DAILY_UNIQUE_USERS': '{:.0f}',
                'TOTAL_OPERATIONS': '{:,.0f}'
            }),
            use_container_width=True
        )
    
    with col2:
        fig = px.pie(
            service_agg,
            values='TOTAL_CREDITS',
            names='SERVICE_TYPE',
            title='Credits by Service'
        )
        st.plotly_chart(fig, use_container_width=True)
    
    st.divider()
    
    # Usage trends
    st.subheader("Usage Trends")
    
    daily_totals = df.groupby(['DATE', 'SERVICE_TYPE'])['TOTAL_CREDITS'].sum().reset_index()
    
    fig = px.line(
        daily_totals,
        x='DATE',
        y='TOTAL_CREDITS',
        color='SERVICE_TYPE',
        title='Daily Credits Usage by Service'
    )
    fig.update_layout(hovermode='x unified')
    st.plotly_chart(fig, use_container_width=True)

@st.cache_data(ttl=300)  # Cache for 5 minutes
def fetch_aisql_data():
    """Fetch all AISQL data in one go (cached for performance)"""
    try:
        # Function Summary - LIMIT to top 50 for performance
        function_summary_df = session.sql("""
            SELECT 
                function_name,
                model_name,
                call_count,
                total_credits,
                total_tokens,
                avg_credits_per_call,
                avg_tokens_per_call,
                cost_per_million_tokens,
                serverless_calls,
                compute_calls
            FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_AISQL_FUNCTION_SUMMARY
            ORDER BY total_credits DESC
            LIMIT 50
        """).to_pandas()
        
        # Model Comparison
        model_comparison_df = session.sql("""
            SELECT 
                model_name,
                functions_used,
                total_calls,
                total_credits,
                total_tokens,
                avg_credits_per_call,
                cost_per_million_tokens,
                median_credits,
                p90_credits
            FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_AISQL_MODEL_COMPARISON
            ORDER BY total_credits DESC
            LIMIT 20
        """).to_pandas()
        
        # Daily Trends - LIMIT to last 30 days and top functions
        daily_trends_df = session.sql("""
            SELECT 
                usage_date,
                function_name,
                model_name,
                daily_credits,
                daily_tokens,
                serverless_calls,
                compute_calls
            FROM SNOWFLAKE_EXAMPLE.CORTEX_USAGE.V_AISQL_DAILY_TRENDS
            WHERE usage_date >= DATEADD('day', -30, CURRENT_DATE())
            ORDER BY usage_date DESC, daily_credits DESC
            LIMIT 500
        """).to_pandas()
        
        return function_summary_df, model_comparison_df, daily_trends_df
    except Exception as e:
        return None, None, None

def show_aisql_functions(credit_cost):
    """Display AISQL Functions analysis tab (NEW in v2.5)"""
    st.header("🤖 AISQL Function & Model Analysis")
    st.markdown("**Detailed tracking of Cortex AISQL functions and models** (v2.6: Updated pricing Oct 31, 2025)")
    
    # ========================================================================
    # Fetch AISQL data (cached for performance)
    # ========================================================================
    
    with st.spinner("Loading AISQL data..."):
        function_summary_df, model_comparison_df, daily_trends_df = fetch_aisql_data()
    
    if function_summary_df is None:
        st.error("Unable to load AISQL function data.")
        st.info("💡 Make sure you've deployed v2.5 views using deploy_cortex_monitoring.sql")
        return
    
    if function_summary_df.empty:
        st.warning("No AISQL function usage found. Start using Cortex AISQL functions to see data here!")
        st.markdown("""
        **Tracked AISQL Functions:**
        - AI_COMPLETE, COMPLETE
        - AI_CLASSIFY
        - AI_FILTER
        - AI_AGG
        - AI_EMBED, EMBED_TEXT, EMBED_IMAGE
        - AI_EXTRACT
        - AI_SENTIMENT
        - AI_SUMMARIZE_AGG
        - AI_TRANSCRIBE
        - And more...
        """)
        return
    
    if model_comparison_df is None:
        model_comparison_df = pd.DataFrame()
    if daily_trends_df is None:
        daily_trends_df = pd.DataFrame()
    
    # ========================================================================
    # Section 1: Function & Model Overview
    # ========================================================================
    
    st.subheader("📊 Function & Model Overview")
    
    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        total_functions = function_summary_df['FUNCTION_NAME'].nunique()
        st.metric("Functions Used", total_functions)
    
    with col2:
        total_models = function_summary_df['MODEL_NAME'].dropna().nunique()
        st.metric("Models Used", total_models)
    
    with col3:
        total_calls = function_summary_df['CALL_COUNT'].sum()
        st.metric("Total Calls", f"{total_calls:,.0f}")
    
    with col4:
        total_credits = function_summary_df['TOTAL_CREDITS'].sum()
        total_cost = total_credits * credit_cost
        st.metric("Total Cost", f"${total_cost:,.2f}")
    
    st.markdown("---")
    
    # ========================================================================
    # Section 2: Top Functions by Cost
    # ========================================================================
    
    st.subheader("💰 Top Functions by Cost")
    
    # Aggregate by function (across all models)
    top_functions = function_summary_df.groupby('FUNCTION_NAME').agg({
        'CALL_COUNT': 'sum',
        'TOTAL_CREDITS': 'sum',
        'TOTAL_TOKENS': 'sum',
        'SERVERLESS_CALLS': 'sum',
        'COMPUTE_CALLS': 'sum'
    }).reset_index()
    
    top_functions['COST_USD'] = top_functions['TOTAL_CREDITS'] * credit_cost
    top_functions = top_functions.sort_values('TOTAL_CREDITS', ascending=False).head(10)
    
    # Bar chart
    fig_functions = px.bar(
        top_functions,
        x='FUNCTION_NAME',
        y='TOTAL_CREDITS',
        title='Top 10 AISQL Functions by Credit Usage',
        labels={'TOTAL_CREDITS': 'Total Credits', 'FUNCTION_NAME': 'Function'},
        color='TOTAL_CREDITS',
        color_continuous_scale='Viridis'
    )
    fig_functions.update_layout(showlegend=False)
    st.plotly_chart(fig_functions, use_container_width=True)
    
    # Display table
    display_cols = ['FUNCTION_NAME', 'CALL_COUNT', 'TOTAL_CREDITS', 'COST_USD', 
                    'TOTAL_TOKENS', 'SERVERLESS_CALLS', 'COMPUTE_CALLS']
    st.dataframe(
        top_functions[display_cols].style.format({
            'CALL_COUNT': '{:,.0f}',
            'TOTAL_CREDITS': '{:.4f}',
            'COST_USD': '${:,.2f}',
            'TOTAL_TOKENS': '{:,.0f}',
            'SERVERLESS_CALLS': '{:,.0f}',
            'COMPUTE_CALLS': '{:,.0f}'
        }),
        use_container_width=True,
        hide_index=True
    )
    
    st.markdown("---")
    
    # ========================================================================
    # Section 3: Model Comparison
    # ========================================================================
    
    if not model_comparison_df.empty:
        st.subheader("🎯 Model Comparison")
        
        # Prepare data
        model_comparison_df['COST_USD'] = model_comparison_df['TOTAL_CREDITS'] * credit_cost
        model_comparison_df['COST_PER_MILLION_USD'] = model_comparison_df['COST_PER_MILLION_TOKENS'] * credit_cost
        
        # Scatter plot: Cost vs Usage
        fig_models = px.scatter(
            model_comparison_df,
            x='TOTAL_CALLS',
            y='TOTAL_CREDITS',
            size='TOTAL_TOKENS',
            color='MODEL_NAME',
            title='Model Usage: Calls vs Credits (bubble size = tokens)',
            labels={
                'TOTAL_CALLS': 'Total Calls',
                'TOTAL_CREDITS': 'Total Credits',
                'MODEL_NAME': 'Model'
            },
            hover_data=['FUNCTIONS_USED', 'AVG_CREDITS_PER_CALL', 'COST_PER_MILLION_TOKENS']
        )
        fig_models.update_traces(marker=dict(sizemode='diameter', sizeref=model_comparison_df['TOTAL_TOKENS'].max()/1e6))
        st.plotly_chart(fig_models, use_container_width=True)
        
        # Model comparison table
        st.markdown("**📋 Model Details**")
        display_cols_model = ['MODEL_NAME', 'FUNCTIONS_USED', 'TOTAL_CALLS', 'TOTAL_CREDITS', 
                              'COST_USD', 'COST_PER_MILLION_USD', 'TOTAL_TOKENS']
        st.dataframe(
            model_comparison_df[display_cols_model].style.format({
                'FUNCTIONS_USED': '{:.0f}',
                'TOTAL_CALLS': '{:,.0f}',
                'TOTAL_CREDITS': '{:.4f}',
                'COST_USD': '${:,.2f}',
                'COST_PER_MILLION_USD': '${:,.2f}',
                'TOTAL_TOKENS': '{:,.0f}'
            }),
            use_container_width=True,
            hide_index=True
        )
        
        st.markdown("---")
    
    # ========================================================================
    # Section 4: Function-Model Heatmap (Collapsible for performance)
    # ========================================================================
    
    with st.expander("🔥 Function-Model Usage Heatmap", expanded=False):
        # Create pivot table for heatmap
        heatmap_data = function_summary_df.pivot_table(
            index='FUNCTION_NAME',
            columns='MODEL_NAME',
            values='TOTAL_CREDITS',
            fill_value=0
        )
        
        # Create heatmap
        fig_heatmap = px.imshow(
            heatmap_data,
            labels=dict(x="Model", y="Function", color="Credits"),
            title="Credit Usage by Function and Model",
            color_continuous_scale='YlOrRd',
            aspect='auto'
        )
        fig_heatmap.update_xaxes(side='bottom')
        st.plotly_chart(fig_heatmap, use_container_width=True)
    
    st.markdown("---")
    
    # ========================================================================
    # Section 5: Daily Trends (Collapsible for performance)
    # ========================================================================
    
    if not daily_trends_df.empty:
        with st.expander("📈 Daily Usage Trends (Last 30 Days)", expanded=False):
            # Aggregate by date and function
            daily_agg = daily_trends_df.groupby(['USAGE_DATE', 'FUNCTION_NAME']).agg({
                'DAILY_CREDITS': 'sum',
                'DAILY_TOKENS': 'sum'
            }).reset_index()
            
            # Line chart
            fig_trends = px.line(
                daily_agg,
                x='USAGE_DATE',
                y='DAILY_CREDITS',
                color='FUNCTION_NAME',
                title='Daily Credit Usage by Function (Last 30 Days)',
                labels={'DAILY_CREDITS': 'Daily Credits', 'USAGE_DATE': 'Date'}
            )
            fig_trends.update_layout(hovermode='x unified')
            st.plotly_chart(fig_trends, use_container_width=True)
        
        st.markdown("---")
    
    # ========================================================================
    # Section 6: Detailed Function-Model Table (Collapsible for performance)
    # ========================================================================
    
    with st.expander("📋 Detailed Function-Model Breakdown", expanded=False):
        st.markdown("**Complete data table with all metrics**")
        
        # Prepare detailed table
        detailed_df = function_summary_df.copy()
        detailed_df['COST_USD'] = detailed_df['TOTAL_CREDITS'] * credit_cost
        detailed_df['COST_PER_MILLION_USD'] = detailed_df['COST_PER_MILLION_TOKENS'] * credit_cost
        detailed_df = detailed_df.sort_values('TOTAL_CREDITS', ascending=False)
        
        display_cols_detailed = [
            'FUNCTION_NAME', 'MODEL_NAME', 'CALL_COUNT', 'TOTAL_CREDITS', 'COST_USD',
            'TOTAL_TOKENS', 'COST_PER_MILLION_USD', 'AVG_TOKENS_PER_CALL',
            'SERVERLESS_CALLS', 'COMPUTE_CALLS'
        ]
        
        st.dataframe(
            detailed_df[display_cols_detailed].style.format({
                'CALL_COUNT': '{:,.0f}',
                'TOTAL_CREDITS': '{:.6f}',
                'COST_USD': '${:,.4f}',
                'TOTAL_TOKENS': '{:,.0f}',
                'COST_PER_MILLION_USD': '${:,.2f}',
                'AVG_TOKENS_PER_CALL': '{:,.0f}',
                'SERVERLESS_CALLS': '{:,.0f}',
                'COMPUTE_CALLS': '{:,.0f}'
            }),
            use_container_width=True,
            hide_index=True
        )
        
        # Download button
        csv = detailed_df.to_csv(index=False)
        st.download_button(
            label="📥 Download AISQL Data as CSV",
            data=csv,
            file_name=f"aisql_function_analysis_{datetime.now().strftime('%Y%m%d')}.csv",
            mime="text/csv"
        )
    
    st.markdown("---")
    st.info("💡 **Tip**: Use this data to optimize your AISQL function usage and choose the most cost-effective models for your use case.")

def show_cost_projections(df, credit_cost, variance_pct):
    """Display cost projections tab"""
    st.header("Cost Projections")
    
    # ========================================================================
    # Important: API vs SQL Function Usage
    # ========================================================================
    st.info("""
    ### 🔍 Understanding Your Cortex Usage Costs
    
    **Two Ways to Use Cortex Services:**
    
    1. **SQL Functions** (e.g., `SELECT SNOWFLAKE.CORTEX.COMPLETE(...)`)
       - ✅ Hourly aggregated tracking via `CORTEX_FUNCTIONS_USAGE_HISTORY` (tokens, credits, function, model)
       - ✅ **Plus** query-level tracking via `CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY`
       - ✅ Full visibility: per-query breakdown + per-model breakdown + hourly trends
    
    2. **REST API** (e.g., `POST /api/v2/cortex/complete`)
       - ✅ Hourly aggregated tracking via `CORTEX_FUNCTIONS_USAGE_HISTORY` (tokens, credits, function, model)
       - ℹ️ Query-level details not available (Snowflake limitation)
       - ✅ All essential metrics tracked: total tokens, credits, function names, models used
    
    **💡 Key Insight:** Both access methods are fully tracked in `CORTEX_FUNCTIONS_USAGE_HISTORY` with 
    tokens, credits, and model information. The only difference is that SQL functions get **additional** 
    query-level detail. **All cost projections in this calculator are accurate for both access methods** 
    because they're based on the aggregated usage data that captures everything.
    """)
    
    # ========================================================================
    # Snowflake Official Consumption Rates (Reference)
    # ========================================================================
    with st.expander("📘 Snowflake Official Consumption Rates (Updated Oct 31, 2025)", expanded=False):
        st.markdown("""
        **Reference: Snowflake AI Features Credit Table (Table 6)**
        
        These are Snowflake's published consumption rates for Cortex services:
        *Source: [Snowflake Service Consumption Table](https://www.snowflake.com/legal-files/CreditConsumptionTable.pdf) (Effective Oct 31, 2025)*
        """)
        
        # Create tabs for different service categories
        rate_tab1, rate_tab2, rate_tab3, rate_tab4 = st.tabs([
            "📄 Document AI & Search",
            "🤖 LLM Functions", 
            "🎯 Text Functions",
            "🖼️ Embeddings"
        ])
        
        with rate_tab1:
            st.markdown("**Document AI & Search Services**")
            rates_data_doc = pd.DataFrame([
                {
                    'Service': 'AI Parse Document (Layout)',
                    'Rate': '3.33 credits per 1,000 pages',
                    'Access': 'SQL + API',
                    'Metric': 'Pages processed',
                    'Your Data': 'V_DOCUMENT_AI_DETAIL view'
                },
                {
                    'Service': 'AI Parse Document (OCR)',
                    'Rate': '0.5 credits per 1,000 pages',
                    'Access': 'SQL + API',
                    'Metric': 'Pages processed',
                    'Your Data': 'V_DOCUMENT_AI_DETAIL view'
                },
                {
                    'Service': 'Cortex Analyst',
                    'Rate': '67 credits per 1,000 messages (0.067/msg)',
                    'Access': 'API only',
                    'Metric': 'Messages/requests',
                    'Your Data': 'V_CORTEX_ANALYST_DETAIL view'
                },
                {
                    'Service': 'Cortex Search',
                    'Rate': '6.3 credits per GB/month',
                    'Access': 'SQL + API',
                    'Metric': 'Indexed data size',
                    'Your Data': 'V_CORTEX_SEARCH_DETAIL view'
                },
                {
                    'Service': 'Document AI',
                    'Rate': '8 credits per hour',
                    'Access': 'SQL + API',
                    'Metric': 'Compute hours',
                    'Your Data': 'V_DOCUMENT_AI_DETAIL view'
                }
            ])
            st.dataframe(rates_data_doc, use_container_width=True, hide_index=True)
        
        with rate_tab2:
            st.markdown("**LLM Text Generation Functions (COMPLETE, CLASSIFY, etc.)**")
            st.caption("Rates shown are credits per 1 million tokens. Available via SQL functions AND REST API.")
            
            llm_rates = pd.DataFrame([
                {'Model': 'claude-3-5-sonnet', 'Input': 3.0, 'Output': 15.0, 'Access': 'SQL + API', 'Notes': 'High capability'},
                {'Model': 'claude-3-5-haiku', 'Input': 1.0, 'Output': 5.0, 'Access': 'SQL + API', 'Notes': 'Fast & efficient'},
                {'Model': 'claude-3-opus', 'Input': 15.0, 'Output': 75.0, 'Access': 'SQL + API', 'Notes': 'Most capable'},
                {'Model': 'claude-3-sonnet', 'Input': 3.0, 'Output': 15.0, 'Access': 'SQL + API', 'Notes': 'Balanced'},
                {'Model': 'claude-3-haiku', 'Input': 0.25, 'Output': 1.25, 'Access': 'SQL + API', 'Notes': 'Fastest'},
                {'Model': 'llama3.1-405b', 'Input': 3.0, 'Output': 3.0, 'Access': 'SQL + API', 'Notes': 'Large model'},
                {'Model': 'llama3.1-70b', 'Input': 0.4, 'Output': 0.4, 'Access': 'SQL + API', 'Notes': 'Good balance'},
                {'Model': 'llama3.1-8b', 'Input': 0.1, 'Output': 0.1, 'Access': 'SQL + API', 'Notes': 'Efficient'},
                {'Model': 'llama3-70b', 'Input': 0.4, 'Output': 0.4, 'Access': 'SQL + API', 'Notes': 'Previous gen'},
                {'Model': 'llama3-8b', 'Input': 0.1, 'Output': 0.1, 'Access': 'SQL + API', 'Notes': 'Previous gen'},
                {'Model': 'mistral-large2', 'Input': 2.0, 'Output': 6.0, 'Access': 'SQL + API', 'Notes': 'Latest large'},
                {'Model': 'mistral-large', 'Input': 2.0, 'Output': 6.0, 'Access': 'SQL + API', 'Notes': 'Large model'},
                {'Model': 'mixtral-8x7b', 'Input': 0.15, 'Output': 0.15, 'Access': 'SQL + API', 'Notes': 'MoE model'},
                {'Model': 'mistral-7b', 'Input': 0.1, 'Output': 0.1, 'Access': 'SQL + API', 'Notes': 'Base model'},
                {'Model': 'jamba-1.5-large', 'Input': 2.0, 'Output': 8.0, 'Access': 'SQL + API', 'Notes': 'Hybrid SSM'},
                {'Model': 'jamba-1.5-mini', 'Input': 0.2, 'Output': 0.4, 'Access': 'SQL + API', 'Notes': 'Efficient'},
                {'Model': 'gemma-7b', 'Input': 0.1, 'Output': 0.1, 'Access': 'SQL + API', 'Notes': 'Google model'},
                {'Model': 'reka-core', 'Input': 3.0, 'Output': 15.0, 'Access': 'SQL + API', 'Notes': 'Multimodal'},
                {'Model': 'reka-flash', 'Input': 0.3, 'Output': 1.5, 'Access': 'SQL + API', 'Notes': 'Fast multimodal'}
            ])
            
            st.dataframe(
                llm_rates.style.format({
                    'Input': '{:.2f}',
                    'Output': '{:.2f}'
                }),
                use_container_width=True,
                hide_index=True
            )
            
            st.info("""
            💡 **Important**: These models are used for functions like:
            - `COMPLETE()` / `AI_COMPLETE()` - Text generation
            - `AI_CLASSIFY()` - Classification tasks
            - `AI_FILTER()` - Content filtering
            - `AI_AGG()` - Aggregation tasks
            """)
        
        with rate_tab3:
            st.markdown("**Specialized Text Functions**")
            st.caption("Rates shown are credits per 1 million tokens. Available via SQL functions AND REST API.")
            
            text_rates = pd.DataFrame([
                {'Function': 'SENTIMENT', 'Rate': 0.056, 'Access': 'SQL + API', 'Metric': 'per 1M tokens'},
                {'Function': 'SUMMARIZE', 'Rate': 0.056, 'Access': 'SQL + API', 'Metric': 'per 1M tokens'},
                {'Function': 'TRANSLATE', 'Rate': 0.056, 'Access': 'SQL + API', 'Metric': 'per 1M tokens'},
                {'Function': 'EXTRACT_ANSWER', 'Rate': 0.056, 'Access': 'SQL + API', 'Metric': 'per 1M tokens'},
                {'Function': 'AI_EXTRACT (standard)', 'Rate': 0.15, 'Access': 'SQL + API', 'Metric': 'per 1M tokens'},
                {'Function': 'AI_EXTRACT (mistral-large)', 'Rate': 2.0, 'Access': 'SQL + API', 'Metric': 'per 1M input tokens'},
                {'Function': 'AI_EXTRACT (mistral-large)', 'Rate': 6.0, 'Access': 'SQL + API', 'Metric': 'per 1M output tokens'},
                {'Function': 'AI_SENTIMENT', 'Rate': 0.3, 'Access': 'SQL + API', 'Metric': 'per 1M tokens'}
            ])
            
            st.dataframe(
                text_rates.style.format({'Rate': '{:.3f}'}),
                use_container_width=True,
                hide_index=True
            )
        
        with rate_tab4:
            st.markdown("**Embedding Functions**")
            st.caption("Rates shown are credits per 1 million tokens. Available via SQL functions AND REST API.")
            
            embedding_rates = pd.DataFrame([
                {'Function': 'EMBED_TEXT_768', 'Rate': 0.014, 'Access': 'SQL + API', 'Dimensions': 768},
                {'Function': 'EMBED_TEXT_1024', 'Rate': 0.014, 'Access': 'SQL + API', 'Dimensions': 1024},
                {'Function': 'AI_EMBED (e5-base-v2)', 'Rate': 0.014, 'Access': 'SQL + API', 'Dimensions': 768},
                {'Function': 'AI_EMBED (multilingual-e5-large)', 'Rate': 0.014, 'Access': 'SQL + API', 'Dimensions': 1024},
                {'Function': 'AI_EMBED (snowflake-arctic-embed-l-v2.0)', 'Rate': 0.014, 'Access': 'SQL + API', 'Dimensions': 1024},
                {'Function': 'AI_EMBED (snowflake-arctic-embed-m-v2.0)', 'Rate': 0.014, 'Access': 'SQL + API', 'Dimensions': 768},
                {'Function': 'EMBED_IMAGE_1024', 'Rate': 0.14, 'Access': 'SQL + API', 'Dimensions': 1024}
            ])
            
            st.dataframe(
                embedding_rates.style.format({'Rate': '{:.4f}'}),
                use_container_width=True,
                hide_index=True
            )
        
        rates_data = pd.DataFrame([
            {
                'Service': 'AI Parse Document (Layout)',
                'Rate': '3.33 credits per 1,000 pages',
                'Access Method': 'SQL + API',
                'Metric': 'Pages processed',
                'Your Data': 'V_DOCUMENT_AI_DETAIL view'
            },
            {
                'Service': 'AI Parse Document (OCR)',
                'Rate': '0.5 credits per 1,000 pages',
                'Access Method': 'SQL + API',
                'Metric': 'Pages processed',
                'Your Data': 'V_DOCUMENT_AI_DETAIL view'
            },
            {
                'Service': 'Cortex Analyst',
                'Rate': '67 credits per 1,000 messages (0.067/msg)',
                'Access Method': 'API only',
                'Metric': 'Messages/requests',
                'Your Data': 'V_CORTEX_ANALYST_DETAIL view'
            },
            {
                'Service': 'Cortex Search',
                'Rate': '6.3 credits per GB/month',
                'Access Method': 'SQL + API',
                'Metric': 'Indexed data size',
                'Your Data': 'V_CORTEX_SEARCH_DETAIL view'
            },
            {
                'Service': 'AISQL Functions',
                'Rate': 'Varies by model & tokens (see tabs above)',
                'Access Method': 'SQL + API',
                'Metric': 'Tokens processed',
                'Your Data': 'V_AISQL_FUNCTION_SUMMARY view'
            }
        ])
        
        st.dataframe(
            rates_data,
            use_container_width=True,
            hide_index=True
        )
        
        st.info("""
        💡 **How to validate your costs:**
        1. Check the "Historical Analysis" tab for actual credit consumption
        2. Compare credits/operation ratios with rates above
        3. For AISQL functions, check the "AISQL Functions" tab for per-token costs
        4. If rates differ significantly, verify your ACCOUNT_USAGE data
        """)
        
        st.success("""
        ✅ **Important Notes:**
        - **Pricing is identical** for both SQL functions AND REST API calls (same rates apply)
        - **All usage is tracked** in ACCOUNT_USAGE views with tokens, credits, function, and model details
        - AISQL function costs vary by model (claude, llama, mistral, etc.) and token usage
        - Token-based pricing depends on input + output tokens
        - Rates shown are for Snowflake-managed compute
        - **Query-level breakdown** available only for SQL functions; REST API usage appears in hourly aggregates
        """)
        
        # Calculate actual rates from data if available
        if not df.empty:
            st.markdown("---")
            st.markdown("**📊 Your Actual Consumption Rates (from ACCOUNT_USAGE)**")
            
            actual_rates = []
            
            for service in df['SERVICE_TYPE'].unique():
                service_data = df[df['SERVICE_TYPE'] == service]
                total_credits = service_data['TOTAL_CREDITS'].sum()
                total_ops = service_data['TOTAL_OPERATIONS'].sum()
                
                if total_ops > 0:
                    rate_per_op = total_credits / total_ops
                    
                    # Add service-specific context
                    if 'Analyst' in service:
                        expected = 0.067  # 0.067 credits per message
                        display_rate = f'{rate_per_op:.4f} credits per message'
                        metric = 'messages'
                    elif 'Document' in service:
                        rate_per_1000 = rate_per_op * 1000
                        expected = 1.915  # Average of Layout (3.33) and OCR (0.5) per 1,000 pages
                        display_rate = f'{rate_per_1000:.2f} credits per 1,000 pages'
                        metric = 'pages'
                    elif 'Search' in service:
                        expected = None  # GB-based, different metric
                        display_rate = f'{rate_per_op:.4f} credits per operation'
                        metric = 'operations'
                    else:
                        expected = None
                        display_rate = f'{rate_per_op:.4f} credits per operation'
                        metric = 'operations'
                    
                    # Check if within range (±50% tolerance)
                    if expected:
                        actual_value = rate_per_op if 'Analyst' in service else rate_per_op * 1000
                        within_range = abs(actual_value - expected) / expected < 0.5
                        status = '✅ Within range' if within_range else '⚠️ Verify'
                    else:
                        status = '📊 No baseline'
                    
                    actual_rates.append({
                        'Service': service,
                        'Your Rate': display_rate,
                        'Total Operations': f'{total_ops:,.0f}',
                        'Total Credits': f'{total_credits:.4f}',
                        'Status': status
                    })
            
            if actual_rates:
                actual_rates_df = pd.DataFrame(actual_rates)
                st.dataframe(
                    actual_rates_df,
                    use_container_width=True,
                    hide_index=True
                )
                
                st.success("""
                ✅ **Validation:** Your actual rates are calculated from ACCOUNT_USAGE data and represent real consumption. 
                Differences from published rates may occur due to:
                - Different models/configurations
                - Mixed operation types (e.g., Layout vs OCR)
                - Rounding in aggregated data
                """)
    
    st.divider()
    
    # ========================================================================
    # Cost Calculation Methodology
    # ========================================================================
    with st.expander("🧮 How We Calculate Your Costs (SQL vs API Usage)", expanded=False):
        st.markdown("""
        ### Calculation Methodology
        
        **Data Sources:**
        - **Total Credits**: Captured from `ACCOUNT_USAGE` views (accurate for both SQL and API usage)
        - **Query-Level Details**: Only available for SQL function calls via `CORTEX_FUNCTIONS_QUERY_USAGE_HISTORY`
        - **REST API Calls**: Included in totals but without per-query breakdown
        
        **What This Means:**
        """)
        
        comparison_data = pd.DataFrame([
            {'Feature': 'Total credits & tokens', 'SQL Functions': '✅ Tracked (hourly)', 'REST API': '✅ Tracked (hourly)'},
            {'Feature': 'Function & model breakdown', 'SQL Functions': '✅ Available', 'REST API': '✅ Available'},
            {'Feature': 'Per-query details', 'SQL Functions': '✅ Yes (QUERY_ID level)', 'REST API': 'ℹ️ No (hourly aggregates only)'},
            {'Feature': 'Cost projections accuracy', 'SQL Functions': '✅ Highly accurate', 'REST API': '✅ Highly accurate'},
            {'Feature': 'Historical trend analysis', 'SQL Functions': '✅ Full detail', 'REST API': '✅ Full detail'}
        ])
        
        st.dataframe(comparison_data, use_container_width=True, hide_index=True)
        
        st.markdown("""
        **Impact on Your Cost Analysis:**
        
        ✅ **Good News:** Cost projections in this calculator are highly accurate for **both** access methods because:
        - `CORTEX_FUNCTIONS_USAGE_HISTORY` captures all usage (SQL + API) with tokens, credits, function, and model details
        - Historical trends, daily summaries, and cost projections use this aggregated data
        - Total credit consumption is 100% accurate regardless of how you access Cortex
        
        ℹ️ **Only Difference:** The "AISQL Functions" tab shows query-level analysis, which is only available for SQL functions.
        REST API users will see accurate totals and trends but won't see individual query breakdowns.
        
        **Bottom Line:** Whether you use SQL functions, REST API, or both, this calculator provides accurate 
        cost tracking and projections based on your actual ACCOUNT_USAGE data.
        """)
    
    # ========================================================================
    # Cost per User Calculator - MOVED TO TOP
    # ========================================================================
    st.subheader("💰 Cost per User Calculator")
    st.markdown("**Estimate per-user costs based on usage patterns**")
    
    show_cost_per_user_calculator(df, credit_cost)
    
    st.divider()
    st.divider()
    
    # ========================================================================
    # Growth-Based Cost Projections
    # ========================================================================
    st.header("📈 Growth-Based Cost Projections")
    
    col1, col2 = st.columns(2)
    
    with col1:
        projection_months = st.slider(
            "Projection Period (months)",
            min_value=3,
            max_value=24,
            value=12
        )
    
    with col2:
        growth_rate = st.slider(
            "Monthly Growth Rate (%)",
            min_value=0,
            max_value=100,
            value=25
        ) / 100
    
    # Calculate projection
    projection_df = calculate_growth_projection(df, growth_rate, projection_months, credit_cost)
    
    # Summary metrics
    monthly_totals = projection_df.groupby('month')['projected_cost_usd'].sum().reset_index()
    
    month_1_cost = monthly_totals[monthly_totals['month'] == 1]['projected_cost_usd'].iloc[0] if len(monthly_totals) > 0 else 0
    month_12_cost = monthly_totals[monthly_totals['month'] == 12]['projected_cost_usd'].iloc[0] if len(monthly_totals) >= 12 else 0
    total_year_cost = monthly_totals['projected_cost_usd'].sum()
    
    st.divider()
    
    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        st.metric("Month 1 Cost", format_currency(month_1_cost))
    with col2:
        st.metric("Month 12 Cost", format_currency(month_12_cost))
    with col3:
        st.metric("Total Year Cost", format_currency(total_year_cost))
    with col4:
        variance_range = f"±{format_currency(total_year_cost * variance_pct)}"
        st.metric("Variance Range", variance_range)
    
    st.divider()
    
    # Projection chart
    fig = go.Figure()
    
    monthly_totals['lower_bound'] = monthly_totals['projected_cost_usd'] * (1 - variance_pct)
    monthly_totals['upper_bound'] = monthly_totals['projected_cost_usd'] * (1 + variance_pct)
    
    fig.add_trace(go.Scatter(
        x=monthly_totals['month'],
        y=monthly_totals['upper_bound'],
        mode='lines',
        name=f'Upper (+{variance_pct*100:.0f}%)',
        line=dict(width=0),
        showlegend=True
    ))
    
    fig.add_trace(go.Scatter(
        x=monthly_totals['month'],
        y=monthly_totals['lower_bound'],
        mode='lines',
        name=f'Lower (-{variance_pct*100:.0f}%)',
        line=dict(width=0),
        fillcolor='rgba(41, 181, 232, 0.2)',
        fill='tonexty',
        showlegend=True
    ))
    
    fig.add_trace(go.Scatter(
        x=monthly_totals['month'],
        y=monthly_totals['projected_cost_usd'],
        mode='lines+markers',
        name='Projected Cost',
        line=dict(color='#29B5E8', width=3)
    ))
    
    fig.update_layout(
        title='Cost Projection with Variance Range',
        xaxis_title='Month',
        yaxis_title='Projected Cost (USD)',
        hovermode='x unified'
    )
    
    st.plotly_chart(fig, use_container_width=True)
    
    # Detailed table
    st.subheader("Monthly Breakdown")
    st.dataframe(
        monthly_totals.style.format({
            'projected_cost_usd': '${:,.2f}',
            'lower_bound': '${:,.2f}',
            'upper_bound': '${:,.2f}'
        }),
        use_container_width=True
    )

def show_cost_per_user_calculator(df, credit_cost):
    """
    Simplified calculator for cost per user estimation
    Shows: persona name, user count, requests per day, cost per request
    """
    
    # Calculate historical baseline metrics from usage data
    # Use a more robust aggregation approach that handles sparse data better
    
    # Aggregate by service type across all available dates
    latest_30d = df.groupby('SERVICE_TYPE').agg({
        'TOTAL_OPERATIONS': 'sum',
        'DAILY_UNIQUE_USERS': 'mean',
        'TOTAL_CREDITS': 'sum',
        'DATE': 'count'  # Count number of days with data
    }).reset_index()
    
    # Rename DATE count to days_with_data for clarity
    latest_30d.rename(columns={'DATE': 'days_with_data'}, inplace=True)
    
    # Calculate average requests per day based on actual days with data
    latest_30d['requests_per_day'] = latest_30d['TOTAL_OPERATIONS'] / latest_30d['days_with_data']
    latest_30d['users_in_env'] = latest_30d['DAILY_UNIQUE_USERS']
    
    # Calculate cost per request (handle division by zero)
    latest_30d['cost_per_request'] = latest_30d.apply(
        lambda row: (row['TOTAL_CREDITS'] * credit_cost) / row['TOTAL_OPERATIONS'] 
        if row['TOTAL_OPERATIONS'] > 0 else 0, 
        axis=1
    )
    
    # ========================================================================
    # Historical Usage Reference Table - MOVED TO TOP AS GUIDE
    # ========================================================================
    st.markdown("#### 📊 Historical Usage Reference (from your data)")
    st.caption("Use these metrics as a guide for your cost estimates below")
    
    # Debug expander to show raw data and accuracy checks
    with st.expander("🔍 Debug: View Raw Data & Accuracy Checks", expanded=False):
        st.markdown("**📊 Latest Aggregated Data:**")
        st.dataframe(latest_30d, use_container_width=True)
        
        st.markdown("---")
        st.markdown("**✅ Accuracy Validation Checks:**")
        
        # Check 1: Cortex Analyst rate validation
        analyst_data = latest_30d[latest_30d['SERVICE_TYPE'] == 'Cortex Analyst']
        if not analyst_data.empty:
            analyst_rate = analyst_data.iloc[0]['cost_per_request'] / credit_cost
            expected_rate = 0.067
            rate_diff_pct = abs((analyst_rate - expected_rate) / expected_rate * 100)
            
            if rate_diff_pct < 5:
                st.success(f"✅ Cortex Analyst: {analyst_rate:.4f} credits/msg (Expected: {expected_rate}, Diff: {rate_diff_pct:.1f}%)")
            elif rate_diff_pct < 20:
                st.warning(f"⚠️ Cortex Analyst: {analyst_rate:.4f} credits/msg (Expected: {expected_rate}, Diff: {rate_diff_pct:.1f}%) - Within acceptable range")
            else:
                st.error(f"❌ Cortex Analyst: {analyst_rate:.4f} credits/msg (Expected: {expected_rate}, Diff: {rate_diff_pct:.1f}%) - Significant deviation!")
        
        # Check 2: Verify no division by zero issues
        zero_ops = latest_30d[latest_30d['TOTAL_OPERATIONS'] == 0]
        if not zero_ops.empty:
            st.error(f"❌ Found {len(zero_ops)} service(s) with 0 operations: {', '.join(zero_ops['SERVICE_TYPE'].tolist())}")
        else:
            st.success("✅ All services have non-zero operations")
        
        # Check 3: Verify cost per request is reasonable
        unreasonable_costs = latest_30d[latest_30d['cost_per_request'] > 10]  # Flag if >$10 per request
        if not unreasonable_costs.empty:
            st.warning(f"⚠️ Unusually high cost per request detected for: {', '.join(unreasonable_costs['SERVICE_TYPE'].tolist())}")
        else:
            st.success("✅ All cost per request values are in reasonable range")
        
        # Check 4: Data completeness
        st.markdown("**📅 Data Completeness:**")
        for _, row in latest_30d.iterrows():
            days_pct = (row['days_with_data'] / 30) * 100
            if days_pct < 30:
                st.warning(f"⚠️ {row['SERVICE_TYPE']}: Only {row['days_with_data']} days of data ({days_pct:.0f}% of 30 days)")
            else:
                st.info(f"ℹ️ {row['SERVICE_TYPE']}: {row['days_with_data']} days of data ({days_pct:.0f}% coverage)")
        
        st.markdown("---")
        st.markdown("**📋 Raw Input Data (Last 10 Rows):**")
        st.dataframe(df.tail(10), use_container_width=True)
    
    reference_table = []
    for _, service in latest_30d.iterrows():
        reference_table.append({
            'Service': service['SERVICE_TYPE'],
            'Days of Data': int(service['days_with_data']),
            'Users in Environment': f"{service['users_in_env']:.0f}",
            'Requests per Day': f"{service['requests_per_day']:,.1f}",
            'Cost per Request': f"${service['cost_per_request']:.6f}"
        })
    
    reference_df = pd.DataFrame(reference_table)
    st.dataframe(reference_df, use_container_width=True, hide_index=True)
    
    st.divider()
    
    # ========================================================================
    # User Persona Configuration
    # ========================================================================
    st.markdown("#### 👤 Define User Personas and Estimate Costs")
    
    # Initialize session state for user personas if not exists
    if 'user_personas_simple' not in st.session_state:
        st.session_state.user_personas_simple = [
            {'name': 'Power User', 'count': 10, 'requests_per_day': 50},
            {'name': 'Regular User', 'count': 30, 'requests_per_day': 20}
        ]
    
    # User persona inputs
    personas_to_remove = []
    for idx, persona in enumerate(st.session_state.user_personas_simple):
        col1, col2, col3, col4 = st.columns([2, 1, 1, 0.5])
        
        with col1:
            persona['name'] = st.text_input(
                "Persona Name",
                value=persona['name'],
                key=f"simple_persona_name_{idx}",
                placeholder="e.g., Power User, Analyst, Executive"
            )
        
        with col2:
            persona['count'] = st.number_input(
                "Number of Users",
                min_value=1,
                value=persona['count'],
                step=1,
                key=f"simple_count_{idx}"
            )
        
        with col3:
            persona['requests_per_day'] = st.number_input(
                "Requests per Day",
                min_value=1,
                value=persona['requests_per_day'],
                step=5,
                key=f"simple_req_{idx}",
                help="Average requests per user per day"
            )
        
        with col4:
            if len(st.session_state.user_personas_simple) > 1:
                if st.button("🗑️", key=f"simple_remove_{idx}", help="Remove"):
                    personas_to_remove.append(idx)
    
    # Remove personas marked for deletion
    for idx in sorted(personas_to_remove, reverse=True):
        st.session_state.user_personas_simple.pop(idx)
        st.rerun()
    
    # Add new persona button
    if st.button("➕ Add Another Persona"):
        st.session_state.user_personas_simple.append({
            'name': f'User Type {len(st.session_state.user_personas_simple) + 1}',
            'count': 10,
            'requests_per_day': 20
        })
        st.rerun()
    
    st.divider()
    
    # ========================================================================
    # Calculate Costs per Persona
    # ========================================================================
    st.markdown("#### 💵 Cost Estimates by Persona")
    
    # Add toggle for rate source
    use_official_rates = st.checkbox(
        "Use official Snowflake rates (0.067 credits/message for Analyst)",
        value=False,
        help="Toggle between actual rates from your usage data vs official published rates"
    )
    
    # Calculate cost per request based on user selection
    if use_official_rates:
        # Use official rate: 0.067 credits per message * credit_cost
        avg_cost_per_request = 0.067 * credit_cost
        st.info(f"📋 Using official rate: 0.067 credits/message = ${avg_cost_per_request:.6f} per request")
    else:
        # Calculate weighted average cost per request across all services from actual data
        total_ops = latest_30d['requests_per_day'].sum() * 30  # Monthly operations
        total_cost_30d = sum(
            (row['requests_per_day'] * 30 * row['cost_per_request']) 
            for _, row in latest_30d.iterrows()
        )
        avg_cost_per_request = total_cost_30d / total_ops if total_ops > 0 else 0
        st.info(f"📊 Using actual observed rate from your data: ${avg_cost_per_request:.6f} per request")
    
    # Calculate costs for each persona
    persona_results = []
    for persona in st.session_state.user_personas_simple:
        monthly_requests = persona['requests_per_day'] * 30
        cost_per_user_monthly = monthly_requests * avg_cost_per_request
        total_cost_monthly = cost_per_user_monthly * persona['count']
        
        persona_results.append({
            'Persona': persona['name'],
            'Users': persona['count'],
            'Requests/Day': persona['requests_per_day'],
            'Requests/Month': f"{monthly_requests:,}",
            'Cost/Request': f"${avg_cost_per_request:.6f}",
            'Cost/User/Month': f"${cost_per_user_monthly:,.2f}",
            'Total Monthly Cost': f"${total_cost_monthly:,.2f}"
        })
    
    results_df = pd.DataFrame(persona_results)
    st.dataframe(results_df, use_container_width=True, hide_index=True)
    
    # Summary metrics
    total_users = sum(p['count'] for p in st.session_state.user_personas_simple)
    total_monthly_cost = sum(
        p['requests_per_day'] * 30 * avg_cost_per_request * p['count'] 
        for p in st.session_state.user_personas_simple
    )
    total_monthly_requests = sum(
        p['requests_per_day'] * 30 * p['count'] 
        for p in st.session_state.user_personas_simple
    )
    avg_cost_per_user = total_monthly_cost / total_users if total_users > 0 else 0
    
    st.divider()
    
    col1, col2, col3, col4 = st.columns(4)
    
    with col1:
        st.metric("Total Users", f"{total_users:,}")
    with col2:
        st.metric("Total Monthly Requests", f"{total_monthly_requests:,.0f}")
    with col3:
        st.metric("Avg Cost per User", f"${avg_cost_per_user:,.2f}")
    with col4:
        st.metric("Total Monthly Cost", f"${total_monthly_cost:,.2f}")
    
    # Quick accuracy check reminder
    st.info(f"""
    💡 **Quick Accuracy Check:**
    - **Cortex Analyst** (Official Rate): 0.067 credits per message = ${0.067 * credit_cost:.4f} per request at ${credit_cost:.2f}/credit
    - **Manual verification**: Total Monthly Cost = Total Users × Requests/Day × 30 days × Cost/Request
    - **Toggle the checkbox above** to compare actual rates vs official Snowflake rates
    - **Open the Debug expander** at the top to see detailed validation checks
    
    **Official Rates (Oct 31, 2025):**
    - Cortex Analyst: 67 credits per 1,000 messages (0.067/msg)
    - LLM models: Varies by model (0.1 - 75 credits per 1M tokens)
    - Document AI Layout: 3.33 credits per 1,000 pages
    - Document AI OCR: 0.5 credits per 1,000 pages
    """)

def show_summary_report(df, credit_cost, variance_pct):
    """Display summary report tab"""
    st.header("Executive Summary Report")
    
    # Historical summary
    st.markdown("## 📊 Current State")
    
    total_credits = df['TOTAL_CREDITS'].sum()
    total_cost = total_credits * credit_cost
    days_of_data = len(df['DATE'].unique())
    avg_daily_cost = total_cost / days_of_data if days_of_data > 0 else 0
    
    col1, col2, col3 = st.columns(3)
    
    with col1:
        st.metric("Analysis Period", f"{days_of_data} days")
        st.metric("Total Historical Cost", format_currency(total_cost))
    
    with col2:
        st.metric("Avg Daily Cost", format_currency(avg_daily_cost))
        st.metric("Total Credits Used", format_number(total_credits))
    
    with col3:
        service_count = df['SERVICE_TYPE'].nunique()
        st.metric("Active Services", service_count)
        avg_users = df['DAILY_UNIQUE_USERS'].mean()
        st.metric("Avg Daily Users", format_number(avg_users))
    
    st.divider()
    
    # Projection
    st.markdown("## 🔮 12-Month Projection (25% Growth)")
    
    projection_df = calculate_growth_projection(df, 0.25, 12, credit_cost)
    monthly_totals = projection_df.groupby('month')['projected_cost_usd'].sum()
    total_year_cost = monthly_totals.sum()
    
    col1, col2, col3 = st.columns(3)
    
    with col1:
        st.metric("Projected Annual Cost", format_currency(total_year_cost))
    
    with col2:
        lower = total_year_cost * (1 - variance_pct)
        upper = total_year_cost * (1 + variance_pct)
        st.metric(f"Range (±{variance_pct*100:.0f}%)", f"{format_currency(lower)} - {format_currency(upper)}")
    
    with col3:
        avg_monthly = total_year_cost / 12
        st.metric("Avg Monthly Cost", format_currency(avg_monthly))
    
    st.divider()
    
    # Service breakdown
    st.markdown("## 💼 Service Breakdown")
    
    service_agg = df.groupby('SERVICE_TYPE').agg({
        'TOTAL_CREDITS': 'sum',
        'DAILY_UNIQUE_USERS': 'mean',
        'TOTAL_OPERATIONS': 'sum'
    }).reset_index()
    service_agg['TOTAL_COST_USD'] = service_agg['TOTAL_CREDITS'] * credit_cost
    service_agg['PCT_OF_TOTAL'] = service_agg['TOTAL_CREDITS'] / service_agg['TOTAL_CREDITS'].sum() * 100
    service_agg = service_agg.sort_values('TOTAL_CREDITS', ascending=False)
    
    st.dataframe(
        service_agg.style.format({
            'TOTAL_CREDITS': '{:,.0f}',
            'TOTAL_COST_USD': '${:,.2f}',
            'PCT_OF_TOTAL': '{:.1f}%',
            'DAILY_UNIQUE_USERS': '{:.0f}',
            'TOTAL_OPERATIONS': '{:,.0f}'
        }),
        use_container_width=True
    )
    
    # Export options
    st.divider()
    st.markdown("## 📥 Export Data")
    
    csv = df.to_csv(index=False)
    st.download_button(
        label="Download Historical Data (CSV)",
        data=csv,
        file_name=f"cortex_usage_{datetime.now().strftime('%Y%m%d')}.csv",
        mime="text/csv"
    )

if __name__ == "__main__":
    main()
