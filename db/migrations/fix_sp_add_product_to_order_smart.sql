-- Fix partial commit bugs by checking materials FIRST
CREATE OR REPLACE FUNCTION public.sp_add_product_to_order_smart(
        p_order_id integer,
        p_product_id integer,
        p_qty integer,
        p_deadline date DEFAULT NULL::date
    ) RETURNS TABLE(
        status character varying,
        message character varying
    ) LANGUAGE plpgsql AS $function$
DECLARE v_price NUMERIC;
v_deadline DATE;
v_exists BOOLEAN;
r RECORD;
m RECORD;
v_needed_qty INTEGER;
v_stock_qty INTEGER;
v_take_from_stock INTEGER;
v_missing_qty INTEGER;
v_components_added INTEGER := 0;
BEGIN IF EXISTS(
    SELECT 1
    FROM Заказ
    WHERE id_заказа = p_order_id
        AND статус IN ('выполнен', 'отменен', 'отгружен', 'завершен')
) THEN status := 'ERROR';
message := 'Нельзя изменить завершенный заказ';
RETURN NEXT;
RETURN;
END IF;
SELECT стоимость INTO v_price
FROM Изделие
WHERE id_изделия = p_product_id;
IF p_deadline IS NULL THEN
SELECT COALESCE(
        дата_готовности,
        CURRENT_DATE + INTERVAL '7 days'
    ) INTO v_deadline
FROM Заказ
WHERE id_заказа = p_order_id;
ELSE v_deadline := p_deadline;
END IF;
SELECT EXISTS(
        SELECT 1
        FROM СоставЗаказа
        WHERE id_заказа = p_order_id
            AND id_изделия = p_product_id
    ) INTO v_exists;
-- ПРОАКТИВНАЯ ПРОВЕРКА НАЛИЧИЯ ВСЕХ МАТЕРИАЛОВ ДО ВНЕСЕНИЯ ИЗМЕНЕНИЙ В БД
FOR r IN (
    SELECT si.id_заготовки,
        si.количество_заготовки
    FROM СоставИзделия si
    WHERE si.id_изделия = p_product_id
) LOOP v_needed_qty := COALESCE(r.количество_заготовки, 0) * p_qty;
SELECT количество_готовых INTO v_stock_qty
FROM Заготовка
WHERE id_заготовки = r.id_заготовки;
v_take_from_stock := LEAST(v_needed_qty, COALESCE(v_stock_qty, 0));
IF v_take_from_stock < v_needed_qty THEN v_missing_qty := v_needed_qty - v_take_from_stock;
FOR m IN (
    SELECT rm.id_материала,
        rm.количество_материала,
        mat.количество_на_складе,
        mat.наименование
    FROM РасходМатериалов rm
        JOIN Материал mat ON rm.id_материала = mat.id_материала
    WHERE rm.id_заготовки = r.id_заготовки
) LOOP IF m.количество_на_складе < (m.количество_материала * v_missing_qty) THEN status := 'ERROR';
message := 'НЕОБХОДИМА ЗАКУПКА: Недостаточно материала "' || m.наименование || '" (нужно ' || (m.количество_материала * v_missing_qty) || ', есть ' || m.количество_на_складе || ').';
RETURN NEXT;
RETURN;
END IF;
END LOOP;
END IF;
END LOOP;
-- МАТЕРИАЛЫ В НАЛИЧИИ/МЫ МОЖЕМ СОЗДАТЬ ЗАДАЧУ. ТЕПЕРЬ ОБНОВЛЯЕМ ДАННЫЕ
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
VALUES (
        p_order_id,
        p_product_id,
        p_qty,
        COALESCE(v_price, 0)
    );
END IF;
FOR r IN (
    SELECT si.id_заготовки,
        si.количество_заготовки
    FROM СоставИзделия si
    WHERE si.id_изделия = p_product_id
) LOOP v_needed_qty := COALESCE(r.количество_заготовки, 0) * p_qty;
SELECT количество_готовых INTO v_stock_qty
FROM Заготовка
WHERE id_заготовки = r.id_заготовки;
v_take_from_stock := LEAST(v_needed_qty, COALESCE(v_stock_qty, 0));
IF v_take_from_stock > 0 THEN
UPDATE Заготовка
SET количество_готовых = количество_готовых - v_take_from_stock
WHERE id_заготовки = r.id_заготовки;
END IF;
IF v_take_from_stock < v_needed_qty THEN v_missing_qty := v_needed_qty - v_take_from_stock;
INSERT INTO "ПланЗаготовок" (
        id_заказа,
        id_заготовки,
        плановое_количество,
        фактическое_количество,
        дата_план,
        статус,
        дата_факт,
        материалы_списаны
    )
VALUES (
        p_order_id,
        r.id_заготовки,
        v_missing_qty,
        0,
        p_deadline,
        'принято',
        NULL,
        FALSE
    );
v_components_added := v_components_added + 1;
END IF;
END LOOP;
IF v_components_added = 0 THEN status := 'OK';
message := 'Изделие добавлено. Все компоненты взяты со склада.';
ELSE
UPDATE Заказ
SET статус = 'в_работе'
WHERE id_заказа = p_order_id
    AND статус = 'принят';
