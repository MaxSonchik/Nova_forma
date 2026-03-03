-- Fix sp_add_order_item(integer, integer, integer)
-- Add material deduction logic when production tasks are created
CREATE OR REPLACE FUNCTION sp_add_order_item(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_stock INTEGER;
v_missing_product INTEGER;
v_date_ready DATE;
v_missing_material_name VARCHAR;
v_exists BOOLEAN;
rec RECORD;
mat_rec RECORD;
BEGIN -- Check order status
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
-- Calculate ready date
SELECT дата_готовности INTO v_date_ready
FROM Заказ
WHERE id_заказа = p_order_id;
IF v_date_ready IS NULL THEN v_date_ready := CURRENT_DATE + INTERVAL '7 days';
END IF;
-- Add/Update item in Order
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
-- CHECK STOCK
SELECT количество_на_складе INTO v_stock
FROM Изделие
WHERE id_изделия = p_product_id;
IF v_stock >= p_qty THEN -- Enough stock: Reserve it (deduct from stock)
UPDATE Изделие
SET количество_на_складе = количество_на_складе - p_qty
WHERE id_изделия = p_product_id;
status := 'OK';
message := 'Изделия зарезервированы со склада.';
ELSE -- Insufficient product stock -> Need Production
v_missing_product := p_qty - v_stock;
-- Use up existing product stock
IF v_stock > 0 THEN
UPDATE Изделие
SET количество_на_складе = 0
WHERE id_изделия = p_product_id;
END IF;
-- CHECK MATERIALS for ALL required components BEFORE creating tasks
SELECT m.наименование INTO v_missing_material_name
FROM СоставИзделия si
    JOIN РасходМатериалов rm ON si.id_заготовки = rm.id_заготовки
    JOIN Материал m ON rm.id_материала = m.id_материала
WHERE si.id_изделия = p_product_id
    AND m.количество_на_складе < (
        v_missing_product * si.количество_заготовки * rm.количество_материала
    )
LIMIT 1;
IF v_missing_material_name IS NOT NULL THEN -- Rollback: delete the order item we just added
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
-- Restore product stock if we used any
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
-- DEDUCT MATERIALS for production tasks
FOR rec IN
SELECT si.id_заготовки,
    si.количество_заготовки
FROM СоставИзделия si
WHERE si.id_изделия = p_product_id LOOP -- Deduct raw materials for each component
    FOR mat_rec IN
SELECT rm.id_материала,
    (
        rm.количество_материала * rec.количество_заготовки * v_missing_product
    ) AS needed
FROM РасходМатериалов rm
WHERE rm.id_заготовки = rec.id_заготовки LOOP
UPDATE Материал
SET количество_на_складе = количество_на_складе - mat_rec.needed
WHERE id_материала = mat_rec.id_материала;
END LOOP;
-- Create/Update production task
IF EXISTS(
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
message := 'Заказ принят, но изделий не хватает. Материалы списаны, созданы задачи на производство.';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;