import os
import random
import sys

import psycopg2

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config


def fill_stock():
    print("📦 Обновление остатков готовых изделий...")
    try:
        conn = psycopg2.connect(config.DATABASE_URL)
        cur = conn.cursor()

                                 
        cur.execute("SELECT id_изделия FROM Изделие")
        products = cur.fetchall()

        for (p_id,) in products:
                                                                                        
            qty = random.randint(0, 5)
            cur.execute(
                "UPDATE Изделие SET количество_на_складе = %s WHERE id_изделия = %s",
                (qty, p_id),
            )

        conn.commit()
        print(f"✅ Успешно обновлено {len(products)} изделий.")

        cur.close()
        conn.close()
    except Exception as e:
        print(f"❌ Ошибка: {e}")


if __name__ == "__main__":
    fill_stock()
