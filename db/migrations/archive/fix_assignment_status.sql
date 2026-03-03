
DROP FUNCTION IF EXISTS sp_assign_worker_to_task(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_assign_worker_to_task(
        p_id_заготовки INTEGER,
        p_id_заказа INTEGER,
        p_worker_id INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_worker INTEGER;
BEGIN
SELECT id_сотрудника INTO v_current_worker
FROM ПланЗаготовок
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
RETURN NEXT;
RETURN;
END IF;

IF v_current_worker IS NOT NULL THEN status := 'WARNING';
message := 'Задача переназначена (ранее была у другого сотрудника)';
ELSE status := 'OK';
message := 'Сборщик назначен';
END IF;
UPDATE ПланЗаготовок
SET id_сотрудника = p_worker_id,
    статус = 'в_работе' 
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;