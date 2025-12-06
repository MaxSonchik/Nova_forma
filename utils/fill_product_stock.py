import sys
import os
import random
import psycopg2

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config

def fill_stock():
    print("📦 Обновление остатков готовых изделий...")
    try:
        conn = psycopg2.connect(config.DATABASE_URL)
        cur = conn.cursor()
        
        # Получаем все ID изделий
        cur.execute("SELECT id_изделия FROM изделия")
        products = cur.fetchall()
        
        for (p_id,) in products:
            # Делаем малое количество (0-5), чтобы легко было вызвать нехватку на складе
            qty = random.randint(0, 5)
            cur.execute("UPDATE изделия SET количество_на_складе = %s WHERE id_изделия = %s", (qty, p_id))
            
        conn.commit()
        print(f"✅ Успешно обновлено {len(products)} изделий.")
        
        cur.close()
        conn.close()
    except Exception as e:
        print(f"❌ Ошибка: {e}")

if __name__ == "__main__":
    fill_stock()