-- FORCE update of sp_add_order_item logic
-- This script ensures assembly tasks are created correctly.
-- 1. Re-define sp_add_order_item
DROP FUNCTION IF EXISTS sp_add_order_item(INTEGER, INTEGER, INTEGER);
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
ELSE -- Insufficient product stock -> Need Production
v_missing_product := p_qty - v_stock;
-- Use up existing product stock
IF v_stock > 0 THEN
UPDATE изделия
SET количество_на_складе = 0
WHERE id_изделия = p_product_id;
END IF;
-- CHECK MATERIALS for components
SELECT m.наименование INTO v_missing_material_name
FROM состав_изделия si
    JOIN состав_заготовки sz ON si.id_заготовки = sz.id_заготовки
    JOIN материалы m ON sz.id_материала = m.id_материала
WHERE si.id_изделия = p_product_id
    AND m.количество_на_складе < (
        v_missing_product * si.количество_заготовок * sz.количество_материала
    )
LIMIT 1;
IF v_missing_material_name IS NOT NULL THEN RAISE EXCEPTION 'НЕОБХОДИМА ЗАКУПКА: Для производства недостающих изделий не хватает материала "%"',
v_missing_material_name;
END IF;
-- 1. Create ASSEMBLY task (PLAN SBORKI)
-- Explicitly verify table exists in logic (it does from previous scripts)
INSERT INTO план_сборки (
        id_заказа,
        id_изделия,
        плановое_количество,
        дата_план,
        статус
    )
VALUES (
        p_order_id,
        p_product_id,
        v_missing_product,
        v_date_ready,
        'принято'
    );
-- 2. Create COMPONENT tasks
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
message := 'Недостаточно на складе. Созданы задания на производство и сборку ' || v_missing_product || ' ед.';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := SQLERRM;
-- Cleanup
DELETE FROM состав_заказа
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id
    AND количество_изделий = p_qty
    AND цена_фиксированная = v_price;
RETURN NEXT;
END;
$$;