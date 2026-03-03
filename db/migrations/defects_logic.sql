


DROP FUNCTION IF EXISTS sp_report_defect(INTEGER, INTEGER, INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_report_defect(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER,
        p_reason VARCHAR
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_order_status VARCHAR;
BEGIN 
SELECT статус INTO v_order_status
FROM Заказ
WHERE id_заказа = p_order_id;
IF v_order_status IS NULL THEN status := 'ERROR';
message := 'Заказ не найден';
RETURN NEXT;
RETURN;
END IF;

IF v_order_status = 'завершен' THEN
UPDATE Заказ
SET статус = 'в_работе',
    дата_готовности = NULL
WHERE id_заказа = p_order_id;
END IF;








status := 'WARNING';

message := 'Статус заказа возвращен в "в_работе". Пожалуйста, создайте задачи на переделку вручную.';
RETURN NEXT;
END;
$$;