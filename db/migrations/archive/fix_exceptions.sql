


DROP FUNCTION IF EXISTS sp_assign_worker_to_task(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_assign_worker_to_task(p_plan_id INTEGER, p_worker_id INTEGER) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_status VARCHAR;
v_current_worker INTEGER;
v_worker_load INTEGER;
BEGIN 
SELECT статус,
    id_сборщика INTO v_current_status,
    v_current_worker
FROM ПланЗаготовок
WHERE id_плана = p_plan_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
RETURN NEXT;
RETURN;
END IF;

IF v_current_status IN ('выполнено', 'отменено') THEN status := 'ERROR';
message := 'Нельзя назначить сборщика на завершенную/отмененную задачу. Статус: ' || v_current_status;
RETURN NEXT;
RETURN;
END IF;

IF v_current_worker IS NOT NULL
AND v_current_worker != p_worker_id THEN status := 'ERROR';
message := 'Задача уже назначена другому сборщику. Сначала освободите задачу.';
RETURN NEXT;
RETURN;
END IF;

SELECT COUNT(*) INTO v_worker_load
FROM ПланЗаготовок
WHERE id_сборщика = p_worker_id
    AND статус = 'в_работе';
UPDATE ПланЗаготовок
SET id_сборщика = p_worker_id
WHERE id_плана = p_plan_id;
IF v_worker_load >= 3 THEN status := 'WARNING';
message := 'Сборщик назначен. Внимание: у него уже ' || v_worker_load || ' активных задач!';
ELSE status := 'OK';
message := 'Сборщик назначен';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_release_task(INTEGER);
CREATE OR REPLACE FUNCTION sp_release_task(p_plan_id INTEGER) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_status VARCHAR;
BEGIN
SELECT статус INTO v_current_status
FROM ПланЗаготовок
WHERE id_плана = p_plan_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
RETURN NEXT;
RETURN;
END IF;

IF v_current_status NOT IN ('принято') THEN status := 'ERROR';
message := 'Нельзя освободить задачу со статусом: ' || v_current_status;
RETURN NEXT;
RETURN;
END IF;
UPDATE ПланЗаготовок
SET id_сборщика = NULL
WHERE id_плана = p_plan_id;
status := 'OK';
message := 'Задача освобождена';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_update_order_status(INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_update_order_status(
        p_order_id INTEGER,
        p_new_status VARCHAR
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_status VARCHAR;
v_missing_items TEXT := '';
rec RECORD;
BEGIN
SELECT статус INTO v_current_status
FROM Заказ
WHERE id_заказа = p_order_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Заказ не найден';
RETURN NEXT;
RETURN;
END IF;

IF p_new_status = 'в_работе'
AND v_current_status != 'принят' THEN status := 'ERROR';
message := 'Нельзя перевести в работу. Текущий статус: ' || v_current_status;
RETURN NEXT;
RETURN;
END IF;

IF p_new_status = 'выполнен' THEN IF v_current_status != 'в_работе' THEN status := 'ERROR';
message := 'Для завершения заказ должен быть в работе. Текущий: ' || v_current_status;
RETURN NEXT;
RETURN;
END IF;

FOR rec IN
SELECT z.наименование,
    pz.плановое_количество,
    pz.фактическое_количество,
    pz.статус
FROM ПланЗаготовок pz
    JOIN Заготовка z ON pz.id_заготовки = z.id_заготовки
WHERE pz.id_заказа = p_order_id
    AND pz.статус != 'выполнено' LOOP v_missing_items := v_missing_items || rec.наименование || ' (статус: ' || rec.статус || '), ';
END LOOP;
IF v_missing_items != '' THEN status := 'ERROR';
message := 'Не все производственные задачи завершены: ' || v_missing_items;
RETURN NEXT;
RETURN;
END IF;

FOR rec IN
SELECT i.наименование,
    sz.количество_изделий as required,
    i.количество_на_складе as stock
FROM СоставЗаказа sz
    JOIN Изделие i ON sz.id_изделия = i.id_изделия
WHERE sz.id_заказа = p_order_id
    AND i.количество_на_складе < sz.количество_изделий LOOP v_missing_items := v_missing_items || rec.наименование || ' (нужно: ' || rec.required || ', на складе: ' || rec.stock || '), ';
END LOOP;
IF v_missing_items != '' THEN status := 'ERROR';
message := 'Недостаточно изделий на складе: ' || v_missing_items;
RETURN NEXT;
RETURN;
END IF;
END IF;
IF p_new_status = 'отгружен'
AND v_current_status != 'выполнен' THEN status := 'ERROR';
message := 'Нельзя отгрузить. Заказ не готов. Текущий: ' || v_current_status;
RETURN NEXT;
RETURN;
END IF;

UPDATE Заказ
SET статус = p_new_status
WHERE id_заказа = p_order_id;
status := 'OK';
message := 'Статус изменен на: ' || p_new_status;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;