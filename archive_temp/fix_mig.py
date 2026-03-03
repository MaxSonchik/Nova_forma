import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
import time

try:
    conn = psycopg2.connect(dbname='postgres', user='postgres', password='123456', host='localhost')
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cur = conn.cursor()
    cur.execute("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'nova_forma_crm' AND pid <> pg_backend_pid();")
    conn.close()
    
    time.sleep(1)
    
    conn2 = psycopg2.connect(dbname='nova_forma_crm', user='postgres', password='123456', host='localhost')
    conn2.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cur2 = conn2.cursor()
    with open('db/migrations/fix_sp_add_product_to_order_smart.sql', 'r') as f:
        sql = f.read()
    cur2.execute(sql)
    print("Migration successful.")
except Exception as e:
    print("Error:", e)
