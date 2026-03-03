--
-- PostgreSQL database dump
--

\restrict Qycxxdc9UyPxbbx4zgnUna2ALP29dTrDJ73oXcAeVYSq5bRlC7PfWL2b6QWoKqO

-- Dumped from database version 18.1
-- Dumped by pg_dump version 18.1

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: 
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: fn_check_order_completion(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_check_order_completion() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE v_pending_count INTEGER;
BEGIN -- Only check if we are completing a task
IF NEW.статус = 'выполнено' THEN -- Check if there are any other tasks for this order that are NOT completed
SELECT COUNT(*) INTO v_pending_count
FROM ПланЗаготовок
WHERE id_заказа = NEW.id_заказа
    AND статус != 'выполнено'
    AND статус != 'отменено';
-- Ignored cancelled tasks? Or should they block? Assuming 'отменено' tasks don't block completion.
-- If no pending tasks remain, complete the order
IF v_pending_count = 0 THEN
UPDATE Заказ
SET статус = 'завершен',
    -- Or 'выполнен' matching constraint? Constraint says 'завершен' is valid.
    дата_готовности = CURRENT_DATE
WHERE id_заказа = NEW.id_заказа
    AND статус != 'завершен';
END IF;
END IF;
RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_check_order_completion() OWNER TO postgres;

--
-- Name: fn_update_task_date_fact(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fn_update_task_date_fact() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN IF NEW.статус = 'выполнено'
    AND OLD.статус != 'выполнено' THEN NEW.дата_факт := CURRENT_DATE;
ELSIF NEW.статус != 'выполнено' THEN NEW.дата_факт := NULL;
END IF;
RETURN NEW;
END;
$$;


ALTER FUNCTION public.fn_update_task_date_fact() OWNER TO postgres;

--
-- Name: sp_add_client(character varying, character varying, text, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_add_client(p_fio character varying, p_phone character varying, p_address text, p_inn character varying) RETURNS TABLE(status character varying, message character varying, "id_клиента" integer)
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.sp_add_client(p_fio character varying, p_phone character varying, p_address text, p_inn character varying) OWNER TO postgres;

--
-- Name: sp_add_component_material(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_add_component_material(p_comp_id integer, p_mat_id integer, p_qty integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN
INSERT INTO РасходМатериалов (id_заготовки, id_материала, количество_материала)
VALUES (p_comp_id, p_mat_id, p_qty) ON CONFLICT (id_заготовки, id_материала) DO
UPDATE
SET количество_материала = РасходМатериалов.количество_материала + p_qty;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Материал добавлен'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;


ALTER FUNCTION public.sp_add_component_material(p_comp_id integer, p_mat_id integer, p_qty integer) OWNER TO postgres;

--
-- Name: sp_add_manual_component_task(integer, integer, integer, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_add_manual_component_task(p_order_id integer, p_component_id integer, p_qty integer, p_deadline date DEFAULT NULL::date) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE v_deadline DATE;
BEGIN IF p_deadline IS NULL THEN
SELECT дата_готовности - INTERVAL '1 day' INTO v_deadline
FROM заказы
WHERE id_заказа = p_order_id;
ELSE v_deadline := p_deadline;
END IF;
INSERT INTO план_заготовок (
        id_заказа,
        id_заготовки,
        плановое_количество,
        дата_план,
        статус
    )
VALUES (
        p_order_id,
        p_component_id,
        p_qty,
        v_deadline,
        'принято'
    );
status := 'OK';
message := 'Задача добавлена в план';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;


ALTER FUNCTION public.sp_add_manual_component_task(p_order_id integer, p_component_id integer, p_qty integer, p_deadline date) OWNER TO postgres;

--
-- Name: sp_add_manual_component_task(integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_add_manual_component_task(p_order_id integer, p_component_id integer, p_qty integer, p_worker_id integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN
INSERT INTO план_заготовок (
        id_заготовки,
        id_заказа,
        плановое_количество,
        дата_план,
        id_сотрудника,
        статус
    )
VALUES (
        p_component_id,
        p_order_id,
        p_qty,
        (
            SELECT COALESCE(
                    дата_готовности,
                    CURRENT_DATE + INTERVAL '7 days'
                )
            FROM заказы
            WHERE id_заказа = p_order_id
        ),
        p_worker_id,
        'принято'
    ) ON CONFLICT (id_заготовки, id_заказа) DO
UPDATE
SET плановое_количество = план_заготовок.плановое_количество + EXCLUDED.плановое_количество;
status := 'OK';
message := 'Задача добавлена в план';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;


ALTER FUNCTION public.sp_add_manual_component_task(p_order_id integer, p_component_id integer, p_qty integer, p_worker_id integer) OWNER TO postgres;

--
-- Name: sp_add_material(character varying, character varying, character varying, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_add_material(p_articul character varying, p_name character varying, p_unit character varying, p_price numeric) RETURNS TABLE(status character varying, message character varying, "id_материала" integer)
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.sp_add_material(p_articul character varying, p_name character varying, p_unit character varying, p_price numeric) OWNER TO postgres;

--
-- Name: sp_add_order_item(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_add_order_item(p_order_id integer, p_product_id integer, p_qty integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE v_stock INTEGER;
v_missing_product INTEGER;
v_date_ready DATE;
v_missing_material_name VARCHAR;
v_exists BOOLEAN;
rec RECORD;
BEGIN -- Check order status
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
-- Calculate ready date (simplified: +7 days)
v_date_ready := CURRENT_DATE + INTERVAL '7 days';
-- Add/Update item in Order
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
-- CHECK STOCK
SELECT количество_на_складе INTO v_stock
FROM Изделие
WHERE id_изделия = p_product_id;
IF v_stock >= p_qty THEN -- Enough stock: Reserve it (deduct from stock)
UPDATE Изделие
SET количество_на_складе = количество_на_складе - p_qty
WHERE id_изделия = p_product_id;
status := 'OK';
message := 'Изделия зарезервированы со склада.';
ELSE -- Insufficient product stock -> Need Production
v_missing_product := p_qty - v_stock;
-- Use up existing product stock
IF v_stock > 0 THEN
UPDATE Изделие
SET количество_на_складе = 0
WHERE id_изделия = p_product_id;
END IF;
-- CHECK MATERIALS for ALL required components BEFORE creating tasks
-- HERE IS THE FIX: РасходМатериалов
SELECT m.наименование INTO v_missing_material_name
FROM СоставИзделия si
    JOIN РасходМатериалов rm ON si.id_заготовки = rm.id_заготовки
    JOIN Материал m ON rm.id_материала = m.id_материала
WHERE si.id_изделия = p_product_id
    AND m.количество_на_складе < (
        v_missing_product * si.количество_заготовки * rm.количество_материала
    )
LIMIT 1;
IF v_missing_material_name IS NOT NULL THEN -- Rollback: delete the order item we just added
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
-- Restore product stock if we used any
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
-- 2. Create/Update COMPONENT tasks in ПланЗаготовок
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
message := 'Заказ принят, но изделий не хватает. Созданы задачи на производство.';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;


ALTER FUNCTION public.sp_add_order_item(p_order_id integer, p_product_id integer, p_qty integer) OWNER TO postgres;

--
-- Name: sp_add_order_item(integer, integer, integer, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_add_order_item(p_order_id integer, p_product_id integer, p_qty integer, p_price numeric DEFAULT NULL::numeric) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE v_price NUMERIC;
BEGIN -- If price not provided, get from product
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
-- Update total price
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


ALTER FUNCTION public.sp_add_order_item(p_order_id integer, p_product_id integer, p_qty integer, p_price numeric) OWNER TO postgres;

--
-- Name: sp_add_product(character varying, character varying, character varying, character varying, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_add_product(p_articul character varying, p_name character varying, p_type character varying, p_size character varying, p_price numeric) RETURNS TABLE(status character varying, message character varying, "id_изделия" integer)
    LANGUAGE plpgsql
    AS $$
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


ALTER FUNCTION public.sp_add_product(p_articul character varying, p_name character varying, p_type character varying, p_size character varying, p_price numeric) OWNER TO postgres;

--
-- Name: sp_add_product_component(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_add_product_component(p_prod_id integer, p_comp_id integer, p_qty integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN
INSERT INTO СоставИзделия (id_изделия, id_заготовки, количество_заготовки)
VALUES (p_prod_id, p_comp_id, p_qty) ON CONFLICT (id_изделия, id_заготовки) DO
UPDATE
SET количество_заготовки = СоставИзделия.количество_заготовки + p_qty;
-- Add to existing logic
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Заготовка добавлена'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;


ALTER FUNCTION public.sp_add_product_component(p_prod_id integer, p_comp_id integer, p_qty integer) OWNER TO postgres;

--
-- Name: sp_add_product_to_order_smart(integer, integer, integer, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_add_product_to_order_smart(p_order_id integer, p_product_id integer, p_qty integer, p_deadline date) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE r RECORD;
rm_rec RECORD;
v_needed_qty INTEGER;
v_stock_qty INTEGER;
v_missing_qty INTEGER;
v_components_added INTEGER := 0;
v_price NUMERIC;
v_missing_text VARCHAR := '';
BEGIN
SELECT стоимость INTO v_price
FROM Изделие
WHERE id_изделия = p_product_id;
-- Pre-calculate and check materials for ALL missing components
FOR r IN (
    SELECT si.id_заготовки,
        si.количество_заготовки
    FROM СоставИзделия si
    WHERE si.id_изделия = p_product_id
) LOOP v_needed_qty := COALESCE(r.количество_заготовки, 0) * p_qty;
SELECT количество_готовых INTO v_stock_qty
FROM Заготовка
WHERE id_заготовки = r.id_заготовки;
IF COALESCE(v_stock_qty, 0) < v_needed_qty THEN v_missing_qty := v_needed_qty - COALESCE(v_stock_qty, 0);
-- Check materials for v_missing_qty of this component
FOR rm_rec IN (
    SELECT m.наименование,
        m.количество_на_складе,
        (
            COALESCE(sz.количество_материала, 0) * v_missing_qty
        ) as needed
    FROM СоставЗаготовки sz
        JOIN Материал m ON sz.id_материала = m.id_материала
    WHERE sz.id_заготовки = r.id_заготовки
) LOOP IF COALESCE(rm_rec.количество_на_складе, 0) < rm_rec.needed THEN v_missing_text := v_missing_text || rm_rec.наименование || ' (нужно ' || rm_rec.needed || ', есть ' || COALESCE(rm_rec.количество_на_складе, 0) || '); ';
END IF;
END LOOP;
END IF;
END LOOP;
IF v_missing_text != '' THEN status := 'ERROR';
message := 'Не хватает материалов для заготовок: ' || v_missing_text;
RETURN NEXT;
RETURN;
END IF;
-- All materials are sufficient. Proceed with inserting order item.
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
-- Deduct materials and create tasks
FOR r IN (
    SELECT si.id_заготовки,
        si.количество_заготовки
    FROM СоставИзделия si
    WHERE si.id_изделия = p_product_id
) LOOP v_needed_qty := COALESCE(r.количество_заготовки, 0) * p_qty;
SELECT количество_готовых INTO v_stock_qty
FROM Заготовка
WHERE id_заготовки = r.id_заготовки;
IF COALESCE(v_stock_qty, 0) < v_needed_qty THEN v_missing_qty := v_needed_qty - COALESCE(v_stock_qty, 0);
-- Deduct materials!
FOR rm_rec IN (
    SELECT sz.id_материала,
        (
            COALESCE(sz.количество_материала, 0) * v_missing_qty
        ) as needed
    FROM СоставЗаготовки sz
    WHERE sz.id_заготовки = r.id_заготовки
) LOOP
UPDATE Материал
SET количество_на_складе = количество_на_складе - rm_rec.needed
WHERE id_материала = rm_rec.id_материала;
END LOOP;
INSERT INTO ПланЗаготовок (
        id_заказа,
        id_заготовки,
        плановое_количество,
        фактическое_количество,
        дата_план,
        статус,
        дата_факт
    )
VALUES (
        p_order_id,
        r.id_заготовки,
        v_missing_qty,
        0,
        p_deadline,
        'принято',
        NULL
    );
v_components_added := v_components_added + 1;
END IF;
END LOOP;
IF v_components_added = 0 THEN status := 'OK';
message := 'Изделие добавлено. Все компоненты в наличии.';
ELSE
UPDATE Заказ
SET статус = 'в_работе'
WHERE id_заказа = p_order_id
    AND статус = 'принят';
status := 'OK';
message := 'Созданы задачи для ' || v_components_added || ' компонентов и списаны материалы.';
END IF;
RETURN NEXT;
END;
$$;


ALTER FUNCTION public.sp_add_product_to_order_smart(p_order_id integer, p_product_id integer, p_qty integer, p_deadline date) OWNER TO postgres;

--
-- Name: sp_assign_worker_to_task(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_assign_worker_to_task("p_id_заготовки" integer, "p_id_заказа" integer, p_worker_id integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$
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
UPDATE ПланЗаготовок
SET id_сотрудника = p_worker_id,
    статус = 'назначено'
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF FOUND THEN status := 'OK';
message := 'Сборщик назначен';
ELSE status := 'ERROR';
message := 'Задача не найдена';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;


ALTER FUNCTION public.sp_assign_worker_to_task("p_id_заготовки" integer, "p_id_заказа" integer, p_worker_id integer) OWNER TO postgres;

--
-- Name: sp_calculate_order_sum(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_calculate_order_sum() RETURNS trigger
    LANGUAGE plpgsql
    AS $$ BEGIN
UPDATE Заказ
SET сумма_заказа = (
        SELECT COALESCE(
                SUM(sz.количество_изделий * sz.цена_фиксированная),
                0
            )
        FROM СоставЗаказа sz
        WHERE sz.id_заказа = COALESCE(NEW.id_заказа, OLD.id_заказа)
    )
WHERE id_заказа = COALESCE(NEW.id_заказа, OLD.id_заказа);
RETURN NULL;
END;
$$;


ALTER FUNCTION public.sp_calculate_order_sum() OWNER TO postgres;

--
-- Name: sp_calculate_product_stock(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_calculate_product_stock() RETURNS TABLE("id_изделия" integer, "наименование" character varying, "расчетный_остаток" integer)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT i.id_изделия,
    i.наименование,
    COALESCE(
        MIN(
            FLOOR(z.количество_готовых / si.количество_заготовки)
        ),
        0
    )::INTEGER AS расчетный_остаток
FROM Изделие i
    JOIN СоставИзделия si ON i.id_изделия = si.id_изделия
    JOIN Заготовка z ON si.id_заготовки = z.id_заготовки
GROUP BY i.id_изделия,
    i.наименование
ORDER BY i.наименование;
END;
$$;


ALTER FUNCTION public.sp_calculate_product_stock() OWNER TO postgres;

--
-- Name: sp_cancel_purchase(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_cancel_purchase(p_purchase_id integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE v_current_status VARCHAR;
BEGIN
SELECT статус INTO v_current_status
FROM закупки_материалов
WHERE id_закупки = p_purchase_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Закупка не найдена';
RETURN NEXT;
RETURN;
END IF;
IF v_current_status = 'выполнено' THEN status := 'ERROR';
message := 'Нельзя отменить выполненную закупку';
RETURN NEXT;
RETURN;
END IF;
IF v_current_status = 'отменено' THEN status := 'ERROR';
message := 'Закупка уже отменена';
RETURN NEXT;
RETURN;
END IF;
UPDATE закупки_материалов
SET статус = 'отменено'
WHERE id_закупки = p_purchase_id;
status := 'OK';
message := 'Закупка отменена';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;


ALTER FUNCTION public.sp_cancel_purchase(p_purchase_id integer) OWNER TO postgres;

--
-- Name: sp_check_order_ready(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_check_order_ready() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE v_id_order INTEGER;
v_pending_count INTEGER;
BEGIN v_id_order := NEW.id_заказа;
SELECT COUNT(*) INTO v_pending_count
FROM "ПланЗаготовок"
WHERE id_заказа = v_id_order
    AND статус != 'выполнено';
IF v_pending_count = 0 THEN
UPDATE Заказ
SET статус = 'завершен',
    дата_готовности = CURRENT_DATE
WHERE id_заказа = v_id_order
    AND статус = 'в_работе';
END IF;
RETURN NEW;
END;
$$;


ALTER FUNCTION public.sp_check_order_ready() OWNER TO postgres;

--
-- Name: sp_confirm_purchase(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_confirm_purchase(p_purchase_id integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE v_status VARCHAR;
rec RECORD;
BEGIN -- Check current status
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
-- Update status
UPDATE Закупка
SET статус = 'выполнено'
WHERE id_закупки = p_purchase_id;
-- Update stock
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


ALTER FUNCTION public.sp_confirm_purchase(p_purchase_id integer) OWNER TO postgres;

--
-- Name: sp_create_component(character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_create_component(p_name character varying) RETURNS TABLE(status character varying, message character varying, "id_заготовки" integer)
    LANGUAGE plpgsql
    AS $$
DECLARE new_id INTEGER;
BEGIN
INSERT INTO Заготовка (
        наименование,
        количество_готовых
    )
VALUES (p_name, 0) -- Corrected: 2 values for 2 columns
RETURNING Заготовка.id_заготовки INTO new_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Заготовка создана'::VARCHAR,
    new_id;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR,
    NULL::INTEGER;
END;
$$;


ALTER FUNCTION public.sp_create_component(p_name character varying) OWNER TO postgres;

--
-- Name: sp_create_manual_production_task(integer, integer, integer, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_create_manual_production_task(p_order_id integer, p_component_id integer, p_qty integer, p_deadline date DEFAULT NULL::date) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$
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
-- Check materials (using СоставЗаготовки)
FOR rm_rec IN (
    SELECT m.наименование,
        m.количество_на_складе,
        (COALESCE(sz.количество_материала, 0) * p_qty) as needed
    FROM СоставЗаготовки sz
        JOIN Материал m ON sz.id_материала = m.id_материала
    WHERE sz.id_заготовки = p_component_id
) LOOP IF COALESCE(rm_rec.количество_на_складе, 0) < rm_rec.needed THEN v_missing_text := v_missing_text || rm_rec.наименование || ' (нужно ' || rm_rec.needed || ', есть ' || COALESCE(rm_rec.количество_на_складе, 0) || '); ';
END IF;
END LOOP;
IF v_missing_text != '' THEN status := 'ERROR';
message := 'НЕОБХОДИМА ЗАКУПКА: Недостаточно материалов: ' || v_missing_text;
RETURN NEXT;
RETURN;
END IF;
-- Deduct materials
FOR rm_rec IN (
    SELECT sz.id_материала,
        (COALESCE(sz.количество_материала, 0) * p_qty) as needed
    FROM СоставЗаготовки sz
    WHERE sz.id_заготовки = p_component_id
) LOOP
UPDATE Материал
SET количество_на_складе = количество_на_складе - rm_rec.needed
WHERE id_материала = rm_rec.id_материала;
END LOOP;
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


ALTER FUNCTION public.sp_create_manual_production_task(p_order_id integer, p_component_id integer, p_qty integer, p_deadline date) OWNER TO postgres;

--
-- Name: sp_create_material(character varying, character varying, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_create_material(p_article character varying, p_name character varying, p_qty integer DEFAULT 0) RETURNS TABLE(status character varying, message character varying, "id_материала" integer)
    LANGUAGE plpgsql
    AS $$
DECLARE new_id INTEGER;
BEGIN
INSERT INTO Материал (
        артикул_материала,
        наименование,
        количество_на_складе
    )
VALUES (p_article, p_name, p_qty)
RETURNING Материал.id_материала INTO new_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Материал создан'::VARCHAR,
    new_id;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR,
    NULL::INTEGER;
END;
$$;


ALTER FUNCTION public.sp_create_material(p_article character varying, p_name character varying, p_qty integer) OWNER TO postgres;

--
-- Name: sp_create_order(integer, integer, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_create_order(p_client_id integer, p_manager_id integer, p_deadline date) RETURNS TABLE(status character varying, message character varying, "id_заказа" integer)
    LANGUAGE plpgsql
    AS $$
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
        'принят',
        -- CHANGED: 'новый' -> 'принят' (valid status)
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


ALTER FUNCTION public.sp_create_order(p_client_id integer, p_manager_id integer, p_deadline date) OWNER TO postgres;

--
-- Name: sp_create_product(character varying, character varying, character varying, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_create_product(p_name character varying, p_type character varying, p_size character varying, p_price numeric) RETURNS TABLE(status character varying, message character varying, "id_изделия" integer)
    LANGUAGE plpgsql
    AS $$
DECLARE new_id INTEGER;
BEGIN
INSERT INTO Изделие (
        наименование,
        тип,
        размеры,
        стоимость,
        количество_на_складе
    )
VALUES (p_name, p_type, p_size, p_price, 0)
RETURNING Изделие.id_изделия INTO new_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Изделие создано'::VARCHAR,
    new_id;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR,
    NULL::INTEGER;
END;
$$;


ALTER FUNCTION public.sp_create_product(p_name character varying, p_type character varying, p_size character varying, p_price numeric) OWNER TO postgres;

--
-- Name: sp_delete_client(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_delete_client(p_client_id integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN IF EXISTS (
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


ALTER FUNCTION public.sp_delete_client(p_client_id integer) OWNER TO postgres;

--
-- Name: sp_delete_component_material(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_delete_component_material(p_comp_id integer, p_mat_id integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN
DELETE FROM РасходМатериалов
WHERE id_заготовки = p_comp_id
    AND id_материала = p_mat_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Материал удален из состава'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;


ALTER FUNCTION public.sp_delete_component_material(p_comp_id integer, p_mat_id integer) OWNER TO postgres;

--
-- Name: sp_delete_product_component(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_delete_product_component(p_prod_id integer, p_comp_id integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN
DELETE FROM СоставИзделия
WHERE id_изделия = p_prod_id
    AND id_заготовки = p_comp_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Заготовка удалена из состава'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;


ALTER FUNCTION public.sp_delete_product_component(p_prod_id integer, p_comp_id integer) OWNER TO postgres;

--
-- Name: sp_get_all_components(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_all_components() RETURNS TABLE("id_заготовки" integer, "наименование" character varying, "количество_на_складе" integer)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT z.id_заготовки,
    z.наименование,
    z.количество_готовых -- Fixed column name
FROM Заготовка z;
END;
$$;


ALTER FUNCTION public.sp_get_all_components() OWNER TO postgres;

--
-- Name: sp_get_all_materials(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_all_materials() RETURNS TABLE("id_материала" integer, "наименование" character varying, "количество_на_складе" integer, "единица_измерения" character varying, "минимальный_остаток" integer)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    m.количество_на_складе,
    m.единица_измерения,
    -- m.цена_закупки,  -- REMOVED: Column does not exist
    m.минимальный_остаток
FROM Материал m
ORDER BY m.наименование;
END;
$$;


ALTER FUNCTION public.sp_get_all_materials() OWNER TO postgres;

--
-- Name: sp_get_assembler_tasks(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_assembler_tasks() RETURNS TABLE("тип_задачи" character varying, "id_объекта" integer, "id_заказа" integer, "наименование_задачи" character varying, "плановое_количество" integer, "фактическое_количество" integer, "дедлайн" date, "статус" character varying, "id_сборщика" integer)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT 'заготовка'::VARCHAR as тип_задачи,
    pz.id_заготовки as id_объекта,
    pz.id_заказа,
    z.наименование as наименование_задачи,
    pz.плановое_количество,
    COALESCE(pz.фактическое_количество, 0),
    pz.дата_план as дедлайн,
    pz.статус,
    pz.id_сотрудника as id_сборщика
FROM "ПланЗаготовок" pz
    JOIN Заготовка z ON pz.id_заготовки = z.id_заготовки
ORDER BY pz.дата_план;
END;
$$;


ALTER FUNCTION public.sp_get_assembler_tasks() OWNER TO postgres;

--
-- Name: sp_get_avg_check_chart_data(date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_avg_check_chart_data(p_start date, p_end date) RETURNS TABLE(d date, val numeric)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT дата_заказа as d,
    AVG(сумма_заказа) as val
FROM Заказ
WHERE статус IN ('выполнен', 'завершен', 'отгружен')
    AND дата_заказа BETWEEN p_start AND p_end
GROUP BY дата_заказа
ORDER BY дата_заказа;
END;
$$;


ALTER FUNCTION public.sp_get_avg_check_chart_data(p_start date, p_end date) OWNER TO postgres;

--
-- Name: sp_get_cancel_rate_chart_data(date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_cancel_rate_chart_data(p_start date, p_end date) RETURNS TABLE(d date, val numeric)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT дата_заказа as d,
    (
        COUNT(*) FILTER (
            WHERE статус = 'отменен'
        )::numeric / NULLIF(COUNT(*), 0)
    ) * 100 as val
FROM Заказ
WHERE дата_заказа BETWEEN p_start AND p_end
GROUP BY дата_заказа
ORDER BY дата_заказа;
END;
$$;


ALTER FUNCTION public.sp_get_cancel_rate_chart_data(p_start date, p_end date) OWNER TO postgres;

--
-- Name: sp_get_clients(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_clients() RETURNS TABLE("id_клиента" integer, "фио" character varying, "номер_телефона" character varying, "адрес" text, "дата_регистрации" date, "инн" character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT k.id_клиента,
    k.фио,
    k.номер_телефона,
    k.адрес,
    k.дата_регистрации,
    k.инн
FROM Клиент k
ORDER BY k.фио;
END;
$$;


ALTER FUNCTION public.sp_get_clients() OWNER TO postgres;

--
-- Name: sp_get_component_materials(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_component_materials(p_comp_id integer) RETURNS TABLE("id_материала" integer, "наименование" character varying, "количество" integer)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    rm.количество_материала
FROM РасходМатериалов rm
    JOIN Материал m ON rm.id_материала = m.id_материала
WHERE rm.id_заготовки = p_comp_id;
END;
$$;


ALTER FUNCTION public.sp_get_component_materials(p_comp_id integer) OWNER TO postgres;

--
-- Name: sp_get_components(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_components() RETURNS TABLE("id_заготовки" integer, "наименование" character varying, "количество_готовых" integer)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT z.id_заготовки,
    z.наименование,
    z.количество_готовых
FROM Заготовка z
ORDER BY z.наименование;
END;
$$;


ALTER FUNCTION public.sp_get_components() OWNER TO postgres;

--
-- Name: sp_get_dashboard_counts(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_dashboard_counts() RETURNS TABLE(orders_count integer, revenue numeric, employees_count integer, products_count integer)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT (
        SELECT COUNT(*)::INTEGER
        FROM Заказ
    ),
    (
        SELECT COALESCE(SUM(сумма_заказа), 0)
        FROM Заказ
    ),
    (
        SELECT COUNT(*)::INTEGER
        FROM Сотрудник
        WHERE дата_увольнения IS NULL
    ),
    (
        SELECT COUNT(*)::INTEGER
        FROM Изделие
    );
END;
$$;


ALTER FUNCTION public.sp_get_dashboard_counts() OWNER TO postgres;

--
-- Name: sp_get_dashboard_summary(date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_dashboard_summary(p_start date, p_end date) RETURNS TABLE(revenue numeric, orders_count integer, expenses numeric, cancels integer, staff_count integer)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT (
        SELECT COALESCE(SUM(сумма_заказа), 0)
        FROM Заказ
        WHERE статус IN ('выполнен', 'завершен', 'отгружен')
            AND дата_заказа BETWEEN p_start AND p_end
    ) as revenue,
    (
        SELECT COUNT(*)::INTEGER
        FROM Заказ
        WHERE статус IN ('выполнен', 'завершен', 'отгружен')
            AND дата_заказа BETWEEN p_start AND p_end
    ) as orders_count,
    (
        SELECT COALESCE(SUM(sz.количество * sz.цена_закупки), 0)
        FROM Закупка zm
            JOIN СоставЗакупки sz ON zm.id_закупки = sz.id_закупки
        WHERE zm.статус = 'выполнено'
            AND zm.дата_закупки BETWEEN p_start AND p_end
    ) as expenses,
    (
        SELECT COUNT(*)::INTEGER
        FROM Заказ
        WHERE статус = 'отменен'
            AND дата_заказа BETWEEN p_start AND p_end
    ) as cancels,
    (
        SELECT COUNT(*)::INTEGER
        FROM Сотрудник
        WHERE дата_увольнения IS NULL
    ) as staff_count;
END;
$$;


ALTER FUNCTION public.sp_get_dashboard_summary(p_start date, p_end date) OWNER TO postgres;

--
-- Name: sp_get_employees(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_employees() RETURNS TABLE("id_сотрудника" integer, "фио" character varying, "должность" character varying, login character varying, "дата_увольнения" date, "номер_телефона" character varying, "зарплата" numeric)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT s.id_сотрудника,
    s.фио,
    s.должность,
    s.login,
    s.дата_увольнения,
    s.номер_телефона,
    s.зарплата
FROM Сотрудник s
ORDER BY s.дата_увольнения NULLS FIRST,
    s.фио;
END;
$$;


ALTER FUNCTION public.sp_get_employees() OWNER TO postgres;

--
-- Name: sp_get_expenses_chart_data(date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_expenses_chart_data(p_start date, p_end date) RETURNS TABLE(d date, val numeric)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT zm.дата_закупки as d,
    SUM(sz.количество * sz.цена_закупки) as val
FROM Закупка zm
    JOIN СоставЗакупки sz ON zm.id_закупки = sz.id_закупки
WHERE zm.статус = 'выполнено'
    AND zm.дата_закупки BETWEEN p_start AND p_end
GROUP BY zm.дата_закупки
ORDER BY zm.дата_закупки;
END;
$$;


ALTER FUNCTION public.sp_get_expenses_chart_data(p_start date, p_end date) OWNER TO postgres;

--
-- Name: sp_get_materials(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_materials() RETURNS TABLE("id_материала" integer, "наименование" character varying, "количество_на_складе" integer, "единица_измерения" character varying, "минимальный_остаток" integer, "цена_за_единицу" numeric)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
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


ALTER FUNCTION public.sp_get_materials() OWNER TO postgres;

--
-- Name: sp_get_order_items(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_order_items(p_order_id integer) RETURNS TABLE("id_изделия" integer, "наименование" character varying, "количество" integer, "цена" numeric, "сумма" numeric)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT sz.id_изделия,
    i.наименование,
    COALESCE(sz.количество_изделий, 0) AS количество,
    COALESCE(i.стоимость, 0) AS цена,
    (
        COALESCE(sz.количество_изделий, 0) * COALESCE(i.стоимость, 0)
    ) AS сумма
FROM СоставЗаказа sz
    JOIN Изделие i ON sz.id_изделия = i.id_изделия
WHERE sz.id_заказа = p_order_id;
END;
$$;


ALTER FUNCTION public.sp_get_order_items(p_order_id integer) OWNER TO postgres;

--
-- Name: sp_get_order_tasks(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_order_tasks(p_order_id integer) RETURNS TABLE("тип_задачи" character varying, "наименование" character varying, "плановое_количество" integer, "статус" character varying, "дедлайн" date)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT 'заготовка'::VARCHAR,
    z.наименование,
    pz.плановое_количество,
    pz.статус,
    pz.дата_план
FROM "ПланЗаготовок" pz
    JOIN Заготовка z ON pz.id_заготовки = z.id_заготовки
WHERE pz.id_заказа = p_order_id
ORDER BY pz.дата_план;
END;
$$;


ALTER FUNCTION public.sp_get_order_tasks(p_order_id integer) OWNER TO postgres;

--
-- Name: sp_get_orders_count_chart_data(date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_orders_count_chart_data(p_start date, p_end date) RETURNS TABLE(d date, val bigint)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT дата_заказа as d,
    COUNT(*) as val
FROM Заказ
WHERE статус IN ('выполнен', 'завершен', 'отгружен')
    AND дата_заказа BETWEEN p_start AND p_end
GROUP BY дата_заказа
ORDER BY дата_заказа;
END;
$$;


ALTER FUNCTION public.sp_get_orders_count_chart_data(p_start date, p_end date) OWNER TO postgres;

--
-- Name: sp_get_product_components(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_product_components(p_product_id integer) RETURNS TABLE("id_заготовки" integer, "наименование" character varying, "количество" integer)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT z.id_заготовки,
    z.наименование,
    si.количество_заготовки AS количество
FROM СоставИзделия si
    JOIN Заготовка z ON si.id_заготовки = z.id_заготовки
WHERE si.id_изделия = p_product_id
ORDER BY z.наименование;
END;
$$;


ALTER FUNCTION public.sp_get_product_components(p_product_id integer) OWNER TO postgres;

--
-- Name: sp_get_product_components_status(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_product_components_status(p_order_id integer, p_product_id integer) RETURNS TABLE("наименование_заготовки" character varying, "требуется" integer, "выполнено" integer, "осталось" integer)
    LANGUAGE plpgsql
    AS $$
DECLARE v_product_qty INTEGER;
BEGIN
SELECT COALESCE(sz.количество_изделий, 0) INTO v_product_qty
FROM СоставЗаказа sz
WHERE sz.id_заказа = p_order_id
    AND sz.id_изделия = p_product_id;
IF v_product_qty IS NULL
OR v_product_qty = 0 THEN RETURN;
END IF;
RETURN QUERY
SELECT z.наименование::VARCHAR,
    (si.количество_заготовки * v_product_qty)::INTEGER,
    COALESCE(SUM(pp.фактическое_количество), 0)::INTEGER,
    GREATEST(
        0,
        (si.количество_заготовки * v_product_qty) - COALESCE(SUM(pp.фактическое_количество), 0)
    )::INTEGER
FROM СоставИзделия si
    JOIN Заготовка z ON si.id_заготовки = z.id_заготовки
    LEFT JOIN "ПланЗаготовок" pp ON pp.id_заказа = p_order_id
    AND pp.id_заготовки = si.id_заготовки
WHERE si.id_изделия = p_product_id
GROUP BY z.наименование,
    si.количество_заготовки;
END;
$$;


ALTER FUNCTION public.sp_get_product_components_status(p_order_id integer, p_product_id integer) OWNER TO postgres;

--
-- Name: sp_get_production_dashboard_data(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_production_dashboard_data(p_user_id integer) RETURNS TABLE("id_заготовки" integer, "id_заказа" integer, "наименование_заготовки" character varying, "плановое_количество" integer, "фактическое_количество" integer, "дата_план" date, "статус" character varying, "id_клиента" integer, "фио_клиента" character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT pz.id_заготовки,
    pz.id_заказа,
    z.наименование,
    pz.плановое_количество,
    pz.фактическое_количество,
    pz.дата_план,
    pz.статус,
    o.id_клиента,
    k.фио
FROM план_заготовок pz
    JOIN заготовки z ON pz.id_заготовки = z.id_заготовки
    JOIN заказы o ON pz.id_заказа = o.id_заказа
    JOIN клиенты k ON o.id_клиента = k.id_клиента
WHERE (
        pz.id_сотрудника = p_user_id
        OR pz.id_сотрудника IS NULL
    )
    AND pz.статус NOT IN ('выполнено', 'отменено')
ORDER BY pz.дата_план;
END;
$$;


ALTER FUNCTION public.sp_get_production_dashboard_data(p_user_id integer) OWNER TO postgres;

--
-- Name: sp_get_production_plan_full(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_production_plan_full() RETURNS TABLE("id_заготовки" integer, "id_заказа" integer, "заготовка" character varying, "плановое_количество" integer, "фактическое_количество" integer, "дедлайн" date, "статус" character varying, "сборщик" character varying, "id_сотрудника" integer)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT pz.id_заготовки,
    pz.id_заказа,
    z.наименование AS заготовка,
    pz.плановое_количество,
    pz.фактическое_количество,
    pz.дата_план AS дедлайн,
    pz.статус,
    COALESCE(s.фио, 'Не назначен')::VARCHAR as сборщик,
    pz.id_сотрудника
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


ALTER FUNCTION public.sp_get_production_plan_full() OWNER TO postgres;

--
-- Name: sp_get_products(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_products() RETURNS TABLE("id_изделия" integer, "наименование" character varying, "тип" character varying, "размеры" character varying, "стоимость" numeric, "количество_на_складе" integer)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
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


ALTER FUNCTION public.sp_get_products() OWNER TO postgres;

--
-- Name: sp_get_profit_chart_data(date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_profit_chart_data(p_start date, p_end date) RETURNS TABLE(d date, val numeric)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT дата_заказа as d,
    SUM(сумма_заказа) * 0.3 as val
FROM Заказ
WHERE статус IN ('выполнен', 'завершен', 'отгружен')
    AND дата_заказа BETWEEN p_start AND p_end
GROUP BY дата_заказа
ORDER BY дата_заказа;
END;
$$;


ALTER FUNCTION public.sp_get_profit_chart_data(p_start date, p_end date) OWNER TO postgres;

--
-- Name: sp_get_purchase_items(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_purchase_items(p_purchase_id integer) RETURNS TABLE("id_материала" integer, "наименование" character varying, "количество" integer, "цена_закупки" numeric)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    sz.количество,
    sz.цена_закупки
FROM СоставЗакупки sz
    JOIN Материал m ON sz.id_материала = m.id_материала
WHERE sz.id_закупки = p_purchase_id
ORDER BY m.наименование;
END;
$$;


ALTER FUNCTION public.sp_get_purchase_items(p_purchase_id integer) OWNER TO postgres;

--
-- Name: sp_get_purchases(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_purchases() RETURNS TABLE("id_закупки" integer, "дата_закупки" date, "поставщик" character varying, "статус" character varying, "сумма" numeric)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT z.id_закупки,
    z.дата_закупки,
    z.поставщик,
    z.статус,
    (
        SELECT COALESCE(SUM(количество * цена_закупки), 0)
        FROM СоставЗакупки sz
        WHERE sz.id_закупки = z.id_закупки
    ) as сумма
FROM Закупка z
ORDER BY z.дата_закупки DESC;
END;
$$;


ALTER FUNCTION public.sp_get_purchases() OWNER TO postgres;

--
-- Name: sp_get_sales_chart_data(date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_sales_chart_data(p_start date, p_end date) RETURNS TABLE(d date, val numeric)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT дата_заказа as d,
    SUM(сумма_заказа) as val
FROM Заказ
WHERE статус IN ('выполнен', 'завершен', 'отгружен')
    AND дата_заказа BETWEEN p_start AND p_end
GROUP BY дата_заказа
ORDER BY дата_заказа;
END;
$$;


ALTER FUNCTION public.sp_get_sales_chart_data(p_start date, p_end date) OWNER TO postgres;

--
-- Name: sp_get_schedule(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_schedule(p_employee_id integer) RETURNS TABLE("дата" date, "статус" character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT График.дата,
    График.статус
FROM График
WHERE id_сотрудника = p_employee_id;
END;
$$;


ALTER FUNCTION public.sp_get_schedule(p_employee_id integer) OWNER TO postgres;

--
-- Name: sp_get_warehouse_summary(character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_warehouse_summary(p_search character varying DEFAULT NULL::character varying, p_type character varying DEFAULT NULL::character varying) RETURNS TABLE("тип" character varying, "наименование" character varying, "количество" integer, "ед_изм" character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT base.тип,
    base.наименование,
    base.количество,
    base.ед_изм
FROM (
        -- Materials
        SELECT 'Материал'::VARCHAR as тип,
            m.наименование,
            m.количество_на_складе as количество,
            m.единица_измерения as ед_изм
        FROM Материал m
        UNION ALL
        -- Components (Zagotovka)
        SELECT 'Заготовка'::VARCHAR,
            z.наименование,
            z.количество_готовых,
            'шт'::VARCHAR
        FROM Заготовка z
        UNION ALL
        -- Products (Calculated dynamic stock)
        SELECT 'Изделие'::VARCHAR,
            p.наименование,
            p.расчетный_остаток,
            'шт'::VARCHAR
        FROM sp_calculate_product_stock() p
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


ALTER FUNCTION public.sp_get_warehouse_summary(p_search character varying, p_type character varying) OWNER TO postgres;

--
-- Name: sp_get_workers(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_get_workers() RETURNS TABLE("id_сотрудника" integer, "фио" character varying, "должность" character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT s.id_сотрудника,
    s.фио,
    s.должность
FROM Сотрудник s
WHERE s.дата_увольнения IS NULL
ORDER BY s.фио;
END;
$$;


ALTER FUNCTION public.sp_get_workers() OWNER TO postgres;

--
-- Name: sp_hire_employee(character varying, character varying, date, character varying, integer, character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_hire_employee(p_fio character varying, p_phone character varying, p_birth_date date, p_role character varying, p_salary integer, p_login character varying, p_password_raw character varying) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN -- Validation
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
-- Insert
INSERT INTO сотрудники (
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


ALTER FUNCTION public.sp_hire_employee(p_fio character varying, p_phone character varying, p_birth_date date, p_role character varying, p_salary integer, p_login character varying, p_password_raw character varying) OWNER TO postgres;

--
-- Name: sp_login(character varying, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_login(p_login character varying, p_password character varying) RETURNS TABLE(status character varying, message character varying, user_id integer, role character varying, fio character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE rec RECORD;
BEGIN -- 1. Find user from 'Сотрудник'
SELECT id_сотрудника,
    password_hash,
    должность,
    фио INTO rec
FROM Сотрудник
WHERE login = p_login;
IF NOT FOUND THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    'Пользователь не найден'::VARCHAR,
    NULL::INTEGER,
    NULL::VARCHAR,
    NULL::VARCHAR;
RETURN;
END IF;
-- 2. Check password
IF NOT (
    rec.password_hash = crypt(p_password, rec.password_hash)
) THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    'Неверный пароль'::VARCHAR,
    NULL::INTEGER,
    NULL::VARCHAR,
    NULL::VARCHAR;
RETURN;
END IF;
-- 3. Success
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Успешный вход'::VARCHAR,
    rec.id_сотрудника,
    rec.должность,
    rec.фио;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    'Ошибка БД: ' || SQLERRM,
    NULL::INTEGER,
    NULL::VARCHAR,
    NULL::VARCHAR;
END;
$$;


ALTER FUNCTION public.sp_login(p_login character varying, p_password character varying) OWNER TO postgres;

--
-- Name: sp_release_task(integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_release_task("p_id_заготовки" integer, "p_id_заказа" integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN
UPDATE ПланЗаготовок
SET id_сотрудника = NULL,
    статус = 'принято' -- Reset status
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF FOUND THEN status := 'OK';
message := 'Задача освобождена';
ELSE status := 'ERROR';
message := 'Задача не найдена';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;


ALTER FUNCTION public.sp_release_task("p_id_заготовки" integer, "p_id_заказа" integer) OWNER TO postgres;

--
-- Name: sp_report_defect(integer, integer, integer, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_report_defect(p_order_id integer, p_product_id integer, p_qty integer, p_reason character varying) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE v_order_status VARCHAR;
BEGIN 
SELECT статус INTO v_order_status
FROM Заказ
WHERE id_заказа = p_order_id;
IF v_order_status IS NULL THEN status := 'ERROR';
message := 'Заказ не найден';
RETURN NEXT;
RETURN;
END IF;

IF v_order_status = 'завершен' THEN
UPDATE Заказ
SET статус = 'в_работе',
    дата_готовности = NULL
WHERE id_заказа = p_order_id;
END IF;








status := 'WARNING';

message := 'Статус заказа возвращен в "в_работе". Пожалуйста, создайте задачи на переделку вручную.';
RETURN NEXT;
END;
$$;


ALTER FUNCTION public.sp_report_defect(p_order_id integer, p_product_id integer, p_qty integer, p_reason character varying) OWNER TO postgres;

--
-- Name: sp_save_client(integer, character varying, character varying, integer, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_save_client(p_id_client integer, p_fio character varying, p_phone character varying, p_inn integer, p_address character varying) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN IF p_id_client IS NOT NULL THEN
UPDATE клиенты
SET фио = p_fio,
    номер_телефона = p_phone,
    инн = p_inn,
    адрес = p_address
WHERE id_клиента = p_id_client;
message := 'Данные клиента обновлены!';
ELSE
INSERT INTO клиенты (фио, номер_телефона, инн, адрес)
VALUES (p_fio, p_phone, p_inn, p_address);
message := 'Новый клиент создан!';
END IF;
status := 'OK';
RETURN NEXT;
EXCEPTION
WHEN unique_violation THEN status := 'ERROR';
message := 'Клиент с таким телефоном уже существует!';
RETURN NEXT;
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка сохранения клиента: ' || SQLERRM;
RETURN NEXT;
END;
$$;


ALTER FUNCTION public.sp_save_client(p_id_client integer, p_fio character varying, p_phone character varying, p_inn integer, p_address character varying) OWNER TO postgres;

--
-- Name: sp_save_client(integer, character varying, character varying, character varying, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_save_client(p_id integer, p_fio character varying, p_phone character varying, p_inn character varying, p_address text) RETURNS TABLE(status character varying, message character varying, "id_клиента" integer)
    LANGUAGE plpgsql
    AS $$
DECLARE v_new_id INTEGER;
BEGIN IF p_id IS NOT NULL THEN -- Update
PERFORM sp_update_client(p_id, p_fio, p_phone, p_inn, p_address);
status := 'OK';
message := 'Клиент обновлен';
id_клиента := p_id;
RETURN NEXT;
ELSE -- Insert
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


ALTER FUNCTION public.sp_save_client(p_id integer, p_fio character varying, p_phone character varying, p_inn character varying, p_address text) OWNER TO postgres;

--
-- Name: sp_search_clients(character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_search_clients(p_query character varying) RETURNS TABLE("id_клиента" integer, "фио" character varying, "номер_телефона" character varying, "адрес" text, "дата_регистрации" date, "инн" character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
SELECT c.id_клиента,
    c.фио,
    c.номер_телефона,
    c.адрес,
    c.дата_регистрации,
    c.инн
FROM Клиент c
WHERE LOWER(c.фио) LIKE LOWER(p_query)
    OR LOWER(c.номер_телефона) LIKE LOWER(p_query)
ORDER BY c.фио;
END;
$$;


ALTER FUNCTION public.sp_search_clients(p_query character varying) OWNER TO postgres;

--
-- Name: sp_search_orders(integer, character varying, character varying, date, date); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_search_orders(p_user_id integer, p_search_text character varying, p_status character varying, p_date_from date, p_date_to date) RETURNS TABLE("id_заказа" integer, "клиент" character varying, "менеджер" character varying, "дата_заказа" date, "дата_готовности" date, "статус_заказа" character varying, "сумма_заказа" numeric, "состояние_сроков" character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN RETURN QUERY
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


ALTER FUNCTION public.sp_search_orders(p_user_id integer, p_search_text character varying, p_status character varying, p_date_from date, p_date_to date) OWNER TO postgres;

--
-- Name: sp_set_day_status(integer, date, character varying); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_set_day_status(IN p_employee_id integer, IN p_date date, IN p_status character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN
INSERT INTO График (id_сотрудника, дата, статус)
VALUES (p_employee_id, p_date, p_status) ON CONFLICT (id_сотрудника, дата) DO
UPDATE
SET статус = p_status;
END;
$$;


ALTER PROCEDURE public.sp_set_day_status(IN p_employee_id integer, IN p_date date, IN p_status character varying) OWNER TO postgres;

--
-- Name: sp_submit_assembly_work(integer, integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_submit_assembly_work(IN p_product_id integer, IN p_order_id integer, IN p_qty integer)
    LANGUAGE plpgsql
    AS $$
DECLARE v_status VARCHAR;
v_planned INTEGER;
v_actual INTEGER;
BEGIN
SELECT статус,
    количество_план,
    количество_факт INTO v_status,
    v_planned,
    v_actual
FROM ПланСборки
WHERE id_изделия = p_product_id
    AND id_заказа = p_order_id;
IF v_status = 'выполнено' THEN RAISE EXCEPTION 'Сборка уже выполнена';
END IF;
-- Reduce components stock? Logic likely needed here.
-- (Omitted for brevity, assuming existing sp_сдать_сборку logic was correct or minimal)
-- Simply update plan for now.
UPDATE ПланСборки
SET количество_факт = количество_факт + p_qty,
    статус = CASE
        WHEN (количество_факт + p_qty) >= количество_план THEN 'выполнено'
        ELSE 'в_работе'
    END
WHERE id_изделия = p_product_id
    AND id_заказа = p_order_id;
-- Update Product Stock?
UPDATE Изделие
SET количество_на_складе = количество_на_складе + p_qty
WHERE id_изделия = p_product_id;
END;
$$;


ALTER PROCEDURE public.sp_submit_assembly_work(IN p_product_id integer, IN p_order_id integer, IN p_qty integer) OWNER TO postgres;

--
-- Name: sp_submit_component_work(integer, integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_submit_component_work(p_component_id integer, p_order_id integer, p_qty integer, p_worker_id integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE v_status VARCHAR;
v_planned INTEGER;
v_actual INTEGER;
v_assigned_worker INTEGER;
v_row_count INTEGER;
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
message := 'Нельзя сделать больше, чем запланировано! Осталось сделать: ' || (v_planned - v_actual);
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
-- Only add stock to warehouse if the task is completely finished.
IF (v_actual + p_qty) >= v_planned THEN
UPDATE Заготовка
SET количество_готовых = количество_готовых + v_planned
WHERE id_заготовки = p_component_id;
END IF;
status := 'OK';
message := 'Работа принята';
RETURN NEXT;
END;
$$;


ALTER FUNCTION public.sp_submit_component_work(p_component_id integer, p_order_id integer, p_qty integer, p_worker_id integer) OWNER TO postgres;

--
-- Name: sp_take_assembly_task(integer, integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public.sp_take_assembly_task(IN p_product_id integer, IN p_order_id integer, IN p_worker_id integer)
    LANGUAGE plpgsql
    AS $$ BEGIN
UPDATE ПланСборки
SET id_сотрудника = p_worker_id,
    статус = 'в_работе'
WHERE id_изделия = p_product_id
    AND id_заказа = p_order_id;
END;
$$;


ALTER PROCEDURE public.sp_take_assembly_task(IN p_product_id integer, IN p_order_id integer, IN p_worker_id integer) OWNER TO postgres;

--
-- Name: sp_take_component_task(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_take_component_task(p_component_id integer, p_order_id integer, p_worker_id integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE v_status VARCHAR;
v_assigned_worker INTEGER;
v_planned_qty INTEGER;
v_fire_date DATE;
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
    плановое_количество INTO v_status,
    v_assigned_worker,
    v_planned_qty
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
IF v_assigned_worker IS NOT NULL
AND v_assigned_worker != p_worker_id THEN status := 'ERROR';
message := 'Задача уже занята другим сотрудником';
RETURN NEXT;
RETURN;
END IF;
UPDATE ПланЗаготовок
SET id_сотрудника = p_worker_id,
    статус = 'в_работе'
WHERE id_заготовки = p_component_id
    AND id_заказа = p_order_id;
status := 'OK';
message := 'Задача взята в работу.';
RETURN NEXT;
END;
$$;


ALTER FUNCTION public.sp_take_component_task(p_component_id integer, p_order_id integer, p_worker_id integer) OWNER TO postgres;

--
-- Name: sp_update_client(integer, character varying, character varying, character varying, text); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_update_client(p_id integer, p_fio character varying, p_phone character varying, p_inn character varying, p_address text) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN
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


ALTER FUNCTION public.sp_update_client(p_id integer, p_fio character varying, p_phone character varying, p_inn character varying, p_address text) OWNER TO postgres;

--
-- Name: sp_update_component(integer, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_update_component(p_id integer, p_name character varying) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN
UPDATE Заготовка
SET наименование = p_name
WHERE id_заготовки = p_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Заготовка обновлена'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;


ALTER FUNCTION public.sp_update_component(p_id integer, p_name character varying) OWNER TO postgres;

--
-- Name: sp_update_component_material(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_update_component_material(p_comp_id integer, p_mat_id integer, p_qty integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN
UPDATE РасходМатериалов
SET количество_материала = p_qty
WHERE id_заготовки = p_comp_id
    AND id_материала = p_mat_id;
RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Количество обновлено'::VARCHAR;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;


ALTER FUNCTION public.sp_update_component_material(p_comp_id integer, p_mat_id integer, p_qty integer) OWNER TO postgres;

--
-- Name: sp_update_order_status(integer, character varying); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_update_order_status(p_order_id integer, p_new_status character varying) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$
DECLARE v_current_status VARCHAR;
v_pending_tasks INTEGER;
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
IF p_new_status = 'завершен' THEN
SELECT COUNT(*) INTO v_pending_tasks
FROM "ПланЗаготовок"
WHERE id_заказа = p_order_id
    AND статус != 'выполнено';
IF v_pending_tasks > 0 THEN status := 'ERROR';
message := 'Нельзя отметить готовым: есть незавершенные задачи (' || v_pending_tasks || ')';
RETURN NEXT;
RETURN;
END IF;
END IF;
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
UPDATE Заказ
SET статус = p_new_status
WHERE id_заказа = p_order_id;
status := 'OK';
message := 'Статус обновлен';
RETURN NEXT;
END;
$$;


ALTER FUNCTION public.sp_update_order_status(p_order_id integer, p_new_status character varying) OWNER TO postgres;

--
-- Name: sp_update_product(integer, character varying, numeric); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_update_product(p_id integer, p_name character varying, p_price numeric) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN
UPDATE Изделие
SET наименование = p_name,
    стоимость = p_price
WHERE id_изделия = p_id;
IF FOUND THEN RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Изделие обновлено'::VARCHAR;
ELSE RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    'Изделие не найдено'::VARCHAR;
END IF;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;


ALTER FUNCTION public.sp_update_product(p_id integer, p_name character varying, p_price numeric) OWNER TO postgres;

--
-- Name: sp_update_product_component(integer, integer, integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.sp_update_product_component(p_prod_id integer, p_comp_id integer, p_qty integer) RETURNS TABLE(status character varying, message character varying)
    LANGUAGE plpgsql
    AS $$ BEGIN
UPDATE СоставИзделия
SET количество_заготовки = p_qty
WHERE id_изделия = p_prod_id
    AND id_заготовки = p_comp_id;
IF NOT FOUND THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    'Заготовка не найдена в составе'::VARCHAR;
ELSE RETURN QUERY
SELECT 'OK'::VARCHAR,
    'Количество обновлено'::VARCHAR;
END IF;
EXCEPTION
WHEN OTHERS THEN RETURN QUERY
SELECT 'ERROR'::VARCHAR,
    SQLERRM::VARCHAR;
END;
$$;


ALTER FUNCTION public.sp_update_product_component(p_prod_id integer, p_comp_id integer, p_qty integer) OWNER TO postgres;

--
-- Name: sp_взять_задачу_в_работу(integer, integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public."sp_взять_задачу_в_работу"(IN "p_id_заготовки" integer, IN "p_id_заказа" integer, IN "p_id_сборщика" integer)
    LANGUAGE plpgsql
    AS $$
DECLARE v_status VARCHAR;
v_current_worker INTEGER;
BEGIN
SELECT статус,
    id_сотрудника INTO v_status,
    v_current_worker
FROM план_заготовок
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN RAISE EXCEPTION 'Задача не найдена';
END IF;
IF v_status NOT IN ('принято', 'просрочено') THEN RAISE EXCEPTION 'Задача уже в работе или завершена (статус: %)',
v_status;
END IF;
IF v_current_worker IS NOT NULL
AND v_current_worker != p_id_сборщика THEN RAISE EXCEPTION 'Задача уже назначена другому сборщику';
END IF;
UPDATE план_заготовок
SET id_сотрудника = p_id_сборщика
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
END;
$$;


ALTER PROCEDURE public."sp_взять_задачу_в_работу"(IN "p_id_заготовки" integer, IN "p_id_заказа" integer, IN "p_id_сборщика" integer) OWNER TO postgres;

--
-- Name: sp_закрыть_заказ(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public."sp_закрыть_заказ"(IN "p_id_заказа" integer)
    LANGUAGE plpgsql
    AS $$
DECLARE v_status VARCHAR;
BEGIN
SELECT статус INTO v_status
FROM Заказ
WHERE id_заказа = p_id_заказа;
IF v_status != 'отгружен' THEN RAISE EXCEPTION 'ОШИБКА: Можно закрыть только отгруженный заказ! Текущий статус: %',
v_status;
END IF;
UPDATE Заказ
SET статус = 'завершен'
WHERE id_заказа = p_id_заказа;
END;
$$;


ALTER PROCEDURE public."sp_закрыть_заказ"(IN "p_id_заказа" integer) OWNER TO postgres;

--
-- Name: sp_отгрузить_заказ(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public."sp_отгрузить_заказ"(IN "p_id_заказа" integer)
    LANGUAGE plpgsql
    AS $$
DECLARE v_status VARCHAR;
BEGIN
SELECT статус INTO v_status
FROM Заказ
WHERE id_заказа = p_id_заказа;
IF v_status != 'завершен' THEN RAISE EXCEPTION 'ОШИБКА: Можно отгрузить только завершённый заказ! Текущий статус: %',
v_status;
END IF;
UPDATE Заказ
SET статус = 'отгружен'
WHERE id_заказа = p_id_заказа;
END;
$$;


ALTER PROCEDURE public."sp_отгрузить_заказ"(IN "p_id_заказа" integer) OWNER TO postgres;

--
-- Name: sp_подтвердить_закупку(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public."sp_подтвердить_закупку"(IN "p_id_закупки" integer)
    LANGUAGE plpgsql
    AS $$
DECLARE
    rec RECORD;
    curr_status VARCHAR;
BEGIN
    SELECT статус INTO curr_status FROM закупки_материалов WHERE id_закупки = p_id_закупки;
    
    IF curr_status = 'выполнено' THEN
        RAISE EXCEPTION 'Закупка уже выполнена!';
    END IF;

    -- Обновляем статус
    UPDATE закупки_материалов SET статус = 'выполнено' WHERE id_закупки = p_id_закупки;

    -- Увеличиваем остатки на складе
    FOR rec IN SELECT id_материала, количество FROM состав_закупки WHERE id_закупки = p_id_закупки
    LOOP
        UPDATE материалы 
        SET количество_на_складе = количество_на_складе + rec.количество
        WHERE id_материала = rec.id_материала;
    END LOOP;
END;
$$;


ALTER PROCEDURE public."sp_подтвердить_закупку"(IN "p_id_закупки" integer) OWNER TO postgres;

--
-- Name: sp_подтвердить_отгрузку(integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public."sp_подтвердить_отгрузку"(IN "p_id_заказа" integer)
    LANGUAGE plpgsql
    AS $$
BEGIN
    -- Здесь можно добавить проверку оплаты и т.д.
    UPDATE заказы SET статус = 'выполнен' WHERE id_заказа = p_id_заказа;
END;
$$;


ALTER PROCEDURE public."sp_подтвердить_отгрузку"(IN "p_id_заказа" integer) OWNER TO postgres;

--
-- Name: sp_сдать_работу(integer, integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public."sp_сдать_работу"(IN "p_id_заготовки" integer, IN "p_id_заказа" integer, IN "p_количество" integer)
    LANGUAGE plpgsql
    AS $$
DECLARE v_status VARCHAR;
v_planned INTEGER;
v_actual INTEGER;
v_missing_material_name VARCHAR;
BEGIN
SELECT статус,
    плановое_количество,
    фактическое_количество INTO v_status,
    v_planned,
    v_actual
FROM план_заготовок
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
IF NOT FOUND THEN RAISE EXCEPTION 'Задача не найдена';
END IF;
IF v_status = 'выполнено' THEN RAISE EXCEPTION 'Задача уже выполнена';
END IF;
IF v_status = 'отменено' THEN RAISE EXCEPTION 'Задача отменена';
END IF;
-- STRICT MATERIAL CHECK
-- Check if any material is insufficient
SELECT m.наименование INTO v_missing_material_name
FROM состав_заготовки sz
    JOIN материалы m ON sz.id_материала = m.id_материала
WHERE sz.id_заготовки = p_id_заготовки
    AND m.количество_на_складе < (sz.количество_материала * p_количество)
LIMIT 1;
IF v_missing_material_name IS NOT NULL THEN RAISE EXCEPTION 'НЕОБХОДИМА ЗАКУПКА: Недостаточно материала "%" для изготовления заготовки',
v_missing_material_name;
END IF;
-- Deduct materials (safe to use simple subtraction now)
UPDATE материалы m
SET количество_на_складе = количество_на_складе - (sz.количество_материала * p_количество)
FROM состав_заготовки sz
WHERE sz.id_заготовки = p_id_заготовки
    AND m.id_материала = sz.id_материала;
-- Update plan
UPDATE план_заготовок
SET фактическое_количество = фактическое_количество + p_количество,
    дата_факт = CURRENT_DATE
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
-- Update zagotovki stock
UPDATE заготовки
SET количество_готовых = количество_готовых + p_количество
WHERE id_заготовки = p_id_заготовки;
-- Check completion
IF (v_actual + p_количество) >= v_planned THEN
UPDATE план_заготовок
SET статус = 'выполнено'
WHERE id_заготовки = p_id_заготовки
    AND id_заказа = p_id_заказа;
END IF;
END;
$$;


ALTER PROCEDURE public."sp_сдать_работу"(IN "p_id_заготовки" integer, IN "p_id_заказа" integer, IN "p_количество" integer) OWNER TO postgres;

--
-- Name: sp_сдать_сборку(integer, integer, integer); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public."sp_сдать_сборку"(IN "p_id_изделия" integer, IN "p_id_заказа" integer, IN "p_количество" integer)
    LANGUAGE plpgsql
    AS $$
DECLARE v_status VARCHAR;
v_planned INTEGER;
v_actual INTEGER;
v_missing_component_name VARCHAR;
BEGIN -- Get current assembly task state
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
SELECT z.наименование INTO v_missing_component_name
FROM состав_изделия si
    JOIN заготовки z ON si.id_заготовки = z.id_заготовки
WHERE si.id_изделия = p_id_изделия
    AND z.количество_готовых < (si.количество_заготовки * p_количество)
LIMIT 1;
IF v_missing_component_name IS NOT NULL THEN RAISE EXCEPTION 'Недостаточно заготовок "%" для сборки изделия!',
v_missing_component_name;
END IF;
-- Deduct components from warehouse
UPDATE заготовки z
SET количество_готовых = количество_готовых - (si.количество_заготовки * p_количество)
FROM состав_изделия si
WHERE si.id_изделия = p_id_изделия
    AND z.id_заготовки = si.id_заготовки;
-- Update assembly plan
UPDATE план_сборки
SET фактическое_количество = фактическое_количество + p_количество,
    дата_факт = CURRENT_DATE
WHERE id_изделия = p_id_изделия
    AND id_заказа = p_id_заказа;
-- Update PRODUCT Stock (add assembled products to warehouse)
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


ALTER PROCEDURE public."sp_сдать_сборку"(IN "p_id_изделия" integer, IN "p_id_заказа" integer, IN "p_количество" integer) OWNER TO postgres;

--
-- Name: sp_установить_статус_дня(integer, date, character varying); Type: PROCEDURE; Schema: public; Owner: postgres
--

CREATE PROCEDURE public."sp_установить_статус_дня"(IN "p_id_сотрудника" integer, IN "p_дата" date, IN "p_статус" character varying)
    LANGUAGE plpgsql
    AS $$
BEGIN
    INSERT INTO график_работы (id_сотрудника, дата, статус)
    VALUES (p_id_сотрудника, p_дата, p_статус)
    ON CONFLICT (id_сотрудника, дата) 
    DO UPDATE SET статус = p_статус;
END;
$$;


ALTER PROCEDURE public."sp_установить_статус_дня"(IN "p_id_сотрудника" integer, IN "p_дата" date, IN "p_статус" character varying) OWNER TO postgres;

--
-- Name: trg_check_age_func(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_check_age_func() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (EXTRACT(YEAR FROM age(NEW.дата_рождения)) < 18) THEN
        RAISE EXCEPTION 'Сотрудник должен быть совершеннолетним!';
    END IF;
    RETURN NEW;
END;
$$;


ALTER FUNCTION public.trg_check_age_func() OWNER TO postgres;

--
-- Name: trg_update_order_sum_func(); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.trg_update_order_sum_func() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
    IF (TG_OP = 'DELETE') THEN
        UPDATE заказы SET сумма_заказа = (
            SELECT COALESCE(SUM(cantidad_izd * price_fix), 0)
            FROM (SELECT количество_изделий as cantidad_izd, цена_фиксированная as price_fix FROM состав_заказа WHERE id_заказа = OLD.id_заказа) as sub
        ) WHERE id_заказа = OLD.id_заказа;
        RETURN OLD;
    ELSE
        UPDATE заказы SET сумма_заказа = (
            SELECT COALESCE(SUM(количество_изделий * цена_фиксированная), 0)
            FROM состав_заказа WHERE id_заказа = NEW.id_заказа
        ) WHERE id_заказа = NEW.id_заказа;
        RETURN NEW;
    END IF;
END;
$$;


ALTER FUNCTION public.trg_update_order_sum_func() OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: debuglog; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.debuglog (
    id integer CONSTRAINT debug_log_id_not_null NOT NULL,
    msg text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.debuglog OWNER TO postgres;

--
-- Name: debug_log_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.debug_log_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.debug_log_id_seq OWNER TO postgres;

--
-- Name: debug_log_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.debug_log_id_seq OWNED BY public.debuglog.id;


--
-- Name: График; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."График" (
    "id_графика" integer CONSTRAINT "график_работы_id_графика_not_null" NOT NULL,
    "id_сотрудника" integer,
    "дата" date CONSTRAINT "график_работы_дата_not_null" NOT NULL,
    "статус" character varying(20),
    CONSTRAINT "график_работы_статус_check" CHECK ((("статус")::text = ANY ((ARRAY['рабочий'::character varying, 'выходной'::character varying, 'отпуск'::character varying, 'больничный'::character varying])::text[])))
);


ALTER TABLE public."График" OWNER TO postgres;

--
-- Name: Заготовка; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Заготовка" (
    "id_заготовки" integer CONSTRAINT "заготовки_id_заготовки_not_null" NOT NULL,
    "наименование" character varying(100) CONSTRAINT "заготовки_наименование_not_null" NOT NULL,
    "количество_готовых" integer DEFAULT 0,
    "описание" text,
    CONSTRAINT "заготовки_количество_готовых_check" CHECK (("количество_готовых" >= 0))
);


ALTER TABLE public."Заготовка" OWNER TO postgres;

--
-- Name: Заказ; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Заказ" (
    "id_заказа" integer CONSTRAINT "заказы_id_заказа_not_null" NOT NULL,
    "id_клиента" integer,
    "id_менеджера" integer,
    "дата_заказа" date DEFAULT CURRENT_DATE,
    "дата_готовности" date,
    "статус" character varying(20) DEFAULT 'принят'::character varying,
    "сумма_заказа" numeric(12,2) DEFAULT 0,
    "примечания" text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT "заказы_статус_check" CHECK ((("статус")::text = ANY ((ARRAY['принят'::character varying, 'в_обработке'::character varying, 'в_работе'::character varying, 'выполнен'::character varying, 'отменен'::character varying, 'отгружен'::character varying, 'завершен'::character varying])::text[])))
);


ALTER TABLE public."Заказ" OWNER TO postgres;

--
-- Name: Закупка; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Закупка" (
    "id_закупки" integer CONSTRAINT "закупки_материалов_id_закупки_not_null" NOT NULL,
    "дата_закупки" date DEFAULT CURRENT_DATE,
    "поставщик" character varying(100),
    "статус" character varying(30) DEFAULT 'ожидает_подтверждения'::character varying
);


ALTER TABLE public."Закупка" OWNER TO postgres;

--
-- Name: Изделие; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Изделие" (
    "id_изделия" integer CONSTRAINT "изделия_id_изделия_not_null" NOT NULL,
    "наименование" character varying(100) CONSTRAINT "изделия_наименование_not_null" NOT NULL,
    "тип" character varying(50),
    "размеры" character varying(50),
    "стоимость" numeric(10,2),
    "количество_на_складе" integer DEFAULT 0,
    CONSTRAINT "изделия_количество_на_складе_check" CHECK (("количество_на_складе" >= 0)),
    CONSTRAINT "изделия_стоимость_check" CHECK (("стоимость" >= (0)::numeric))
);


ALTER TABLE public."Изделие" OWNER TO postgres;

--
-- Name: Клиент; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Клиент" (
    "id_клиента" integer CONSTRAINT "клиенты_id_клиента_not_null" NOT NULL,
    "фио" character varying(100) CONSTRAINT "клиенты_фио_not_null" NOT NULL,
    "инн" character varying(12),
    "номер_телефона" character varying(20) CONSTRAINT "клиенты_номер_телефона_not_null" NOT NULL,
    "адрес" text,
    "дата_регистрации" date DEFAULT CURRENT_DATE
);


ALTER TABLE public."Клиент" OWNER TO postgres;

--
-- Name: Материал; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Материал" (
    "id_материала" integer CONSTRAINT "материалы_id_материала_not_null" NOT NULL,
    "наименование" character varying(100) CONSTRAINT "материалы_наименование_not_null" NOT NULL,
    "количество_на_складе" integer DEFAULT 0,
    "единица_измерения" character varying(10) DEFAULT 'шт'::character varying,
    "минимальный_остаток" integer DEFAULT 10,
    "цена_за_единицу" numeric(10,2),
    CONSTRAINT "материалы_количество_на_складе_check" CHECK (("количество_на_складе" >= 0)),
    CONSTRAINT "материалы_цена_за_единицу_check" CHECK (("цена_за_единицу" >= (0)::numeric))
);


ALTER TABLE public."Материал" OWNER TO postgres;

--
-- Name: ПланЗаготовок; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."ПланЗаготовок" (
    "id_заготовки" integer CONSTRAINT "план_заготовок_id_заготовки_not_null" NOT NULL,
    "id_сотрудника" integer,
    "id_заказа" integer CONSTRAINT "план_заготовок_id_заказа_not_null" NOT NULL,
    "плановое_количество" integer CONSTRAINT "план_заготовок_плановое_коли_not_null" NOT NULL,
    "фактическое_количество" integer DEFAULT 0 CONSTRAINT "план_заготовок_фактическое_к_not_null" NOT NULL,
    "дата_план" date CONSTRAINT "план_заготовок_дата_план_not_null" NOT NULL,
    "дата_факт" date,
    "статус" character varying(15) DEFAULT 'принято'::character varying CONSTRAINT "план_заготовок_статус_not_null" NOT NULL,
    CONSTRAINT "план_заготовок_статус_check" CHECK ((("статус")::text = ANY ((ARRAY['ожидает'::character varying, 'принято'::character varying, 'назначено'::character varying, 'в_работе'::character varying, 'завершен'::character varying, 'отменено'::character varying, 'брак'::character varying, 'выполнено'::character varying])::text[])))
);


ALTER TABLE public."ПланЗаготовок" OWNER TO postgres;

--
-- Name: РасходМатериалов; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."РасходМатериалов" (
    "id_заготовки" integer CONSTRAINT "расход_материало_id_заготовки_not_null" NOT NULL,
    "id_материала" integer CONSTRAINT "расход_материало_id_материала_not_null" NOT NULL,
    "количество_материала" integer CONSTRAINT "расход_материа_количество_ма_not_null" NOT NULL,
    CONSTRAINT "расход_материа_количество_мат_check" CHECK (("количество_материала" > 0))
);


ALTER TABLE public."РасходМатериалов" OWNER TO postgres;

--
-- Name: СоставЗаготовки; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."СоставЗаготовки" (
    "id_заготовки" integer CONSTRAINT "состав_заготовки_id_заготовки_not_null" NOT NULL,
    "id_материала" integer CONSTRAINT "состав_заготовки_id_материала_not_null" NOT NULL,
    "количество_материала" integer DEFAULT 1 CONSTRAINT "состав_заготов_количество_ма_not_null" NOT NULL
);


ALTER TABLE public."СоставЗаготовки" OWNER TO postgres;

--
-- Name: СоставЗаказа; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."СоставЗаказа" (
    "id_заказа" integer CONSTRAINT "состав_заказа_id_заказа_not_null" NOT NULL,
    "id_изделия" integer CONSTRAINT "состав_заказа_id_изделия_not_null" NOT NULL,
    "цена_фиксированная" numeric(10,2) CONSTRAINT "состав_заказа_цена_фиксирова_not_null" NOT NULL,
    "количество_изделий" integer CONSTRAINT "состав_заказа_количество_изд_not_null" NOT NULL,
    CONSTRAINT "состав_заказа_количество_издел_check" CHECK (("количество_изделий" > 0))
);


ALTER TABLE public."СоставЗаказа" OWNER TO postgres;

--
-- Name: СоставЗакупки; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."СоставЗакупки" (
    "id_закупки" integer CONSTRAINT "состав_закупки_id_закупки_not_null" NOT NULL,
    "id_материала" integer CONSTRAINT "состав_закупки_id_материала_not_null" NOT NULL,
    "количество" integer CONSTRAINT "состав_закупки_количество_not_null" NOT NULL,
    "цена_закупки" numeric(10,2),
    CONSTRAINT "состав_закупки_количество_check" CHECK (("количество" > 0))
);


ALTER TABLE public."СоставЗакупки" OWNER TO postgres;

--
-- Name: СоставИзделия; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."СоставИзделия" (
    "id_изделия" integer CONSTRAINT "состав_изделия_id_изделия_not_null" NOT NULL,
    "id_заготовки" integer CONSTRAINT "состав_изделия_id_заготовки_not_null" NOT NULL,
    "количество_заготовки" integer CONSTRAINT "состав_изделия_количество_за_not_null" NOT NULL,
    "количество_заготовок" integer DEFAULT 1,
    CONSTRAINT "состав_изделия_количество_заг_check1" CHECK (("количество_заготовок" > 0)),
    CONSTRAINT "состав_изделия_количество_заго_check" CHECK (("количество_заготовки" > 0))
);


ALTER TABLE public."СоставИзделия" OWNER TO postgres;

--
-- Name: Сотрудник; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public."Сотрудник" (
    "id_сотрудника" integer CONSTRAINT "сотрудники_id_сотрудника_not_null" NOT NULL,
    "фио" character varying(100) CONSTRAINT "сотрудники_фио_not_null" NOT NULL,
    "номер_телефона" character varying(20) CONSTRAINT "сотрудники_номер_телефона_not_null" NOT NULL,
    "дата_рождения" date,
    "должность" character varying(50),
    "зарплата" numeric(10,2),
    "дата_найма" date DEFAULT CURRENT_DATE,
    "дата_увольнения" date,
    login character varying(50) CONSTRAINT "сотрудники_login_not_null" NOT NULL,
    password_hash character varying(255) CONSTRAINT "сотрудники_password_hash_not_null" NOT NULL,
    CONSTRAINT "сотрудники_дата_рождения_check" CHECK (("дата_рождения" <= (CURRENT_DATE - '18 years'::interval))),
    CONSTRAINT "сотрудники_должность_check" CHECK ((("должность")::text = ANY ((ARRAY['сборщик'::character varying, 'менеджер'::character varying, 'директор'::character varying])::text[]))),
    CONSTRAINT "сотрудники_зарплата_check" CHECK (("зарплата" > (0)::numeric))
);


ALTER TABLE public."Сотрудник" OWNER TO postgres;

--
-- Name: график_работы_id_графика_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."график_работы_id_графика_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."график_работы_id_графика_seq" OWNER TO postgres;

--
-- Name: график_работы_id_графика_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."график_работы_id_графика_seq" OWNED BY public."График"."id_графика";


--
-- Name: заготовки_id_заготовки_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."заготовки_id_заготовки_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."заготовки_id_заготовки_seq" OWNER TO postgres;

--
-- Name: заготовки_id_заготовки_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."заготовки_id_заготовки_seq" OWNED BY public."Заготовка"."id_заготовки";


--
-- Name: заказы_id_заказа_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."заказы_id_заказа_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."заказы_id_заказа_seq" OWNER TO postgres;

--
-- Name: заказы_id_заказа_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."заказы_id_заказа_seq" OWNED BY public."Заказ"."id_заказа";


--
-- Name: закупки_материалов_id_закупки_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."закупки_материалов_id_закупки_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."закупки_материалов_id_закупки_seq" OWNER TO postgres;

--
-- Name: закупки_материалов_id_закупки_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."закупки_материалов_id_закупки_seq" OWNED BY public."Закупка"."id_закупки";


--
-- Name: изделия_id_изделия_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."изделия_id_изделия_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."изделия_id_изделия_seq" OWNER TO postgres;

--
-- Name: изделия_id_изделия_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."изделия_id_изделия_seq" OWNED BY public."Изделие"."id_изделия";


--
-- Name: клиенты_id_клиента_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."клиенты_id_клиента_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."клиенты_id_клиента_seq" OWNER TO postgres;

--
-- Name: клиенты_id_клиента_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."клиенты_id_клиента_seq" OWNED BY public."Клиент"."id_клиента";


--
-- Name: материалы_id_материала_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."материалы_id_материала_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."материалы_id_материала_seq" OWNER TO postgres;

--
-- Name: материалы_id_материала_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."материалы_id_материала_seq" OWNED BY public."Материал"."id_материала";


--
-- Name: сотрудники_id_сотрудника_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public."сотрудники_id_сотрудника_seq"
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public."сотрудники_id_сотрудника_seq" OWNER TO postgres;

--
-- Name: сотрудники_id_сотрудника_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public."сотрудники_id_сотрудника_seq" OWNED BY public."Сотрудник"."id_сотрудника";


--
-- Name: debuglog id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.debuglog ALTER COLUMN id SET DEFAULT nextval('public.debug_log_id_seq'::regclass);


--
-- Name: График id_графика; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."График" ALTER COLUMN "id_графика" SET DEFAULT nextval('public."график_работы_id_графика_seq"'::regclass);


--
-- Name: Заготовка id_заготовки; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Заготовка" ALTER COLUMN "id_заготовки" SET DEFAULT nextval('public."заготовки_id_заготовки_seq"'::regclass);


--
-- Name: Заказ id_заказа; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Заказ" ALTER COLUMN "id_заказа" SET DEFAULT nextval('public."заказы_id_заказа_seq"'::regclass);


--
-- Name: Закупка id_закупки; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Закупка" ALTER COLUMN "id_закупки" SET DEFAULT nextval('public."закупки_материалов_id_закупки_seq"'::regclass);


--
-- Name: Изделие id_изделия; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Изделие" ALTER COLUMN "id_изделия" SET DEFAULT nextval('public."изделия_id_изделия_seq"'::regclass);


--
-- Name: Клиент id_клиента; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Клиент" ALTER COLUMN "id_клиента" SET DEFAULT nextval('public."клиенты_id_клиента_seq"'::regclass);


--
-- Name: Материал id_материала; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Материал" ALTER COLUMN "id_материала" SET DEFAULT nextval('public."материалы_id_материала_seq"'::regclass);


--
-- Name: Сотрудник id_сотрудника; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Сотрудник" ALTER COLUMN "id_сотрудника" SET DEFAULT nextval('public."сотрудники_id_сотрудника_seq"'::regclass);


--
-- Name: debuglog debug_log_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.debuglog
    ADD CONSTRAINT debug_log_pkey PRIMARY KEY (id);


--
-- Name: График график_работы_id_сотрудника_дата_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."График"
    ADD CONSTRAINT "график_работы_id_сотрудника_дата_key" UNIQUE ("id_сотрудника", "дата");


--
-- Name: График график_работы_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."График"
    ADD CONSTRAINT "график_работы_pkey" PRIMARY KEY ("id_графика");


--
-- Name: Заготовка заготовки_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Заготовка"
    ADD CONSTRAINT "заготовки_pkey" PRIMARY KEY ("id_заготовки");


--
-- Name: Заказ заказы_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Заказ"
    ADD CONSTRAINT "заказы_pkey" PRIMARY KEY ("id_заказа");


--
-- Name: Закупка закупки_материалов_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Закупка"
    ADD CONSTRAINT "закупки_материалов_pkey" PRIMARY KEY ("id_закупки");


--
-- Name: Изделие изделия_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Изделие"
    ADD CONSTRAINT "изделия_pkey" PRIMARY KEY ("id_изделия");


--
-- Name: Клиент клиенты_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Клиент"
    ADD CONSTRAINT "клиенты_pkey" PRIMARY KEY ("id_клиента");


--
-- Name: Материал материалы_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Материал"
    ADD CONSTRAINT "материалы_pkey" PRIMARY KEY ("id_материала");


--
-- Name: ПланЗаготовок план_заготовок_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."ПланЗаготовок"
    ADD CONSTRAINT "план_заготовок_pkey" PRIMARY KEY ("id_заготовки", "id_заказа");


--
-- Name: РасходМатериалов расход_материалов_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."РасходМатериалов"
    ADD CONSTRAINT "расход_материалов_pkey" PRIMARY KEY ("id_заготовки", "id_материала");


--
-- Name: СоставЗаготовки состав_заготовки_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."СоставЗаготовки"
    ADD CONSTRAINT "состав_заготовки_pkey" PRIMARY KEY ("id_заготовки", "id_материала");


--
-- Name: СоставЗаказа состав_заказа_order_product_unique; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."СоставЗаказа"
    ADD CONSTRAINT "состав_заказа_order_product_unique" UNIQUE ("id_заказа", "id_изделия");


--
-- Name: СоставЗаказа состав_заказа_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."СоставЗаказа"
    ADD CONSTRAINT "состав_заказа_pkey" PRIMARY KEY ("id_заказа", "id_изделия");


--
-- Name: СоставЗакупки состав_закупки_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."СоставЗакупки"
    ADD CONSTRAINT "состав_закупки_pkey" PRIMARY KEY ("id_закупки", "id_материала");


--
-- Name: СоставИзделия состав_изделия_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."СоставИзделия"
    ADD CONSTRAINT "состав_изделия_pkey" PRIMARY KEY ("id_изделия", "id_заготовки");


--
-- Name: Сотрудник сотрудники_login_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Сотрудник"
    ADD CONSTRAINT "сотрудники_login_key" UNIQUE (login);


--
-- Name: Сотрудник сотрудники_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Сотрудник"
    ADD CONSTRAINT "сотрудники_pkey" PRIMARY KEY ("id_сотрудника");


--
-- Name: Сотрудник сотрудники_номер_телефона_key; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Сотрудник"
    ADD CONSTRAINT "сотрудники_номер_телефона_key" UNIQUE ("номер_телефона");


--
-- Name: ПланЗаготовок tr_check_order_ready; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER tr_check_order_ready AFTER UPDATE OF "статус" ON public."ПланЗаготовок" FOR EACH ROW WHEN (((new."статус")::text = 'выполнено'::text)) EXECUTE FUNCTION public.sp_check_order_ready();


--
-- Name: СоставЗаказа tr_order_sum_update; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER tr_order_sum_update AFTER INSERT OR DELETE OR UPDATE ON public."СоставЗаказа" FOR EACH ROW EXECUTE FUNCTION public.sp_calculate_order_sum();


--
-- Name: Сотрудник trg_check_age; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_check_age BEFORE INSERT OR UPDATE ON public."Сотрудник" FOR EACH ROW EXECUTE FUNCTION public.trg_check_age_func();


--
-- Name: ПланЗаготовок trg_order_completion; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_order_completion AFTER UPDATE ON public."ПланЗаготовок" FOR EACH ROW EXECUTE FUNCTION public.fn_check_order_completion();


--
-- Name: ПланЗаготовок trg_task_date_fact; Type: TRIGGER; Schema: public; Owner: postgres
--

CREATE TRIGGER trg_task_date_fact BEFORE UPDATE ON public."ПланЗаготовок" FOR EACH ROW EXECUTE FUNCTION public.fn_update_task_date_fact();


--
-- Name: График график_работы_id_сотрудника_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."График"
    ADD CONSTRAINT "график_работы_id_сотрудника_fkey" FOREIGN KEY ("id_сотрудника") REFERENCES public."Сотрудник"("id_сотрудника") ON DELETE CASCADE;


--
-- Name: Заказ заказы_id_клиента_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Заказ"
    ADD CONSTRAINT "заказы_id_клиента_fkey" FOREIGN KEY ("id_клиента") REFERENCES public."Клиент"("id_клиента") ON DELETE RESTRICT;


--
-- Name: Заказ заказы_id_менеджера_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."Заказ"
    ADD CONSTRAINT "заказы_id_менеджера_fkey" FOREIGN KEY ("id_менеджера") REFERENCES public."Сотрудник"("id_сотрудника") ON DELETE SET NULL;


--
-- Name: ПланЗаготовок план_заготовок_id_заготовки_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."ПланЗаготовок"
    ADD CONSTRAINT "план_заготовок_id_заготовки_fkey" FOREIGN KEY ("id_заготовки") REFERENCES public."Заготовка"("id_заготовки");


--
-- Name: ПланЗаготовок план_заготовок_id_заказа_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."ПланЗаготовок"
    ADD CONSTRAINT "план_заготовок_id_заказа_fkey" FOREIGN KEY ("id_заказа") REFERENCES public."Заказ"("id_заказа") ON DELETE CASCADE;


--
-- Name: ПланЗаготовок план_заготовок_id_сотрудника_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."ПланЗаготовок"
    ADD CONSTRAINT "план_заготовок_id_сотрудника_fkey" FOREIGN KEY ("id_сотрудника") REFERENCES public."Сотрудник"("id_сотрудника");


--
-- Name: РасходМатериалов расход_материалов_id_заготовки_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."РасходМатериалов"
    ADD CONSTRAINT "расход_материалов_id_заготовки_fkey" FOREIGN KEY ("id_заготовки") REFERENCES public."Заготовка"("id_заготовки") ON DELETE CASCADE;


--
-- Name: РасходМатериалов расход_материалов_id_материала_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."РасходМатериалов"
    ADD CONSTRAINT "расход_материалов_id_материала_fkey" FOREIGN KEY ("id_материала") REFERENCES public."Материал"("id_материала") ON DELETE RESTRICT;


--
-- Name: СоставЗаготовки состав_заготовки_id_заготовки_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."СоставЗаготовки"
    ADD CONSTRAINT "состав_заготовки_id_заготовки_fkey" FOREIGN KEY ("id_заготовки") REFERENCES public."Заготовка"("id_заготовки") ON DELETE CASCADE;


--
-- Name: СоставЗаготовки состав_заготовки_id_материала_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."СоставЗаготовки"
    ADD CONSTRAINT "состав_заготовки_id_материала_fkey" FOREIGN KEY ("id_материала") REFERENCES public."Материал"("id_материала") ON DELETE CASCADE;


--
-- Name: СоставЗаказа состав_заказа_id_заказа_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."СоставЗаказа"
    ADD CONSTRAINT "состав_заказа_id_заказа_fkey" FOREIGN KEY ("id_заказа") REFERENCES public."Заказ"("id_заказа") ON DELETE CASCADE;


--
-- Name: СоставЗаказа состав_заказа_id_изделия_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."СоставЗаказа"
    ADD CONSTRAINT "состав_заказа_id_изделия_fkey" FOREIGN KEY ("id_изделия") REFERENCES public."Изделие"("id_изделия") ON DELETE RESTRICT;


--
-- Name: СоставЗакупки состав_закупки_id_закупки_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."СоставЗакупки"
    ADD CONSTRAINT "состав_закупки_id_закупки_fkey" FOREIGN KEY ("id_закупки") REFERENCES public."Закупка"("id_закупки") ON DELETE CASCADE;


--
-- Name: СоставЗакупки состав_закупки_id_материала_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."СоставЗакупки"
    ADD CONSTRAINT "состав_закупки_id_материала_fkey" FOREIGN KEY ("id_материала") REFERENCES public."Материал"("id_материала") ON DELETE CASCADE;


--
-- Name: СоставИзделия состав_изделия_id_заготовки_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."СоставИзделия"
    ADD CONSTRAINT "состав_изделия_id_заготовки_fkey" FOREIGN KEY ("id_заготовки") REFERENCES public."Заготовка"("id_заготовки") ON DELETE RESTRICT;


--
-- Name: СоставИзделия состав_изделия_id_изделия_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public."СоставИзделия"
    ADD CONSTRAINT "состав_изделия_id_изделия_fkey" FOREIGN KEY ("id_изделия") REFERENCES public."Изделие"("id_изделия") ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict Qycxxdc9UyPxbbx4zgnUna2ALP29dTrDJ73oXcAeVYSq5bRlC7PfWL2b6QWoKqO

