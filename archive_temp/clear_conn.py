import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
try:
    conn = psycopg2.connect(dbname='postgres', user='postgres', password='123456', host='localhost')
    conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
    cur = conn.cursor()
    cur.execute("SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'nova_forma_crm' AND pid <> pg_backend_pid();")
    print('Terminated connections.')
except Exception as e:
    print('Error:', e)
