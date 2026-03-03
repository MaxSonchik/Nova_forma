import os
import sys
import unittest

import psycopg2

sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config


class TestStage3Logic(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        """Подключение к БД перед тестами"""
        cls.conn = psycopg2.connect(config.DATABASE_URL)
        cls.conn.autocommit = False                                  
        cls.cur = cls.conn.cursor()

    @classmethod
    def tearDownClass(cls):
        """Закрытие соединения"""
        cls.cur.close()
        cls.conn.close()

    def setUp(self):
        """Начало транзакции перед каждым тестом"""
                                                                              
                                                                             
                                                                
        pass

    def test_01_view_warehouse(self):
        print("\n--- Тест 1: Представление v_склад_общий ---")
        self.cur.execute("SELECT count(*) FROM v_склад_общий")
        count = self.cur.fetchone()[0]
        print(f"Записей на складе: {count}")
        self.assertGreater(count, 0, "Склад не должен быть пустым")

    def test_02_trigger_age_restriction(self):
        print("\n--- Тест 2: Триггер возраста (trg_check_age) ---")
        try:
            self.cur.execute(
                """
                INSERT INTO Сотрудник (фио, номер_телефона, дата_рождения, должность, зарплата, login, password_hash)
                VALUES ('Школьник Тест', '999000111', CURRENT_DATE - INTERVAL '16 years', 'сборщик', 50000, 'kid', 'hash')
            """
            )
            self.conn.commit()
            self.fail("Триггер не сработал! Удалось добавить сотрудника 16 лет.")
        except psycopg2.Error as e:
            self.conn.rollback()                
            print(f"✅ Успешно поймана ошибка: {e.pgerror.strip()}")

    def test_03_director_procurement_logic(self):
        print("\n--- Тест 3: Логика Директора (Закупка -> Склад) ---")
                                        
        self.cur.execute(
            "SELECT id_материала, количество_на_складе FROM Материал LIMIT 1"
        )
        mat_id, initial_stock = self.cur.fetchone()

                            
        self.cur.execute(
            "INSERT INTO Закупка (поставщик, статус) VALUES ('Тест Поставщик', 'подтверждено') RETURNING id_закупки"
        )
        zak_id = self.cur.fetchone()[0]

                                                
        qty_to_buy = 100
        self.cur.execute(
            """
            INSERT INTO СоставЗакупки (id_закупки, id_материала, количество, цена_закупки)
            VALUES (%s, %s, %s, 100)
        """,
            (zak_id, mat_id, qty_to_buy),
        )

                                              
        self.cur.execute("CALL sp_подтвердить_закупку(%s)", (zak_id,))
        self.conn.commit()

                              
        self.cur.execute(
            "SELECT количество_на_складе FROM Материал WHERE id_материала = %s",
            (mat_id,),
        )
        new_stock = self.cur.fetchone()[0]

        print(f"Было: {initial_stock}, Купили: {qty_to_buy}, Стало: {new_stock}")
        self.assertEqual(
            new_stock,
            initial_stock + qty_to_buy,
            "Остаток материала не увеличился корректно",
        )

    def test_04_manager_auto_sum_trigger(self):
        print("\n--- Тест 4: Триггер пересчета суммы заказа ---")
                          
        self.cur.execute("SELECT id_клиента FROM Клиент LIMIT 1")
        c_id = self.cur.fetchone()[0]
        self.cur.execute(
            "INSERT INTO Заказ (id_клиента) VALUES (%s) RETURNING id_заказа", (c_id,)
        )
        o_id = self.cur.fetchone()[0]

                                                      
        self.cur.execute("SELECT id_изделия FROM Изделие LIMIT 1")
        p_id = self.cur.fetchone()[0]

        self.cur.execute(
            """
            INSERT INTO СоставЗаказа (id_заказа, id_изделия, количество_изделий, цена_фиксированная)
            VALUES (%s, %s, 2, 100)
        """,
            (o_id, p_id),
        )
        self.conn.commit()

                                           
        self.cur.execute(
            "SELECT сумма_заказа FROM Заказ WHERE id_заказа = %s", (o_id,)
        )
        total = self.cur.fetchone()[0]
        print(f"Сумма заказа: {total}")
        self.assertEqual(total, 200, "Сумма заказа посчиталась неверно")

    def test_05_manager_production_plan_logic(self):
        print("\n--- Тест 5: Менеджер -> Дефицит -> План производства ---")
                          
        self.cur.execute("SELECT id_клиента FROM Клиент LIMIT 1")
        c_id = self.cur.fetchone()[0]
                                                              
        self.cur.execute(
            "INSERT INTO Заказ (id_клиента, дата_готовности) VALUES (%s, CURRENT_DATE + 10) RETURNING id_заказа",
            (c_id,),
        )
        o_id = self.cur.fetchone()[0]

                                                               
        self.cur.execute(
            """
            SELECT i.id_изделия FROM Изделие i 
            JOIN СоставИзделия si ON i.id_изделия = si.id_изделия 
            LIMIT 1
        """
        )
        p_id = self.cur.fetchone()

        if not p_id:
            print("⚠️ Пропуск теста: нет изделий с составом")
            return
        p_id = p_id[0]

                                                                     
        qty = 1000
        self.cur.execute(
            "SELECT sp_добавить_изделие_в_заказ(%s, %s, %s)", (o_id, p_id, qty)
        )
        res_msg = self.cur.fetchone()[0]
        self.conn.commit()

        print(f"Ответ системы: {res_msg}")
        self.assertIn("WARNING", res_msg, "Система не выдала предупреждение о дефиците")

                                           
        self.cur.execute(
            "SELECT count(*) FROM ПланЗаготовок WHERE id_заказа = %s", (o_id,)
        )
        tasks = self.cur.fetchone()[0]
        print(f"Создано задач сборщикам: {tasks}")
        self.assertGreater(tasks, 0, "План производства не создался")

                                                 
        self.cur.execute(
            "SELECT id_плана FROM ПланЗаготовок WHERE id_заказа = %s LIMIT 1", (o_id,)
        )
        TestStage3Logic.shared_plan_id = self.cur.fetchone()[0]
        TestStage3Logic.shared_plan_order_id = o_id

    def test_06_assembler_work_logic(self):
        print("\n--- Тест 6: Сборщик берет задачу -> Списание материалов ---")
        if not hasattr(TestStage3Logic, "shared_plan_id"):
            print("⚠️ Пропуск теста: нет ID плана из предыдущего теста")
            return

        plan_id = TestStage3Logic.shared_plan_id

                                              
        self.cur.execute(
            "SELECT id_сотрудника FROM Сотрудник WHERE должность='сборщик' LIMIT 1"
        )
        sb_id = self.cur.fetchone()
        if not sb_id:
                                             
            self.cur.execute("SELECT id_сотрудника FROM Сотрудник LIMIT 1")
            sb_id = self.cur.fetchone()
        sb_id = sb_id[0]

                                                                          
                                                                                   
                                                                                                                 
                                                                                   
        self.cur.execute("UPDATE Материал SET количество_на_складе = 100000")
        self.conn.commit()

                                                
        print(f"Сборщик {sb_id} берет задачу {plan_id}...")
        try:
            self.cur.execute("CALL sp_взять_задачу_в_работу(%s, %s)", (plan_id, sb_id))
            self.conn.commit()
            print("✅ Процедура выполнена успешно")

                                 
            self.cur.execute(
                "SELECT статус FROM ПланЗаготовок WHERE id_плана = %s", (plan_id,)
            )
            status = self.cur.fetchone()[0]
            self.assertEqual(status, "в_работе", "Статус задачи не изменился")

        except psycopg2.Error as e:
            self.fail(f"Ошибка при взятии задачи: {e.pgerror}")


if __name__ == "__main__":
    unittest.main()
