import os
import sys

import psycopg2
from psycopg2.extras import RealDictCursor

                          
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config


class Database:
    """Класс-обертка для работы с БД"""

    @staticmethod
    def connect():
        return psycopg2.connect(config.DATABASE_URL)

    @staticmethod
    def call_procedure(proc_name, params=None):
        """
        Вызывает хранимую процедуру и возвращает стандартный ответ:
        {status: 'OK'|'ERROR', message: '...', ...data}
        """
        conn = None
        try:
            conn = Database.connect()
            cur = conn.cursor(cursor_factory=RealDictCursor)
            
                                                            
                                                    
            placeholders = ",".join(["%s"] * len(params)) if params else ""
            query = f"SELECT * FROM {proc_name}({placeholders})"
            
            cur.execute(query, params)
            result = cur.fetchone()
            
            conn.commit()                                                  
            cur.close()
            
            if result:
                return dict(result)
            return {"status": "ERROR", "message": "Процедура ничего не вернула"}

        except Exception as e:
            if conn:
                conn.rollback()
            return {"status": "ERROR", "message": f"Ошибка соединения: {str(e)}"}
        finally:
            if conn:
                conn.close()

    @staticmethod
    def fetch_all(query, params=None):
        """Выполняет SELECT и возвращает список словарей"""
        conn = None
        try:
            conn = Database.connect()
            cur = conn.cursor(cursor_factory=RealDictCursor)
            cur.execute(query, params)
            result = cur.fetchall()
            cur.close()
            return result
        except Exception as e:
            print(f"❌ Ошибка БД (fetch_all): {e}")
            return []
        finally:
            if conn:
                conn.close()

                                                                         
    @staticmethod
    def insert_returning(query, params=None):
        return Database.fetch_one(query, params)                                                 

    @staticmethod
    def execute(query, params=None):
        """
        [DEPRECATED] Direct SQL execution.
        Use call_procedure for logic.
        """
        conn = None
        try:
            conn = Database.connect()
            cur = conn.cursor()
            cur.execute(query, params)
            conn.commit()
            cur.close()
            return True, "Успешно"
        except Exception as e:
            if conn:
                conn.rollback()
            return False, str(e)
        finally:
            if conn:
                conn.close()

    @staticmethod
    def fetch_one(query, params=None):
        """Возвращает одну строку"""
        conn = None
        try:
            conn = Database.connect()
            cur = conn.cursor(cursor_factory=RealDictCursor)
            cur.execute(query, params)
            result = cur.fetchone()
                                                               
            if query.strip().upper().startswith("INSERT") or query.strip().upper().startswith("UPDATE"):
                conn.commit()
            
            cur.close()
            return result
        except Exception as e:
            print(f"❌ Ошибка БД (fetch_one): {e}")
            return None
        finally:
            if conn:
                conn.close()

    @staticmethod
    def create_order_transaction(client_id, manager_id, deadline, cart_items):
        """Creates an order and all its items in a single transaction."""
        conn = None
        try:
            conn = Database.connect()
            cur = conn.cursor(cursor_factory=RealDictCursor)
            
            # Step 1: Create Order
            cur.execute("SELECT * FROM sp_create_order(%s, %s, %s)", (client_id, manager_id, deadline))
            res_order = cur.fetchone()
            
            if not res_order or res_order.get('status') != 'OK':
                conn.rollback()
                return {"status": "ERROR", "message": res_order.get('message', 'Ошибка создания заказа') if res_order else "Нет ответа"}
                
            order_id = res_order.get('id_заказа')
            warnings = []
            
            # Step 2: Add Products
            for item in cart_items:
                cur.execute("SELECT * FROM sp_add_product_to_order_smart(%s, %s, %s, %s)", 
                            (order_id, item["id"], item["qty"], deadline))
                res_item = cur.fetchone()
                
                if not res_item:
                    conn.rollback()
                    return {"status": "ERROR", "message": f"Ошибка добавления {item['name']}"}
                    
                status = res_item.get('status')
                msg = res_item.get('message', '')
                
                if status == 'ERROR':
                    # Crucial: Rollback everything if any item fails
                    conn.rollback()
                    return {"status": "ERROR", "message": f"Не удалось добавить '{item['name']}': {msg}"}
                elif status == 'WARNING':
                    warnings.append(f"- {item['name']}: {msg}")
                elif msg and 'задач' in msg.lower():
                    warnings.append(f"🔧 {item['name']}: {msg}")
            
            # If we reached here, everything succeeded
            conn.commit()
            return {"status": "OK", "id_заказа": order_id, "warnings": warnings}
            
        except Exception as e:
            if conn:
                conn.rollback()
            return {"status": "ERROR", "message": f"Ошибка транзакции: {str(e)}"}
        finally:
            if conn:
                conn.close()
