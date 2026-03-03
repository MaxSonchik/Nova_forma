




ALTER TABLE Материал DROP COLUMN IF EXISTS артикул_материала;
ALTER TABLE Заготовка DROP COLUMN IF EXISTS артикул_заготовки;
ALTER TABLE Изделие DROP COLUMN IF EXISTS артикул_изделия;



ALTER TABLE Заготовка DROP COLUMN IF EXISTS количество_на_складе;




DROP VIEW IF EXISTS v_задачи_сборщика CASCADE;

DROP TABLE IF EXISTS ПланСборки CASCADE;



CREATE OR REPLACE FUNCTION fn_update_task_date_fact() RETURNS TRIGGER AS $$ BEGIN IF NEW.статус = 'выполнено'
    AND OLD.статус != 'выполнено' THEN NEW.дата_факт := CURRENT_DATE;
ELSIF NEW.статус != 'выполнено' THEN NEW.дата_факт := NULL;
END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_task_date_fact ON ПланЗаготовок;
CREATE TRIGGER trg_task_date_fact BEFORE
UPDATE ON ПланЗаготовок FOR EACH ROW EXECUTE FUNCTION fn_update_task_date_fact();

CREATE OR REPLACE FUNCTION fn_check_order_completion() RETURNS TRIGGER AS $$
DECLARE v_pending_count INTEGER;
BEGIN 
IF NEW.статус = 'выполнено' THEN 
SELECT COUNT(*) INTO v_pending_count
FROM ПланЗаготовок
WHERE id_заказа = NEW.id_заказа
    AND статус != 'выполнено'
    AND статус != 'отменено';


IF v_pending_count = 0 THEN
UPDATE Заказ
SET статус = 'завершен',
    
    дата_готовности = CURRENT_DATE
WHERE id_заказа = NEW.id_заказа
    AND статус != 'завершен';
END IF;
END IF;
RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_order_completion ON ПланЗаготовок;
CREATE TRIGGER trg_order_completion
AFTER
UPDATE ON ПланЗаготовок FOR EACH ROW EXECUTE FUNCTION fn_check_order_completion();




































CREATE OR REPLACE FUNCTION sp_add_order_item(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_stock INTEGER;
v_price NUMERIC;
v_missing_product INTEGER;

v_date_ready DATE;
v_exists BOOLEAN;
rec RECORD;
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


IF v_stock >= p_qty THEN
UPDATE Изделие
SET количество_на_складе = количество_на_складе - p_qty
WHERE id_изделия = p_product_id;
status := 'OK';
message := 'Добавлено из наличия';
ELSE 
v_missing_product := p_qty - v_stock;
IF v_stock > 0 THEN
UPDATE Изделие
SET количество_на_складе = 0
WHERE id_изделия = p_product_id;
END IF;










FOR rec IN
SELECT id_заготовки,
    количество_заготовки
FROM СоставИзделия
WHERE id_изделия = p_product_id LOOP
DECLARE v_comp_needed INTEGER := rec.количество_заготовки * v_missing_product;
v_comp_stock INTEGER;
v_comp_missing INTEGER;
BEGIN
SELECT количество_готовых INTO v_comp_stock
FROM Заготовка
WHERE id_заготовки = rec.id_заготовки;
IF v_comp_stock >= v_comp_needed THEN 


UPDATE Заготовка
SET количество_готовых = количество_готовых - v_comp_needed
WHERE id_заготовки = rec.id_заготовки;
ELSE 
v_comp_missing := v_comp_needed - v_comp_stock;

IF v_comp_stock > 0 THEN
UPDATE Заготовка
SET количество_готовых = 0
WHERE id_заготовки = rec.id_заготовки;
END IF;

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
        v_comp_missing,
        COALESCE(
            (
                SELECT дата_готовности
                FROM Заказ
                WHERE id_заказа = p_order_id
            ),
            CURRENT_DATE + 7
        ),
        'принято'
    );
