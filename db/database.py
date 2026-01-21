import os
import sys

import psycopg2
from psycopg2.extras import RealDictCursor

# Добавляем путь к конфигу
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
            
            # Формируем SQL: SELECT * FROM proc_name(%s, %s)
            # Если params пустой, просто proc_name()
            placeholders = ",".join(["%s"] * len(params)) if params else ""
            query = f"SELECT * FROM {proc_name}({placeholders})"
            
            cur.execute(query, params)
            result = cur.fetchone()
            
            conn.commit() # Важно закоммитить, если процедура меняет данные
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

    # Legacy methods for compatibility, but we should move away from them
    @staticmethod
    def insert_returning(query, params=None):
        return Database.fetch_one(query, params) # Just wrapper if needed, but logic is different

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
            # Если это insert/update returning, надо коммитить!
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
