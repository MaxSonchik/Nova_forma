import sys
import os
import psycopg2
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config

def apply():
    conn = psycopg2.connect(config.DATABASE_URL)
    with conn.cursor() as cur:
        with open("db/migrations/assembler_logic.sql", "r", encoding="utf-8") as f:
            cur.execute(f.read())
        conn.commit()
    print("✅ Логика сборщика добавлена!")

if __name__ == "__main__":
    apply()