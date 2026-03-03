-- Fix: sp_create_manual_production_task was using СоставЗаготовки (structural data)
-- instead of РасходМатериалов (transactional data) for material checks and deductions.
-- This caused different materials to be deducted depending on the order creation path.
CREATE OR REPLACE FUNCTION sp_create_manual_production_task(
        p_order_id INTEGER,
        p_component_id INTEGER,
        p_qty INTEGER,
        p_deadline DATE DEFAULT NULL
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_deadline DATE;
rm_rec RECORD;
v_missing_text VARCHAR := '';
BEGIN IF p_deadline IS NULL THEN
SELECT COALESCE(
        дата_готовности,
        CURRENT_DATE + INTERVAL '7 days'
    ) INTO v_deadline
FROM Заказ
WHERE id_заказа = p_order_id;
ELSE v_deadline := p_deadline;
END IF;
-- Check materials (using РасходМатериалов — transactional table)
FOR rm_rec IN (
    SELECT m.наименование,
        m.количество_на_складе,
        (COALESCE(rm.количество_материала, 0) * p_qty) AS needed
    FROM РасходМатериалов rm
        JOIN Материал m ON rm.id_материала = m.id_материала
    WHERE rm.id_заготовки = p_component_id
) LOOP IF COALESCE(rm_rec.количество_на_складе, 0) < rm_rec.needed THEN v_missing_text := v_missing_text || rm_rec.наименование || ' (нужно ' || rm_rec.needed || ', есть ' || COALESCE(rm_rec.количество_на_складе, 0) || '); ';
END IF;
END LOOP;
IF v_missing_text != '' THEN status := 'ERROR';
message := 'НЕОБХОДИМА ЗАКУПКА: Недостаточно материалов: ' || v_missing_text;
RETURN NEXT;
RETURN;
END IF;
-- Deduct materials (using РасходМатериалов)
FOR rm_rec IN (
    SELECT rm.id_материала,
        (COALESCE(rm.количество_материала, 0) * p_qty) AS needed
    FROM РасходМатериалов rm
    WHERE rm.id_заготовки = p_component_id
) LOOP
UPDATE Материал
SET количество_на_складе = количество_на_складе - rm_rec.needed
WHERE id_материала = rm_rec.id_материала;
END LOOP;
-- Create or update production task
IF EXISTS(
    SELECT 1
    FROM ПланЗаготовок
    WHERE id_заготовки = p_component_id
        AND id_заказа = p_order_id
        AND статус != 'выполнено'
) THEN
UPDATE ПланЗаготовок
SET плановое_количество = плановое_количество + p_qty
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id
    AND статус != 'выполнено';
ELSE
INSERT INTO ПланЗаготовок (
        id_заготовки,
        id_заказа,
        плановое_количество,
        дата_план,
        статус
    )
VALUES (
        p_component_id,
        p_order_id,
        p_qty,
        v_deadline,
        'принято'
    );
END IF;
status := 'OK';
message := 'Задача добавлена в план, материалы списаны';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;