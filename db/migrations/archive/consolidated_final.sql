












DO $$ BEGIN IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'состав_заказа_order_product_unique'
) THEN 
IF NOT EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE table_name = 'СоставЗаказа'
        AND constraint_type = 'PRIMARY KEY'
        AND constraint_name LIKE '%id_заказа%id_изделия%'
) THEN 
ALTER TABLE СоставЗаказа
ADD CONSTRAINT состав_заказа_order_product_unique UNIQUE (id_заказа, id_изделия);
END IF;
END IF;
EXCEPTION
WHEN duplicate_table THEN NULL;
WHEN duplicate_object THEN NULL;
END $$;



CREATE TABLE IF NOT EXISTS ПланСборки (
    id_сборки SERIAL PRIMARY KEY,
    id_заказа INTEGER NOT NULL REFERENCES Заказ(id_заказа) ON DELETE CASCADE,
    id_изделия INTEGER NOT NULL REFERENCES Изделие(id_изделия),
    плановое_количество INTEGER NOT NULL CHECK(плановое_количество > 0),
    фактическое_количество INTEGER DEFAULT 0 CHECK(фактическое_количество >= 0),
    статус VARCHAR(30) DEFAULT 'принято' CHECK(
        статус IN ('принято', 'в_работе', 'выполнено', 'отменено')
    ),
    id_сборщика INTEGER REFERENCES Сотрудник(id_сотрудника),
    дата_план DATE,
    дата_факт DATE,
    UNIQUE(id_заказа, id_изделия)
);




DROP VIEW IF EXISTS v_задачи_сборщика CASCADE;
CREATE OR REPLACE VIEW v_задачи_сборщика AS 
SELECT 'заготовка'::VARCHAR AS тип_задачи,
    pz.id_заготовки AS id_задачи,
    pz.id_заказа,
    z.наименование AS наименование_задачи,
    pz.плановое_количество,
    pz.фактическое_количество,
    pz.статус,
    pz.id_сотрудника AS id_сборщика,
    pz.дата_план,
    pz.дата_факт,
    pz.id_заготовки AS id_объекта
FROM ПланЗаготовок pz
    JOIN Заготовка z ON pz.id_заготовки = z.id_заготовки
UNION ALL

SELECT 'сборка'::VARCHAR AS тип_задачи,
    ps.id_сборки AS id_задачи,
    ps.id_заказа,
    ('Сборка: ' || i.наименование)::VARCHAR AS наименование_задачи,
    ps.плановое_количество,
    ps.фактическое_количество,
    ps.статус,
    ps.id_сборщика,
    ps.дата_план,
    ps.дата_факт,
    ps.id_изделия AS id_объекта
FROM ПланСборки ps
    JOIN Изделие i ON ps.id_изделия = i.id_изделия;



