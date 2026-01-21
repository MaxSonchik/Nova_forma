-- Enable pgcrypto
CREATE EXTENSION IF NOT EXISTS pgcrypto;
-- 1. AUTH
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
FROM сотрудники
WHERE login = p_login;
IF NOT FOUND THEN status := 'ERROR';
message := 'Пользователь не найден';
RETURN NEXT;
RETURN;
END IF;
IF (
    rec.password_hash = crypt(p_password, rec.password_hash)
) THEN status := 'OK';
message := 'Успешный вход';
user_id := rec.id_сотрудника;
role := rec.должность;
fio := rec.фио;
RETURN NEXT;
ELSE status := 'ERROR';
message := 'Неверный пароль';
RETURN NEXT;
END IF;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка БД: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 2. ORDERS SEARCH
DROP FUNCTION IF EXISTS sp_search_orders(INTEGER, VARCHAR, VARCHAR, DATE, DATE);
CREATE OR REPLACE FUNCTION sp_search_orders(
        p_manager_id INTEGER,
        p_search_text VARCHAR DEFAULT NULL,
        p_status VARCHAR DEFAULT 'Все статусы',
        p_date_from DATE DEFAULT NULL,
        p_date_to DATE DEFAULT NULL
    ) RETURNS TABLE (
        id_заказа INTEGER,
        клиент VARCHAR,
        менеджер VARCHAR,
        дата_заказа DATE,
        дата_готовности DATE,
        статус_заказа VARCHAR,
        сумма_заказа NUMERIC,
        позиций_в_заказе BIGINT,
        состояние_сроков TEXT
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.id_заказа,
    z.клиент::VARCHAR,
    z.менеджер::VARCHAR,
    z.дата_заказа,
    z.дата_готовности,
    z.статус::VARCHAR,
    z.сумма_заказа::NUMERIC,
    z.позиций_в_заказе,
    z.состояние_сроков
FROM v_заказы_менеджер z
WHERE (
        p_search_text IS NULL
        OR CASE
            WHEN p_search_text ~ '^[0-9]+$' THEN z.id_заказа = p_search_text::INTEGER
            ELSE LOWER(z.клиент) LIKE '%' || LOWER(p_search_text) || '%'
        END
    )
    AND (
        p_status IS NULL
        OR p_status = 'Все статусы'
        OR (
            p_status = 'ПРОСРОЧЕН'
            AND z.состояние_сроков = 'ПРОСРОЧЕН'
        )
        OR (z.статус = p_status)
    )
    AND (
        p_date_from IS NULL
        OR z.дата_заказа >= p_date_from
    )
    AND (
        p_date_to IS NULL
        OR z.дата_заказа <= p_date_to
    )
ORDER BY z.id_заказа DESC;
END;
$$;
-- 3. CREATE ORDER
DROP FUNCTION IF EXISTS sp_create_order(INTEGER, INTEGER, DATE);
CREATE OR REPLACE FUNCTION sp_create_order(
        p_client_id INTEGER,
        p_manager_id INTEGER,
        p_date_ready DATE
    ) RETURNS TABLE (
        status VARCHAR,
        message VARCHAR,
        new_order_id INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE v_id INTEGER;
BEGIN
INSERT INTO заказы (
        id_клиента,
        id_менеджера,
        дата_готовности,
        статус
    )
VALUES (
        p_client_id,
        p_manager_id,
        p_date_ready,
        'принят'
    )
RETURNING id_заказа INTO v_id;
status := 'OK';
message := 'Заказ создан';
new_order_id := v_id;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка создания заказа: ' || SQLERRM;
new_order_id := NULL;
RETURN NEXT;
END;
$$;
-- 4. ADD ITEM
DROP FUNCTION IF EXISTS sp_add_order_item(INTEGER, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS sp_добавить_изделие_в_заказ(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_add_order_item(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_stock INTEGER;
v_price NUMERIC;
v_missing INTEGER;
rec RECORD;
v_date_ready DATE;
BEGIN
SELECT стоимость,
    количество_на_складе INTO v_price,
    v_stock
FROM изделия
WHERE id_изделия = p_product_id;
INSERT INTO состав_заказа (
        id_заказа,
        id_изделия,
        количество_изделий,
        цена_фиксированная
    )
VALUES (p_order_id, p_product_id, p_qty, v_price);
SELECT дата_готовности INTO v_date_ready
FROM заказы
WHERE id_заказа = p_order_id;
IF v_stock >= p_qty THEN
UPDATE изделия
SET количество_на_складе = количество_на_складе - p_qty
WHERE id_изделия = p_product_id;
status := 'OK';
message := 'Изделия зарезервированы со склада.';
ELSE v_missing := p_qty - v_stock;
IF v_stock > 0 THEN
UPDATE изделия
SET количество_на_складе = 0
WHERE id_изделия = p_product_id;
END IF;
FOR rec IN
SELECT id_заготовки,
    количество_заготовок
FROM состав_изделия
WHERE id_изделия = p_product_id LOOP
INSERT INTO план_заготовок (
        id_заказа,
        id_заготовки,
        плановое_количество,
        дата_план,
        статус
    )
VALUES (
        p_order_id,
        rec.id_заготовки,
        rec.количество_заготовок * v_missing,
        v_date_ready - INTERVAL '1 day',
        'принято'
    );
END LOOP;
status := 'WARNING';
message := 'Недостаточно на складе. Созданы задания на производство ' || v_missing || ' ед.';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка добавления позиции: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 5. SAVE CLIENT
DROP FUNCTION IF EXISTS sp_save_client(INTEGER, VARCHAR, VARCHAR, INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_save_client(
        p_id_client INTEGER,
        p_fio VARCHAR,
        p_phone VARCHAR,
        p_inn INTEGER,
        p_address VARCHAR
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN IF p_id_client IS NOT NULL THEN
UPDATE клиенты
SET фио = p_fio,
    номер_телефона = p_phone,
    инн = p_inn,
    адрес = p_address
WHERE id_клиента = p_id_client;
message := 'Данные клиента обновлены!';
ELSE
INSERT INTO клиенты (фио, номер_телефона, инн, адрес)
VALUES (p_fio, p_phone, p_inn, p_address);
message := 'Новый клиент создан!';
END IF;
status := 'OK';
RETURN NEXT;
EXCEPTION
WHEN unique_violation THEN status := 'ERROR';
message := 'Клиент с таким телефоном уже существует!';
RETURN NEXT;
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка сохранения клиента: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 6. HIRE EMPLOYEE
DROP FUNCTION IF EXISTS sp_hire_employee(
    VARCHAR,
    VARCHAR,
    DATE,
    VARCHAR,
    INTEGER,
    VARCHAR,
    VARCHAR
);
CREATE OR REPLACE FUNCTION sp_hire_employee(
        p_fio VARCHAR,
        p_phone VARCHAR,
        p_birth DATE,
        p_role VARCHAR,
        p_salary INTEGER,
        p_login VARCHAR,
        p_password VARCHAR
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
INSERT INTO сотрудники (
        фио,
        номер_телефона,
        дата_рождения,
        должность,
        зарплата,
        дата_найма,
        login,
        password_hash
    )
VALUES (
        p_fio,
        p_phone,
        p_birth,
        p_role,
        p_salary,
        CURRENT_DATE,
        p_login,
        crypt(p_password, gen_salt('bf'))
    );
status := 'OK';
message := 'Сотрудник нанят!';
RETURN NEXT;
EXCEPTION
WHEN unique_violation THEN status := 'ERROR';
message := 'Логин или телефон уже занят!';
RETURN NEXT;
WHEN check_violation THEN status := 'ERROR';
message := 'Нарушение ограничений (возраст и т.д.): ' || SQLERRM;
RETURN NEXT;
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 7. DICTIONARIES
DROP FUNCTION IF EXISTS sp_get_clients();
CREATE OR REPLACE FUNCTION sp_get_clients() RETURNS TABLE (id_клиента INTEGER, фио VARCHAR) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT k.id_клиента,
    k.фио::VARCHAR
FROM клиенты k
ORDER BY k.фио;
END;
$$;
DROP FUNCTION IF EXISTS sp_get_products();
CREATE OR REPLACE FUNCTION sp_get_products() RETURNS TABLE (
        id_изделия INTEGER,
        наименование VARCHAR,
        стоимость NUMERIC,
        количество_на_складе INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT i.id_изделия,
    i.наименование::VARCHAR,
    i.стоимость,
    i.количество_на_складе
FROM изделия i
ORDER BY i.наименование;
END;
$$;