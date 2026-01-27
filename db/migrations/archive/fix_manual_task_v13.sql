-- Logic for Manual Task Creation with Material Check
-- This replaces direct INSERT in python code if any, or creates a new procedure
DROP FUNCTION IF EXISTS sp_create_manual_production_task(INTEGER, INTEGER, INTEGER, DATE);
CREATE OR REPLACE FUNCTION sp_create_manual_production_task(
        p_order_id INTEGER,
        p_component_id INTEGER,
        p_qty INTEGER,
        p_deadline DATE
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_missing_material_name VARCHAR;
BEGIN -- 1. MATERIAL CHECK
-- Check if we have enough materials for this specific task
SELECT m.наименование INTO v_missing_material_name
FROM состав_заготовки sz
    JOIN материалы m ON sz.id_материала = m.id_материала
WHERE sz.id_заготовки = p_component_id
    AND m.количество_на_складе < (sz.количество_материала * p_qty)
LIMIT 1;
IF v_missing_material_name IS NOT NULL THEN status := 'ERROR';
message := 'НЕОБХОДИМА ЗАКУПКА: Недостаточно материала "' || v_missing_material_name || '" для этой задачи.';
RETURN NEXT;
RETURN;
END IF;
-- 2. Create Task
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
        p_deadline,
        'принято'
    );
status := 'OK';
message := 'Задача успешно создана';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;