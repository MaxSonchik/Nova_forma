-- ============================================================================
-- Миграция v2: Безопасный перенос списания материалов
-- Решает проблемы: двойное списание + возврат материалов
-- ============================================================================
-- Использует колонку материалы_списаны для отслеживания состояния
-- ============================================================================
BEGIN;
-- ============================================================================
-- 0. Добавляем колонку-флаг для отслеживания списания материалов
-- ============================================================================
ALTER TABLE "ПланЗаготовок"
ADD COLUMN IF NOT EXISTS материалы_списаны BOOLEAN DEFAULT FALSE;
-- Для существующих задач в 'в_работе' или 'выполнено' — материалы УЖЕ списаны
-- (старой логикой при создании заказа)
UPDATE "ПланЗаготовок"
SET материалы_списаны = TRUE
WHERE статус IN ('в_работе', 'выполнено', 'назначено');
-- Для задач в 'принято' — зависит от того, была ли старая или новая логика.
-- Безопаснее считать что материалы УЖЕ списаны старой логикой.
UPDATE "ПланЗаготовок"
SET материалы_списаны = TRUE
WHERE статус = 'принято';
-- ============================================================================
-- 1. sp_add_product_to_order_smart
--    Убираем списание материалов (оставляем проверку наличия)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.sp_add_product_to_order_smart(
        p_order_id integer,
        p_product_id integer,
        p_qty integer,
        p_deadline date
    ) RETURNS TABLE(
        status character varying,
        message character varying
    ) LANGUAGE plpgsql AS $function$
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
message := 'НЕОБХОДИМА ЗАКУПКА: Недостаточно материала "' || m.наименование || '" для заготовки (нужно ' || (m.количество_материала * v_missing_qty) || ', есть ' || m.количество_на_складе || ').';
RETURN NEXT;
RETURN;
END IF;
END LOOP;
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
        FALSE -- материалы НЕ списаны
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
-- 2. sp_take_component_task
--    Списание ТОЛЬКО если материалы_списаны = FALSE (защита от двойного списания)
-- ============================================================================
CREATE OR REPLACE FUNCTION public.sp_take_component_task(
        p_component_id integer,
        p_order_id integer,
        p_worker_id integer
    ) RETURNS TABLE(
        status character varying,
        message character varying
    ) LANGUAGE plpgsql AS $function$
DECLARE v_status VARCHAR;
v_assigned_worker INTEGER;
v_planned_qty INTEGER;
v_materials_deducted BOOLEAN;
v_fire_date DATE;
m RECORD;
BEGIN
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
FROM ПланЗаготовок
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
-- Назначить работника и пометить материалы как списанные
UPDATE ПланЗаготовок
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
-- 3. sp_release_task
--    Возврат материалов ТОЛЬКО если материалы_списаны = TRUE
-- ============================================================================
CREATE OR REPLACE FUNCTION public.sp_release_task(
        "p_id_заготовки" integer,
        "p_id_заказа" integer
    ) RETURNS TABLE(
        status character varying,
        message character varying
    ) LANGUAGE plpgsql AS $function$
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
FROM ПланЗаготовок
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN status := 'ERROR';
message := 'Задача не найдена';
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
UPDATE ПланЗаготовок
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
-- 4. sp_update_order_status
--    Возврат заготовок и материалов при отмене заказа
-- ============================================================================
CREATE OR REPLACE FUNCTION public.sp_update_order_status(
        p_order_id integer,
        p_new_status character varying
    ) RETURNS TABLE(
        status character varying,
        message character varying
    ) LANGUAGE plpgsql AS $function$
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
IF p_new_status = 'отменен' THEN -- 1. Обработка задач
FOR t IN (
    SELECT id_заготовки,
        статус,
        плановое_количество,
        COALESCE(фактическое_количество, 0) AS факт,
        COALESCE(материалы_списаны, FALSE) AS мат_списаны
    FROM "ПланЗаготовок"
    WHERE id_заказа = p_order_id
        AND статус != 'отменено'
) LOOP -- Вернуть материалы если они были списаны
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
-- 2. Возврат заготовок со склада
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
COMMIT;