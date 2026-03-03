




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
FROM расход_материалов rm
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

DROP FUNCTION IF EXISTS sp_assign_worker_to_task(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_assign_worker_to_task(
        p_id_заготовки INTEGER,
        
        p_id_заказа INTEGER,
        p_worker_id INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE ПланЗаготовок
SET id_сотрудника = p_worker_id,
    статус = 'назначено' 
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF FOUND THEN status := 'OK';
message := 'Сборщик назначен';
ELSE status := 'ERROR';
message := 'Задача не найдена';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_release_task(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_release_task(
        p_id_заготовки INTEGER,
        p_id_заказа INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE ПланЗаготовок
SET id_сотрудника = NULL,
    статус = 'принято' 
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF FOUND THEN status := 'OK';
message := 'Задача освобождена';
ELSE status := 'ERROR';
message := 'Задача не найдена';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;