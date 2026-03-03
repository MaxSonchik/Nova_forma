DROP FUNCTION IF EXISTS sp_complete_task(INTEGER, INTEGER);
DROP FUNCTION IF EXISTS sp_add_product_to_order_smart(INTEGER, INTEGER, INTEGER, DATE);
DROP FUNCTION IF EXISTS sp_get_order_items(INTEGER);
DROP FUNCTION IF EXISTS sp_update_order_status(INTEGER, VARCHAR);
DROP FUNCTION IF EXISTS sp_get_product_components_status(INTEGER, INTEGER);
DROP TRIGGER IF EXISTS tr_check_order_ready ON "ПланЗаготовок";
DROP FUNCTION IF EXISTS sp_check_order_ready();
DROP ROUTINE IF EXISTS sp_take_component_task(INTEGER, INTEGER, INTEGER);
DROP ROUTINE IF EXISTS sp_submit_component_work(INTEGER, INTEGER, INTEGER, INTEGER);
DROP ROUTINE IF EXISTS sp_get_worker_tasks(INTEGER);
DROP FUNCTION IF EXISTS sp_get_order_tasks(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_order_items(p_order_id INTEGER) RETURNS TABLE (
        id_изделия INTEGER,
        наименование VARCHAR,
        количество INTEGER,
        цена NUMERIC,
        сумма NUMERIC
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT sz.id_изделия,
    i.наименование,
    COALESCE(sz.количество_изделий, 0) AS количество,
    COALESCE(i.стоимость, 0) AS цена,
    (
        COALESCE(sz.количество_изделий, 0) * COALESCE(i.стоимость, 0)
    ) AS сумма
FROM СоставЗаказа sz
    JOIN Изделие i ON sz.id_изделия = i.id_изделия
WHERE sz.id_заказа = p_order_id;
END;
$$;
CREATE OR REPLACE FUNCTION sp_update_order_status(p_order_id INTEGER, p_new_status VARCHAR) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_status VARCHAR;
v_pending_tasks INTEGER;
BEGIN
SELECT s.статус INTO v_current_status
FROM Заказ s
WHERE s.id_заказа = p_order_id;
IF v_current_status IS NULL THEN status := 'ERROR';
message := 'Заказ не найден';
RETURN NEXT;
RETURN;
END IF;
IF v_current_status = 'отгружен' THEN status := 'ERROR';
message := 'Нельзя изменить статус отгруженного заказа';
RETURN NEXT;
RETURN;
END IF;
IF p_new_status = 'завершен' THEN
SELECT COUNT(*) INTO v_pending_tasks
FROM "ПланЗаготовок"
WHERE id_заказа = p_order_id
    AND статус != 'выполнено';
IF v_pending_tasks > 0 THEN status := 'ERROR';
message := 'Нельзя отметить готовым: есть незавершенные задачи (' || v_pending_tasks || ')';
RETURN NEXT;
RETURN;
END IF;
END IF;
IF v_current_status = 'завершен'
AND p_new_status = 'в_работе' THEN
UPDATE Заказ
SET статус = p_new_status
WHERE id_заказа = p_order_id;
status := 'OK';
message := 'Брак зафиксирован. Заказ возвращен в работу.';
RETURN NEXT;
RETURN;
END IF;
UPDATE Заказ
SET статус = p_new_status
WHERE id_заказа = p_order_id;
status := 'OK';
message := 'Статус обновлен';
RETURN NEXT;
END;
$$;
CREATE OR REPLACE FUNCTION sp_add_product_to_order_smart(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER,
        p_deadline DATE
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE r RECORD;
v_needed_qty INTEGER;
v_stock_qty INTEGER;
v_missing_qty INTEGER;
v_components_added INTEGER := 0;
v_price NUMERIC;
BEGIN
SELECT стоимость INTO v_price
FROM Изделие
WHERE id_изделия = p_product_id;
IF EXISTS (
    SELECT 1
    FROM СоставЗаказа
    WHERE id_заказа = p_order_id
        AND id_изделия = p_product_id
) THEN
UPDATE СоставЗаказа
SET количество_изделий = количество_изделий + p_qty
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
ELSE
INSERT INTO СоставЗаказа (
        id_заказа,
        id_изделия,
        количество_изделий,
        цена_фиксированная
    )
VALUES (
        p_order_id,
        p_product_id,
        p_qty,
        COALESCE(v_price, 0)
    );
END IF;
FOR r IN (
    SELECT si.id_заготовки,
        si.количество_заготовки
    FROM СоставИзделия si
    WHERE si.id_изделия = p_product_id
) LOOP v_needed_qty := COALESCE(r.количество_заготовки, 0) * p_qty;
SELECT количество_готовых INTO v_stock_qty
FROM Заготовка
WHERE id_заготовки = r.id_заготовки;
IF COALESCE(v_stock_qty, 0) >= v_needed_qty THEN NULL;
ELSE v_missing_qty := v_needed_qty - COALESCE(v_stock_qty, 0);
INSERT INTO "ПланЗаготовок" (
        id_заказа,
        id_заготовки,
        плановое_количество,
        фактическое_количество,
        дата_план,
        статус,
        дата_факт
    )
VALUES (
        p_order_id,
        r.id_заготовки,
        v_missing_qty,
        0,
        p_deadline,
        'принято',
        NULL
    );
v_components_added := v_components_added + 1;
END IF;
END LOOP;
IF v_components_added = 0 THEN status := 'OK';
message := 'Изделие добавлено. Все компоненты в наличии.';
ELSE
UPDATE Заказ
SET статус = 'в_работе'
WHERE id_заказа = p_order_id
    AND статус = 'принят';
status := 'OK';
message := 'Созданы задачи для ' || v_components_added || ' компонентов.';
END IF;
RETURN NEXT;
END;
$$;
CREATE OR REPLACE FUNCTION sp_check_order_ready() RETURNS TRIGGER AS $$
DECLARE v_id_order INTEGER;
v_pending_count INTEGER;
BEGIN v_id_order := NEW.id_заказа;
SELECT COUNT(*) INTO v_pending_count
FROM "ПланЗаготовок"
WHERE id_заказа = v_id_order
    AND статус != 'выполнено';
IF v_pending_count = 0 THEN
UPDATE Заказ
SET статус = 'завершен',
    дата_готовности = CURRENT_DATE
WHERE id_заказа = v_id_order
    AND статус = 'в_работе';
END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER tr_check_order_ready
AFTER
UPDATE OF статус ON "ПланЗаготовок" FOR EACH ROW
    WHEN (NEW.статус = 'выполнено') EXECUTE FUNCTION sp_check_order_ready();
CREATE OR REPLACE FUNCTION sp_get_product_components_status(p_order_id INTEGER, p_product_id INTEGER) RETURNS TABLE (
        наименование_заготовки VARCHAR,
        требуется INTEGER,
        выполнено INTEGER,
        осталось INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE v_product_qty INTEGER;
BEGIN
SELECT COALESCE(sz.количество_изделий, 0) INTO v_product_qty
FROM СоставЗаказа sz
WHERE sz.id_заказа = p_order_id
    AND sz.id_изделия = p_product_id;
IF v_product_qty IS NULL
OR v_product_qty = 0 THEN RETURN;
END IF;
RETURN QUERY
SELECT z.наименование::VARCHAR,
    (si.количество_заготовки * v_product_qty)::INTEGER,
    COALESCE(SUM(pp.фактическое_количество), 0)::INTEGER,
    GREATEST(
        0,
        (si.количество_заготовки * v_product_qty) - COALESCE(SUM(pp.фактическое_количество), 0)
    )::INTEGER
FROM СоставИзделия si
    JOIN Заготовка z ON si.id_заготовки = z.id_заготовки
    LEFT JOIN "ПланЗаготовок" pp ON pp.id_заказа = p_order_id
    AND pp.id_заготовки = si.id_заготовки
WHERE si.id_изделия = p_product_id
GROUP BY z.наименование,
    si.количество_заготовки;
END;
$$;
CREATE OR REPLACE FUNCTION sp_get_assembler_tasks() RETURNS TABLE(
        тип_задачи VARCHAR,
        id_объекта INTEGER,
        id_заказа INTEGER,
        наименование_задачи VARCHAR,
        плановое_количество INTEGER,
        фактическое_количество INTEGER,
        дедлайн DATE,
        статус VARCHAR,
        id_сборщика INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT 'заготовка'::VARCHAR as тип_задачи,
    pz.id_заготовки as id_объекта,
    pz.id_заказа,
    z.наименование as наименование_задачи,
    pz.плановое_количество,
    COALESCE(pz.фактическое_количество, 0),
    pz.дата_план as дедлайн,
    pz.статус,
    pz.id_сотрудника as id_сборщика
FROM "ПланЗаготовок" pz
    JOIN Заготовка z ON pz.id_заготовки = z.id_заготовки
ORDER BY pz.дата_план;
END;
$$;
CREATE OR REPLACE FUNCTION sp_submit_component_work(
        p_component_id INTEGER,
        p_order_id INTEGER,
        p_qty INTEGER,
        p_worker_id INTEGER
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
v_planned INTEGER;
v_actual INTEGER;
v_assigned_worker INTEGER;
BEGIN
SELECT статус,
    плановое_количество,
    COALESCE(фактическое_количество, 0),
    id_сотрудника INTO v_status,
    v_planned,
    v_actual,
    v_assigned_worker
FROM "ПланЗаготовок"
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
RETURN NEXT;
RETURN;
END IF;
IF v_assigned_worker IS NULL THEN status := 'ERROR';
message := 'Задача не взята в работу (не назначен исполнитель)';
RETURN NEXT;
RETURN;
ELSIF v_assigned_worker != p_worker_id THEN status := 'ERROR';
message := 'Вы не являетесь исполнителем этой задачи';
RETURN NEXT;
RETURN;
END IF;
IF v_status = 'выполнено' THEN status := 'ERROR';
message := 'Задача уже выполнена';
RETURN NEXT;
RETURN;
END IF;
IF (v_actual + p_qty) > v_planned THEN status := 'ERROR';
message := 'Нельзя сделать больше, чем запланировано! Осталось сделать: ' || (v_planned - v_actual);
RETURN NEXT;
RETURN;
END IF;
UPDATE "ПланЗаготовок"
SET фактическое_количество = COALESCE(фактическое_количество, 0) + p_qty,
    дата_факт = CURRENT_DATE,
    статус = CASE
        WHEN (COALESCE(фактическое_количество, 0) + p_qty) >= плановое_количество THEN 'выполнено'
        ELSE 'в_работе'
    END
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
GET DIAGNOSTICS v_actual = ROW_COUNT;
IF v_actual = 0 THEN status := 'ERROR';
message := 'Не удалось обновить задачу (данные изменились)';
RETURN NEXT;
RETURN;
END IF;
UPDATE Заготовка
SET количество_готовых = количество_готовых + p_qty
WHERE id_заготовки = p_component_id;
status := 'OK';
message := 'Работа принята';
RETURN NEXT;
END;
$$;
CREATE OR REPLACE FUNCTION sp_get_order_tasks(p_order_id INTEGER) RETURNS TABLE (
        тип_задачи VARCHAR,
        наименование VARCHAR,
        плановое_количество INTEGER,
        статус VARCHAR,
        дедлайн DATE
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT 'заготовка'::VARCHAR,
    z.наименование,
    pz.плановое_количество,
    pz.статус,
    pz.дата_план
FROM "ПланЗаготовок" pz
    JOIN Заготовка z ON pz.id_заготовки = z.id_заготовки
WHERE pz.id_заказа = p_order_id
ORDER BY pz.дата_план;
END;
$$;
CREATE OR REPLACE FUNCTION sp_take_component_task(
        p_component_id INTEGER,
        p_order_id INTEGER,
        p_worker_id INTEGER
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
v_assigned_worker INTEGER;
v_planned_qty INTEGER;
r RECORD;
v_missing_text VARCHAR := '';
BEGIN
SELECT статус,
    id_сотрудника,
    плановое_количество INTO v_status,
    v_assigned_worker,
    v_planned_qty
FROM "ПланЗаготовок"
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
RETURN NEXT;
RETURN;
END IF;
IF v_status = 'выполнено' THEN status := 'ERROR';
message := 'Задача уже выполнена';
RETURN NEXT;
RETURN;
END IF;
IF v_assigned_worker IS NOT NULL
AND v_assigned_worker != p_worker_id THEN status := 'ERROR';
message := 'Задача уже занята другим сотрудником';
RETURN NEXT;
RETURN;
END IF;
FOR r IN (
    SELECT m.наименование,
        COALESCE(sz.количество_материала, 0) * COALESCE(v_planned_qty, 0) as needed,
        m.количество_на_складе as stock,
        m.id_материала
    FROM СоставЗаготовки sz
        JOIN Материал m ON sz.id_материала = m.id_материала
    WHERE sz.id_заготовки = p_component_id
) LOOP IF COALESCE(r.stock, 0) < r.needed THEN v_missing_text := v_missing_text || r.наименование || ' (нужно ' || r.needed || ', есть ' || COALESCE(r.stock, 0) || '); ';
END IF;
END LOOP;
IF v_missing_text != '' THEN status := 'ERROR';
message := 'Не хватает материалов: ' || v_missing_text;
RETURN NEXT;
RETURN;
END IF;
FOR r IN (
    SELECT sz.id_материала,
        COALESCE(sz.количество_материала, 0) * COALESCE(v_planned_qty, 0) as needed
    FROM СоставЗаготовки sz
    WHERE sz.id_заготовки = p_component_id
) LOOP
UPDATE Материал
SET количество_на_складе = количество_на_складе - r.needed
WHERE id_материала = r.id_материала;
END LOOP;
UPDATE "ПланЗаготовок"
SET id_сотрудника = p_worker_id,
    статус = 'в_работе'
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
status := 'OK';
message := 'Задача взята в работу. Материалы списаны.';
RETURN NEXT;
END;
$$;
CREATE OR REPLACE FUNCTION sp_calculate_order_sum() RETURNS TRIGGER AS $$ BEGIN
UPDATE Заказ
SET сумма = (
        SELECT COALESCE(
                SUM(sz.количество_изделий * sz.цена_фиксированная),
                0
            )
        FROM СоставЗаказа sz
        WHERE sz.id_заказа = COALESCE(NEW.id_заказа, OLD.id_заказа)
    )
WHERE id_заказа = COALESCE(NEW.id_заказа, OLD.id_заказа);
RETURN NULL;
END;
$$ LANGUAGE plpgsql;
DROP TRIGGER IF EXISTS tr_order_sum_update ON СоставЗаказа;
CREATE TRIGGER tr_order_sum_update
AFTER
INSERT
    OR
UPDATE
    OR DELETE ON СоставЗаказа FOR EACH ROW EXECUTE FUNCTION sp_calculate_order_sum();