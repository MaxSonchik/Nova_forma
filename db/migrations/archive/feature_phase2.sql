-- Phase 2: Schedule Blocking, Nomenclature, Order Flow, Production Planning
-- ==========================================================================
-- 1. LOGIN WITH SCHEDULE CHECK
DROP FUNCTION IF EXISTS sp_login(VARCHAR, VARCHAR);
CREATE OR REPLACE FUNCTION sp_login(p_login VARCHAR, p_password VARCHAR) RETURNS TABLE (
        status VARCHAR,
        message VARCHAR,
        user_id INTEGER,
        role VARCHAR,
        fio VARCHAR
    ) LANGUAGE plpgsql AS $$
DECLARE rec RECORD;
v_schedule_status VARCHAR;
BEGIN -- Find user
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
-- Check password
IF NOT (
    rec.password_hash = crypt(p_password, rec.password_hash)
) THEN status := 'ERROR';
message := 'Неверный пароль';
RETURN NEXT;
RETURN;
END IF;
-- Check schedule for today
SELECT g.статус INTO v_schedule_status
FROM график_работы g
WHERE g.id_сотрудника = rec.id_сотрудника
    AND g.дата = CURRENT_DATE;
-- If schedule record exists and it's NOT 'рабочий', block login
IF FOUND
AND v_schedule_status IS NOT NULL
AND v_schedule_status != 'рабочий' THEN status := 'ERROR';
message := 'Доступ запрещен: ' || v_schedule_status;
RETURN NEXT;
RETURN;
END IF;
-- Success
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
-- 2. NOMENCLATURE: Update Product
DROP FUNCTION IF EXISTS sp_update_product(INTEGER, VARCHAR, NUMERIC);
CREATE OR REPLACE FUNCTION sp_update_product(
        p_id_product INTEGER,
        p_name VARCHAR,
        p_price NUMERIC
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE изделия
SET наименование = p_name,
    стоимость = p_price
WHERE id_изделия = p_id_product;
IF NOT FOUND THEN status := 'ERROR';
message := 'Изделие не найдено';
ELSE status := 'OK';
message := 'Изделие обновлено';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 3. NOMENCLATURE: Get Product Components
DROP FUNCTION IF EXISTS sp_get_product_components(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_product_components(p_id_product INTEGER) RETURNS TABLE (
        id_заготовки INTEGER,
        наименование VARCHAR,
        количество INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.id_заготовки,
    z.наименование::VARCHAR,
    si.количество_заготовок
FROM состав_изделия si
    JOIN заготовки z ON si.id_заготовки = z.id_заготовки
WHERE si.id_изделия = p_id_product
ORDER BY z.наименование;
END;
$$;
-- 4. ORDER WORKFLOW: Update Status with validation
DROP FUNCTION IF EXISTS sp_update_order_status(INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_update_order_status(
        p_order_id INTEGER,
        p_new_status VARCHAR
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_status VARCHAR;
BEGIN
SELECT статус INTO v_current_status
FROM заказы
WHERE id_заказа = p_order_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Заказ не найден';
RETURN NEXT;
RETURN;
END IF;
-- Validate transitions
IF p_new_status = 'в_работе'
AND v_current_status != 'принят' THEN status := 'ERROR';
message := 'Нельзя перевести в работу. Текущий статус: ' || v_current_status;
RETURN NEXT;
RETURN;
END IF;
IF p_new_status = 'выполнен'
AND v_current_status != 'в_работе' THEN status := 'ERROR';
message := 'Нельзя завершить. Заказ должен быть в работе. Текущий: ' || v_current_status;
RETURN NEXT;
RETURN;
END IF;
IF p_new_status = 'отгружен'
AND v_current_status != 'выполнен' THEN status := 'ERROR';
message := 'Нельзя отгрузить. Заказ не готов. Текущий: ' || v_current_status;
RETURN NEXT;
RETURN;
END IF;
-- Perform update
UPDATE заказы
SET статус = p_new_status
WHERE id_заказа = p_order_id;
status := 'OK';
message := 'Статус изменен на: ' || p_new_status;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 5. PRODUCTION PLAN: Get Full View
DROP FUNCTION IF EXISTS sp_get_production_plan_full();
CREATE OR REPLACE FUNCTION sp_get_production_plan_full() RETURNS TABLE (
        id_плана INTEGER,
        заготовка VARCHAR,
        плановое_количество INTEGER,
        фактическое_количество INTEGER,
        дедлайн DATE,
        статус VARCHAR,
        сборщик VARCHAR,
        id_заказа INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT pz.id_плана,
    z.наименование::VARCHAR AS заготовка,
    pz.плановое_количество,
    pz.фактическое_количество,
    pz.дата_план::DATE AS дедлайн,
    pz.статус::VARCHAR,
    COALESCE(s.фио, 'Не назначен')::VARCHAR AS сборщик,
    pz.id_заказа
FROM план_заготовок pz
    JOIN заготовки z ON pz.id_заготовки = z.id_заготовки
    LEFT JOIN сотрудники s ON pz.id_сборщика = s.id_сотрудника
ORDER BY pz.дата_план,
    pz.id_плана;
END;
$$;
-- 6. PRODUCTION PLAN: Assign Worker
DROP FUNCTION IF EXISTS sp_assign_worker_to_task(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_assign_worker_to_task(p_plan_id INTEGER, p_worker_id INTEGER) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_worker_load INTEGER;
BEGIN -- Check worker's current load (optional: warn if high)
SELECT COUNT(*) INTO v_worker_load
FROM план_заготовок
WHERE id_сборщика = p_worker_id
    AND статус = 'в_работе';
UPDATE план_заготовок
SET id_сборщика = p_worker_id
WHERE id_плана = p_plan_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
RETURN NEXT;
RETURN;
END IF;
IF v_worker_load >= 3 THEN status := 'WARNING';
message := 'Сборщик назначен. Внимание: у него уже ' || v_worker_load || ' активных задач!';
ELSE status := 'OK';
message := 'Сборщик назначен';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 7. PRODUCTION PLAN: Add Manual Task
DROP FUNCTION IF EXISTS sp_add_manual_component_task(INTEGER, INTEGER, INTEGER, DATE);
CREATE OR REPLACE FUNCTION sp_add_manual_component_task(
        p_order_id INTEGER,
        p_component_id INTEGER,
        p_qty INTEGER,
        p_deadline DATE DEFAULT NULL
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_deadline DATE;
BEGIN IF p_deadline IS NULL THEN
SELECT дата_готовности - INTERVAL '1 day' INTO v_deadline
FROM заказы
WHERE id_заказа = p_order_id;
ELSE v_deadline := p_deadline;
END IF;
INSERT INTO план_заготовок (
        id_заказа,
        id_заготовки,
        плановое_количество,
        дата_план,
        статус
    )
VALUES (
        p_order_id,
        p_component_id,
        p_qty,
        v_deadline,
        'принято'
    );
status := 'OK';
message := 'Задача добавлена в план';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 8. HELPER: Get Workers (for dropdown)
DROP FUNCTION IF EXISTS sp_get_workers();
CREATE OR REPLACE FUNCTION sp_get_workers() RETURNS TABLE (
        id_сотрудника INTEGER,
        фио VARCHAR,
        должность VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT s.id_сотрудника,
    s.фио::VARCHAR,
    s.должность::VARCHAR
FROM сотрудники s
WHERE s.должность = 'сборщик'
ORDER BY s.фио;
END;
$$;
-- 9. HELPER: Get Components (for dropdown)
DROP FUNCTION IF EXISTS sp_get_components();
CREATE OR REPLACE FUNCTION sp_get_components() RETURNS TABLE (id_заготовки INTEGER, наименование VARCHAR) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.id_заготовки,
    z.наименование::VARCHAR
FROM заготовки z
ORDER BY z.наименование;
END;
$$;