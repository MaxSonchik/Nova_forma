IF p_new_status = 'отменен' THEN 
FOR t IN (
    SELECT id_заготовки,
        статус,
        плановое_количество,
        COALESCE(фактическое_количество, 0) AS факт
    FROM "ПланЗаготовок"
    WHERE id_заказа = p_order_id
) LOOP 
IF t.статус = 'в_работе' THEN v_return_qty := t.плановое_количество - t.факт;
IF v_return_qty > 0 THEN FOR m IN (
    SELECT rm.id_материала,
        rm.количество_материала
    FROM РасходМатериалов rm
    WHERE rm.id_заготовки = t.id_заготовки
) LOOP
UPDATE Материал
SET количество_на_складе = количество_на_складе + (m.количество_материала * v_return_qty)
WHERE id_материала = m.id_материала;
END LOOP;
END IF;
END IF;

IF t.статус = 'выполнено'
AND t.факт > 0 THEN
UPDATE Заготовка
SET количество_готовых = количество_готовых + t.факт
WHERE id_заготовки = t.id_заготовки;
END IF;
END LOOP;
UPDATE "ПланЗаготовок"
SET статус = 'отменено'
WHERE id_заказа = p_order_id
    AND статус != 'отменено';
FOR c IN (
    SELECT si.id_заготовки,
        si.количество_заготовки * sz.количество_изделий AS total_needed
    FROM СоставЗаказа sz
        JOIN СоставИзделия si ON si.id_изделия = sz.id_изделия
    WHERE sz.id_заказа = p_order_id
) LOOP -- How much was tasked (from ПланЗаготовок)?
SELECT COALESCE(SUM(плановое_количество), 0) INTO v_task_planned
FROM "ПланЗаготовок"
WHERE id_заказа = p_order_id
    AND id_заготовки = c.id_заготовки;
v_stock_taken := c.total_needed - v_task_planned;
IF v_stock_taken > 0 THEN
UPDATE Заготовка
SET количество_готовых = количество_готовых + v_stock_taken
WHERE id_заготовки = c.id_заготовки;
END IF;
END LOOP;
END IF;
UPDATE Заказ
SET статус = p_new_status
WHERE id_заказа = p_order_id;
status := 'OK';
IF p_new_status = 'отменен' THEN message := 'Заказ отменен. Материалы и заготовки возвращены на склад.';
ELSE message := 'Статус обновлен';
END IF;
RETURN NEXT;
END;
$function$;
COMMIT;