


ALTER TABLE IF EXISTS сотрудники
    RENAME TO Сотрудник;
ALTER TABLE IF EXISTS клиенты
    RENAME TO Клиент;
ALTER TABLE IF EXISTS заказы
    RENAME TO Заказ;
ALTER TABLE IF EXISTS изделия
    RENAME TO Изделие;
ALTER TABLE IF EXISTS материалы
    RENAME TO Материал;
ALTER TABLE IF EXISTS закупки_материалов
    RENAME TO Закупка;
ALTER TABLE IF EXISTS состав_закупки
    RENAME TO СоставЗакупки;
ALTER TABLE IF EXISTS состав_заказа
    RENAME TO СоставЗаказа;
ALTER TABLE IF EXISTS график_работы
    RENAME TO График;

DROP FUNCTION IF EXISTS sp_login(VARCHAR, VARCHAR);
CREATE OR REPLACE FUNCTION sp_login(p_login VARCHAR, p_password VARCHAR) RETURNS TABLE (
        status VARCHAR,
        message VARCHAR,
        user_id INTEGER,
        role VARCHAR,
        fio VARCHAR
    ) LANGUAGE plpgsql AS $$
DECLARE rec RECORD;
BEGIN 
SELECT id_сотрудника,
    password_hash,
    должность,
    фио INTO rec
FROM Сотрудник
WHERE login = p_login;
IF NOT FOUND THEN status := 'ERROR';
message := 'Пользователь не найден';
RETURN NEXT;
RETURN;
END IF;

IF NOT (
    rec.password_hash = crypt(p_password, rec.password_hash)
) THEN status := 'ERROR';
message := 'Неверный пароль';
RETURN NEXT;
RETURN;
END IF;

status := 'OK';
message := 'Успешный вход';
user_id := rec.id_сотрудника;
role := rec.должность;
fio := rec.фио;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка БД: ' || SQLERRM;
RETURN NEXT;
END;
$$;