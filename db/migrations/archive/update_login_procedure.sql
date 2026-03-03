
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
IF NOT FOUND THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    'Пользователь не найден'::VARCHAR,
    NULL::INTEGER,
    NULL::VARCHAR,
    NULL::VARCHAR;
RETURN;
END IF;

IF NOT (
    rec.password_hash = crypt(p_password, rec.password_hash)
) THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    'Неверный пароль'::VARCHAR,
    NULL::INTEGER,
    NULL::VARCHAR,
    NULL::VARCHAR;
RETURN;
END IF;

RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Успешный вход'::VARCHAR,
    rec.id_сотрудника,
    rec.должность,
    rec.фио;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    'Ошибка БД: ' || SQLERRM,
    NULL::INTEGER,
    NULL::VARCHAR,
    NULL::VARCHAR;
END;
$$;