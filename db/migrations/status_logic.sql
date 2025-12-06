-- 1. Удаляем таблицу логов (упрощение)
DROP TABLE IF EXISTS логи_операций CASCADE;

-- 2. Обновляем ограничение (CHECK) для статусов заказа
-- Нам нужно добавить статусы 'отгружен' и 'завершен'
ALTER TABLE заказы DROP CONSTRAINT IF EXISTS заказы_статус_check;

ALTER TABLE заказы 
ADD CONSTRAINT заказы_статус_check 
CHECK (статус IN ('принят', 'в_обработке', 'в_работе', 'выполнен', 'отменен', 'отгружен', 'завершен'));

-- 3. ПРОЦЕДУРА МЕНЕДЖЕРА: Отгрузка клиенту
-- Переводит из 'выполнен' в 'отгружен'. Требует, чтобы заказ был готов.
CREATE OR REPLACE PROCEDURE sp_отгрузить_заказ(p_id_заказа INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR;
BEGIN
    SELECT статус INTO v_status FROM заказы WHERE id_заказа = p_id_заказа;

    IF v_status != 'выполнен' THEN
        RAISE EXCEPTION 'ОШИБКА: Можно отгрузить только выполненный заказ! Текущий статус: %', v_status;
    END IF;

    UPDATE заказы SET статус = 'отгружен' WHERE id_заказа = p_id_заказа;
END;
$$;

-- 4. ПРОЦЕДУРА ДИРЕКТОРА: Закрытие заказа (Финал)
-- Переводит из 'отгружен' в 'завершен'. Подтверждает получение денег/документов.
CREATE OR REPLACE PROCEDURE sp_закрыть_заказ(p_id_заказа INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    v_status VARCHAR;
BEGIN
    SELECT статус INTO v_status FROM заказы WHERE id_заказа = p_id_заказа;

    IF v_status != 'отгружен' THEN
        RAISE EXCEPTION 'ОШИБКА: Можно закрыть только отгруженный заказ! Текущий статус: %', v_status;
    END IF;

    UPDATE заказы SET статус = 'завершен' WHERE id_заказа = p_id_заказа;
END;
$$;