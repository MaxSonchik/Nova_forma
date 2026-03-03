CREATE OR REPLACE FUNCTION sp_add_product_to_order_smart(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER,
        p_deadline DATE
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE r RECORD;
rm_rec RECORD;
v_needed_qty INTEGER;
v_stock_qty INTEGER;
v_missing_qty INTEGER;
v_components_added INTEGER := 0;
v_price NUMERIC;
v_missing_text VARCHAR := '';
BEGIN
SELECT стоимость INTO v_price
FROM Изделие
WHERE id_изделия = p_product_id;
-- Pre-calculate and check materials for ALL missing components
FOR r IN (
    SELECT si.id_заготовки,
        si.количество_заготовки
    FROM СоставИзделия si
    WHERE si.id_изделия = p_product_id
) LOOP v_needed_qty := COALESCE(r.количество_заготовки, 0) * p_qty;
SELECT количество_готовых INTO v_stock_qty
FROM Заготовка
WHERE id_заготовки = r.id_заготовки;
IF COALESCE(v_stock_qty, 0) < v_needed_qty THEN v_missing_qty := v_needed_qty - COALESCE(v_stock_qty, 0);
-- Check materials for v_missing_qty of this component
FOR rm_rec IN (
    SELECT m.наименование,
        m.количество_на_складе,
        (
            COALESCE(sz.количество_материала, 0) * v_missing_qty
        ) as needed
    FROM СоставЗаготовки sz
        JOIN Материал m ON sz.id_материала = m.id_материала
    WHERE sz.id_заготовки = r.id_заготовки
) LOOP IF COALESCE(rm_rec.количество_на_складе, 0) < rm_rec.needed THEN v_missing_text := v_missing_text || rm_rec.наименование || ' (нужно ' || rm_rec.needed || ', есть ' || COALESCE(rm_rec.количество_на_складе, 0) || '); ';
END IF;
END LOOP;
END IF;
END LOOP;
IF v_missing_text != '' THEN status := 'ERROR';
message := 'Не хватает материалов для заготовок: ' || v_missing_text;
RETURN NEXT;
RETURN;
END IF;
-- All materials are sufficient. Proceed with inserting order item.
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
-- Deduct materials and create tasks
FOR r IN (
    SELECT si.id_заготовки,
        si.количество_заготовки
    FROM СоставИзделия si
    WHERE si.id_изделия = p_product_id
) LOOP v_needed_qty := COALESCE(r.количество_заготовки, 0) * p_qty;
SELECT количество_готовых INTO v_stock_qty
FROM Заготовка
WHERE id_заготовки = r.id_заготовки;
IF COALESCE(v_stock_qty, 0) < v_needed_qty THEN v_missing_qty := v_needed_qty - COALESCE(v_stock_qty, 0);
-- Deduct materials!
FOR rm_rec IN (
    SELECT sz.id_материала,
        (
            COALESCE(sz.количество_материала, 0) * v_missing_qty
        ) as needed
    FROM СоставЗаготовки sz
    WHERE sz.id_заготовки = r.id_заготовки
) LOOP
UPDATE Материал
SET количество_на_складе = количество_на_складе - rm_rec.needed
WHERE id_материала = rm_rec.id_материала;
END LOOP;
INSERT INTO ПланЗаготовок (
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
message := 'Созданы задачи для ' || v_components_added || ' компонентов и списаны материалы.';
END IF;
RETURN NEXT;
END;
$$;
CREATE OR REPLACE FUNCTION sp_create_manual_production_task(
        p_order_id INTEGER,
        p_component_id INTEGER,
        p_qty INTEGER,
        p_deadline DATE DEFAULT NULL
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_deadline DATE;
rm_rec RECORD;
v_missing_text VARCHAR := '';
BEGIN IF p_deadline IS NULL THEN
SELECT COALESCE(
        дата_готовности,
        CURRENT_DATE + INTERVAL '7 days'
    ) INTO v_deadline
FROM Заказ
WHERE id_заказа = p_order_id;
ELSE v_deadline := p_deadline;
END IF;
-- Check materials (using СоставЗаготовки)
FOR rm_rec IN (
    SELECT m.наименование,
        m.количество_на_складе,
        (COALESCE(sz.количество_материала, 0) * p_qty) as needed
    FROM СоставЗаготовки sz
        JOIN Материал m ON sz.id_материала = m.id_материала
    WHERE sz.id_заготовки = p_component_id
) LOOP IF COALESCE(rm_rec.количество_на_складе, 0) < rm_rec.needed THEN v_missing_text := v_missing_text || rm_rec.наименование || ' (нужно ' || rm_rec.needed || ', есть ' || COALESCE(rm_rec.количество_на_складе, 0) || '); ';
END IF;
END LOOP;
IF v_missing_text != '' THEN status := 'ERROR';
message := 'НЕОБХОДИМА ЗАКУПКА: Недостаточно материалов: ' || v_missing_text;
RETURN NEXT;
RETURN;
END IF;
-- Deduct materials
FOR rm_rec IN (
    SELECT sz.id_материала,
        (COALESCE(sz.количество_материала, 0) * p_qty) as needed
    FROM СоставЗаготовки sz
    WHERE sz.id_заготовки = p_component_id
) LOOP
UPDATE Материал
SET количество_на_складе = количество_на_складе - rm_rec.needed
WHERE id_материала = rm_rec.id_материала;
END LOOP;
IF EXISTS(
    SELECT 1
    FROM ПланЗаготовок
    WHERE id_заготовки = p_component_id
        AND id_заказа = p_order_id
        AND статус != 'выполнено'
) THEN
UPDATE ПланЗаготовок
SET плановое_количество = плановое_количество + p_qty
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id
    AND статус != 'выполнено';
ELSE
INSERT INTO ПланЗаготовок (
        id_заготовки,
        id_заказа,
        плановое_количество,
        дата_план,
        статус
    )
VALUES (
        p_component_id,
        p_order_id,
        p_qty,
        v_deadline,
        'принято'
    );
END IF;
status := 'OK';
message := 'Задача добавлена в план, материалы списаны';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
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
v_fire_date DATE;
BEGIN
SELECT дата_увольнения INTO v_fire_date
FROM Сотрудник
WHERE id_сотрудника = p_worker_id;
IF v_fire_date IS NOT NULL THEN status := 'ERROR';
message := 'Уволенный сотрудник не может брать задачи';
RETURN NEXT;
RETURN;
END IF;
SELECT статус,
    id_сотрудника,
    плановое_количество INTO v_status,
    v_assigned_worker,
    v_planned_qty
FROM ПланЗаготовок
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
UPDATE ПланЗаготовок
SET id_сотрудника = p_worker_id,
    статус = 'в_работе'
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
status := 'OK';
message := 'Задача взята в работу.';
RETURN NEXT;
END;
$$;
CREATE OR REPLACE FUNCTION sp_assign_worker_to_task(
        p_id_заготовки INTEGER,
        p_id_заказа INTEGER,
        p_worker_id INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_fire_date DATE;
BEGIN
SELECT дата_увольнения INTO v_fire_date
FROM Сотрудник
WHERE id_сотрудника = p_worker_id;
IF v_fire_date IS NOT NULL THEN status := 'ERROR';
message := 'Нельзя назначить задачу уволенному сотруднику';
RETURN NEXT;
RETURN;
END IF;
UPDATE ПланЗаготовок
SET id_сотрудника = p_worker_id,
    статус = 'назначено'
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF FOUND THEN status := 'OK';
message := 'Сборщик назначен';
ELSE status := 'ERROR';
message := 'Задача не найдена';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;