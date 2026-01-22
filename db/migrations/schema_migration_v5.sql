-- Phase 5: Schema Migration to Composite Primary Keys
-- =====================================================
-- ВАЖНО: Выполняйте этот скрипт в одной транзакции!
BEGIN;
-- ============================================================================
-- 1. BACKUP DATA INTO TEMP TABLES
-- ============================================================================
CREATE TEMP TABLE temp_план_заготовок AS
SELECT *
FROM план_заготовок;
CREATE TEMP TABLE temp_состав_заказа AS
SELECT *
FROM состав_заказа;
CREATE TEMP TABLE temp_расход_материалов AS
SELECT *
FROM расход_материалов;
CREATE TEMP TABLE temp_состав_изделия AS
SELECT *
FROM состав_изделия;
CREATE TEMP TABLE temp_состав_закупки AS
SELECT *
FROM состав_закупки;
-- ============================================================================
-- 2. DROP OLD TABLES (cascade will drop dependent constraints)
-- ============================================================================
DROP TABLE IF EXISTS план_заготовок CASCADE;
DROP TABLE IF EXISTS состав_заказа CASCADE;
DROP TABLE IF EXISTS расход_материалов CASCADE;
DROP TABLE IF EXISTS состав_изделия CASCADE;
DROP TABLE IF EXISTS состав_закупки CASCADE;
-- ============================================================================
-- 3. CREATE NEW TABLES WITH COMPOSITE PRIMARY KEYS
-- ============================================================================
-- 3.1 расход_материалов (Таблица 1.8)
CREATE TABLE расход_материалов (
    id_заготовки INTEGER NOT NULL REFERENCES заготовки(id_заготовки) ON DELETE CASCADE,
    id_материала INTEGER NOT NULL REFERENCES материалы(id_материала) ON DELETE RESTRICT,
    количество_материала INTEGER NOT NULL CHECK (количество_материала > 0),
    PRIMARY KEY (id_заготовки, id_материала)
);
-- 3.2 состав_изделия (Таблица 1.9)
CREATE TABLE состав_изделия (
    id_изделия INTEGER NOT NULL REFERENCES изделия(id_изделия) ON DELETE CASCADE,
    id_заготовки INTEGER NOT NULL REFERENCES заготовки(id_заготовки) ON DELETE RESTRICT,
    количество_заготовки INTEGER NOT NULL CHECK (количество_заготовки > 0),
    PRIMARY KEY (id_изделия, id_заготовки)
);
-- 3.3 состав_заказа (Таблица 1.7)
CREATE TABLE состав_заказа (
    id_заказа INTEGER NOT NULL REFERENCES заказы(id_заказа) ON DELETE CASCADE,
    id_изделия INTEGER NOT NULL REFERENCES изделия(id_изделия) ON DELETE RESTRICT,
    цена_фиксированная NUMERIC(10, 2) NOT NULL,
    количество_изделий INTEGER NOT NULL CHECK (количество_изделий > 0),
    PRIMARY KEY (id_заказа, id_изделия)
);
-- 3.4 состав_закупки (без скриншота, но упомянуто)
CREATE TABLE состав_закупки (
    id_закупки INTEGER NOT NULL REFERENCES закупки_материалов(id_закупки) ON DELETE CASCADE,
    id_материала INTEGER NOT NULL REFERENCES материалы(id_материала) ON DELETE CASCADE,
    количество INTEGER NOT NULL CHECK (количество > 0),
    цена_закупки NUMERIC(10, 2),
    PRIMARY KEY (id_закупки, id_материала)
);
-- 3.5 план_заготовок (Таблица 1.4)
CREATE TABLE план_заготовок (
    id_заготовки INTEGER NOT NULL REFERENCES заготовки(id_заготовки),
    id_сотрудника INTEGER REFERENCES сотрудники(id_сотрудника),
    id_заказа INTEGER NOT NULL REFERENCES заказы(id_заказа) ON DELETE CASCADE,
    плановое_количество INTEGER NOT NULL,
    фактическое_количество INTEGER NOT NULL DEFAULT 0,
    дата_план DATE NOT NULL,
    дата_факт DATE,
    статус VARCHAR(15) NOT NULL DEFAULT 'принято' CHECK (
        статус IN (
            'принято',
            'в_работе',
            'выполнено',
            'отменено',
            'просрочено'
        )
    ),
    PRIMARY KEY (id_заготовки, id_заказа)
);
-- ============================================================================
-- 4. RESTORE DATA FROM TEMP TABLES
-- ============================================================================
-- 4.1 расход_материалов
INSERT INTO расход_материалов (id_заготовки, id_материала, количество_материала)
SELECT DISTINCT ON (id_заготовки, id_материала) id_заготовки,
    id_материала,
    количество_материала
