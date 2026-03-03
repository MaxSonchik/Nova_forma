import unittest
import sys
import os
import psycopg2
from decimal import Decimal

with open('test_launch.log', 'w') as f:
    f.write("Launched\n")

                                              
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config

class TestDBProcedures(unittest.TestCase):
    
    @classmethod
    def setUpClass(cls):
        cls.conn = psycopg2.connect(config.DATABASE_URL)
        cls.conn.autocommit = False                           
        cls.cur = cls.conn.cursor()

    @classmethod
    def tearDownClass(cls):
        cls.conn.close()

    def tearDown(self):
                                                   
        self.conn.rollback()

    def call_proc(self, name, args):
        placeholders = ",".join(["%s"] * len(args))
        query = f"SELECT * FROM {name}({placeholders})"
        self.cur.execute(query, args)
        return self.cur.fetchone()

    def test_dicts(self):
                                                                                                                  
                                                                          
        self.cur.execute("SELECT * FROM sp_get_clients()")
        clients = self.cur.fetchall()
        self.assertIsInstance(clients, list)
        
        self.cur.execute("SELECT * FROM sp_get_products()")
        products = self.cur.fetchall()
        self.assertIsInstance(products, list)

    def test_hire_employee(self):
                     
                                                                            
        res_list = self.call_proc('sp_hire_employee', ['Test User', '9999999999', '1990-01-01', 'менеджер', 50000, 'test_user', 'pass'])
                                              
                                  
        status, msg = res_list
        self.assertEqual(status, 'OK')
        
                                  
                                                                   
        res_login = self.call_proc('sp_login', ['test_user', 'pass'])
        self.assertEqual(res_login[0], 'OK')
        self.assertEqual(res_login[3], 'менеджер')

                             
        res_login_bad = self.call_proc('sp_login', ['test_user', 'wrong'])
        self.assertEqual(res_login_bad[0], 'ERROR')

    def test_client_and_order_flow(self):
                          
                                                      
        self.cur.execute("SELECT * FROM sp_save_client(%s, %s, %s, %s, %s)", (None, 'Test Client', '70000001', 123, 'Addr'))
        res_save = self.cur.fetchone()
        self.assertEqual(res_save[0], 'OK')
        
                                                                                                  
                                          
        self.cur.execute("SELECT id_клиента FROM Клиент WHERE номер_телефона = '70000001'")
        client_id = self.cur.fetchone()[0]

                                                     
                                                                                                             
                                
        self.call_proc('sp_hire_employee', ['Mgr', '8888', '1990-01-01', 'менеджер', 50000, 'mgr', '123'])
        self.cur.execute("SELECT id_сотрудника FROM Сотрудник WHERE login='mgr'")
        mgr_id = self.cur.fetchone()[0]

                         
                                                                     
        res_order = self.call_proc('sp_create_order', [client_id, mgr_id, '2025-01-01'])
        self.assertEqual(res_order[0], 'OK')
        order_id = res_order[2]
        self.assertTrue(order_id > 0)

                          
                                                        
                                                                       
        self.cur.execute("SELECT * FROM sp_search_orders(%s, %s, %s, %s, %s)", (mgr_id, None, 'Все статусы', None, None))
        rows = self.cur.fetchall()
                                        
    def test_exceptions(self):
        """Проверка обработки исключений и пограничных случаев"""
        
                          
        res = self.call_proc('sp_login', ['non_existent', '123'])
        self.assertEqual(res[0], 'ERROR')
        self.assertEqual(res[1], 'Пользователь не найден')

                                       
        self.call_proc('sp_hire_employee', ['Test User', '555000', '1990-01-01', 'менеджер', 50000, 'test_user', 'pass'])
        res = self.call_proc('sp_login', ['test_user', 'wrong_pass'])
        self.assertEqual(res[0], 'ERROR')
        self.assertEqual(res[1], 'Неверный пароль')

                              
                             
                                                                      
        res = self.call_proc('sp_hire_employee', ['Kid', '111', '2015-01-01', 'сборщик', 20000, 'kid', '123'])
        self.assertEqual(res[0], 'ERROR')
        self.assertIn('Сотрудник должен быть совершеннолетним', res[1])

                               
                           
        self.call_proc('sp_hire_employee', ['Unique', '777', '1990-01-01', 'сборщик', 30000, 'unique', '123'])
                                   
        res = self.call_proc('sp_hire_employee', ['Copy', '778', '1990-01-01', 'сборщик', 30000, 'unique', '123'])
        self.assertEqual(res[0], 'ERROR')
        self.assertIn('Логин или телефон уже занят', res[1])

                                     
                                     
        self.cur.execute("SELECT id_сотрудника FROM Сотрудник LIMIT 1")
        mgr_id = self.cur.fetchone()[0]
        self.cur.execute("SELECT id_клиента FROM Клиент LIMIT 1")
        client_id = self.cur.fetchone()[0]
        
                                               
        self.cur.execute("SELECT id_изделия FROM Изделие LIMIT 1")
        prod_id = self.cur.fetchone()[0]
        self.cur.execute("UPDATE Изделие SET количество_на_складе = 2 WHERE id_изделия = %s", (prod_id,))
        
                      
        res_order = self.call_proc('sp_create_order', [client_id, mgr_id, '2026-02-01'])
        order_id = res_order[2]
        
                                  
        res_add = self.call_proc('sp_add_order_item', [order_id, prod_id, 5])
        self.assertEqual(res_add[0], 'WARNING')
        self.assertIn('Недостаточно на складе', res_add[1])
        
                                         
        self.cur.execute("SELECT count(*) FROM ПланЗаготовок WHERE id_заказа = %s", (order_id,))
        count = self.cur.fetchone()[0]
                                                                       
        self.cur.execute("SELECT количество_на_складе FROM Изделие WHERE id_изделия=%s", (prod_id,))
        new_stock = self.cur.fetchone()[0]
        self.assertEqual(new_stock, 0)

if __name__ == '__main__':
    with open('tests/results.txt', 'w') as f:
        runner = unittest.TextTestRunner(stream=f, verbosity=2)
        unittest.main(testRunner=runner, exit=False)
