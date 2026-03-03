-- ============================================================================
-- Консолидированная миграция: Единая бизнес-логика Nova Forma
-- Дата: 2026-03-03
-- ============================================================================
-- Устанавливает корректные версии ВСЕХ ключевых процедур.
-- Правила:
--   1. Материалы списываются при ВЗЯТИИ задачи сотрудником (sp_take_component_task)
--   2. При создании заказа — только ПРОВЕРКА наличия материалов
--   3. Заготовки со склада списываются при создании заказа
--   4. Произведённые заготовки НЕ возвращаются на склад (кроме сервисных заказов)
--   5. При отмене — возврат всего (материалов + заготовок)
-- ============================================================================
BEGIN;
-- ============================================================================
-- 0. Добавляем колонку-флаг отслеживания списания (если ещё нет)
-- ============================================================================
ALTER TABLE "ПланЗаготовок"
ADD COLUMN IF NOT EXISTS материалы_списаны BOOLEAN DEFAULT FALSE;
-- Для существующих задач в работе — материалы уже списаны
UPDATE "ПланЗаготовок"
SET материалы_списаны = TRUE
WHERE статус IN ('в_работе', 'выполнено', 'назначено')
    AND материалы_списаны IS NOT TRUE;
-- ============================================================================
-- 1. sp_add_product_to_order_smart
--    Добавление изделия в заказ.
--    Списывает заготовки со склада, ПРОВЕРЯЕТ материалы (без списания!),
--    создаёт задачи с материалы_списаны = FALSE.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.sp_add_product_to_order_smart(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER,
        p_deadline DATE
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $function$
DECLARE r RECORD;
m RECORD;
v_needed_qty INTEGER;
v_stock_qty INTEGER;
v_missing_qty INTEGER;
v_take_from_stock INTEGER;
v_components_added INTEGER := 0;
v_price NUMERIC;
BEGIN
SELECT стоимость INTO v_price
FROM Изделие
WHERE id_изделия = p_product_id;
-- Добавить / обновить позицию в составе заказа
IF EXISTS (
    SELECT 1
    FROM СоставЗаказа
    WHERE id_заказа = p_order_id
        AND id_изделия = p_product_id
) THEN
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
-- Обработка компонентов (заготовок)
FOR r IN (
    SELECT si.id_заготовки,
        si.количество_заготовки
    FROM СоставИзделия si
    WHERE si.id_изделия = p_product_id
) LOOP v_needed_qty := COALESCE(r.количество_заготовки, 0) * p_qty;
SELECT количество_готовых INTO v_stock_qty
FROM Заготовка
WHERE id_заготовки = r.id_заготовки;
-- Забрать со склада сколько есть
v_take_from_stock := LEAST(v_needed_qty, COALESCE(v_stock_qty, 0));
IF v_take_from_stock > 0 THEN
UPDATE Заготовка
SET количество_готовых = количество_готовых - v_take_from_stock
WHERE id_заготовки = r.id_заготовки;
END IF;
-- Если не хватает — проверить материалы и создать задачу
IF v_take_from_stock < v_needed_qty THEN v_missing_qty := v_needed_qty - v_take_from_stock;
-- Только ПРОВЕРКА наличия материалов (без списания!)
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
-- Создать задачу (материалы НЕ списаны — будут списаны при взятии)
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
-- ============================================================================
-- 2. sp_add_order_item
--    Альтернативный путь добавления изделия (из диалога заказа).
--    Аналогичная логика: проверка материалов, без списания.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_add_order_item(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_stock INTEGER;
v_missing_product INTEGER;
v_date_ready DATE;
v_exists BOOLEAN;
rec RECORD;
m RECORD;
v_needed_comp INTEGER;
v_comp_stock INTEGER;
v_missing_comp INTEGER;
v_take_from_stock INTEGER;
v_components_added INTEGER := 0;
BEGIN -- Проверить статус заказа
IF EXISTS(
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
-- Добавить / обновить позицию
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
SELECT p_order_id,
    p_product_id,
    p_qty,
    стоимость
FROM Изделие
WHERE id_изделия = p_product_id;
END IF;
-- Обработка компонентов
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
-- Только ПРОВЕРКА материалов
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
-- Задача: материалы НЕ списаны
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
$$;
-- ============================================================================
-- 3. sp_create_manual_production_task
--    Ручное создание задачи. Только ПРОВЕРКА материалов, без списания.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_create_manual_production_task(
        p_order_id INTEGER,
        p_component_id INTEGER,
        p_qty INTEGER,
        p_deadline DATE DEFAULT NULL
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_deadline DATE;
m RECORD;
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
-- Только ПРОВЕРКА материалов (используя РасходМатериалов)
FOR m IN (
    SELECT mat.наименование,
        mat.количество_на_складе,
        (COALESCE(rm.количество_материала, 0) * p_qty) AS needed
    FROM РасходМатериалов rm
        JOIN Материал mat ON rm.id_материала = mat.id_материала
    WHERE rm.id_заготовки = p_component_id
) LOOP IF COALESCE(m.количество_на_складе, 0) < m.needed THEN v_missing_text := v_missing_text || m.наименование || ' (нужно ' || m.needed || ', есть ' || COALESCE(m.количество_на_складе, 0) || '); ';
END IF;
END LOOP;
IF v_missing_text != '' THEN status := 'ERROR';
message := 'НЕОБХОДИМА ЗАКУПКА: Недостаточно материалов: ' || v_missing_text;
RETURN NEXT;
RETURN;
END IF;
-- НЕ списываем материалы! Они будут списаны при взятии задачи.
-- Создать или обновить задачу
IF EXISTS(
    SELECT 1
    FROM "ПланЗаготовок"
    WHERE id_заготовки = p_component_id
        AND id_заказа = p_order_id
        AND статус NOT IN ('выполнено', 'отменено')
) THEN
UPDATE "ПланЗаготовок"
SET плановое_количество = плановое_количество + p_qty
WHERE id_заготовки = p_component_id
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
        p_component_id,
        p_order_id,
        p_qty,
        v_deadline,
        'принято',
        FALSE
    );
END IF;
status := 'OK';
message := 'Задача добавлена в план. Материалы будут списаны при взятии в работу.';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- ============================================================================
-- 4. sp_take_component_task
--    Сотрудник берёт задачу. СПИСЫВАЕТ материалы. Проверяет увольнение.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.sp_take_component_task(
        p_component_id INTEGER,
        p_order_id INTEGER,
        p_worker_id INTEGER
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $function$
DECLARE v_status VARCHAR;
v_assigned_worker INTEGER;
v_planned_qty INTEGER;
v_materials_deducted BOOLEAN;
v_fire_date DATE;
m RECORD;
BEGIN -- Проверка увольнения
SELECT дата_увольнения INTO v_fire_date
FROM Сотрудник
WHERE id_сотрудника = p_worker_id;
IF v_fire_date IS NOT NULL THEN status := 'ERROR';
message := 'Уволенный сотрудник не может брать задачи';
RETURN NEXT;
RETURN;
END IF;
SELECT статус,
    id_сотрудника,
    плановое_количество,
    COALESCE(материалы_списаны, FALSE) INTO v_status,
    v_assigned_worker,
    v_planned_qty,
    v_materials_deducted
FROM "ПланЗаготовок"
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
RETURN NEXT;
RETURN;
END IF;
IF v_status = 'выполнено' THEN status := 'ERROR';
message := 'Задача уже выполнена';
RETURN NEXT;
RETURN;
END IF;
IF v_status = 'в_работе' THEN status := 'ERROR';
message := 'Задача уже в работе';
RETURN NEXT;
RETURN;
END IF;
IF v_assigned_worker IS NOT NULL
AND v_assigned_worker != p_worker_id THEN status := 'ERROR';
message := 'Задача уже занята другим сотрудником';
RETURN NEXT;
RETURN;
END IF;
-- Списание материалов ТОЛЬКО если ещё не списаны
IF NOT v_materials_deducted THEN FOR m IN (
    SELECT rm.id_материала,
        rm.количество_материала,
        mat.количество_на_складе,
        mat.наименование
    FROM РасходМатериалов rm
        JOIN Материал mat ON rm.id_материала = mat.id_материала
    WHERE rm.id_заготовки = p_component_id
) LOOP IF m.количество_на_складе < (m.количество_материала * v_planned_qty) THEN status := 'ERROR';
message := 'Недостаточно материала "' || m.наименование || '" (нужно ' || (m.количество_материала * v_planned_qty) || ', есть ' || m.количество_на_складе || ')';
RETURN NEXT;
RETURN;
END IF;
UPDATE Материал
SET количество_на_складе = количество_на_складе - (m.количество_материала * v_planned_qty)
WHERE id_материала = m.id_материала;
END LOOP;
END IF;
-- Назначить работника
UPDATE "ПланЗаготовок"
SET id_сотрудника = p_worker_id,
    статус = 'в_работе',
    материалы_списаны = TRUE
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
IF v_materials_deducted THEN status := 'OK';
message := 'Задача взята в работу (материалы были списаны ранее).';
ELSE status := 'OK';
message := 'Задача взята в работу. Материалы списаны.';
END IF;
RETURN NEXT;
END;
$function$;
-- ============================================================================
-- 5. sp_submit_component_work
--    Сдача работы. Для сервисных заказов (без клиента) — на склад.
--    Для клиентских заказов — НЕ на склад.
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_submit_component_work(
        p_component_id INTEGER,
        p_order_id INTEGER,
        p_qty INTEGER,
        p_worker_id INTEGER
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_status VARCHAR;
v_planned INTEGER;
v_actual INTEGER;
v_assigned_worker INTEGER;
v_row_count INTEGER;
v_is_service_order BOOLEAN;
BEGIN
SELECT "ПланЗаготовок".статус,
    плановое_количество,
    COALESCE(фактическое_количество, 0),
    id_сотрудника INTO v_status,
    v_planned,
    v_actual,
    v_assigned_worker
FROM "ПланЗаготовок"
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
RETURN NEXT;
RETURN;
END IF;
IF v_assigned_worker IS NULL THEN status := 'ERROR';
message := 'Задача не взята в работу (не назначен исполнитель)';
RETURN NEXT;
RETURN;
ELSIF v_assigned_worker != p_worker_id THEN status := 'ERROR';
message := 'Вы не являетесь исполнителем этой задачи';
RETURN NEXT;
RETURN;
END IF;
IF v_status = 'выполнено' THEN status := 'ERROR';
message := 'Задача уже выполнена';
RETURN NEXT;
RETURN;
END IF;
IF (v_actual + p_qty) > v_planned THEN status := 'ERROR';
message := 'Нельзя сделать больше, чем запланировано! Осталось: ' || (v_planned - v_actual);
RETURN NEXT;
RETURN;
END IF;
UPDATE "ПланЗаготовок"
SET фактическое_количество = COALESCE(фактическое_количество, 0) + p_qty,
    дата_факт = CURRENT_DATE,
    статус = CASE
        WHEN (COALESCE(фактическое_количество, 0) + p_qty) >= плановое_количество THEN 'выполнено'
        ELSE 'в_работе'
    END
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
GET DIAGNOSTICS v_row_count = ROW_COUNT;
IF v_row_count = 0 THEN status := 'ERROR';
message := 'Не удалось обновить задачу (данные изменились)';
RETURN NEXT;
RETURN;
END IF;
-- Сервисный заказ (без клиента) = пополнение склада
SELECT (id_клиента IS NULL) INTO v_is_service_order
FROM Заказ
WHERE id_заказа = p_order_id;
IF v_is_service_order THEN
UPDATE Заготовка
SET количество_готовых = количество_готовых + p_qty
WHERE id_заготовки = p_component_id;
END IF;
status := 'OK';
message := 'Работа принята';
RETURN NEXT;
END;
$$;
-- ============================================================================
-- 6. sp_release_task
--    Снятие задачи. Возврат материалов, если были списаны.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.sp_release_task(
        "p_id_заготовки" INTEGER,
        "p_id_заказа" INTEGER
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $function$
DECLARE v_status VARCHAR;
v_planned_qty INTEGER;
v_actual_qty INTEGER;
v_materials_deducted BOOLEAN;
v_return_qty INTEGER;
m RECORD;
BEGIN
SELECT статус,
    плановое_количество,
    COALESCE(фактическое_количество, 0),
    COALESCE(материалы_списаны, FALSE) INTO v_status,
    v_planned_qty,
    v_actual_qty,
    v_materials_deducted
FROM "ПланЗаготовок"
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
RETURN NEXT;
RETURN;
END IF;
IF v_status = 'выполнено' THEN status := 'ERROR';
message := 'Нельзя снять выполненную задачу';
RETURN NEXT;
RETURN;
END IF;
-- Вернуть материалы если они были списаны
IF v_materials_deducted THEN v_return_qty := v_planned_qty - v_actual_qty;
IF v_return_qty > 0 THEN FOR m IN (
    SELECT rm.id_материала,
        rm.количество_материала
    FROM РасходМатериалов rm
    WHERE rm.id_заготовки = p_id_заготовки
) LOOP
UPDATE Материал
SET количество_на_складе = количество_на_складе + (m.количество_материала * v_return_qty)
WHERE id_материала = m.id_материала;
END LOOP;
END IF;
END IF;
-- Сброс задачи
UPDATE "ПланЗаготовок"
SET id_сотрудника = NULL,
    статус = 'принято',
    фактическое_количество = 0,
    материалы_списаны = FALSE
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF v_materials_deducted THEN status := 'OK';
message := 'Задача освобождена. Материалы возвращены на склад.';
ELSE status := 'OK';
message := 'Задача освобождена.';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$function$;
-- ============================================================================
-- 7. sp_update_order_status
--    Изменение статуса заказа. При отмене — возврат ВСЕГО.
-- ============================================================================
CREATE OR REPLACE FUNCTION public.sp_update_order_status(
        p_order_id INTEGER,
        p_new_status VARCHAR
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $function$
DECLARE v_current_status VARCHAR;
v_pending_tasks INTEGER;
t RECORD;
c RECORD;
m RECORD;
v_return_qty INTEGER;
v_task_planned INTEGER;
v_stock_taken INTEGER;
BEGIN
SELECT s.статус INTO v_current_status
FROM Заказ s
WHERE s.id_заказа = p_order_id;
IF v_current_status IS NULL THEN status := 'ERROR';
message := 'Заказ не найден';
RETURN NEXT;
RETURN;
END IF;
IF v_current_status = 'отгружен' THEN status := 'ERROR';
message := 'Нельзя изменить статус отгруженного заказа';
RETURN NEXT;
RETURN;
END IF;
IF v_current_status = 'отменен' THEN status := 'ERROR';
message := 'Заказ уже отменен';
RETURN NEXT;
RETURN;
END IF;
-- Проверка завершения
IF p_new_status = 'завершен' THEN
SELECT COUNT(*) INTO v_pending_tasks
FROM "ПланЗаготовок"
WHERE id_заказа = p_order_id
    AND статус NOT IN ('выполнено', 'отменено');
IF v_pending_tasks > 0 THEN status := 'ERROR';
message := 'Нельзя отметить готовым: есть незавершенные задачи (' || v_pending_tasks || ')';
RETURN NEXT;
RETURN;
END IF;
END IF;
-- Брак: завершен → в_работе
IF v_current_status = 'завершен'
AND p_new_status = 'в_работе' THEN
UPDATE Заказ
SET статус = p_new_status
WHERE id_заказа = p_order_id;
status := 'OK';
message := 'Брак зафиксирован. Заказ возвращен в работу.';
RETURN NEXT;
RETURN;
END IF;
-- === ОТМЕНА ЗАКАЗА ===
IF p_new_status = 'отменен' THEN -- 1. Обработка задач: возврат материалов
FOR t IN (
    SELECT id_заготовки,
        статус,
        плановое_количество,
        COALESCE(фактическое_количество, 0) AS факт,
        COALESCE(материалы_списаны, FALSE) AS мат_списаны
    FROM "ПланЗаготовок"
    WHERE id_заказа = p_order_id
        AND статус != 'отменено'
) LOOP -- Вернуть материалы если были списаны
IF t.мат_списаны THEN v_return_qty := t.плановое_количество - t.факт;
IF v_return_qty > 0 THEN FOR m IN (
    SELECT rm.id_материала,
        rm.количество_материала
    FROM РасходМатериалов rm
    WHERE rm.id_заготовки = t.id_заготовки
) LOOP
UPDATE Материал
SET количество_на_складе = количество_на_складе + (m.количество_материала * v_return_qty)
WHERE id_материала = m.id_материала;
END LOOP;
END IF;
END IF;
-- Выполненные задачи: вернуть произведённые заготовки на склад
IF t.статус = 'выполнено'
AND t.факт > 0 THEN
UPDATE Заготовка
SET количество_готовых = количество_готовых + t.факт
WHERE id_заготовки = t.id_заготовки;
END IF;
END LOOP;
-- Отмена всех задач
UPDATE "ПланЗаготовок"
SET статус = 'отменено',
    материалы_списаны = FALSE
WHERE id_заказа = p_order_id
    AND статус != 'отменено';
-- 2. Возврат заготовок, взятых со склада при создании заказа
FOR c IN (
    SELECT si.id_заготовки,
        si.количество_заготовки * sz.количество_изделий AS total_needed
    FROM СоставЗаказа sz
        JOIN СоставИзделия si ON si.id_изделия = sz.id_изделия
    WHERE sz.id_заказа = p_order_id
) LOOP
SELECT COALESCE(SUM(плановое_количество), 0) INTO v_task_planned
FROM "ПланЗаготовок"
WHERE id_заказа = p_order_id
    AND id_заготовки = c.id_заготовки;
v_stock_taken := c.total_needed - v_task_planned;
IF v_stock_taken > 0 THEN
UPDATE Заготовка
SET количество_готовых = количество_готовых + v_stock_taken
WHERE id_заготовки = c.id_заготовки;
END IF;
END LOOP;
END IF;
UPDATE Заказ
SET статус = p_new_status
WHERE id_заказа = p_order_id;
status := 'OK';
IF p_new_status = 'отменен' THEN message := 'Заказ отменен. Материалы и заготовки возвращены на склад.';
ELSE message := 'Статус обновлен';
END IF;
RETURN NEXT;
END;
$function$;
-- ============================================================================
-- 8. sp_assign_worker_to_task (fix constraint + fired worker check)
-- ============================================================================
CREATE OR REPLACE FUNCTION sp_assign_worker_to_task(
        p_id_заготовки INTEGER,
        p_id_заказа INTEGER,
        p_worker_id INTEGER
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_fire_date DATE;
BEGIN
SELECT дата_увольнения INTO v_fire_date
FROM Сотрудник
WHERE id_сотрудника = p_worker_id;
IF v_fire_date IS NOT NULL THEN status := 'ERROR';
message := 'Нельзя назначить задачу уволенному сотруднику';
RETURN NEXT;
RETURN;
END IF;
UPDATE "ПланЗаготовок"
SET id_сотрудника = p_worker_id,
    статус = 'назначено'
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF FOUND THEN status := 'OK';
message := 'Сотрудник назначен';
ELSE status := 'ERROR';
message := 'Задача не найдена';
END IF;
RETURN NEXT;
END;
$$;
-- ============================================================================
-- 9. Fix status constraint to allow 'назначено' and 'отменено'
-- ============================================================================
DO $$ BEGIN BEGIN
ALTER TABLE "ПланЗаготовок" DROP CONSTRAINT IF EXISTS "планзаготовок_статус_check";
EXCEPTION
WHEN OTHERS THEN NULL;
END;
BEGIN
ALTER TABLE "ПланЗаготовок" DROP CONSTRAINT IF EXISTS "ПланЗаготовок_статус_check";
EXCEPTION
WHEN OTHERS THEN NULL;
END;
BEGIN
ALTER TABLE "ПланЗаготовок" DROP CONSTRAINT IF EXISTS "план_заготовок_статус_check";
EXCEPTION
WHEN OTHERS THEN NULL;
END;
ALTER TABLE "ПланЗаготовок"
ADD CONSTRAINT "планзаготовок_статус_check" CHECK (
        статус IN (
            'принято',
            'назначено',
            'в_работе',
            'выполнено',
            'отменено'
        )
    );
END;
$$;
COMMIT;