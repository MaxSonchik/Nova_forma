CREATE OR REPLACE PROCEDURE sp_взять_задачу_в_работу(p_id_плана INTEGER, p_id_сборщика INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    rec RECORD;
    v_id_заготовки INTEGER;
    v_plan_qty INTEGER;
    v_status VARCHAR;
    v_mat_name VARCHAR; -- Переменная для названия
    v_required_qty INTEGER;
    v_stock_qty INTEGER;
BEGIN
    -- Получаем данные задачи
    SELECT id_заготовки, плановое_количество, статус INTO v_id_заготовки, v_plan_qty, v_status
    FROM план_заготовок WHERE id_плана = p_id_плана;

    IF v_status != 'принято' THEN
        RAISE EXCEPTION 'Задача уже в работе или выполнена/отменена';
    END IF;

    -- Проверяем наличие материалов
    FOR rec IN SELECT id_материала, количество_материала FROM расход_материалов WHERE id_заготовки = v_id_заготовки
    LOOP
        v_required_qty := rec.количество_материала * v_plan_qty;
        
        SELECT количество_на_складе, наименование INTO v_stock_qty, v_mat_name 
        FROM материалы WHERE id_материала = rec.id_материала;
        
        IF v_stock_qty < v_required_qty THEN
            -- ТЕПЕРЬ ВЫВОДИМ НАЗВАНИЕ
            RAISE EXCEPTION 'Недостаточно материала "%" (Нужно: %, Есть: %)', v_mat_name, v_required_qty, v_stock_qty;
        END IF;
    END LOOP;

    -- Списываем
    FOR rec IN SELECT id_материала, количество_материала FROM расход_материалов WHERE id_заготовки = v_id_заготовки
    LOOP
        UPDATE материалы 
        SET количество_на_складе = количество_на_складе - (rec.количество_материала * v_plan_qty)
        WHERE id_материала = rec.id_материала;
    END LOOP;

    UPDATE план_заготовок 
    SET статус = 'в_работе', id_сборщика = p_id_сборщика 
    WHERE id_плана = p_id_плана;
END;
$$;