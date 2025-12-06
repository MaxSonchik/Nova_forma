import sys
import os
import psycopg2

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config

def apply_logic():
    print(f"Подключение к {config.DB_NAME}...")
    try:
        conn = psycopg2.connect(config.DATABASE_URL)
        cur = conn.cursor()
        
        with open("db/migrations/create_logic.sql", "r", encoding="utf-8") as f:
            sql = f.read()
            
        print("Применение логики (Views, Triggers, Procedures)...")
        cur.execute(sql)
        conn.commit()
        print("✅ Логика успешно применена!")
        
        cur.close()
        conn.close()
    except Exception as e:
        print(f"❌ Ошибка: {e}")

if __name__ == "__main__":
    apply_logic()