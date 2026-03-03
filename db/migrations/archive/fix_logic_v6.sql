
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
FROM ПланЗаготовок
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN RAISE EXCEPTION 'Задача не найдена';
END IF;
IF v_status = 'выполнено' THEN RAISE EXCEPTION 'Задача уже выполнена';
END IF;
IF v_status = 'отменено' THEN RAISE EXCEPTION 'Задача отменена';
END IF;

UPDATE ПланЗаготовок
SET фактическое_количество = фактическое_количество + p_количество,
    дата_факт = CURRENT_DATE
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;

UPDATE Заготовка
SET количество_готовых = количество_готовых + p_количество
WHERE id_заготовки = p_id_заготовки;

IF (v_actual + p_количество) >= v_planned THEN
UPDATE ПланЗаготовок
SET статус = 'выполнено'
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
END IF;
END;
$$;