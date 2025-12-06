import os
import sys

import psycopg2

# Добавляем корневую директорию в путь, чтобы импортировать config
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config


def run_migration():
    print(f"Подключение к {config.DB_NAME}...")
    try:
        conn = psycopg2.connect(config.DATABASE_URL)
        cur = conn.cursor()

        # Читаем SQL файл
        with open("db/migrations/create_table.sql", "r", encoding="utf-8") as f:
            sql = f.read()

        print("Создание таблиц...")
        cur.execute(sql)
        conn.commit()
        print("✅ Таблицы успешно созданы!")

        cur.close()
        conn.close()
    except Exception as e:
        print(f"❌ Ошибка: {e}")


if __name__ == "__main__":
    run_migration()
