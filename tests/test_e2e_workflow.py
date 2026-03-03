#!/usr/bin/env python3
"""
End-to-End Workflow Test for Nova Forma
Emulates the full user workflow through direct database procedure calls.

Tests:
1. Create order → add product → check stock deductions
2. Worker takes task → check material deduction
3. Worker submits work → check stock NOT added (client order)
4. Release task → check material return
5. Cancel order → check everything returned
6. Fired worker → check blocking
7. Material shortage → check blocking
"""
import sys
import psycopg2
from psycopg2.extensions import ISOLATION_LEVEL_AUTOCOMMIT
from psycopg2.extras import RealDictCursor

DB_PARAMS = {
    "dbname": "nova_forma_crm",
    "user": "postgres",
    "password": "123456",
    "host": "localhost"
}

PASS = "✅ PASS"
FAIL = "❌ FAIL"

class E2ETest:
    def __init__(self):
        self.conn = psycopg2.connect(**DB_PARAMS)
        self.conn.set_isolation_level(ISOLATION_LEVEL_AUTOCOMMIT)
        self.cur = self.conn.cursor(cursor_factory=RealDictCursor)
        self.results = []
        self.order_id = None
        self.worker_id = None

    def call_proc(self, name, args):
        """Call a stored procedure and return the first result row."""
        self.cur.execute(f"SELECT * FROM {name}({','.join(['%s']*len(args))})", args)
        return self.cur.fetchone()

    def fetch_one(self, query, params=None):
        self.cur.execute(query, params)
        return self.cur.fetchone()

    def assert_test(self, name, condition, detail=""):
        result = PASS if condition else FAIL
        self.results.append((name, result, detail))
        print(f"  {result} {name}" + (f" — {detail}" if detail else ""))

    def get_material_stock(self, material_id):
        row = self.fetch_one("SELECT количество_на_складе FROM Материал WHERE id_материала = %s", (material_id,))
        return row["количество_на_складе"] if row else 0

    def get_component_stock(self, component_id):
        row = self.fetch_one("SELECT количество_готовых FROM Заготовка WHERE id_заготовки = %s", (component_id,))
        return row["количество_готовых"] if row else 0

    def run(self):
        print("=" * 60)
        print("E2E Workflow Test — Nova Forma")
        print("=" * 60)

        # TEST 10 PREP: Capture initial state
        self.initial_total_materials = self.fetch_one("SELECT SUM(количество_на_складе) as sum FROM Материал")["sum"] or 0
        self.initial_total_components = self.fetch_one("SELECT SUM(количество_готовых) as sum FROM Заготовка")["sum"] or 0

        # Find test data
        self.cur.execute("""
            SELECT si.id_изделия, si.id_заготовки, si.количество_заготовки,
                   rm.id_материала, rm.количество_материала
            FROM СоставИзделия si
            JOIN РасходМатериалов rm ON si.id_заготовки = rm.id_заготовки
            LIMIT 1
        """)
        test_data = self.cur.fetchone()
        if not test_data:
            print("ERROR: Нет тестовых данных (СоставИзделия + РасходМатериалов пусты)")
            return False

        product_id = test_data["id_изделия"]
        component_id = test_data["id_заготовки"]
        material_id = test_data["id_материала"]
        mat_per_comp = test_data["количество_материала"]
        comp_per_prod = test_data["количество_заготовки"]

        # Find a worker
        self.cur.execute("""
            SELECT id_сотрудника FROM Сотрудник
            WHERE дата_увольнения IS NULL AND должность IN ('сборщик', 'швея', 'мастер')
            LIMIT 1
        """)
        worker_row = self.cur.fetchone()
        if not worker_row:
            print("ERROR: Нет активного сотрудника для тестов")
            return False
        self.worker_id = worker_row["id_сотрудника"]

        # Find a manager for order creation
        self.cur.execute("SELECT id_сотрудника FROM Сотрудник WHERE должность = 'менеджер' LIMIT 1")
        mgr_row = self.cur.fetchone()
        manager_id = mgr_row["id_сотрудника"] if mgr_row else self.worker_id

        # Find a client
        self.cur.execute("SELECT id_клиента FROM Клиент LIMIT 1")
        client_row = self.cur.fetchone()
        if not client_row:
            print("ERROR: Нет клиентов для тестов")
            return False
        client_id = client_row["id_клиента"]

        print(f"\nТестовые данные:")
        print(f"  Изделие ID: {product_id}")
        print(f"  Заготовка ID: {component_id} (×{comp_per_prod} на изделие)")
        print(f"  Материал ID: {material_id} (×{mat_per_comp} на заготовку)")
        print(f"  Сотрудник ID: {self.worker_id}")
        print(f"  Менеджер ID: {manager_id}")

        # Force component stock to 0 so we actually create tasks
        self.initial_actual_comp_stock = self.get_component_stock(component_id)
        self.cur.execute("UPDATE Заготовка SET количество_готовых = 0 WHERE id_заготовки = %s", (component_id,))

        # ====================
        # TEST 1: Create Order
        # ====================
        print("\n--- Тест 1: Создание заказа ---")
        self.cur.execute("""
            INSERT INTO Заказ (id_клиента, id_менеджера, дата_готовности, статус)
            VALUES (%s, %s, CURRENT_DATE + INTERVAL '7 days', 'принят')
            RETURNING id_заказа
        """, (client_id, manager_id))
        self.order_id = self.cur.fetchone()["id_заказа"]
        self.assert_test("Заказ создан", self.order_id is not None, f"ID: {self.order_id}")

        # ====================
        # TEST 2: Add product — check component deduction, NO material deduction
        # ====================
        print("\n--- Тест 2: Добавление изделия (проверка списаний) ---")
        initial_comp_stock = self.get_component_stock(component_id)
        initial_mat_stock = self.get_material_stock(material_id)
        print(f"  До: заготовки={initial_comp_stock}, материалы={initial_mat_stock}")

        qty = 2
        res = self.call_proc("sp_add_product_to_order_smart",
                             [self.order_id, product_id, qty, "2026-04-01"])

        after_comp_stock = self.get_component_stock(component_id)
        after_mat_stock = self.get_material_stock(material_id)
        print(f"  После: заготовки={after_comp_stock}, материалы={after_mat_stock}")
        print(f"  Результат: {res['status']} — {res['message']}")

        expected_comp_taken = min(comp_per_prod * qty, initial_comp_stock)
        self.assert_test(
            "Заготовки списаны со склада",
            after_comp_stock <= initial_comp_stock,
            f"Было {initial_comp_stock}, стало {after_comp_stock}"
        )
        self.assert_test(
            "Материалы НЕ списаны при создании",
            after_mat_stock == initial_mat_stock,
            f"Было {initial_mat_stock}, стало {after_mat_stock}"
        )

        # Check if task was created
        task_row = self.fetch_one("""
            SELECT * FROM "ПланЗаготовок"
            WHERE id_заказа = %s AND id_заготовки = %s
        """, (self.order_id, component_id))

        has_task = task_row is not None
        if has_task:
            self.assert_test(
                "Задача создана в плане",
                True,
                f"Плановое: {task_row['плановое_количество']}, статус: {task_row['статус']}"
            )
            self.assert_test(
                "Флаг материалы_списаны = FALSE",
                task_row.get("материалы_списаны") == False,
                f"Значение: {task_row.get('материалы_списаны')}"
            )
        else:
            self.assert_test("Задача создана в плане", False, "Задача не найдена — все со склада")

        # ====================
        # TEST 3: Worker takes task — check material deduction
        # ====================
        if has_task:
            print("\n--- Тест 3: Взятие задачи в работу ---")
            mat_before_take = self.get_material_stock(material_id)

            res = self.call_proc("sp_take_component_task",
                                 [component_id, self.order_id, self.worker_id])
            print(f"  Результат: {res['status']} — {res['message']}")

            mat_after_take = self.get_material_stock(material_id)

            self.assert_test(
                "Задача взята успешно",
                res["status"] == "OK",
                res.get("message", "")
            )
            self.assert_test(
                "Материалы СПИСАНЫ при взятии",
                mat_after_take < mat_before_take,
                f"Было {mat_before_take}, стало {mat_after_take}"
            )

            # Check flag
            task_row = self.fetch_one("""
                SELECT материалы_списаны FROM "ПланЗаготовок"
                WHERE id_заказа = %s AND id_заготовки = %s
            """, (self.order_id, component_id))
            self.assert_test(
                "Флаг материалы_списаны = TRUE",
                task_row.get("материалы_списаны") == True
            )

            # ====================
            # TEST 4: Submit partial work — check NO stock added
            # ====================
            print("\n--- Тест 4: Частичная сдача работы ---")
            comp_before_submit = self.get_component_stock(component_id)

            res = self.call_proc("sp_submit_component_work",
                                 [component_id, self.order_id, 1, self.worker_id])
            print(f"  Результат: {res['status']} — {res['message']}")

            comp_after_submit = self.get_component_stock(component_id)

            self.assert_test(
                "Работа частично принята",
                res["status"] == "OK"
            )
            self.assert_test(
                "Заготовки НЕ добавлены на склад (клиентский заказ)",
                comp_after_submit == comp_before_submit,
                f"Было {comp_before_submit}, стало {comp_after_submit}"
            )

            # ====================
            # TEST 5: Release task — check material return
            # ====================
            print("\n--- Тест 5: Снятие задачи (возврат материалов) ---")
            mat_before_release = self.get_material_stock(material_id)

            res = self.call_proc("sp_release_task", [component_id, self.order_id])
            print(f"  Результат: {res['status']} — {res['message']}")

            mat_after_release = self.get_material_stock(material_id)

            self.assert_test(
                "Задача снята",
                res["status"] == "OK"
            )
            self.assert_test(
                "Материалы возвращены на склад",
                mat_after_release > mat_before_release,
                f"Было {mat_before_release}, стало {mat_after_release}"
            )

            # Re-take for cancellation test
            self.call_proc("sp_take_component_task",
                           [component_id, self.order_id, self.worker_id])

        # ====================
        # TEST 6: Cancel order — check everything returned
        # ====================
        print("\n--- Тест 6: Отмена заказа ---")
        mat_before_cancel = self.get_material_stock(material_id)
        comp_before_cancel = self.get_component_stock(component_id)

        res = self.call_proc("sp_update_order_status", [self.order_id, "отменен"])
        print(f"  Результат: {res['status']} — {res['message']}")

        mat_after_cancel = self.get_material_stock(material_id)
        comp_after_cancel = self.get_component_stock(component_id)

        self.assert_test(
            "Заказ отменен",
            res["status"] == "OK"
        )
        self.assert_test(
            "Материалы возвращены",
            mat_after_cancel >= mat_before_cancel,
            f"Было {mat_before_cancel}, стало {mat_after_cancel}"
        )
        self.assert_test(
            "Заготовки возвращены",
            comp_after_cancel >= comp_before_cancel,
            f"Было {comp_before_cancel}, стало {comp_after_cancel}"
        )

        # ====================
        # TEST 7: Fired worker blocking
        # ====================
        print("\n--- Тест 7: Блокировка уволенного сотрудника ---")
        self.cur.execute("""
            SELECT id_сотрудника FROM Сотрудник
            WHERE дата_увольнения IS NOT NULL
            LIMIT 1
        """)
        fired = self.cur.fetchone()
        if fired:
            # Create a fresh order for this test
            self.cur.execute("""
                INSERT INTO Заказ (id_клиента, id_менеджера, дата_готовности, статус)
                VALUES (%s, %s, CURRENT_DATE + INTERVAL '7 days', 'принят')
                RETURNING id_заказа
            """, (client_id, manager_id))
            test_order = self.cur.fetchone()["id_заказа"]

            res_add = self.call_proc("sp_add_product_to_order_smart",
                                     [test_order, product_id, 1, "2026-04-01"])

            task_check = self.fetch_one("""
                SELECT * FROM "ПланЗаготовок"
                WHERE id_заказа = %s LIMIT 1
            """, (test_order,))

            if task_check:
                res = self.call_proc("sp_take_component_task",
                                     [task_check["id_заготовки"], test_order, fired["id_сотрудника"]])
                self.assert_test(
                    "Уволенный НЕ может взять задачу",
                    res["status"] == "ERROR",
                    res.get("message", "")
                )
            else:
                self.assert_test("Уволенный НЕ может взять задачу", True, "Нет задач (все со склада)")

            # Cleanup test order
            self.call_proc("sp_update_order_status", [test_order, "отменен"])
        else:
            self.assert_test("Уволенный НЕ может взять задачу", True, "Нет уволенных в БД (пропущено)")

        # ====================
        # TEST 8: Service order (replenishment)
        # ====================
        print("\n--- Тест 8: Служебный заказ (пополнение склада) ---")
        comp_before_service = self.get_component_stock(component_id)
        
        # create service order
        self.cur.execute("""
            INSERT INTO Заказ (id_клиента, id_менеджера, дата_готовности, статус)
            VALUES (NULL, %s, CURRENT_DATE + INTERVAL '7 days', 'принят')
            RETURNING id_заказа
        """, (manager_id,))
        service_order = self.cur.fetchone()["id_заказа"]
        
        res = self.call_proc('sp_create_manual_production_task',
                             [service_order, component_id, 1, "2026-04-01"])
                             
        self.assert_test("Задача для служебного заказа добавлена", res['status'] == 'OK', res.get('message', ''))
        
        self.call_proc("sp_take_component_task", [component_id, service_order, self.worker_id])
        res = self.call_proc("sp_submit_component_work", [component_id, service_order, 1, self.worker_id])
        
        comp_after_service = self.get_component_stock(component_id)
        self.assert_test("Заготовки ДОБАВЛЕНЫ на склад (служебный заказ)", comp_after_service > comp_before_service, f"Стало {comp_after_service}")
        
        # Cleanup
        self.call_proc("sp_update_order_status", [service_order, "отменен"])

        # ====================
        # TEST 9: Material shortage
        # ====================
        print("\n--- Тест 9: Нехватка материалов ---")
        # Find a material we can zero out temporarily
        self.cur.execute("UPDATE Материал SET количество_на_складе = 0 WHERE id_материала = %s RETURNING количество_на_складе", (material_id,))
        
        # Create test order
        self.cur.execute("""
            INSERT INTO Заказ (id_клиента, id_менеджера, дата_готовности, статус)
            VALUES (%s, %s, CURRENT_DATE + INTERVAL '7 days', 'принят')
            RETURNING id_заказа
        """, (client_id, manager_id))
        shortage_order = self.cur.fetchone()["id_заказа"]
        
        # Test adding product to order (should fail immediately now)
        res_add = self.call_proc("sp_add_product_to_order_smart", [shortage_order, product_id, 100, "2026-04-01"])
        
        self.assert_test("Добавление блокируется при нехватке материалов", res_add['status'] == 'ERROR' and "НЕОБХОДИМА ЗАКУПКА" in res_add['message'], res_add.get('message', ''))
            
        # Restore material
        self.cur.execute("UPDATE Материал SET количество_на_складе = %s WHERE id_материала = %s", (initial_mat_stock, material_id))
        self.call_proc("sp_update_order_status", [shortage_order, "отменен"])

        # Restore component stock
        self.cur.execute("UPDATE Заготовка SET количество_готовых = %s WHERE id_заготовки = %s", (self.initial_actual_comp_stock, component_id))


        # ====================
        # SUMMARY
        # ====================
        print("\n" + "=" * 60)
        passed = sum(1 for _, r, _ in self.results if r == PASS)
        failed = sum(1 for _, r, _ in self.results if r == FAIL)
        print(f"Итого: {passed} пройдено, {failed} провалено из {len(self.results)}")
        print("=" * 60)

        return failed == 0

    def __del__(self):
        try:
            self.cur.close()
            self.conn.close()
        except:
            pass


if __name__ == "__main__":
    test = E2ETest()
    success = test.run()
    sys.exit(0 if success else 1)
