-- Fix: convert PROCEDUREs to FUNCTIONs returning TABLE(status, message)
-- because the python code uses SELECT * FROM proc() which crashes on PROCEDUREs.
DROP PROCEDURE IF EXISTS sp_take_assembly_task(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_take_assembly_task(
        p_product_id INTEGER,
        p_order_id INTEGER,
        p_worker_id INTEGER
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE ПланСборки
SET id_сотрудника = p_worker_id,
    статус = 'в_работе'
WHERE id_изделия = p_product_id
    AND id_заказа = p_order_id;
IF FOUND THEN status := 'OK';
message := 'Задача на сборку взята в работу';
ELSE status := 'ERROR';
message := 'Задача на сборку не найдена';
END IF;
RETURN NEXT;
END;
$$;
DROP PROCEDURE IF EXISTS sp_submit_assembly_work(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_submit_assembly_work(
        p_product_id INTEGER,
        p_order_id INTEGER,
        p_qty INTEGER,
        p_worker_id INTEGER DEFAULT '-'
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
v_planned INTEGER;
v_actual INTEGER;
BEGIN
SELECT статус,
    плановое_количество,
    COALESCE(фактическое_количество, 0) INTO v_status,
    v_planned,
    v_actual
FROM ПланСборки
WHERE id_изделия = p_product_id
    AND id_заказа = p_order_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача на сборку не найдена';
RETURN NEXT;
RETURN;
END IF;
IF v_status = 'выполнено' THEN status := 'ERROR';
message := 'Задача уже выполнена';
RETURN NEXT;
RETURN;
END IF;
IF (v_actual + p_qty) > v_planned THEN status := 'ERROR';
message := 'Нельзя сделать больше, чем запланировано!';
RETURN NEXT;
RETURN;
END IF;
UPDATE ПланСборки
SET фактическое_количество = COALESCE(фактическое_количество, 0) + p_qty,
    статус = CASE
        WHEN (COALESCE(фактическое_количество, 0) + p_qty) >= плановое_количество THEN 'выполнено'
        ELSE 'в_работе'
    END
WHERE id_изделия = p_product_id
    AND id_заказа = p_order_id;
status := 'OK';
message := 'Работа по сборке принята';
RETURN NEXT;
END;
$$;
DROP PROCEDURE IF EXISTS sp_set_day_status(INTEGER, DATE, VARCHAR);
CREATE OR REPLACE FUNCTION sp_set_day_status(
        p_employee_id INTEGER,
        p_date DATE,
        p_status VARCHAR
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
INSERT INTO УчетРабочегоВремени (id_сотрудника, дата, статус)
VALUES (p_employee_id, p_date, p_status) ON CONFLICT (id_сотрудника, дата) DO
UPDATE
SET статус = p_status;
status := 'OK';
message := 'Статус обновлен';
RETURN NEXT;
END;
$$;