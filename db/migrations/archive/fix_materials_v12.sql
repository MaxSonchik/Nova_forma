-- Fix Material Deduction Logic v12
-- Implement strict checks: reject if insufficient materials
-- 1. FIX: sp_сдать_работу (Report Work)
CREATE OR REPLACE PROCEDURE sp_сдать_работу(
        p_id_заготовки INTEGER,
        p_id_заказа INTEGER,
        p_количество INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
v_planned INTEGER;
v_actual INTEGER;
v_missing_material_name VARCHAR;
BEGIN
SELECT статус,
    плановое_количество,
    фактическое_количество INTO v_status,
    v_planned,
    v_actual
FROM план_заготовок
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN RAISE EXCEPTION 'Задача не найдена';
END IF;
IF v_status = 'выполнено' THEN RAISE EXCEPTION 'Задача уже выполнена';
END IF;
IF v_status = 'отменено' THEN RAISE EXCEPTION 'Задача отменена';
END IF;
-- STRICT MATERIAL CHECK
-- Check if any material is insufficient
SELECT m.наименование INTO v_missing_material_name
FROM состав_заготовки sz
    JOIN материалы m ON sz.id_материала = m.id_материала
WHERE sz.id_заготовки = p_id_заготовки
    AND m.количество_на_складе < (sz.количество_материала * p_количество)
LIMIT 1;
IF v_missing_material_name IS NOT NULL THEN RAISE EXCEPTION 'НЕОБХОДИМА ЗАКУПКА: Недостаточно материала "%" для изготовления заготовки',
v_missing_material_name;
END IF;
-- Deduct materials (safe to use simple subtraction now)
UPDATE материалы m
SET количество_на_складе = количество_на_складе - (sz.количество_материала * p_количество)
FROM состав_заготовки sz
WHERE sz.id_заготовки = p_id_заготовки
    AND m.id_материала = sz.id_материала;
-- Update plan
UPDATE план_заготовок
SET фактическое_количество = фактическое_количество + p_количество,
    дата_факт = CURRENT_DATE
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
-- Update zagotovki stock
UPDATE заготовки
SET количество_готовых = количество_готовых + p_количество
WHERE id_заготовки = p_id_заготовки;
-- Check completion
IF (v_actual + p_количество) >= v_planned THEN
UPDATE план_заготовок
SET статус = 'выполнено'
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
END IF;
END;
$$;
-- 2. FIX: sp_add_order_item (Cascaded Material Check)
CREATE OR REPLACE FUNCTION sp_add_order_item(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_stock INTEGER;
v_price NUMERIC;
v_missing_product INTEGER;
v_missing_material_name VARCHAR;
v_date_ready DATE;
rec RECORD;
BEGIN
SELECT стоимость,
    количество_на_складе INTO v_price,
    v_stock
FROM изделия
WHERE id_изделия = p_product_id;
-- Insert into order items
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
-- Check product stock
IF v_stock >= p_qty THEN -- Sufficient product stock
UPDATE изделия
SET количество_на_складе = количество_на_складе - p_qty
WHERE id_изделия = p_product_id;
status := 'OK';
message := 'Изделия зарезервированы со склада.';
ELSE -- Insufficient product stock
v_missing_product := p_qty - v_stock;
-- Use up existing product stock
IF v_stock > 0 THEN
UPDATE изделия
SET количество_на_складе = 0
WHERE id_изделия = p_product_id;
END IF;
-- CHECK MATERIALS for ALL required components BEFORE creating tasks
-- We join composition of product -> composition of component -> materials
SELECT m.наименование INTO v_missing_material_name
FROM состав_изделия si
    JOIN состав_заготовки sz ON si.id_заготовки = sz.id_заготовки
    JOIN материалы m ON sz.id_материала = m.id_материала
WHERE si.id_изделия = p_product_id
    AND m.количество_на_складе < (
        -- Total needed for this material: (missing products * component qty per product * material qty per component)
        -- Note: This is a simplification. It checks if CURRENT stock covers THIS order.
        -- It does NOT reserve materials yet (materials are deducted when work is reported).
        -- But user wants to REJECT creation if materials are missing NOW.
        v_missing_product * si.количество_заготовок * sz.количество_материала
    )
LIMIT 1;
IF v_missing_material_name IS NOT NULL THEN -- Rollback everything done so far in this transaction (implicitly by raising exception)
RAISE EXCEPTION 'НЕОБХОДИМА ЗАКУПКА: Для производства недостающих изделий не хватает материала "%"',
v_missing_material_name;
END IF;
-- Create tasks for missing components
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
        rec.количество_заготовок * v_missing_product,
        v_date_ready - INTERVAL '1 day',
        'принято'
    );
END LOOP;
status := 'WARNING';
message := 'Недостаточно на складе. Созданы задания на производство ' || v_missing_product || ' ед. Материалы в наличии.';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN -- If we raised exception, we want to return ERROR status, but also rollback the insert into composition?
-- Functions in Postgres: modifications are atomic within the statement but if we catch exception we can return status.
-- BUT: We already INSERTED into состав_заказа.
-- If we want to fully prevent the item addition, we should likely RAISE error to propagate up, 
-- causing the caller (Python transaction or dialog) to handle it.
-- OR we can manualy delete what we inserted.
-- Given user requirement "cancellation of product creation", let's propagate the specific "Purchase" error message 
-- but format it as ERROR status so UI handles it.
-- Ideally we should ROLLBACK the INSERT INTO состав_заказа too.
-- Since we can't rollback inside a function with exception block easily without savepoints (complex in plpgsql block),
-- simpler is to propagate the exception and let the transaction fail?
-- But our python code expects (status, message).
-- Let's try to be clean:
status := 'ERROR';
message := SQLERRM;
-- The Python code `sp_add_order_item` call is separate from `sp_create_order`.
-- If this fails, the order header exists but item is not added. That's acceptable for "Add item" failure.
-- But wait, we inserted into состав_заказа at the start of this block!
-- If we return ERROR, that row REMAINS.
-- We MUST delete it if we fail.
DELETE FROM состав_заказа
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id
    AND количество_изделий = p_qty
    AND цена_фиксированная = v_price;
-- (Ideally use returned ID if we had it, but this should match loosely enough for the current transaction snapshot)
RETURN NEXT;
END;
$$;