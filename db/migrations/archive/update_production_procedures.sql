


DROP PROCEDURE IF EXISTS sp_set_day_status(INTEGER, DATE, VARCHAR);
CREATE OR REPLACE PROCEDURE sp_set_day_status(
        p_employee_id INTEGER,
        p_date DATE,
        p_status VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN
INSERT INTO График (id_сотрудника, дата, статус)
VALUES (p_employee_id, p_date, p_status) ON CONFLICT (id_сотрудника, дата) DO
UPDATE
SET статус = p_status;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_assembler_tasks();
CREATE OR REPLACE FUNCTION sp_get_assembler_tasks() RETURNS TABLE (
        тип_задачи VARCHAR,
        id_объекта INTEGER,
        
        id_заказа INTEGER,
        наименование_задачи VARCHAR,
        плановое_количество INTEGER,
        фактическое_количество INTEGER,
        дедлайн DATE,
        статус VARCHAR,
        id_сборщика INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY 
SELECT 'заготовка'::VARCHAR as тип_задачи,
    pz.id_заготовки as id_объекта,
    pz.id_заказа,
    z.наименование as наименование_задачи,
    pz.плановое_количество,
    pz.фактическое_количество,
    pz.дата_план as дедлайн,
    pz.статус,
    pz.id_сотрудника as id_сборщика
FROM ПланЗаготовок pz
    JOIN Заготовка z ON pz.id_заготовки = z.id_заготовки
UNION ALL


SELECT 'сборка'::VARCHAR as тип_задачи,
    ps.id_изделия as id_объекта,
    ps.id_заказа,
    i.наименование as наименование_задачи,
    ps.количество_план as плановое_количество,
    ps.количество_факт as фактическое_количество,
    ps.дата_план as дедлайн,
    ps.статус,
    ps.id_сотрудника as id_сборщика
FROM ПланСборки ps
    JOIN Изделие i ON ps.id_изделия = i.id_изделия
ORDER BY дедлайн;
END;
$$;

DROP PROCEDURE IF EXISTS sp_take_component_task(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE PROCEDURE sp_take_component_task(
        p_component_id INTEGER,
        p_order_id INTEGER,
        p_worker_id INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
v_current_worker INTEGER;
BEGIN
SELECT статус,
    id_сотрудника INTO v_status,
    v_current_worker
FROM ПланЗаготовок
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
IF NOT FOUND THEN RAISE EXCEPTION 'Задача не найдена';
END IF;
IF v_status NOT IN ('принято', 'просрочено') THEN RAISE EXCEPTION 'Задача уже в работе или завершена (статус: %)',
v_status;
END IF;
IF v_current_worker IS NOT NULL
AND v_current_worker != p_worker_id THEN RAISE EXCEPTION 'Задача уже назначена другому сборщику';
END IF;
UPDATE ПланЗаготовок
SET id_сотрудника = p_worker_id,
    статус = 'в_работе' 
    
    
    
    
    
    
    
    
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
END;
$$;

DROP PROCEDURE IF EXISTS sp_submit_component_work(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE PROCEDURE sp_submit_component_work(
        p_component_id INTEGER,
        p_order_id INTEGER,
        p_qty INTEGER
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
FROM ПланЗаготовок
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
IF NOT FOUND THEN RAISE EXCEPTION 'Задача не найдена';
END IF;
IF v_status = 'выполнено' THEN RAISE EXCEPTION 'Задача уже выполнена';
END IF;
UPDATE ПланЗаготовок
SET фактическое_количество = фактическое_количество + p_qty,
    дата_факт = CURRENT_DATE,
    статус = CASE
        WHEN (фактическое_количество + p_qty) >= плановое_количество THEN 'выполнено'
        ELSE 'в_работе'
    END
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;

UPDATE Заготовка
SET количество_готовых = количество_готовых + p_qty
WHERE id_заготовки = p_component_id;
END;
$$;

DROP PROCEDURE IF EXISTS sp_take_assembly_task(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE PROCEDURE sp_take_assembly_task(
        p_product_id INTEGER,
        p_order_id INTEGER,
        p_worker_id INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN
UPDATE ПланСборки
SET id_сотрудника = p_worker_id,
    статус = 'в_работе'
WHERE id_изделия = p_product_id
    AND id_заказа = p_order_id;
END;
$$;

DROP PROCEDURE IF EXISTS sp_submit_assembly_work(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE PROCEDURE sp_submit_assembly_work(
        p_product_id INTEGER,
        p_order_id INTEGER,
        p_qty INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
v_planned INTEGER;
v_actual INTEGER;
BEGIN
SELECT статус,
    количество_план,
    количество_факт INTO v_status,
    v_planned,
    v_actual
FROM ПланСборки
WHERE id_изделия = p_product_id
    AND id_заказа = p_order_id;
IF v_status = 'выполнено' THEN RAISE EXCEPTION 'Сборка уже выполнена';
END IF;



UPDATE ПланСборки
SET количество_факт = количество_факт + p_qty,
    статус = CASE
        WHEN (количество_факт + p_qty) >= количество_план THEN 'выполнено'
        ELSE 'в_работе'
    END
WHERE id_изделия = p_product_id
    AND id_заказа = p_order_id;

UPDATE Изделие
SET количество_на_складе = количество_на_складе + p_qty
WHERE id_изделия = p_product_id;
END;
$$;