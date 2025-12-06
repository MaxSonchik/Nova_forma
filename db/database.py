import psycopg2
from psycopg2.extras import RealDictCursor
import sys
import os

# Добавляем путь к конфигу
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config

class Database:
    """Класс-обертка для работы с БД"""
    
    @staticmethod
    def connect():
        return psycopg2.connect(config.DATABASE_URL)

    @staticmethod
    def fetch_all(query, params=None):
        """Выполняет SELECT и возвращает список словарей"""
        conn = None
        try:
            conn = Database.connect()
            # RealDictCursor позволяет обращаться к полям по имени (row['id'])
            cur = conn.cursor(cursor_factory=RealDictCursor)
            cur.execute(query, params)
            result = cur.fetchall()
            cur.close()
            return result
        except Exception as e:
            print(f"❌ Ошибка БД (fetch_all): {e}")
            return []
        finally:
            if conn: conn.close()

    @staticmethod
    def execute(query, params=None):
        """Выполняет INSERT, UPDATE, DELETE, CALL"""
        conn = None
        try:
            conn = Database.connect()
            cur = conn.cursor()
            cur.execute(query, params)
            conn.commit()
            cur.close()
            return True, "Успешно"
        except Exception as e:
            if conn: conn.rollback()
            error_msg = str(e).split('\n')[0] # Берем первую строку ошибки
            print(f"❌ Ошибка БД (execute): {error_msg}")
            return False, error_msg
        finally:
            if conn: conn.close()

    @staticmethod
    def fetch_one(query, params=None):
        """Возвращает одну строку"""
        conn = None
        try:
            conn = Database.connect()
            cur = conn.cursor(cursor_factory=RealDictCursor)
            cur.execute(query, params)
            result = cur.fetchone()
            cur.close()
            return result
        except Exception as e:
            print(f"❌ Ошибка БД (fetch_one): {e}")
            return None
        finally:
            if conn: conn.close()