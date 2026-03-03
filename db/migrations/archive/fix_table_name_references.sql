






DROP FUNCTION IF EXISTS sp_create_manual_production_task(INTEGER, INTEGER, INTEGER, DATE);
CREATE OR REPLACE FUNCTION sp_create_manual_production_task(
        p_order_id INTEGER,
        p_component_id INTEGER,
        p_qty INTEGER,
        p_deadline DATE DEFAULT NULL
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_deadline DATE;
v_missing_material_name VARCHAR;
BEGIN 
IF p_deadline IS NULL THEN
SELECT COALESCE(
        дата_готовности,
        CURRENT_DATE + INTERVAL '7 days'
    ) INTO v_deadline
FROM Заказ
WHERE id_заказа = p_order_id;
ELSE v_deadline := p_deadline;
END IF;


SELECT m.наименование INTO v_missing_material_name
FROM РасходМатериалов rm
    JOIN Материал m ON rm.id_материала = m.id_материала
WHERE rm.id_заготовки = p_component_id
    AND m.количество_на_складе < (rm.количество_материала * p_qty)
LIMIT 1;
IF v_missing_material_name IS NOT NULL THEN status := 'ERROR';
message := 'НЕОБХОДИМА ЗАКУПКА: Недостаточно материала "' || v_missing_material_name || '" для изготовления Заготовки';
RETURN NEXT;
RETURN;
END IF;

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
message := 'Задача добавлена в план';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;


DROP FUNCTION IF EXISTS sp_add_component_material(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_add_component_material(
        p_comp_id INTEGER,
        p_mat_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
INSERT INTO РасходМатериалов (id_заготовки, id_материала, количество_материала)
VALUES (p_comp_id, p_mat_id, p_qty) ON CONFLICT (id_заготовки, id_материала) DO
UPDATE
SET количество_материала = РасходМатериалов.количество_материала + p_qty;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Материал добавлен'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;
DROP FUNCTION IF EXISTS sp_update_component_material(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_update_component_material(
        p_comp_id INTEGER,
        p_mat_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE РасходМатериалов
SET количество_материала = p_qty
WHERE id_заготовки = p_comp_id
    AND id_материала = p_mat_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Количество обновлено'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;
DROP FUNCTION IF EXISTS sp_delete_component_material(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_delete_component_material(p_comp_id INTEGER, p_mat_id INTEGER) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
DELETE FROM РасходМатериалов
WHERE id_заготовки = p_comp_id
    AND id_материала = p_mat_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Материал удален из состава'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;
DROP FUNCTION IF EXISTS sp_get_component_materials(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_component_materials(p_comp_id INTEGER) RETURNS TABLE (
        id_материала INTEGER,
        наименование VARCHAR,
        количество INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    rm.количество_материала
FROM РасходМатериалов rm
    JOIN Материал m ON rm.id_материала = m.id_материала
WHERE rm.id_заготовки = p_comp_id;
END;
$$;







CREATE OR REPLACE FUNCTION sp_add_order_item(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_stock INTEGER;
v_missing_product INTEGER;
v_date_ready DATE;
v_missing_material_name VARCHAR;
v_exists BOOLEAN;
rec RECORD;
BEGIN 
IF EXISTS(
    SELECT 1
    FROM Заказ
    WHERE id_заказа = p_order_id
        AND статус IN ('выполнен', 'отменен', 'отгружен', 'завершен')
) THEN status := 'ERROR';
message := 'Нельзя изменить завершенный заказ';
RETURN NEXT;
RETURN;
END IF;

v_date_ready := CURRENT_DATE + INTERVAL '7 days';

SELECT EXISTS(
        SELECT 1
        FROM СоставЗаказа
        WHERE id_заказа = p_order_id
            AND id_изделия = p_product_id
    ) INTO v_exists;
IF v_exists THEN
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
SELECT p_order_id,
    p_product_id,
    p_qty,
    стоимость
FROM Изделие
WHERE id_изделия = p_product_id;
END IF;

SELECT количество_на_складе INTO v_stock
FROM Изделие
WHERE id_изделия = p_product_id;
IF v_stock >= p_qty THEN 
UPDATE Изделие
SET количество_на_складе = количество_на_складе - p_qty
WHERE id_изделия = p_product_id;
status := 'OK';
message := 'Изделия зарезервированы со склада.';
ELSE 
v_missing_product := p_qty - v_stock;

IF v_stock > 0 THEN
UPDATE Изделие
SET количество_на_складе = 0
WHERE id_изделия = p_product_id;
END IF;


SELECT m.наименование INTO v_missing_material_name
FROM СоставИзделия si
    JOIN РасходМатериалов rm ON si.id_заготовки = rm.id_заготовки
    JOIN Материал m ON rm.id_материала = m.id_материала
WHERE si.id_изделия = p_product_id
    AND m.количество_на_складе < (
        v_missing_product * si.количество_заготовки * rm.количество_материала
    )
LIMIT 1;
IF v_missing_material_name IS NOT NULL THEN 
IF v_exists THEN
UPDATE СоставЗаказа
SET количество_изделий = количество_изделий - p_qty
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
ELSE
DELETE FROM СоставЗаказа
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
END IF;

IF v_stock > 0 THEN
UPDATE Изделие
SET количество_на_складе = v_stock
WHERE id_изделия = p_product_id;
END IF;
status := 'ERROR';
message := 'НЕОБХОДИМА ЗАКУПКА: Для производства не хватает материала "' || v_missing_material_name || '"';
RETURN NEXT;
RETURN;
END IF;

FOR rec IN
SELECT id_заготовки,
    количество_заготовки
FROM СоставИзделия
WHERE id_изделия = p_product_id LOOP IF EXISTS(
        SELECT 1
        FROM ПланЗаготовок
        WHERE id_заготовки = rec.id_заготовки
            AND id_заказа = p_order_id
    ) THEN
UPDATE ПланЗаготовок
SET плановое_количество = плановое_количество + (rec.количество_заготовки * v_missing_product)
WHERE id_заготовки = rec.id_заготовки
    AND id_заказа = p_order_id;
ELSE
INSERT INTO ПланЗаготовок (
        id_заготовки,
        id_заказа,
        плановое_количество,
        дата_план,
        статус
    )
VALUES (
        rec.id_заготовки,
        p_order_id,
        rec.количество_заготовки * v_missing_product,
        v_date_ready - INTERVAL '1 day',
        'принято'
    );
END IF;
END LOOP;
status := 'WARNING';
message := 'Заказ принят, но изделий не хватает. Созданы задачи на производство.';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;