FROM temp_расход_материалов
WHERE id_заготовки IS NOT NULL
    AND id_материала IS NOT NULL;
-- 4.2 состав_изделия (переименовываем колонку)
INSERT INTO состав_изделия (id_изделия, id_заготовки, количество_заготовки)
SELECT DISTINCT ON (id_изделия, id_заготовки) id_изделия,
    id_заготовки,
    количество_заготовок
FROM temp_состав_изделия
WHERE id_изделия IS NOT NULL
    AND id_заготовки IS NOT NULL;
-- 4.3 состав_заказа
INSERT INTO состав_заказа (
        id_заказа,
        id_изделия,
        цена_фиксированная,
        количество_изделий
    )
SELECT DISTINCT ON (id_заказа, id_изделия) id_заказа,
    id_изделия,
    COALESCE(цена_фиксированная, 0),
    количество_изделий
FROM temp_состав_заказа
WHERE id_заказа IS NOT NULL
    AND id_изделия IS NOT NULL;
-- 4.4 состав_закупки
INSERT INTO состав_закупки (
        id_закупки,
        id_материала,
        количество,
        цена_закупки
    )
SELECT DISTINCT ON (id_закупки, id_материала) id_закупки,
    id_материала,
    количество,
    цена_закупки
FROM temp_состав_закупки
WHERE id_закупки IS NOT NULL
    AND id_материала IS NOT NULL;
-- 4.5 план_заготовок (aggregating if multiple entries per composite key)
INSERT INTO план_заготовок (
        id_заготовки,
        id_сотрудника,
        id_заказа,
        плановое_количество,
        фактическое_количество,
        дата_план,
        дата_факт,
        статус
    )
SELECT DISTINCT ON (id_заготовки, id_заказа) id_заготовки,
    id_сборщика,
    id_заказа,
    плановое_количество,
    COALESCE(фактическое_количество, 0),
    дата_план,
    дата_факт,
    COALESCE(статус, 'принято')
FROM temp_план_заготовок
WHERE id_заготовки IS NOT NULL
    AND id_заказа IS NOT NULL
ORDER BY id_заготовки,
    id_заказа,
    id_плана DESC;
