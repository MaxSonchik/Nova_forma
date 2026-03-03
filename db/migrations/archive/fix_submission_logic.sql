
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
    COALESCE(фактическое_количество, 0) INTO v_status,
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