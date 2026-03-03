


DROP PROCEDURE IF EXISTS sp_submit_component_work(INTEGER, INTEGER, INTEGER);
DROP PROCEDURE IF EXISTS sp_submit_component_work(INTEGER, INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE PROCEDURE sp_submit_component_work(
        p_component_id INTEGER,
        p_order_id INTEGER,
        p_qty INTEGER,
        p_worker_id INTEGER 
    ) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
v_planned INTEGER;
v_actual INTEGER;
v_assigned_worker INTEGER;
BEGIN
SELECT статус,
    плановое_количество,
    COALESCE(фактическое_количество, 0),
    id_сотрудника INTO v_status,
    v_planned,
    v_actual,
    v_assigned_worker
FROM ПланЗаготовок
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
IF NOT FOUND THEN RAISE EXCEPTION 'Задача не найдена';
END IF;

IF v_assigned_worker IS NULL THEN RAISE EXCEPTION 'Задача не взята в работу (не назначен исполнитель)';
ELSIF v_assigned_worker != p_worker_id THEN RAISE EXCEPTION 'Вы не являетесь исполнителем этой задачи';
END IF;
IF v_status = 'выполнено' THEN RAISE EXCEPTION 'Задача уже выполнена';
END IF;

UPDATE ПланЗаготовок
SET фактическое_количество = COALESCE(фактическое_количество, 0) + p_qty,
    дата_факт = CURRENT_DATE,
    статус = CASE
        WHEN (COALESCE(фактическое_количество, 0) + p_qty) >= плановое_количество THEN 'выполнено'
        ELSE 'в_работе'
    END
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;

UPDATE Заготовка
SET количество_готовых = количество_готовых + p_qty
WHERE id_заготовки = p_component_id;
END;
$$;