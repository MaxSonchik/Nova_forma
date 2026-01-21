-- Phase 3: Component Editing, Defects, Purchase Cancellation
-- ===========================================================
-- 1. ADD COMPONENT TO PRODUCT
DROP FUNCTION IF EXISTS sp_add_product_component(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_add_product_component(
        p_product_id INTEGER,
        p_component_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN -- Check if already exists
    IF EXISTS (
        SELECT 1
        FROM состав_изделия
        WHERE id_изделия = p_product_id
            AND id_заготовки = p_component_id
    ) THEN status := 'ERROR';
message := 'Эта заготовка уже есть в составе изделия';
RETURN NEXT;
RETURN;
END IF;
INSERT INTO состав_изделия (id_изделия, id_заготовки, количество_заготовок)
VALUES (p_product_id, p_component_id, p_qty);
status := 'OK';
message := 'Заготовка добавлена в состав';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 2. UPDATE COMPONENT QUANTITY
DROP FUNCTION IF EXISTS sp_update_product_component(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_update_product_component(
        p_product_id INTEGER,
        p_component_id INTEGER,
        p_new_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE состав_изделия
SET количество_заготовок = p_new_qty
WHERE id_изделия = p_product_id
    AND id_заготовки = p_component_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Связь не найдена';
RETURN NEXT;
RETURN;
END IF;
status := 'OK';
message := 'Количество обновлено';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 3. DELETE COMPONENT FROM PRODUCT
DROP FUNCTION IF EXISTS sp_delete_product_component(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_delete_product_component(
        p_product_id INTEGER,
        p_component_id INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
DELETE FROM состав_изделия
WHERE id_изделия = p_product_id
    AND id_заготовки = p_component_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Связь не найдена';
RETURN NEXT;
RETURN;
END IF;
status := 'OK';
message := 'Заготовка удалена из состава';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 4. REPORT DEFECT (for order items)
DROP FUNCTION IF EXISTS sp_report_defect(INTEGER, INTEGER, INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_report_defect(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_defect_qty INTEGER,
        p_reason VARCHAR
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_qty INTEGER;
BEGIN -- Get current quantity in order
SELECT количество_изделий INTO v_current_qty
FROM состав_заказа
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Позиция не найдена в заказе';
RETURN NEXT;
RETURN;
END IF;
IF p_defect_qty > v_current_qty THEN status := 'ERROR';
message := 'Количество брака превышает количество в заказе';
RETURN NEXT;
RETURN;
END IF;
-- Log defect (create table if not exists would be in schema, assume exists)
-- For now, we just reduce quantity and add to plan
UPDATE состав_заказа
SET количество_изделий = количество_изделий - p_defect_qty
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
-- Create production tasks for replacement
INSERT INTO план_заготовок (
        id_заказа,
        id_заготовки,
        плановое_количество,
        дата_план,
        статус
    )
SELECT p_order_id,
    si.id_заготовки,
    si.количество_заготовок * p_defect_qty,
    (
        SELECT дата_готовности
        FROM заказы
        WHERE id_заказа = p_order_id
    ) - INTERVAL '1 day',
    'принято'
FROM состав_изделия si
WHERE si.id_изделия = p_product_id;
status := 'WARNING';
message := 'Брак зафиксирован (' || p_defect_qty || ' шт). Созданы задания на доизготовление. Причина: ' || p_reason;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 5. CANCEL PURCHASE
DROP FUNCTION IF EXISTS sp_cancel_purchase(INTEGER);
CREATE OR REPLACE FUNCTION sp_cancel_purchase(p_purchase_id INTEGER) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_status VARCHAR;
BEGIN
SELECT статус INTO v_current_status
FROM закупки_материалов
WHERE id_закупки = p_purchase_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Закупка не найдена';
RETURN NEXT;
RETURN;
END IF;
IF v_current_status = 'выполнено' THEN status := 'ERROR';
message := 'Нельзя отменить выполненную закупку';
RETURN NEXT;
RETURN;
END IF;
IF v_current_status = 'отменено' THEN status := 'ERROR';
message := 'Закупка уже отменена';
RETURN NEXT;
RETURN;
END IF;
UPDATE закупки_материалов
SET статус = 'отменено'
WHERE id_закупки = p_purchase_id;
status := 'OK';
message := 'Закупка отменена';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 6. UPDATE SAMPLE DATA: Fix overdue orders by moving dates forward
UPDATE заказы
SET дата_готовности = CURRENT_DATE + INTERVAL '7 days'
WHERE дата_готовности < CURRENT_DATE
    AND статус NOT IN ('выполнен', 'отгружен', 'завершен');
UPDATE план_заготовок
SET дата_план = CURRENT_DATE + INTERVAL '5 days'
WHERE дата_план < CURRENT_DATE
    AND статус NOT IN ('выполнено', 'отменено');