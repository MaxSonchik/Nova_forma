import os
import sys
import psycopg2
from pprint import pprint

                          
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
try:
    from config import config
except ImportError:
                                              
    sys.path.append(os.path.dirname(os.path.abspath(__file__)))
    from config import config

def list_tables():
    print("📋 Listing Database Tables...")
    try:
        conn = psycopg2.connect(config.DATABASE_URL)
        cur = conn.cursor()

        cur.execute("""
            SELECT table_name 
            FROM information_schema.tables 
            WHERE table_schema = 'public'
            ORDER BY table_name;
        """)
        rows = cur.fetchall()
        
        if not rows:
            print("❌ No tables found!")
        
        for (table,) in rows:
            print(f"- {table}")

        cur.close()
        conn.close()
    except Exception as e:
        print(f"❌ Error listing tables: {e}")

if __name__ == "__main__":
    list_tables()
