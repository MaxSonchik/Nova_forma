-- Feature: Assembly Tasks
-- Add support for "Product Assembly" tasks (Сборка изделия)
-- 1. Create table for assembly plan
CREATE TABLE IF NOT EXISTS план_сборки (
    id_сборки SERIAL PRIMARY KEY,
    id_заказа INTEGER REFERENCES заказы(id_заказа),
    id_изделия INTEGER REFERENCES изделия(id_изделия),
    плановое_количество INTEGER NOT NULL CHECK(плановое_количество > 0),
    фактическое_количество INTEGER DEFAULT 0 CHECK(фактическое_количество >= 0),
    статус VARCHAR(30) DEFAULT 'принято',
    id_сборщика INTEGER REFERENCES сотрудники(id_сотрудника),
    дата_план DATE,
    дата_факт DATE
);
-- 2. Update View to include both Components(plan_zagotovok) and Assembly(plan_sborki)
DROP VIEW IF EXISTS v_задачи_сборщика;
CREATE OR REPLACE VIEW v_задачи_сборщика AS
SELECT 'заготовка'::VARCHAR as тип_задачи,
    0 as id_задачи,
    -- Valid column, dummy value
    pz.id_заказа,
    z.наименование as наименование_задачи,
    pz.плановое_количество,
    pz.фактическое_количество,
    pz.статус,
    pz.id_сотрудника as id_сборщика,
    -- Table uses id_сотрудника
    pz.дата_план,
    pz.дата_факт,
    -- composite keys for components
    pz.id_заготовки as id_объекта
FROM план_заготовок pz
    JOIN заготовки z ON pz.id_заготовки = z.id_заготовки
UNION ALL
SELECT 'сборка'::VARCHAR as тип_задачи,
    ps.id_сборки as id_задачи,
    ps.id_заказа,
    ('Сборка: ' || i.наименование)::VARCHAR as наименование_задачи,
    ps.плановое_количество,
    ps.фактическое_количество,
    ps.статус,
    ps.id_сборщика,
    ps.дата_план,
    ps.дата_факт,
    -- composite keys for product
    ps.id_изделия as id_объекта
FROM план_сборки ps
    JOIN изделия i ON ps.id_изделия = i.id_изделия;
-- 3. Update sp_add_order_item to create Assembly Tasks
-- (We recreate it based on v12 logic, adding the assembly part)
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
BEGIN
SELECT стоимость,
    количество_на_складе INTO v_price,
    v_stock
FROM изделия
WHERE id_изделия = p_product_id;
-- Insert into order items
INSERT INTO состав_заказа (
        id_заказа,
        id_изделия,
        количество_изделий,
        цена_фиксированная
    )
VALUES (p_order_id, p_product_id, p_qty, v_price);
SELECT дата_готовности INTO v_date_ready
FROM заказы
WHERE id_заказа = p_order_id;
-- Check product stock
IF v_stock >= p_qty THEN -- Sufficient product stock
UPDATE изделия
SET количество_на_складе = количество_на_складе - p_qty
WHERE id_изделия = p_product_id;
status := 'OK';
message := 'Изделия зарезервированы со склада.';
ELSE -- Insufficient product stock -> Need Production
v_missing_product := p_qty - v_stock;
-- Use up existing product stock
IF v_stock > 0 THEN
UPDATE изделия
SET количество_на_складе = 0
WHERE id_изделия = p_product_id;
END IF;
-- CHECK MATERIALS for components
SELECT m.наименование INTO v_missing_material_name
FROM состав_изделия si
    JOIN состав_заготовки sz ON si.id_заготовки = sz.id_заготовки
    JOIN материалы m ON sz.id_материала = m.id_материала
WHERE si.id_изделия = p_product_id
    AND m.количество_на_складе < (
        v_missing_product * si.количество_заготовок * sz.количество_материала
    )
LIMIT 1;
IF v_missing_material_name IS NOT NULL THEN RAISE EXCEPTION 'НЕОБХОДИМА ЗАКУПКА: Для производства недостающих изделий не хватает материала "%"',
v_missing_material_name;
END IF;
-- 1. Create ASSEMBLY task (New!)
INSERT INTO план_сборки (
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
-- 2. Create COMPONENT tasks
FOR rec IN
SELECT id_заготовки,
    количество_заготовок
FROM состав_изделия
WHERE id_изделия = p_product_id LOOP
INSERT INTO план_заготовок (
        id_заказа,
        id_заготовки,
        плановое_количество,
        дата_план,
        статус
    )
VALUES (
        p_order_id,
        rec.id_заготовки,
        rec.количество_заготовок * v_missing_product,
        v_date_ready - INTERVAL '1 day',
        'принято'
    );
END LOOP;
status := 'WARNING';
message := 'Недостаточно на складе. Созданы задания на производство и сборку ' || v_missing_product || ' ед.';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := SQLERRM;
DELETE FROM состав_заказа
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id
    AND количество_изделий = p_qty
    AND цена_фиксированная = v_price;
RETURN NEXT;
END;
$$;
-- 4. Create sp_сдать_сборку (Report Assembly)
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
FROM план_сборки
WHERE id_изделия = p_id_изделия
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN RAISE EXCEPTION 'Задача на сборку не найдена';
END IF;
IF v_status = 'выполнено' THEN RAISE EXCEPTION 'Сборка уже выполнена';
END IF;
IF v_status = 'отменено' THEN RAISE EXCEPTION 'Сборка отменена';
END IF;
-- CHECK COMPONENTS availability
-- Need N components per 1 product * p_qty
SELECT z.наименование INTO v_missing_component_name
FROM состав_изделия si
    JOIN заготовки z ON si.id_заготовки = z.id_заготовки
WHERE si.id_изделия = p_id_изделия
    AND z.количество_готовых < (si.количество_заготовок * p_количество)
LIMIT 1;
IF v_missing_component_name IS NOT NULL THEN RAISE EXCEPTION 'Недостаточно заготовок "%" для сборки изделия!',
v_missing_component_name;
END IF;
-- Deduct components
UPDATE заготовки z
SET количество_готовых = количество_готовых - (si.количество_заготовок * p_количество)
FROM состав_изделия si
WHERE si.id_изделия = p_id_изделия
    AND z.id_заготовки = si.id_заготовки;
-- Update plan
UPDATE план_сборки
SET фактическое_количество = фактическое_количество + p_количество,
    дата_факт = CURRENT_DATE
WHERE id_изделия = p_id_изделия
    AND id_заказа = p_id_заказа;
-- Update PRODUCT Stock
UPDATE изделия
SET количество_на_складе = количество_на_складе + p_количество
WHERE id_изделия = p_id_изделия;
-- Check completion
IF (v_actual + p_количество) >= v_planned THEN
UPDATE план_сборки
SET статус = 'выполнено'
WHERE id_изделия = p_id_изделия
    AND id_заказа = p_id_заказа;
END IF;
END;
$$;