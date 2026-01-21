import unittest
import sys
import os
import psycopg2
from decimal import Decimal

with open('test_launch.log', 'w') as f:
    f.write("Launched\n")

# Add path to import config (parent directory)
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config

class TestDBProcedures(unittest.TestCase):
    
    @classmethod
    def setUpClass(cls):
        cls.conn = psycopg2.connect(config.DATABASE_URL)
        cls.conn.autocommit = False # We will rollback changes
        cls.cur = cls.conn.cursor()

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()

    def tearDown(self):
        # Rollback after each test to keep DB clean
        self.conn.rollback()

    def call_proc(self, name, args):
        placeholders = ",".join(["%s"] * len(args))
        query = f"SELECT * FROM {name}({placeholders})"
        self.cur.execute(query, args)
        return self.cur.fetchone()

    def test_dicts(self):
        # sp_get_clients returns rows (not single result of type record usually handled by call_proc logic above?)
        # My call_proc above assumes fetchone. For dicts we need fetchall.
        self.cur.execute("SELECT * FROM sp_get_clients()")
        clients = self.cur.fetchall()
        self.assertIsInstance(clients, list)
        
        self.cur.execute("SELECT * FROM sp_get_products()")
        products = self.cur.fetchall()
        self.assertIsInstance(products, list)

    def test_hire_employee(self):
        # Test hiring
        # sp_hire_employee(fio, phone, birth, role, salary, login, password)
        res_list = self.call_proc('sp_hire_employee', ['Test User', '9999999999', '1990-01-01', 'менеджер', 50000, 'test_user', 'pass'])
        # res_list is tuple/list from fetchone
        # columns: status, message
        status, msg = res_list
        self.assertEqual(status, 'OK')
        
        # Test Login with new user
        # sp_login(login, password) -> (status, msg, id, role, fio)
        res_login = self.call_proc('sp_login', ['test_user', 'pass'])
        self.assertEqual(res_login[0], 'OK')
        self.assertEqual(res_login[3], 'менеджер')

        # Test Wrong Password
        res_login_bad = self.call_proc('sp_login', ['test_user', 'wrong'])
        self.assertEqual(res_login_bad[0], 'ERROR')

    def test_client_and_order_flow(self):
        # 1. Create Client
        # sp_save_client(id, fio, phone, inn, address)
        self.cur.execute("SELECT * FROM sp_save_client(%s, %s, %s, %s, %s)", (None, 'Test Client', '70000001', 123, 'Addr'))
        res_save = self.cur.fetchone()
        self.assertEqual(res_save[0], 'OK')
        
        # Get Client ID (need to fetch it, but sp_save_client doesn't return ID directly... oops. 
        # But for test we can query table)
        self.cur.execute("SELECT id_клиента FROM клиенты WHERE номер_телефона = '70000001'")
        client_id = self.cur.fetchone()[0]

        # 2. Get Manager (use existing or create one)
        # We can use the one from previous test if we run in same transaction? No, previous test rolled back.
        # Let's create one here.
        self.call_proc('sp_hire_employee', ['Mgr', '8888', '1990-01-01', 'менеджер', 50000, 'mgr', '123'])
        self.cur.execute("SELECT id_сотрудника FROM сотрудники WHERE login='mgr'")
        mgr_id = self.cur.fetchone()[0]

        # 3. Create Order
        # sp_create_order(client, manager, date) -> (status, msg, id)
        res_order = self.call_proc('sp_create_order', [client_id, mgr_id, '2025-01-01'])
        self.assertEqual(res_order[0], 'OK')
        order_id = res_order[2]
        self.assertTrue(order_id > 0)

        # 4. Search Orders
        # sp_search_orders(mgr_id, text, status, d1, d2)
        # Note: sp_search_orders returns TABLE, so use execute/fetchall
        self.cur.execute("SELECT * FROM sp_search_orders(%s, %s, %s, %s, %s)", (mgr_id, None, 'Все статусы', None, None))
        rows = self.cur.fetchall()
        # Should find at least our order
    def test_exceptions(self):
        """Проверка обработки исключений и пограничных случаев"""
        
        # 1. Login Failure
        res = self.call_proc('sp_login', ['non_existent', '123'])
        self.assertEqual(res[0], 'ERROR')
        self.assertEqual(res[1], 'Пользователь не найден')

        # Create user for password test
        self.call_proc('sp_hire_employee', ['Test User', '555000', '1990-01-01', 'менеджер', 50000, 'test_user', 'pass'])
        res = self.call_proc('sp_login', ['test_user', 'wrong_pass'])
        self.assertEqual(res[0], 'ERROR')
        self.assertEqual(res[1], 'Неверный пароль')

        # 2. Hiring Exceptions
        # Underage (Age < 18)
        # Assuming current date is 2026, 2010 birthdate = 16 years old
        res = self.call_proc('sp_hire_employee', ['Kid', '111', '2015-01-01', 'сборщик', 20000, 'kid', '123'])
        self.assertEqual(res[0], 'ERROR')
        self.assertIn('Сотрудник должен быть совершеннолетним', res[1])

        # Duplicate Login/Phone
        # Create user first
        self.call_proc('sp_hire_employee', ['Unique', '777', '1990-01-01', 'сборщик', 30000, 'unique', '123'])
        # Try diff name, same login
        res = self.call_proc('sp_hire_employee', ['Copy', '778', '1990-01-01', 'сборщик', 30000, 'unique', '123'])
        self.assertEqual(res[0], 'ERROR')
        self.assertIn('Логин или телефон уже занят', res[1])

        # 3. Order Item Stock Warning
        # Need an order and a product
        self.cur.execute("SELECT id_сотрудника FROM сотрудники LIMIT 1")
        mgr_id = self.cur.fetchone()[0]
        self.cur.execute("SELECT id_клиента FROM клиенты LIMIT 1")
        client_id = self.cur.fetchone()[0]
        
        # Use existing product and update stock
        self.cur.execute("SELECT id_изделия FROM изделия LIMIT 1")
        prod_id = self.cur.fetchone()[0]
        self.cur.execute("UPDATE изделия SET количество_на_складе = 2 WHERE id_изделия = %s", (prod_id,))
        
        # Create Order
        res_order = self.call_proc('sp_create_order', [client_id, mgr_id, '2026-02-01'])
        order_id = res_order[2]
        
        # Add 5 items (Stock is 2)
        res_add = self.call_proc('sp_add_order_item', [order_id, prod_id, 5])
        self.assertEqual(res_add[0], 'WARNING')
        self.assertIn('Недостаточно на складе', res_add[1])
        
        # Verify Production Tasks created
        self.cur.execute("SELECT count(*) FROM план_заготовок WHERE id_заказа = %s", (order_id,))
        count = self.cur.fetchone()[0]
        # Should be > 0 if components exist, checking stock update to 0
        self.cur.execute("SELECT количество_на_складе FROM изделия WHERE id_изделия=%s", (prod_id,))
        new_stock = self.cur.fetchone()[0]
        self.assertEqual(new_stock, 0)

if __name__ == '__main__':
    with open('tests/results.txt', 'w') as f:
        runner = unittest.TextTestRunner(stream=f, verbosity=2)
        unittest.main(testRunner=runner, exit=False)
