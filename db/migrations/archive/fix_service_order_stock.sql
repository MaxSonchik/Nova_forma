-- Fix: For service orders (id_клиента IS NULL), completed components
-- should be added to stock (Заготовка.количество_готовых).
-- For regular client orders, components are consumed by the order.
CREATE OR REPLACE FUNCTION sp_submit_component_work(
        p_component_id INTEGER,
        p_order_id INTEGER,
        p_qty INTEGER,
        p_worker_id INTEGER
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
v_planned INTEGER;
v_actual INTEGER;
v_assigned_worker INTEGER;
v_row_count INTEGER;
v_is_service_order BOOLEAN;
BEGIN
SELECT "ПланЗаготовок".статус,
    плановое_количество,
    COALESCE(фактическое_количество, 0),
    id_сотрудника INTO v_status,
    v_planned,
    v_actual,
    v_assigned_worker
FROM "ПланЗаготовок"
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
RETURN NEXT;
RETURN;
END IF;
IF v_assigned_worker IS NULL THEN status := 'ERROR';
message := 'Задача не взята в работу (не назначен исполнитель)';
RETURN NEXT;
RETURN;
ELSIF v_assigned_worker != p_worker_id THEN status := 'ERROR';
message := 'Вы не являетесь исполнителем этой задачи';
RETURN NEXT;
RETURN;
END IF;
IF v_status = 'выполнено' THEN status := 'ERROR';
message := 'Задача уже выполнена';
RETURN NEXT;
RETURN;
END IF;
IF (v_actual + p_qty) > v_planned THEN status := 'ERROR';
message := 'Нельзя сделать больше, чем запланировано! Осталось сделать: ' || (v_planned - v_actual);
RETURN NEXT;
RETURN;
END IF;
UPDATE "ПланЗаготовок"
SET фактическое_количество = COALESCE(фактическое_количество, 0) + p_qty,
    дата_факт = CURRENT_DATE,
    статус = CASE
        WHEN (COALESCE(фактическое_количество, 0) + p_qty) >= плановое_количество THEN 'выполнено'
        ELSE 'в_работе'
    END
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
GET DIAGNOSTICS v_row_count = ROW_COUNT;
IF v_row_count = 0 THEN status := 'ERROR';
message := 'Не удалось обновить задачу (данные изменились)';
RETURN NEXT;
RETURN;
END IF;
-- Check if this is a service order (no client = stock replenishment)
SELECT (id_клиента IS NULL) INTO v_is_service_order
FROM Заказ
WHERE id_заказа = p_order_id;
IF v_is_service_order THEN -- Service order: add completed components to warehouse stock
UPDATE Заготовка
SET количество_готовых = количество_готовых + p_qty
WHERE id_заготовки = p_component_id;
END IF;
-- For client orders: do NOT add to stock (components are consumed by the order)
status := 'OK';
message := 'Работа принята';
RETURN NEXT;
END;
$$;