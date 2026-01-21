-- Phase 4: Bug Fixes and Заготовки Tab
-- =====================================
-- 1. FIX: Allow 'отменено' status in закупки_материалов
ALTER TABLE закупки_материалов DROP CONSTRAINT IF EXISTS закупки_материалов_статус_check;
ALTER TABLE закупки_материалов
ADD CONSTRAINT закупки_материалов_статус_check CHECK (
        статус IN (
            'ожидает_подтверждения',
            'выполнено',
            'отменено',
            'в_работе'
        )
    );
-- 2. FIX: sp_report_defect should revert order status to 'в_работе'
DROP FUNCTION IF EXISTS sp_report_defect(INTEGER, INTEGER, INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_report_defect(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_defect_qty INTEGER,
        p_reason VARCHAR
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_qty INTEGER;
v_old_status VARCHAR;
BEGIN -- Get current quantity and status
SELECT количество_изделий INTO v_current_qty
FROM состав_заказа
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
SELECT статус INTO v_old_status
FROM заказы
WHERE id_заказа = p_order_id;
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
-- Reduce quantity
UPDATE состав_заказа
SET количество_изделий = количество_изделий - p_defect_qty
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
-- REVERT ORDER STATUS to 'в_работе' since it's no longer complete
IF v_old_status IN ('выполнен', 'готов_к_отгрузке') THEN
UPDATE заказы
SET статус = 'в_работе'
WHERE id_заказа = p_order_id;
END IF;
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
message := 'Брак: ' || p_defect_qty || ' шт. Статус заказа изменен на "в_работе". Созданы задания. Причина: ' || p_reason;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 3. NEW: Get all заготовки (components)
DROP FUNCTION IF EXISTS sp_get_all_components();
CREATE OR REPLACE FUNCTION sp_get_all_components() RETURNS TABLE (
        id_заготовки INTEGER,
        наименование VARCHAR,
        количество_на_складе INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.id_заготовки,
    z.наименование,
    z.количество_на_складе
FROM заготовки z;
END;
$$;
-- 4. NEW: Get materials for a component
DROP FUNCTION IF EXISTS sp_get_component_materials(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_component_materials(p_component_id INTEGER) RETURNS TABLE (
        id_материала INTEGER,
        наименование VARCHAR,
        количество INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN -- Assume table состав_заготовки exists or we create it
    -- If not exists, we'll add it
    RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    sz.количество_материала
FROM состав_заготовки sz
    JOIN материалы m ON sz.id_материала = m.id_материала
WHERE sz.id_заготовки = p_component_id;
END;
$$;
-- 5. Create состав_заготовки table if not exists (material composition of component)
CREATE TABLE IF NOT EXISTS состав_заготовки (
    id_заготовки INTEGER REFERENCES заготовки(id_заготовки) ON DELETE CASCADE,
    id_материала INTEGER REFERENCES материалы(id_материала) ON DELETE CASCADE,
    количество_материала INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (id_заготовки, id_материала)
);
-- 6. NEW: Add material to component
DROP FUNCTION IF EXISTS sp_add_component_material(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_add_component_material(
        p_component_id INTEGER,
        p_material_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN IF EXISTS (
        SELECT 1
        FROM состав_заготовки
        WHERE id_заготовки = p_component_id
            AND id_материала = p_material_id
    ) THEN status := 'ERROR';
message := 'Этот материал уже добавлен';
RETURN NEXT;
RETURN;
END IF;
INSERT INTO состав_заготовки (id_заготовки, id_материала, количество_материала)
VALUES (p_component_id, p_material_id, p_qty);
status := 'OK';
message := 'Материал добавлен';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 7. NEW: Update material quantity in component
DROP FUNCTION IF EXISTS sp_update_component_material(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_update_component_material(
        p_component_id INTEGER,
        p_material_id INTEGER,
        p_new_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE состав_заготовки
SET количество_материала = p_new_qty
WHERE id_заготовки = p_component_id
    AND id_материала = p_material_id;
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
-- 8. NEW: Delete material from component
DROP FUNCTION IF EXISTS sp_delete_component_material(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_delete_component_material(
        p_component_id INTEGER,
        p_material_id INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
DELETE FROM состав_заготовки
WHERE id_заготовки = p_component_id
    AND id_материала = p_material_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Связь не найдена';
RETURN NEXT;
RETURN;
END IF;
status := 'OK';
message := 'Материал удален';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 9. NEW: Get all materials (for free selection in UI)
DROP FUNCTION IF EXISTS sp_get_all_materials();
CREATE OR REPLACE FUNCTION sp_get_all_materials() RETURNS TABLE (
        id_материала INTEGER,
        наименование VARCHAR,
        количество_на_складе INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    m.количество_на_складе
FROM материалы m;
END;
$$;
-- 10. NEW: Create new component
DROP FUNCTION IF EXISTS sp_create_component(VARCHAR);
CREATE OR REPLACE FUNCTION sp_create_component(p_name VARCHAR) RETURNS TABLE (status VARCHAR, message VARCHAR, id INTEGER) LANGUAGE plpgsql AS $$
DECLARE v_new_id INTEGER;
BEGIN
INSERT INTO заготовки (наименование, количество_на_складе)
VALUES (p_name, 0)
RETURNING id_заготовки INTO v_new_id;
status := 'OK';
message := 'Заготовка создана';
id := v_new_id;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
id := NULL;
RETURN NEXT;
END;
$$;
-- 11. NEW: Update component name
DROP FUNCTION IF EXISTS sp_update_component(INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_update_component(p_id INTEGER, p_name VARCHAR) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE заготовки
SET наименование = p_name
WHERE id_заготовки = p_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Заготовка не найдена';
RETURN NEXT;
RETURN;
END IF;
status := 'OK';
message := 'Заготовка обновлена';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;