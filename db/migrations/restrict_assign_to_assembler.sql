-- Restrict task assignment to assemblers only (role = 'сборщик')
CREATE OR REPLACE FUNCTION sp_assign_worker_to_task(
        p_id_заготовки INTEGER,
        p_id_заказа INTEGER,
        p_worker_id INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_fire_date DATE;
v_role VARCHAR;
BEGIN -- Check if employee exists and get their role
SELECT дата_увольнения,
    должность INTO v_fire_date,
    v_role
FROM Сотрудник
WHERE id_сотрудника = p_worker_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Сотрудник не найден';
RETURN NEXT;
RETURN;
END IF;
IF v_fire_date IS NOT NULL THEN status := 'ERROR';
message := 'Нельзя назначить задачу уволенному сотруднику';
RETURN NEXT;
RETURN;
END IF;
-- Only assemblers can be assigned to tasks
IF LOWER(v_role) != 'сборщик' THEN status := 'ERROR';
message := 'Задачу можно назначить только сотруднику с ролью "сборщик"';
RETURN NEXT;
RETURN;
END IF;
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