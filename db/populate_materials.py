import psycopg2
import random
import sys
import os

                          
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config

def populate_consumption():
    try:
        conn = psycopg2.connect(config.DATABASE_URL)
        cur = conn.cursor()
        
                                                
        cur.execute("SELECT TO_REGCLASS('СоставЗаготовки')")
        if not cur.fetchone()[0]:
            print("Table СоставЗаготовки does not exist. Please run migration feature_phase4.sql first.")
            return

        cur.execute("SELECT COUNT(*) FROM СоставЗаготовки")
        count = cur.fetchone()[0]
        print(f"Current rows in СоставЗаготовки: {count}")
        
        if count > 0:
            print("Table is not empty. Skipping.")
            return

        print("Populating СоставЗаготовки...")
        
                                         
        cur.execute("SELECT id_материала FROM Материал")
        materials = [r[0] for r in cur.fetchall()]
        
        cur.execute("SELECT id_заготовки FROM Заготовка")
        zagotovki = [r[0] for r in cur.fetchall()]
        
        if not materials or not zagotovki:
            print("Materials or Zagotovki tables are empty! Run seed_data.py first.")
            return

        for z_id in zagotovki:
                                                           
            used_mats = random.sample(materials, k=random.randint(1, 3))
            for m_id in used_mats:
                                     
                cur.execute(
                    "SELECT 1 FROM СоставЗаготовки WHERE id_заготовки = %s AND id_материала = %s",
                    (z_id, m_id)
                )
                if cur.fetchone():
                    continue
                    
                cur.execute(
                    "INSERT INTO СоставЗаготовки (id_заготовки, id_материала, количество_материала) VALUES (%s, %s, %s)",
                    (z_id, m_id, random.randint(1, 10))
                )
        
        conn.commit()
        print("Successfully populated СоставЗаготовки")
        
    except Exception as e:
        print(f"Error: {e}")
    finally:
        if conn: conn.close()

if __name__ == "__main__":
    populate_consumption()
