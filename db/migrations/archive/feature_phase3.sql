


DROP FUNCTION IF EXISTS sp_add_product_component(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_add_product_component(
        p_product_id INTEGER,
        p_component_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN 
    IF EXISTS (
        SELECT 1
        FROM СоставИзделия
        WHERE id_изделия = p_product_id
            AND id_заготовки = p_component_id
    ) THEN status := 'ERROR';
message := 'Эта заготовка уже есть в составе Изделие';
RETURN NEXT;
RETURN;
END IF;
INSERT INTO СоставИзделия (id_изделия, id_заготовки, количество_заготовок)
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

DROP FUNCTION IF EXISTS sp_update_product_component(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_update_product_component(
        p_product_id INTEGER,
        p_component_id INTEGER,
        p_new_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE СоставИзделия
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

DROP FUNCTION IF EXISTS sp_delete_product_component(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_delete_product_component(
        p_product_id INTEGER,
        p_component_id INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
DELETE FROM СоставИзделия
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

DROP FUNCTION IF EXISTS sp_report_defect(INTEGER, INTEGER, INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_report_defect(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_defect_qty INTEGER,
        p_reason VARCHAR
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_qty INTEGER;
BEGIN 
SELECT количество_изделий INTO v_current_qty
FROM СоставЗаказа
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


UPDATE СоставЗаказа
SET количество_изделий = количество_изделий - p_defect_qty
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;

INSERT INTO ПланЗаготовок (
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
        FROM Заказ
        WHERE id_заказа = p_order_id
    ) - INTERVAL '1 day',
    'принято'
FROM СоставИзделия si
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

DROP FUNCTION IF EXISTS sp_cancel_purchase(INTEGER);
CREATE OR REPLACE FUNCTION sp_cancel_purchase(p_purchase_id INTEGER) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_status VARCHAR;
BEGIN
SELECT статус INTO v_current_status
FROM Закупка
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
UPDATE Закупка
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

UPDATE Заказ
SET дата_готовности = CURRENT_DATE + INTERVAL '7 days'
WHERE дата_готовности < CURRENT_DATE
    AND статус NOT IN ('выполнен', 'отгружен', 'завершен');
UPDATE ПланЗаготовок
SET дата_план = CURRENT_DATE + INTERVAL '5 days'
WHERE дата_план < CURRENT_DATE
    AND статус NOT IN ('выполнено', 'отменено');