END IF;
END;
END LOOP;
status := 'OK';
message := 'Заказ принят. Сформированы задачи на заготовки.';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_production_plan_full();
CREATE OR REPLACE FUNCTION sp_get_production_plan_full() RETURNS TABLE (
        id_плана INTEGER,
        id_заказа INTEGER,
        
        заготовка VARCHAR,
        плановое_количество INTEGER,
        фактическое_количество INTEGER,
        дедлайн DATE,
        статус VARCHAR,
        сборщик VARCHAR,
        id_сотрудника INTEGER,
        
        id_объекта INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT pz.id_плана,
    pz.id_заказа,
    z.наименование AS заготовка,
    pz.плановое_количество,
    pz.фактическое_количество,
    pz.дата_план,
    pz.статус,
    COALESCE(s.фио, 'Не назначен')::VARCHAR as сборщик,
    pz.id_сотрудника,
    
    pz.id_заготовки
FROM ПланЗаготовок pz
    JOIN Заготовка z ON pz.id_заготовки = z.id_заготовки
    LEFT JOIN Сотрудник s ON pz.id_сотрудника = s.id_сотрудника
ORDER BY CASE
        WHEN pz.статус = 'выполнено' THEN 1
        ELSE 0
    END,
    
    pz.дата_план ASC;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_materials();
CREATE OR REPLACE FUNCTION sp_get_materials() RETURNS TABLE (
        id_материала INTEGER,
        наименование VARCHAR,
        количество_на_складе INTEGER,
        единица_измерения VARCHAR,
        минимальный_остаток INTEGER,
        цена_за_единицу NUMERIC
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    m.количество_на_складе,
    m.единица_измерения,
    m.минимальный_остаток,
    m.цена_за_единицу
FROM Материал m
ORDER BY m.наименование;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_components();
CREATE OR REPLACE FUNCTION sp_get_components() RETURNS TABLE (
        id_заготовки INTEGER,
        наименование VARCHAR,
        количество_готовых INTEGER 
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.id_заготовки,
    z.наименование,
    z.количество_готовых
FROM Заготовка z
ORDER BY z.наименование;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_products();
CREATE OR REPLACE FUNCTION sp_get_products() RETURNS TABLE (
        id_изделия INTEGER,
        наименование VARCHAR,
        тип VARCHAR,
        размеры VARCHAR,
        стоимость NUMERIC,
        количество_на_складе INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT i.id_изделия,
    i.наименование,
    i.тип,
    i.размеры,
    i.стоимость,
    i.количество_на_складе
FROM Изделие i
ORDER BY i.наименование;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_warehouse_summary(VARCHAR, VARCHAR);
CREATE OR REPLACE FUNCTION sp_get_warehouse_summary(
        p_search VARCHAR DEFAULT NULL,
        p_type VARCHAR DEFAULT NULL
    ) RETURNS TABLE (
        тип VARCHAR,
        наименование VARCHAR,
        количество INTEGER,
        ед_изм VARCHAR 
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT base.тип,
    base.наименование,
    base.количество,
    base.ед_изм
FROM (
        SELECT 'Материал'::VARCHAR as тип,
            m.наименование,
            m.количество_на_складе as количество,
            m.единица_измерения as ед_изм
        FROM Материал m
        UNION ALL
        SELECT 'Заготовка'::VARCHAR,
            z.наименование,
            z.количество_готовых,
            'шт'::VARCHAR
        FROM Заготовка z
        UNION ALL
        SELECT 'Изделие'::VARCHAR,
            i.наименование,
            i.количество_на_складе,
            'шт'::VARCHAR
        FROM Изделие i
    ) AS base
WHERE (
        p_type IS NULL
        OR base.тип = p_type
    )
    AND (
        p_search IS NULL
        OR LOWER(base.наименование) LIKE '%' || LOWER(p_search) || '%'
    )
ORDER BY base.наименование;
END;
$$;