status := 'OK';
message := 'Созданы задачи для ' || v_components_added || ' компонентов.';
END IF;
RETURN NEXT;
END;
$function$;
CREATE OR REPLACE FUNCTION public.sp_add_order_item(
        p_order_id integer,
        p_product_id integer,
        p_qty integer
    ) RETURNS TABLE(
        status character varying,
        message character varying
    ) LANGUAGE plpgsql AS $function$
DECLARE v_stock INTEGER;
v_date_ready DATE;
v_exists BOOLEAN;
rec RECORD;
m RECORD;
v_needed_comp INTEGER;
v_comp_stock INTEGER;
v_missing_comp INTEGER;
v_take_from_stock INTEGER;
v_components_added INTEGER := 0;
BEGIN IF EXISTS(
    SELECT 1
    FROM Заказ
    WHERE id_заказа = p_order_id
        AND статус IN ('выполнен', 'отменен', 'отгружен', 'завершен')
) THEN status := 'ERROR';
message := 'Нельзя изменить завершенный заказ';
RETURN NEXT;
RETURN;
END IF;
SELECT дата_готовности INTO v_date_ready
FROM Заказ
WHERE id_заказа = p_order_id;
IF v_date_ready IS NULL THEN v_date_ready := CURRENT_DATE + INTERVAL '7 days';
END IF;
SELECT EXISTS(
        SELECT 1
        FROM СоставЗаказа
        WHERE id_заказа = p_order_id
            AND id_изделия = p_product_id
    ) INTO v_exists;
-- ПРОАКТИВНАЯ ПРОВЕРКА НАЛИЧИЯ ВСЕХ МАТЕРИАЛОВ ДО ВНЕСЕНИЯ ИЗМЕНЕНИЙ В БД
FOR rec IN (
    SELECT si.id_заготовки,
        si.количество_заготовки
    FROM СоставИзделия si
    WHERE si.id_изделия = p_product_id
) LOOP v_needed_comp := COALESCE(rec.количество_заготовки, 0) * p_qty;
SELECT количество_готовых INTO v_comp_stock
FROM Заготовка
WHERE id_заготовки = rec.id_заготовки;
v_take_from_stock := LEAST(v_needed_comp, COALESCE(v_comp_stock, 0));
IF v_take_from_stock < v_needed_comp THEN v_missing_comp := v_needed_comp - v_take_from_stock;
FOR m IN (
    SELECT rm.id_материала,
        rm.количество_материала,
        mat.количество_на_складе,
        mat.наименование
    FROM РасходМатериалов rm
        JOIN Материал mat ON rm.id_материала = mat.id_материала
    WHERE rm.id_заготовки = rec.id_заготовки
) LOOP IF m.количество_на_складе < (m.количество_материала * v_missing_comp) THEN status := 'ERROR';
message := 'НЕОБХОДИМА ЗАКУПКА: Не хватает материала "' || m.наименование || '"';
RETURN NEXT;
RETURN;
END IF;
END LOOP;
END IF;
END LOOP;
-- ТЕПЕРЬ ОБНОВЛЯЕМ ДАННЫЕ
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
SELECT p_order_id,
    p_product_id,
    p_qty,
    стоимость
FROM Изделие
WHERE id_изделия = p_product_id;
END IF;
FOR rec IN (
    SELECT si.id_заготовки,
        si.количество_заготовки
    FROM СоставИзделия si
    WHERE si.id_изделия = p_product_id
) LOOP v_needed_comp := COALESCE(rec.количество_заготовки, 0) * p_qty;
SELECT количество_готовых INTO v_comp_stock
FROM Заготовка
WHERE id_заготовки = rec.id_заготовки;
v_take_from_stock := LEAST(v_needed_comp, COALESCE(v_comp_stock, 0));
IF v_take_from_stock > 0 THEN
UPDATE Заготовка
SET количество_готовых = количество_готовых - v_take_from_stock
WHERE id_заготовки = rec.id_заготовки;
END IF;
IF v_take_from_stock < v_needed_comp THEN v_missing_comp := v_needed_comp - v_take_from_stock;
IF EXISTS(
    SELECT 1
    FROM "ПланЗаготовок"
    WHERE id_заготовки = rec.id_заготовки
        AND id_заказа = p_order_id
        AND статус NOT IN ('выполнено', 'отменено')
) THEN
UPDATE "ПланЗаготовок"
SET плановое_количество = плановое_количество + v_missing_comp
WHERE id_заготовки = rec.id_заготовки
    AND id_заказа = p_order_id
    AND статус NOT IN ('выполнено', 'отменено');
ELSE
INSERT INTO "ПланЗаготовок" (
        id_заготовки,
        id_заказа,
        плановое_количество,
        дата_план,
        статус,
        материалы_списаны
    )
VALUES (
        rec.id_заготовки,
        p_order_id,
        v_missing_comp,
        v_date_ready - INTERVAL '1 day',
        'принято',
        FALSE
    );
END IF;
v_components_added := v_components_added + 1;
END IF;
END LOOP;
IF v_components_added = 0 THEN status := 'OK';
message := 'Изделия зарезервированы со склада.';
ELSE
UPDATE Заказ
SET статус = 'в_работе'
WHERE id_заказа = p_order_id
    AND статус = 'принят';
status := 'OK';
message := 'Созданы задачи для ' || v_components_added || ' компонентов.';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$function$;