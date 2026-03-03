
CREATE OR REPLACE FUNCTION sp_update_order_status(p_order_id INTEGER, p_new_status VARCHAR) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_status VARCHAR;
BEGIN
SELECT s.статус INTO v_current_status
FROM Заказ s
WHERE s.id_заказа = p_order_id;
IF v_current_status IS NULL THEN status := 'ERROR';
message := 'Заказ не найден';
RETURN NEXT;
RETURN;
END IF;


IF v_current_status = 'отгружено' THEN status := 'ERROR';
message := 'Нельзя изменить статус отгруженного заказа.';
RETURN NEXT;
RETURN;
END IF;

IF v_current_status = 'готово'
AND p_new_status = 'в_работе' THEN 
UPDATE Заказ
SET статус = p_new_status
WHERE id_заказа = p_order_id;
status := 'OK';
message := 'Брак зафиксирован. Заказ возвращен в работу.';
RETURN NEXT;
RETURN;
END IF;


IF v_current_status = 'принят'
AND p_new_status = 'в_работе' THEN
UPDATE Заказ
SET статус = p_new_status
WHERE id_заказа = p_order_id;
status := 'OK';
message := 'Статус обновлен';
RETURN NEXT;
RETURN;
END IF;
IF v_current_status = 'в_работе'
AND p_new_status = 'готово' THEN
UPDATE Заказ
SET статус = p_new_status,
    дата_готовности = CURRENT_DATE
WHERE id_заказа = p_order_id;
status := 'OK';
message := 'Заказ готов';
RETURN NEXT;
RETURN;
END IF;
IF v_current_status = 'готово'
AND p_new_status = 'отгружено' THEN
UPDATE Заказ
SET статус = p_new_status
WHERE id_заказа = p_order_id;
status := 'OK';
message := 'Заказ отгружен';
RETURN NEXT;
RETURN;
END IF;

status := 'ERROR';
message := 'Недопустимая смена статуса: ' || v_current_status || ' -> ' || p_new_status;
RETURN NEXT;
END;
$$;