DROP FUNCTION IF EXISTS sp_get_production_plan_full();
CREATE OR REPLACE FUNCTION sp_get_production_plan_full() RETURNS TABLE (
        id_заготовки INTEGER,
        id_заказа INTEGER,
        заготовка VARCHAR,
        плановое_количество INTEGER,
        фактическое_количество INTEGER,
        дедлайн DATE,
        статус VARCHAR,
        сборщик VARCHAR,
        тип_задачи VARCHAR,
        id_объекта INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT v.id_задачи AS id_заготовки,
    
    v.id_заказа,
    v.наименование_задачи AS заготовка,
    v.плановое_количество,
    v.фактическое_количество,
    v.дата_план AS дедлайн,
    v.статус,
    COALESCE(s.фио, 'Не назначен')::VARCHAR AS сборщик,
    v.тип_задачи,
    v.id_объекта
FROM v_задачи_сборщика v
    LEFT JOIN Сотрудник s ON v.id_сборщика = s.id_сотрудника
ORDER BY v.дата_план ASC;
END;
$$;




DROP FUNCTION IF EXISTS sp_get_order_tasks(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_order_tasks(p_order_id INTEGER) RETURNS TABLE (
        тип_задачи VARCHAR,
        наименование VARCHAR,
        плановое_количество INTEGER,
        статус VARCHAR,
        дедлайн DATE
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT v.тип_задачи,
    v.наименование_задачи,
    v.плановое_количество,
    v.статус,
    v.дата_план
FROM v_задачи_сборщика v
WHERE v.id_заказа = p_order_id
ORDER BY v.тип_задачи DESC,
    v.наименование_задачи;

END;
$$;




DROP FUNCTION IF EXISTS sp_add_order_item(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_add_order_item(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_stock INTEGER;
v_price NUMERIC;
v_missing_product INTEGER;
v_missing_material_name VARCHAR;
v_date_ready DATE;
rec RECORD;
v_exists BOOLEAN;
BEGIN 
SELECT стоимость,
    количество_на_складе INTO v_price,
    v_stock
FROM Изделие
WHERE id_изделия = p_product_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Изделие не найдено';
RETURN NEXT;
RETURN;
END IF;

SELECT EXISTS(
        SELECT 1
        FROM СоставЗаказа
        WHERE id_заказа = p_order_id
            AND id_изделия = p_product_id
    ) INTO v_exists;
IF v_exists THEN 
UPDATE СоставЗаказа
SET количество_изделий = количество_изделий + p_qty
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
ELSE 
INSERT INTO СоставЗаказа (
        id_заказа,
        id_изделия,
        количество_изделий,
        цена_фиксированная
    )
VALUES (p_order_id, p_product_id, p_qty, v_price);
END IF;

SELECT дата_готовности INTO v_date_ready
FROM Заказ
WHERE id_заказа = p_order_id;

IF v_stock >= p_qty THEN 
UPDATE Изделие
SET количество_на_складе = количество_на_складе - p_qty
WHERE id_изделия = p_product_id;
status := 'OK';
message := 'Изделия зарезервированы со склада.';
ELSE 
v_missing_product := p_qty - v_stock;

IF v_stock > 0 THEN
UPDATE Изделие
SET количество_на_складе = 0
WHERE id_изделия = p_product_id;
END IF;

SELECT m.наименование INTO v_missing_material_name
FROM СоставИзделия si
    JOIN расход_материалов rm ON si.id_заготовки = rm.id_заготовки
    JOIN Материал m ON rm.id_материала = m.id_материала
WHERE si.id_изделия = p_product_id
    AND m.количество_на_складе < (
        v_missing_product * si.количество_заготовки * rm.количество_материала
    )
LIMIT 1;
IF v_missing_material_name IS NOT NULL THEN 
IF v_exists THEN
UPDATE СоставЗаказа
SET количество_изделий = количество_изделий - p_qty
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
ELSE
DELETE FROM СоставЗаказа
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
END IF;

IF v_stock > 0 THEN
UPDATE Изделие
SET количество_на_складе = v_stock
WHERE id_изделия = p_product_id;
END IF;
status := 'ERROR';
message := 'НЕОБХОДИМА ЗАКУПКА: Для производства не хватает материала "' || v_missing_material_name || '"';
RETURN NEXT;
RETURN;
END IF;

IF EXISTS(
    SELECT 1
    FROM ПланСборки
    WHERE id_заказа = p_order_id
        AND id_изделия = p_product_id
) THEN
UPDATE ПланСборки
SET плановое_количество = плановое_количество + v_missing_product
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
ELSE
INSERT INTO ПланСборки (
        id_заказа,
        id_изделия,
        плановое_количество,
        дата_план,
        статус
    )
VALUES (
        p_order_id,
        p_product_id,
        v_missing_product,
        v_date_ready,
        'принято'
    );
END IF;

FOR rec IN
SELECT id_заготовки,
    количество_заготовки
FROM СоставИзделия
WHERE id_изделия = p_product_id LOOP IF EXISTS(
        SELECT 1
        FROM ПланЗаготовок
        WHERE id_заготовки = rec.id_заготовки
            AND id_заказа = p_order_id
    ) THEN
UPDATE ПланЗаготовок
SET плановое_количество = плановое_количество + (rec.количество_заготовки * v_missing_product)
WHERE id_заготовки = rec.id_заготовки
    AND id_заказа = p_order_id;
ELSE
INSERT INTO ПланЗаготовок (
        id_заготовки,
        id_заказа,
        плановое_количество,
        дата_план,
        статус
    )
VALUES (
        rec.id_заготовки,
        p_order_id,
        rec.количество_заготовки * v_missing_product,
        v_date_ready - INTERVAL '1 day',
        'принято'
    );
END IF;
END LOOP;
status := 'WARNING';
message := 'Недостаточно на складе. Созданы задания на производство ' || v_missing_product || ' ед.';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка добавления позиции: ' || SQLERRM;
RETURN NEXT;
END;
$$;



DROP PROCEDURE IF EXISTS sp_сдать_сборку(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE PROCEDURE sp_сдать_сборку(
        p_id_изделия INTEGER,
        p_id_заказа INTEGER,
        p_количество INTEGER
    ) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
v_planned INTEGER;
v_actual INTEGER;
v_missing_component_name VARCHAR;
BEGIN 
SELECT статус,
    плановое_количество,
    фактическое_количество INTO v_status,
    v_planned,
    v_actual
FROM ПланСборки
WHERE id_изделия = p_id_изделия
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN RAISE EXCEPTION 'Задача на сборку не найдена';
END IF;
IF v_status = 'выполнено' THEN RAISE EXCEPTION 'Сборка уже выполнена';
END IF;
IF v_status = 'отменено' THEN RAISE EXCEPTION 'Сборка отменена';
END IF;

SELECT z.наименование INTO v_missing_component_name
FROM СоставИзделия si
    JOIN Заготовка z ON si.id_заготовки = z.id_заготовки
WHERE si.id_изделия = p_id_изделия
    AND z.количество_готовых < (si.количество_заготовки * p_количество)
LIMIT 1;
IF v_missing_component_name IS NOT NULL THEN RAISE EXCEPTION 'Недостаточно заготовок "%" для сборки Изделие!',
v_missing_component_name;
END IF;

UPDATE Заготовка z
SET количество_готовых = количество_готовых - (si.количество_заготовки * p_количество)
FROM СоставИзделия si
WHERE si.id_изделия = p_id_изделия
    AND z.id_заготовки = si.id_заготовки;

UPDATE ПланСборки
SET фактическое_количество = фактическое_количество + p_количество,
    дата_факт = CURRENT_DATE
WHERE id_изделия = p_id_изделия
    AND id_заказа = p_id_заказа;

UPDATE Изделие
SET количество_на_складе = количество_на_складе + p_количество
WHERE id_изделия = p_id_изделия;

IF (v_actual + p_количество) >= v_planned THEN
UPDATE ПланСборки
SET статус = 'выполнено'
WHERE id_изделия = p_id_изделия
    AND id_заказа = p_id_заказа;
END IF;
END;
$$;



DROP FUNCTION IF EXISTS sp_create_manual_production_task(INTEGER, INTEGER, INTEGER, DATE);
CREATE OR REPLACE FUNCTION sp_create_manual_production_task(
        p_order_id INTEGER,
        p_component_id INTEGER,
        p_qty INTEGER,
        p_deadline DATE DEFAULT NULL
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_deadline DATE;
v_missing_material_name VARCHAR;
BEGIN 
IF p_deadline IS NULL THEN
SELECT COALESCE(
        дата_готовности,
        CURRENT_DATE + INTERVAL '7 days'
    ) INTO v_deadline
FROM Заказ
WHERE id_заказа = p_order_id;
ELSE v_deadline := p_deadline;
END IF;

SELECT m.наименование INTO v_missing_material_name
FROM расход_материалов rm
    JOIN Материал m ON rm.id_материала = m.id_материала
WHERE rm.id_заготовки = p_component_id
    AND m.количество_на_складе < (rm.количество_материала * p_qty)
LIMIT 1;
IF v_missing_material_name IS NOT NULL THEN status := 'ERROR';
message := 'НЕОБХОДИМА ЗАКУПКА: Недостаточно материала "' || v_missing_material_name || '" для изготовления Заготовка';
RETURN NEXT;
RETURN;
END IF;

IF EXISTS(
    SELECT 1
    FROM ПланЗаготовок
    WHERE id_заготовки = p_component_id
        AND id_заказа = p_order_id
) THEN
UPDATE ПланЗаготовок
SET плановое_количество = плановое_количество + p_qty
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
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
message := 'Задача добавлена в план';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;



DROP FUNCTION IF EXISTS sp_assign_worker_to_task(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_assign_worker_to_task(
        p_id_заготовки INTEGER,
        p_id_заказа INTEGER,
        p_worker_id INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_worker INTEGER;
v_worker_load INTEGER;
BEGIN 
SELECT id_сотрудника INTO v_current_worker
FROM ПланЗаготовок
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
RETURN NEXT;
RETURN;
END IF;

SELECT COUNT(*) INTO v_worker_load
FROM ПланЗаготовок
WHERE id_сотрудника = p_worker_id
    AND статус = 'в_работе';

UPDATE ПланЗаготовок
SET id_сотрудника = p_worker_id
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF v_current_worker IS NOT NULL THEN status := 'WARNING';
message := 'Задача переназначена другому сборщику';
ELSIF v_worker_load >= 3 THEN status := 'WARNING';
message := 'Сборщик назначен. Внимание: у него уже ' || v_worker_load || ' активных задач!';
ELSE status := 'OK';
message := 'Сборщик назначен';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;



DROP FUNCTION IF EXISTS sp_release_task(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_release_task(
        p_id_заготовки INTEGER,
        p_id_заказа INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE ПланЗаготовок
SET id_сотрудника = NULL
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
RETURN NEXT;
RETURN;
END IF;
status := 'OK';
message := 'Задача освобождена';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;


