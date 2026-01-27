-- Update sp_update_order_status to support cancellation
DROP FUNCTION IF EXISTS sp_update_order_status(INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_update_order_status(
        p_order_id INTEGER,
        p_new_status VARCHAR
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_status VARCHAR;
BEGIN
SELECT статус INTO v_current_status
FROM заказы
WHERE id_заказа = p_order_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Заказ не найден';
RETURN NEXT;
RETURN;
END IF;
-- Validate transitions
IF p_new_status = 'в_работе'
AND v_current_status != 'принят' THEN status := 'ERROR';
message := 'Нельзя перевести в работу. Текущий статус: ' || v_current_status;
RETURN NEXT;
RETURN;
END IF;
IF p_new_status = 'выполнен'
AND v_current_status != 'в_работе' THEN status := 'ERROR';
message := 'Нельзя завершить. Заказ должен быть в работе. Текущий: ' || v_current_status;
RETURN NEXT;
RETURN;
END IF;
IF p_new_status = 'отгружен'
AND v_current_status != 'выполнен' THEN status := 'ERROR';
message := 'Нельзя отгрузить. Заказ не готов. Текущий: ' || v_current_status;
RETURN NEXT;
RETURN;
END IF;
-- NEW: Allow cancellation from any active status (except maybe already shipped/completed if logic requires)
-- For now allowing cancellation from any status for flexibility, or maybe restrict 'отгружен'
IF p_new_status = 'отменен'
AND v_current_status IN ('отгружен', 'завершен') THEN status := 'ERROR';
message := 'Нельзя отменить завершенный/отгруженный заказ.';
RETURN NEXT;
RETURN;
END IF;
-- Perform update
UPDATE заказы
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