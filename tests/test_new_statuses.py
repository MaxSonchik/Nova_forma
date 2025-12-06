import os
import sys
import unittest

import psycopg2

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config


class TestNewStatuses(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        cls.conn = psycopg2.connect(config.DATABASE_URL)
        cls.cur = cls.conn.cursor()

    @classmethod
    def tearDownClass(cls):
        cls.cur.close()
        cls.conn.close()

    def test_workflow_shipping_closing(self):
        print("\n--- Тест цепочки: Выполнен -> Отгружен -> Завершен ---")

        # 1. Создаем заказ сразу со статусом 'выполнен' (имитация завершенного производства)
        # Нам нужен клиент и менеджер
        self.cur.execute("SELECT id_клиента FROM клиенты LIMIT 1")
        c_id = self.cur.fetchone()[0]

        self.cur.execute(
            """
            INSERT INTO заказы (id_клиента, статус, дата_готовности) 
            VALUES (%s, 'выполнен', CURRENT_DATE) 
            RETURNING id_заказа
        """,
            (c_id,),
        )
        o_id = self.cur.fetchone()[0]
        self.conn.commit()
        print(f"Создан выполненный заказ ID: {o_id}")

        # 2. Менеджер пытается отгрузить (sp_отгрузить_заказ)
        try:
            print("Менеджер отгружает заказ...")
            self.cur.execute("CALL sp_отгрузить_заказ(%s)", (o_id,))
            self.conn.commit()

            # Проверка
            self.cur.execute("SELECT статус FROM заказы WHERE id_заказа = %s", (o_id,))
            st = self.cur.fetchone()[0]
            self.assertEqual(st, "отгружен", "Статус не изменился на 'отгружен'")
            print("✅ Заказ отгружен.")
        except Exception as e:
            self.fail(f"Ошибка отгрузки: {e}")

        # 3. Директор пытается закрыть (sp_закрыть_заказ)
        try:
            print("Директор закрывает заказ...")
            self.cur.execute("CALL sp_закрыть_заказ(%s)", (o_id,))
            self.conn.commit()

            # Проверка
            self.cur.execute("SELECT статус FROM заказы WHERE id_заказа = %s", (o_id,))
            st = self.cur.fetchone()[0]
            self.assertEqual(st, "завершен", "Статус не изменился на 'завершен'")
            print("✅ Заказ успешно закрыт.")
        except Exception as e:
            self.fail(f"Ошибка закрытия: {e}")


if __name__ == "__main__":
    unittest.main()
