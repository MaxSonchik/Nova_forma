import sys
import os
import psycopg2

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config

def run_test():
    conn = psycopg2.connect(config.DATABASE_URL)
    cur = conn.cursor()
    
    print("--- ТЕСТ 1: Добавление заказа Менеджером ---")
    # 1. Берем первого клиента и сотрудника
    cur.execute("SELECT id_клиента FROM клиенты LIMIT 1")
    client_id = cur.fetchone()[0]
    cur.execute("SELECT id_сотрудника FROM сотрудники WHERE должность='менеджер' LIMIT 1")
    mgr_id = cur.fetchone()[0]
    
    # 2. Создаем "пустой" заказ
    cur.execute("""
        INSERT INTO заказы (id_клиента, id_менеджера, дата_готовности) 
        VALUES (%s, %s, CURRENT_DATE + 5) RETURNING id_заказа
    """, (client_id, mgr_id))
    order_id = cur.fetchone()[0]
    print(f"Создан заказ ID: {order_id}")
    
    # 3. Берем изделие
    cur.execute("SELECT id_изделия FROM изделия LIMIT 1")
    prod_id = cur.fetchone()[0]
    
    # 4. Менеджер добавляет изделие (вызов функции)
    # Пытаемся добавить 1000 штук (чтобы точно не хватило на складе и сработал триггер производства)
    qty = 1000
    print(f"Менеджер добавляет изделие {prod_id} в количестве {qty} шт...")
    
    cur.execute("SELECT sp_добавить_изделие_в_заказ(%s, %s, %s)", (order_id, prod_id, qty))
    result_msg = cur.fetchone()[0]
    conn.commit()
    
    print(f"Результат функции: {result_msg}")
    
    # 5. Проверка Плана
    cur.execute("SELECT COUNT(*) FROM план_заготовок WHERE id_заказа = %s", (order_id,))
    count_tasks = cur.fetchone()[0]
    print(f"Записей в плане производства для заказа: {count_tasks}")
    
    if "WARNING" in result_msg and count_tasks > 0:
        print("✅ ТЕСТ ПРОЙДЕН: Система обнаружила дефицит и создала задачи сборщикам.")
    else:
        print("❌ ТЕСТ ПРОВАЛЕН: Логика не сработала.")

    cur.close()
    conn.close()

if __name__ == "__main__":
    run_test()