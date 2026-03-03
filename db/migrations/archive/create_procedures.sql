





DROP FUNCTION IF EXISTS sp_get_clients();
CREATE OR REPLACE FUNCTION sp_get_clients() RETURNS TABLE (
        id_клиента INTEGER,
        фио VARCHAR,
        номер_телефона VARCHAR,
        адрес TEXT,
        дата_регистрации DATE,
        инн VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT *
FROM Клиент
ORDER BY фио;
END;
$$;

DROP FUNCTION IF EXISTS sp_search_clients(VARCHAR);
CREATE OR REPLACE FUNCTION sp_search_clients(p_query VARCHAR) RETURNS TABLE (
        id_клиента INTEGER,
        фио VARCHAR,
        номер_телефона VARCHAR,
        адрес TEXT,
        дата_регистрации DATE,
        инн VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT *
FROM Клиент
WHERE LOWER(фио) LIKE LOWER(p_query)
    OR LOWER(номер_телефона) LIKE LOWER(p_query)
ORDER BY фио;
END;
$$;

DROP FUNCTION IF EXISTS sp_add_client(VARCHAR, VARCHAR, TEXT, VARCHAR);
CREATE OR REPLACE FUNCTION sp_add_client(
        p_fio VARCHAR,
        p_phone VARCHAR,
        p_address TEXT,
        p_inn VARCHAR
    ) RETURNS TABLE (
        status VARCHAR,
        message VARCHAR,
        id_клиента INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE new_id INTEGER;
BEGIN
INSERT INTO Клиент (
        фио,
        номер_телефона,
        адрес,
        инн,
        дата_регистрации
    )
VALUES (p_fio, p_phone, p_address, p_inn, CURRENT_DATE)
RETURNING Клиент.id_клиента INTO new_id;
status := 'OK';
message := 'Клиент успешно добавлен';
id_клиента := new_id;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка добавления клиента: ' || SQLERRM;
id_клиента := NULL;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_update_client(INTEGER, VARCHAR, VARCHAR, VARCHAR, TEXT);
CREATE OR REPLACE FUNCTION sp_update_client(
        p_id INTEGER,
        p_fio VARCHAR,
        p_phone VARCHAR,
        p_inn VARCHAR,
        p_address TEXT
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE Клиент
SET фио = p_fio,
    номер_телефона = p_phone,
    адрес = p_address,
    инн = p_inn
WHERE id_клиента = p_id;
IF FOUND THEN status := 'OK';
message := 'Данные клиента обновлены';
ELSE status := 'ERROR';
message := 'Клиент не найден';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка обновления: ' || SQLERRM;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_save_client(INTEGER, VARCHAR, VARCHAR, VARCHAR, TEXT);
CREATE OR REPLACE FUNCTION sp_save_client(
        p_id INTEGER,
        p_fio VARCHAR,
        p_phone VARCHAR,
        p_inn VARCHAR,
        p_address TEXT
    ) RETURNS TABLE (
        status VARCHAR,
        message VARCHAR,
        id_клиента INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE v_new_id INTEGER;
BEGIN IF p_id IS NOT NULL THEN 
PERFORM sp_update_client(p_id, p_fio, p_phone, p_inn, p_address);
status := 'OK';
message := 'Клиент обновлен';
id_клиента := p_id;
RETURN NEXT;
ELSE 
INSERT INTO Клиент (
        фио,
        номер_телефона,
        адрес,
        инн,
        дата_регистрации
    )
VALUES (p_fio, p_phone, p_address, p_inn, CURRENT_DATE)
RETURNING Клиент.id_клиента INTO v_new_id;
status := 'OK';
message := 'Клиент создан';
id_клиента := v_new_id;
RETURN NEXT;
END IF;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка сохранения: ' || SQLERRM;
id_клиента := NULL;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_delete_client(INTEGER);
CREATE OR REPLACE FUNCTION sp_delete_client(p_client_id INTEGER) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN IF EXISTS (
        SELECT 1
        FROM Заказ
        WHERE id_клиента = p_client_id
    ) THEN status := 'ERROR';
message := 'Нельзя удалить клиента с активными заказами';
RETURN NEXT;
RETURN;
END IF;
DELETE FROM Клиент
WHERE id_клиента = p_client_id;
IF FOUND THEN status := 'OK';
message := 'Клиент удален';
ELSE status := 'ERROR';
message := 'Клиент не найден';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка удаления: ' || SQLERRM;
RETURN NEXT;
END;
$$;




DROP FUNCTION IF EXISTS sp_get_products();
CREATE OR REPLACE FUNCTION sp_get_products() RETURNS TABLE (
        id_изделия INTEGER,
        артикул_изделия VARCHAR,
        наименование VARCHAR,
        тип VARCHAR,
        размеры VARCHAR,
        стоимость NUMERIC,
        количество_на_складе INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT i.id_изделия,
    i.артикул_изделия,
    i.наименование,
    i.тип,
    i.размеры,
    i.стоимость,
    i.количество_на_складе
FROM Изделие i
ORDER BY i.наименование;
END;
$$;

DROP FUNCTION IF EXISTS sp_add_product(VARCHAR, VARCHAR, VARCHAR, VARCHAR, NUMERIC);
CREATE OR REPLACE FUNCTION sp_add_product(
        p_articul VARCHAR,
        p_name VARCHAR,
        p_type VARCHAR,
        p_size VARCHAR,
        p_price NUMERIC
    ) RETURNS TABLE (
        status VARCHAR,
        message VARCHAR,
        id_изделия INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE new_id INTEGER;
BEGIN
INSERT INTO Изделие (
        артикул_изделия,
        наименование,
        тип,
        размеры,
        стоимость,
        количество_на_складе
    )
VALUES (p_articul, p_name, p_type, p_size, p_price, 0)
RETURNING Изделие.id_изделия INTO new_id;
status := 'OK';
message := 'Изделие создано';
id_изделия := new_id;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка создания изделия: ' || SQLERRM;
id_изделия := NULL;
RETURN NEXT;
END;
$$;




DROP FUNCTION IF EXISTS sp_search_orders(INTEGER, VARCHAR, VARCHAR, DATE, DATE);
CREATE OR REPLACE FUNCTION sp_search_orders(
        p_user_id INTEGER,
        p_search_text VARCHAR,
        p_status VARCHAR,
        p_date_from DATE,
        p_date_to DATE
    ) RETURNS TABLE (
        id_заказа INTEGER,
        клиент VARCHAR,
        менеджер VARCHAR,
        дата_заказа DATE,
        дата_готовности DATE,
        статус_заказа VARCHAR,
        сумма_заказа NUMERIC,
        состояние_сроков VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.id_заказа,
    k.фио as клиент,
    s.фио as менеджер,
    z.дата_заказа,
    z.дата_готовности,
    z.статус as статус_заказа,
    z.сумма_заказа,
    CASE
        WHEN z.статус NOT IN ('выполнен', 'отгружен', 'завершен', 'отменен')
        AND z.дата_готовности < CURRENT_DATE THEN 'ПРОСРОЧЕН'::VARCHAR
        ELSE 'OK'::VARCHAR
    END as состояние_сроков
FROM Заказ z
    LEFT JOIN Клиент k ON z.id_клиента = k.id_клиента
    LEFT JOIN Сотрудник s ON z.id_менеджера = s.id_сотрудника
WHERE (
        p_search_text IS NULL
        OR LOWER(k.фио) LIKE LOWER('%' || p_search_text || '%')
        OR CAST(z.id_заказа AS VARCHAR) LIKE p_search_text
    )
    AND (
        p_status IS NULL
        OR z.статус = p_status
    )
    AND (
        p_date_from IS NULL
        OR z.дата_заказа >= p_date_from
    )
    AND (
        p_date_to IS NULL
        OR z.дата_заказа <= p_date_to
    )
ORDER BY z.дата_заказа DESC;
END;
$$;

DROP FUNCTION IF EXISTS sp_create_order(INTEGER, INTEGER, DATE);
CREATE OR REPLACE FUNCTION sp_create_order(
        p_client_id INTEGER,
        p_manager_id INTEGER,
        p_deadline DATE
    ) RETURNS TABLE (
        status VARCHAR,
        message VARCHAR,
        id_заказа INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE new_id INTEGER;
BEGIN
INSERT INTO Заказ (
        id_клиента,
        id_менеджера,
        дата_заказа,
        дата_готовности,
        статус,
        сумма_заказа
    )
VALUES (
        p_client_id,
        p_manager_id,
        CURRENT_DATE,
        p_deadline,
        'новый',
        0
    )
RETURNING Заказ.id_заказа INTO new_id;
status := 'OK';
message := 'Заказ создан';
id_заказа := new_id;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка создания заказа: ' || SQLERRM;
id_заказа := NULL;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_add_order_item(INTEGER, INTEGER, INTEGER, NUMERIC);
CREATE OR REPLACE FUNCTION sp_add_order_item(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER,
        p_price NUMERIC DEFAULT NULL 
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_price NUMERIC;
BEGIN 
IF p_price IS NULL THEN
SELECT стоимость INTO v_price
FROM Изделие
WHERE id_изделия = p_product_id;
ELSE v_price := p_price;
END IF;
INSERT INTO СоставЗаказа (
        id_заказа,
        id_изделия,
        количество_изделий,
        цена_фиксированная
    )
VALUES (
        p_order_id,
        p_product_id,
        p_qty,
        COALESCE(v_price, 0)
    );

UPDATE Заказ
SET сумма_заказа = (
        SELECT COALESCE(SUM(количество_изделий * цена_фиксированная), 0)
        FROM СоставЗаказа
        WHERE id_заказа = p_order_id
    )
WHERE id_заказа = p_order_id;
status := 'OK';
message := 'Позиция добавлена';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка добавления позиции: ' || SQLERRM;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_order_items(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_order_items(p_order_id INTEGER) RETURNS TABLE (
        id_изделия INTEGER,
        наименование VARCHAR,
        количество_изделий INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT sz.id_изделия,
    i.наименование,
    sz.количество_изделий
FROM СоставЗаказа sz
    JOIN Изделие i ON sz.id_изделия = i.id_изделия
WHERE sz.id_заказа = p_order_id;
END;
$$;

DROP FUNCTION IF EXISTS sp_update_order_status(INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_update_order_status(p_order_id INTEGER, p_status VARCHAR) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE Заказ
SET статус = p_status
WHERE id_заказа = p_order_id;
IF FOUND THEN status := 'OK';
message := 'Статус обновлен: ' || p_status;
ELSE status := 'ERROR';
message := 'Заказ не найден';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка обновления статуса: ' || SQLERRM;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_report_defect(INTEGER, INTEGER, INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_report_defect(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_defect_qty INTEGER,
        p_reason VARCHAR
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_qty INTEGER;
v_old_status VARCHAR;
BEGIN
SELECT количество_изделий INTO v_current_qty
FROM СоставЗаказа
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
SELECT статус INTO v_old_status
FROM Заказ
WHERE id_заказа = p_order_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Позиция не найдена в заказе';
RETURN NEXT;
RETURN;
END IF;
IF p_defect_qty > v_current_qty THEN status := 'ERROR';
message := 'Количество брака превышает количество в заказе';
RETURN NEXT;
RETURN;
END IF;

UPDATE СоставЗаказа
SET количество_изделий = количество_изделий - p_defect_qty
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;

IF v_old_status IN ('выполнен', 'готов_к_отгрузке') THEN
UPDATE Заказ
SET статус = 'в_работе'
WHERE id_заказа = p_order_id;
END IF;

INSERT INTO ПланЗаготовок (
        id_заказа,
        id_заготовки,
        плановое_количество,
        дата_план,
        статус
    )
SELECT p_order_id,
    si.id_заготовки,
    si.количество_заготовок * p_defect_qty,
    (
        SELECT дата_готовности
        FROM Заказ
        WHERE id_заказа = p_order_id
    ) - INTERVAL '1 day',
    'принято'
FROM СоставИзделия si
WHERE si.id_изделия = p_product_id;
status := 'WARNING';
message := 'Брак: ' || p_defect_qty || ' шт. Статус заказа изменен на "в_работе". Созданы задания. Причина: ' || p_reason;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_order_tasks(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_order_tasks(p_order_id INTEGER) RETURNS TABLE (
        тип_задачи VARCHAR,
        наименование VARCHAR,
        плановое_количество INTEGER,
        статус VARCHAR
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT 'заготовка'::VARCHAR as тип_задачи,
    z.наименование,
    pz.плановое_количество,
    pz.статус
FROM ПланЗаготовок pz
    JOIN Заготовка z ON pz.id_заготовки = z.id_заготовки
WHERE pz.id_заказа = p_order_id 
UNION ALL
SELECT 'сборка'::VARCHAR as тип_задачи,
    i.наименование,
    ps.количество_план as плановое_количество,
    ps.статус
FROM ПланСборки ps
    JOIN Изделие i ON ps.id_изделия = i.id_изделия
WHERE ps.id_заказа = p_order_id;
END;
$$;




DROP FUNCTION IF EXISTS sp_confirm_purchase(INTEGER);
CREATE OR REPLACE FUNCTION sp_confirm_purchase(p_purchase_id INTEGER) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
rec RECORD;
BEGIN 
SELECT статус INTO v_status
FROM Закупка
WHERE id_закупки = p_purchase_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Закупка не найдена';
RETURN NEXT;
RETURN;
END IF;
IF v_status = 'выполнено' THEN status := 'ERROR';
message := 'Невозможно подтвердить выполненную закупку';
RETURN NEXT;
RETURN;
END IF;

UPDATE Закупка
SET статус = 'выполнено'
WHERE id_закупки = p_purchase_id;

FOR rec IN
SELECT id_материала,
    количество
FROM СоставЗакупки
WHERE id_закупки = p_purchase_id LOOP
UPDATE Материал
SET количество_на_складе = COALESCE(количество_на_складе, 0) + rec.количество
WHERE id_материала = rec.id_материала;
END LOOP;
status := 'OK';
message := 'Закупка подтверждена, склад обновлен';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка подтверждения: ' || SQLERRM;
RETURN NEXT;
END;
$$;




DROP FUNCTION IF EXISTS sp_get_materials();
CREATE OR REPLACE FUNCTION sp_get_materials() RETURNS TABLE (
        id_материала INTEGER,
        артикул_материала VARCHAR,
        наименование VARCHAR,
        количество_на_складе INTEGER,
        единица_измерения VARCHAR,
        цена_за_единицу NUMERIC
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT m.id_материала,
    m.артикул_материала,
    m.наименование,
    m.количество_на_складе,
    m.единица_измерения,
    m.цена_за_единицу
FROM Материал m
ORDER BY m.наименование;
END;
$$;

DROP FUNCTION IF EXISTS sp_add_material(VARCHAR, VARCHAR, VARCHAR, NUMERIC);
CREATE OR REPLACE FUNCTION sp_add_material(
        p_articul VARCHAR,
        p_name VARCHAR,
        p_unit VARCHAR,
        p_price NUMERIC
    ) RETURNS TABLE (
        status VARCHAR,
        message VARCHAR,
        id_материала INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE new_id INTEGER;
BEGIN
INSERT INTO Материал (
        артикул_материала,
        наименование,
        количество_на_складе,
        единица_измерения,
        цена_за_единицу
    )
VALUES (p_articul, p_name, 0, p_unit, p_price)
RETURNING Материал.id_материала INTO new_id;
status := 'OK';
message := 'Материал создан';
id_материала := new_id;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка создания материала: ' || SQLERRM;
id_материала := NULL;
RETURN NEXT;
END;
$$;