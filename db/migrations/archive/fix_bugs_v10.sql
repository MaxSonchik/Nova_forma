

ALTER TABLE СоставИзделия
ADD COLUMN IF NOT EXISTS количество_заготовок INTEGER DEFAULT 1 CHECK (количество_заготовок > 0);

DROP FUNCTION IF EXISTS sp_hire_employee(
    VARCHAR,
    VARCHAR,
    DATE,
    VARCHAR,
    INTEGER,
    VARCHAR,
    VARCHAR
);
DROP FUNCTION IF EXISTS sp_hire_employee(
    VARCHAR,
    VARCHAR,
    VARCHAR,
    VARCHAR,
    INTEGER,
    VARCHAR,
    VARCHAR
);
CREATE OR REPLACE FUNCTION sp_hire_employee(
        p_fio VARCHAR,
        p_phone VARCHAR,
        p_birth_date DATE,
        
        p_role VARCHAR,
        p_salary INTEGER,
        p_login VARCHAR,
        p_password_raw VARCHAR
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN 
    IF LENGTH(p_fio) < 5 THEN status := 'ERROR';
message := 'ФИО слишком короткое';
RETURN NEXT;
RETURN;
END IF;
IF LENGTH(p_phone) < 5 THEN status := 'ERROR';
message := 'Телефон некорректен';
RETURN NEXT;
RETURN;
END IF;
IF p_birth_date > (CURRENT_DATE - INTERVAL '18 years') THEN status := 'ERROR';
message := 'Сотрудник должен быть совершеннолетним';
RETURN NEXT;
RETURN;
END IF;

INSERT INTO Сотрудник (
        фио,
        номер_телефона,
        дата_рождения,
        должность,
        оклад,
        логин,
        пароль_хеш
    )
VALUES (
        p_fio,
        p_phone,
        p_birth_date,
        p_role,
        p_salary,
        p_login,
        crypt(p_password_raw, gen_salt('bf'))
    );
status := 'OK';
message := 'Сотрудник успешно нанят';
RETURN NEXT;
EXCEPTION
WHEN UNIQUE_VIOLATION THEN status := 'ERROR';
message := 'Логин уже занят';
RETURN NEXT;
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION sp_update_order_status(
        p_order_id INTEGER,
        p_new_status VARCHAR
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_status VARCHAR;
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

IF p_new_status = 'отменен'
AND v_current_status IN ('выполнен', 'отгружен', 'завершен') THEN status := 'ERROR';
message := 'Нельзя отменить уже выполненный или отгруженный заказ!';
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



UPDATE Материал m
SET количество_на_складе = GREATEST(
        0,
        количество_на_складе - (sz.количество_материала * p_количество)
    )
FROM СоставЗаготовки sz
WHERE sz.id_заготовки = p_id_заготовки
    AND m.id_материала = sz.id_материала;

IF (v_actual + p_количество) >= v_planned THEN
UPDATE ПланЗаготовок
SET статус = 'выполнено'
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
END IF;
END;
$$;