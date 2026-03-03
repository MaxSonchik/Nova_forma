ALTER TABLE Заказ DROP CONSTRAINT IF EXISTS заказы_статус_check;
ALTER TABLE Заказ
ADD CONSTRAINT заказы_статус_check CHECK (
        статус IN (
            'принят',
            'в_обработке',
            'в_работе',
            'выполнен',
            'отменен',
            'отгружен',
            'завершен'
        )
    );
CREATE OR REPLACE PROCEDURE sp_отгрузить_заказ(p_id_заказа INTEGER) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
BEGIN
SELECT статус INTO v_status
FROM Заказ
WHERE id_заказа = p_id_заказа;
IF v_status != 'завершен' THEN RAISE EXCEPTION 'ОШИБКА: Можно отгрузить только завершённый заказ! Текущий статус: %',
v_status;
END IF;
UPDATE Заказ
SET статус = 'отгружен'
WHERE id_заказа = p_id_заказа;
END;
$$;
CREATE OR REPLACE PROCEDURE sp_закрыть_заказ(p_id_заказа INTEGER) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
BEGIN
SELECT статус INTO v_status
FROM Заказ
WHERE id_заказа = p_id_заказа;
IF v_status != 'отгружен' THEN RAISE EXCEPTION 'ОШИБКА: Можно закрыть только отгруженный заказ! Текущий статус: %',
v_status;
END IF;
UPDATE Заказ
SET статус = 'завершен'
WHERE id_заказа = p_id_заказа;
END;
$$;