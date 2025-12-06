import sys
import os
import psycopg2

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config

def apply_update():
    print(f"Применение обновлений логики (Миграция 003)...")
    try:
        conn = psycopg2.connect(config.DATABASE_URL)
        cur = conn.cursor()
        
        with open("db/migrations/status_logic.sql", "r", encoding="utf-8") as f:
            sql = f.read()
            
        cur.execute(sql)
        conn.commit()
        print("✅ Новые статусы и процедуры успешно внедрены!")
        print("✅ Таблица логов удалена.")
        
        cur.close()
        conn.close()
    except Exception as e:
        print(f"❌ Ошибка: {e}")

if __name__ == "__main__":
    apply_update()