import streamlit as st
import pandas as pd
import plotly.express as px
from sqlalchemy import create_engine

# 1. إعدادات الصفحة
st.set_page_config(page_title="Clothing Store Dashboard", layout="wide")
st.title("📊 Clothing Store Dashboard")
st.markdown("نظام تحليل بيانات محل الملابس - مبني بـ Python و SQL Server")

# 2. الاتصال بقاعدة البيانات
server_name = 'localhost' # لو اسم السيرفر عندك مختلف غيره (مثلاً .\SQLEXPRESS)
database_name = 'ClothingStore'
connection_string = f'mssql+pyodbc://{server_name}/{database_name}?driver=ODBC+Driver+17+for+SQL+Server&trusted_connection=yes'

@st.cache_resource
def get_connection():
    return create_engine(connection_string)

engine = get_connection()

# 3. سحب البيانات
@st.cache_data
def load_data():
    # المبيعات الإجمالية
    df_sales = pd.read_sql("SELECT * FROM vw_SaleTotals", engine)
    
    # المخزون
    df_inventory = pd.read_sql("SELECT * FROM vw_Inventory", engine)
    
    # المخزون المنخفض
    df_low_stock = pd.read_sql("SELECT * FROM vw_LowStock", engine)
    
    # استعلام مخصص عشان نجيب المبيعات حسب القسم الرئيسي (لأنه مش موجود في vw_SaleTotals)
    query_category = """
        SELECT mc.CategoryName AS MainCategory, SUM(si.Quantity * si.UnitPrice) AS TotalSales
        FROM SaleItems si
        JOIN ProductVariants v ON v.VariantID = si.VariantID
        JOIN Products p ON p.ProductID = v.ProductID
        JOIN Categories c ON c.CategoryID = p.CategoryID
        LEFT JOIN Categories mc ON mc.CategoryID = c.ParentCategoryID
        GROUP BY mc.CategoryName
    """
    df_sales_by_cat = pd.read_sql(query_category, engine)
    
    return df_sales, df_inventory, df_low_stock, df_sales_by_cat

df_sales, df_inventory, df_low_stock, df_sales_by_cat = load_data()

# 4. الأرقام الأساسية (KPIs)
st.subheader("📌 النظرة العامة")
col1, col2, col3, col4 = st.columns(4)

total_sales = df_sales['Total'].sum() if not df_sales.empty else 0
total_profit = df_sales['Profit'].sum() if not df_sales.empty else 0
total_orders = len(df_sales)
low_stock_count = len(df_low_stock)

col1.metric("إجمالي المبيعات", f"${total_sales:,.2f}")
col2.metric("إجمالي الأرباح", f"${total_profit:,.2f}")
col3.metric("عدد الفواتير", total_orders)
col4.metric("منتجات قربت تخلص", low_stock_count, delta="- تحتاج طلب", delta_color="inverse")

st.divider()

# 5. الرسومات البيانية
st.subheader("📈 تحليل المبيعات والمخزون")
col_chart1, col_chart2 = st.columns(2)

with col_chart1:
    # مبيعات حسب القسم الرئيسي
    if not df_sales_by_cat.empty:
        fig_pie = px.pie(df_sales_by_cat, names='MainCategory', values='TotalSales', title='المبيعات حسب القسم الرئيسي')
        st.plotly_chart(fig_pie, use_container_width=True)
    else:
        st.info("لا توجد بيانات مبيعات كافية لعرض الرسمة الدائرية.")

with col_chart2:
    # المبيعات بمرور الوقت
    if not df_sales.empty:
        df_sales['SaleDate'] = pd.to_datetime(df_sales['SaleDate'])
        sales_by_date = df_sales.groupby(df_sales['SaleDate'].dt.date)['Total'].sum().reset_index()
        fig_line = px.line(sales_by_date, x='SaleDate', y='Total', title='المبيعات بمرور الوقت')
        st.plotly_chart(fig_line, use_container_width=True)
    else:
        st.info("لا توجد بيانات مبيعات كافية لعرض الرسمة الخطية.")

st.divider()

# 6. جدول المخزون المنخفض
st.subheader("⚠️ تنبيهات المخزون المنخفض")
if not df_low_stock.empty:
    # اختيار أعمدة محددة عشان الجدول ميبقاش مزحمة
    cols_to_show = ['ProductName', 'MainCategory', 'Size', 'Color', 'Quantity', 'ReorderLevel']
    st.dataframe(df_low_stock[cols_to_show], use_container_width=True)
else:
    st.success("كل المنتجات كمياتها كافية! ✅")