-- ============================================================================
-- 5. DROP TEMP TABLES
-- ============================================================================
DROP TABLE temp_план_заготовок;
DROP TABLE temp_состав_заказа;
DROP TABLE temp_расход_материалов;
DROP TABLE temp_состав_изделия;
DROP TABLE temp_состав_закупки;
-- ============================================================================
-- 6. UPDATE STORED PROCEDURES
-- ============================================================================
-- 6.1 sp_взять_задачу_в_работу - now uses composite key
DROP PROCEDURE IF EXISTS sp_взять_задачу_в_работу(INTEGER, INTEGER);
CREATE OR REPLACE PROCEDURE sp_взять_задачу_в_работу(
        p_id_заготовки INTEGER,
        p_id_заказа INTEGER,
        p_id_сборщика INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
v_current_worker INTEGER;
BEGIN
SELECT статус,
    id_сотрудника INTO v_status,
    v_current_worker
FROM план_заготовок
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN RAISE EXCEPTION 'Задача не найдена';
END IF;
IF v_status NOT IN ('принято', 'просрочено') THEN RAISE EXCEPTION 'Задача уже в работе или завершена (статус: %)',
v_status;
END IF;
IF v_current_worker IS NOT NULL
AND v_current_worker != p_id_сборщика THEN RAISE EXCEPTION 'Задача уже назначена другому сборщику';
END IF;
UPDATE план_заготовок
SET id_сотрудника = p_id_сборщика
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
END;
$$;
-- 6.2 sp_сдать_работу - now uses composite key  
DROP PROCEDURE IF EXISTS sp_сдать_работу(INTEGER, INTEGER);
CREATE OR REPLACE PROCEDURE sp_сдать_работу(
        p_id_заготовки INTEGER,
        p_id_заказа INTEGER,
        p_количество INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
v_planned INTEGER;
v_actual INTEGER;
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
UPDATE план_заготовок
SET фактическое_количество = фактическое_количество + p_количество,
    дата_факт = CURRENT_DATE
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
-- Update component stock incrementally
UPDATE заготовки
SET количество_готовых = количество_готовых + p_количество
WHERE id_заготовки = p_id_заготовки;
-- Check if task is complete
IF (v_actual + p_количество) >= v_planned THEN
UPDATE план_заготовок
SET статус = 'выполнено'
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
END IF;
END;
$$;
-- 6.3 sp_get_production_dashboard_data - update to use composite key
DROP FUNCTION IF EXISTS sp_get_production_dashboard_data(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_production_dashboard_data(p_user_id INTEGER) RETURNS TABLE (
        id_заготовки INTEGER,
        id_заказа INTEGER,
        наименование_заготовки VARCHAR,
        плановое_количество INTEGER,
        фактическое_количество INTEGER,
        дата_план DATE,
        статус VARCHAR,
        id_клиента INTEGER,
        фио_клиента VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT pz.id_заготовки,
    pz.id_заказа,
    z.наименование,
    pz.плановое_количество,
    pz.фактическое_количество,
    pz.дата_план,
    pz.статус,
    o.id_клиента,
    k.фио
FROM план_заготовок pz
    JOIN заготовки z ON pz.id_заготовки = z.id_заготовки
    JOIN заказы o ON pz.id_заказа = o.id_заказа
    JOIN клиенты k ON o.id_клиента = k.id_клиента
WHERE (
        pz.id_сотрудника = p_user_id
        OR pz.id_сотрудника IS NULL
    )
    AND pz.статус NOT IN ('выполнено', 'отменено')
ORDER BY pz.дата_план;
END;
$$;
-- 6.4 Update sp_report_defect to work with new schema
DROP FUNCTION IF EXISTS sp_report_defect(INTEGER, INTEGER, INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_report_defect(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_defect_qty INTEGER,
        p_reason VARCHAR
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_qty INTEGER;
v_component RECORD;
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
-- Reduce quantity
UPDATE состав_заказа
SET количество_изделий = количество_изделий - p_defect_qty
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
-- Revert order status if needed
UPDATE заказы
SET статус = 'в_работе'
WHERE id_заказа = p_order_id
    AND статус IN ('выполнен', 'готов_к_отгрузке');
-- Create production tasks for replacement (using INSERT ... ON CONFLICT)
FOR v_component IN
SELECT si.id_заготовки,
    si.количество_заготовки * p_defect_qty as qty
FROM состав_изделия si
WHERE si.id_изделия = p_product_id LOOP
INSERT INTO план_заготовок (
        id_заготовки,
        id_заказа,
        плановое_количество,
        дата_план,
        статус
    )
VALUES (
        v_component.id_заготовки,
        p_order_id,
        v_component.qty,
        (
            SELECT дата_готовности
            FROM заказы
            WHERE id_заказа = p_order_id
        ) - INTERVAL '1 day',
        'принято'
    ) ON CONFLICT (id_заготовки, id_заказа) DO
UPDATE
SET плановое_количество = план_заготовок.плановое_количество + EXCLUDED.плановое_количество;
END LOOP;
status := 'WARNING';
message := 'Брак зафиксирован (' || p_defect_qty || ' шт). Созданы задания на доизготовление. Причина: ' || p_reason;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 6.5 sp_get_product_components - update column name
DROP FUNCTION IF EXISTS sp_get_product_components(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_product_components(p_product_id INTEGER) RETURNS TABLE (
        id_заготовки INTEGER,
        наименование VARCHAR,
        количество INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.id_заготовки,
    z.наименование,
    si.количество_заготовки
FROM состав_изделия si
    JOIN заготовки z ON si.id_заготовки = z.id_заготовки
WHERE si.id_изделия = p_product_id;
END;
$$;
-- 6.6 sp_add_product_component
DROP FUNCTION IF EXISTS sp_add_product_component(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_add_product_component(
        p_product_id INTEGER,
        p_component_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
INSERT INTO состав_изделия (id_изделия, id_заготовки, количество_заготовки)
VALUES (p_product_id, p_component_id, p_qty) ON CONFLICT (id_изделия, id_заготовки) DO NOTHING;
IF NOT FOUND THEN status := 'ERROR';
message := 'Эта заготовка уже есть в составе изделия';
RETURN NEXT;
RETURN;
END IF;
status := 'OK';
message := 'Заготовка добавлена в состав';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 6.7 sp_update_product_component
DROP FUNCTION IF EXISTS sp_update_product_component(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_update_product_component(
        p_product_id INTEGER,
        p_component_id INTEGER,
        p_new_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE состав_изделия
SET количество_заготовки = p_new_qty
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
-- 6.8 sp_delete_product_component
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
-- 6.9 sp_get_component_materials - for ComponentsTab
DROP FUNCTION IF EXISTS sp_get_component_materials(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_component_materials(p_component_id INTEGER) RETURNS TABLE (
        id_материала INTEGER,
        наименование VARCHAR,
        количество INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    rm.количество_материала
FROM расход_материалов rm
    JOIN материалы m ON rm.id_материала = m.id_материала
WHERE rm.id_заготовки = p_component_id;
END;
$$;
-- 6.10 sp_add_component_material
DROP FUNCTION IF EXISTS sp_add_component_material(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_add_component_material(
        p_component_id INTEGER,
        p_material_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
INSERT INTO расход_материалов (id_заготовки, id_материала, количество_материала)
VALUES (p_component_id, p_material_id, p_qty) ON CONFLICT (id_заготовки, id_материала) DO NOTHING;
IF NOT FOUND THEN status := 'ERROR';
message := 'Этот материал уже есть в составе заготовки';
RETURN NEXT;
RETURN;
END IF;
status := 'OK';
message := 'Материал добавлен';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 6.11 sp_update_component_material
DROP FUNCTION IF EXISTS sp_update_component_material(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_update_component_material(
        p_component_id INTEGER,
        p_material_id INTEGER,
        p_new_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE расход_материалов
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
-- 6.12 sp_delete_component_material
DROP FUNCTION IF EXISTS sp_delete_component_material(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_delete_component_material(
        p_component_id INTEGER,
        p_material_id INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
DELETE FROM расход_материалов
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
-- ============================================================================
-- 7. UPDATE VIEW v_задачи_сборщика to use composite key
-- ============================================================================
CREATE OR REPLACE VIEW v_задачи_сборщика AS
SELECT pz.id_заготовки,
    pz.id_заказа,
    z.наименование as заготовка,
    pz.плановое_количество,
    pz.фактическое_количество,
    pz.дата_план as дедлайн,
    pz.статус,
    pz.id_сотрудника as id_сборщика
FROM план_заготовок pz
    JOIN заготовки z ON pz.id_заготовки = z.id_заготовки;
-- ============================================================================
-- 8. UPDATE STORED PROCEDURES FOR production_planning_tab
-- ============================================================================
-- 8.1 sp_get_production_plan_full - returns composite keys
DROP FUNCTION IF EXISTS sp_get_production_plan_full();
CREATE OR REPLACE FUNCTION sp_get_production_plan_full() RETURNS TABLE (
        id_заготовки INTEGER,
        id_заказа INTEGER,
        заготовка VARCHAR,
        плановое_количество INTEGER,
        фактическое_количество INTEGER,
        дедлайн DATE,
        статус VARCHAR,
        сборщик VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT pz.id_заготовки,
    pz.id_заказа,
    z.наименование,
    pz.плановое_количество,
    pz.фактическое_количество,
    pz.дата_план,
    pz.статус,
    COALESCE(s.фио, 'Не назначен')::VARCHAR
FROM план_заготовок pz
    JOIN заготовки z ON pz.id_заготовки = z.id_заготовки
    LEFT JOIN сотрудники s ON pz.id_сотрудника = s.id_сотрудника
ORDER BY pz.дата_план;
END;
$$;
-- 8.2 sp_release_task - now uses composite key
DROP FUNCTION IF EXISTS sp_release_task(INTEGER);
CREATE OR REPLACE FUNCTION sp_release_task(
        p_id_заготовки INTEGER,
        p_id_заказа INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE план_заготовок
SET id_сотрудника = NULL
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
RETURN NEXT;
RETURN;
END IF;
status := 'OK';
message := 'Задача освобождена';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 8.3 sp_assign_worker_to_task - now uses composite key
DROP FUNCTION IF EXISTS sp_assign_worker_to_task(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_assign_worker_to_task(
        p_id_заготовки INTEGER,
        p_id_заказа INTEGER,
        p_worker_id INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_worker INTEGER;
BEGIN
SELECT id_сотрудника INTO v_current_worker
FROM план_заготовок
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
RETURN NEXT;
RETURN;
END IF;
IF v_current_worker IS NOT NULL THEN status := 'WARNING';
message := 'Задача уже была назначена, переназначена';
ELSE status := 'OK';
message := 'Сборщик назначен';
END IF;
UPDATE план_заготовок
SET id_сотрудника = p_worker_id
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- 8.4 sp_add_manual_component_task - now uses ON CONFLICT for composite key
DROP FUNCTION IF EXISTS sp_add_manual_component_task(INTEGER, INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_add_manual_component_task(
        p_order_id INTEGER,
        p_component_id INTEGER,
        p_qty INTEGER,
        p_worker_id INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
INSERT INTO план_заготовок (
        id_заготовки,
        id_заказа,
        плановое_количество,
        дата_план,
        id_сотрудника,
        статус
    )
VALUES (
        p_component_id,
        p_order_id,
        p_qty,
        (
            SELECT COALESCE(
                    дата_готовности,
                    CURRENT_DATE + INTERVAL '7 days'
                )
            FROM заказы
            WHERE id_заказа = p_order_id
        ),
        p_worker_id,
        'принято'
    ) ON CONFLICT (id_заготовки, id_заказа) DO
UPDATE
SET плановое_количество = план_заготовок.плановое_количество + EXCLUDED.плановое_количество;
status := 'OK';
message := 'Задача добавлена в план';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
COMMIT;