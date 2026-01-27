ALTER TABLE изделия ADD COLUMN IF NOT EXISTS количество_на_складе INTEGER DEFAULT 0 CHECK (количество_на_складе >= 0);


CREATE OR REPLACE VIEW v_склад_общий AS
SELECT 'Материал' as тип, артикул_материала as артикул, наименование, количество_на_складе as количество, единица_измерения
FROM материалы
UNION ALL
SELECT 'Заготовка', артикул_заготовки, наименование, количество_готовых, 'шт'
FROM заготовки
UNION ALL
SELECT 'Изделие', артикул_изделия, наименование, количество_на_складе, 'шт'
FROM изделия;


CREATE OR REPLACE VIEW v_заказы_менеджер AS
SELECT 
    z.id_заказа,
    k.фио as клиент,
    s.фио as менеджер,
    z.дата_заказа,
    z.дата_готовности,
    z.статус,
    z.сумма_заказа,
    (SELECT COUNT(*) FROM состав_заказа sz WHERE sz.id_заказа = z.id_заказа) as позиций_в_заказе,
    CASE 
        WHEN z.статус = 'выполнен' THEN 'Готов к отгрузке'
        WHEN z.статус = 'отменен' THEN 'Отмена'
        WHEN z.дата_готовности < CURRENT_DATE AND z.статус != 'выполнен' THEN 'ПРОСРОЧЕН'
        ELSE 'В норме'
    END as состояние_сроков
FROM заказы z
JOIN клиенты k ON z.id_клиента = k.id_клиента
LEFT JOIN сотрудники s ON z.id_менеджера = s.id_сотрудника;


CREATE OR REPLACE VIEW v_задачи_сборщика AS
SELECT 
    pz.id_плана,
    z.наименование as заготовка,
    pz.плановое_количество,
    pz.фактическое_количество,
    pz.дата_план as дедлайн,
    pz.статус,
    pz.id_сборщика
FROM план_заготовок pz
JOIN заготовки z ON pz.id_заготовки = z.id_заготовки;


CREATE OR REPLACE VIEW v_отчет_директора AS
SELECT 
    'Выручка (заказы)' as показатель, 
    COALESCE(SUM(сумма_заказа), 0) as сумма 
FROM заказы WHERE статус = 'выполнен'
UNION ALL
SELECT 
    'Расходы (закупки)', 
    COALESCE(SUM(sz.количество * sz.цена_закупки), 0) 
FROM состав_закупки sz 
JOIN закупки_материалов zm ON sz.id_закупки = zm.id_закупки 
WHERE zm.статус = 'выполнено';







CREATE OR REPLACE FUNCTION trg_check_age_func() RETURNS TRIGGER AS $$
BEGIN
    IF (EXTRACT(YEAR FROM age(NEW.дата_рождения)) < 18) THEN
        RAISE EXCEPTION 'Сотрудник должен быть совершеннолетним!';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_age ON сотрудники;
CREATE TRIGGER trg_check_age
BEFORE INSERT OR UPDATE ON сотрудники
FOR EACH ROW EXECUTE FUNCTION trg_check_age_func();


CREATE OR REPLACE FUNCTION trg_update_order_sum_func() RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_calc_sum ON состав_заказа;
CREATE TRIGGER trg_calc_sum
AFTER INSERT OR UPDATE OR DELETE ON состав_заказа
FOR EACH ROW EXECUTE FUNCTION trg_update_order_sum_func();



CREATE OR REPLACE PROCEDURE sp_подтвердить_закупку(p_id_закупки INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    rec RECORD;
    curr_status VARCHAR;
BEGIN
    SELECT статус INTO curr_status FROM закупки_материалов WHERE id_закупки = p_id_закупки;
    
    IF curr_status = 'выполнено' THEN
        RAISE EXCEPTION 'Закупка уже выполнена!';
    END IF;


    UPDATE закупки_материалов SET статус = 'выполнено' WHERE id_закупки = p_id_закупки;


    FOR rec IN SELECT id_материала, количество FROM состав_закупки WHERE id_закупки = p_id_закупки
    LOOP
        UPDATE материалы 
        SET количество_на_складе = количество_на_складе + rec.количество
        WHERE id_материала = rec.id_материала;
    END LOOP;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_подтвердить_отгрузку(p_id_заказа INTEGER)
LANGUAGE plpgsql AS $$
BEGIN
    UPDATE заказы SET статус = 'выполнен' WHERE id_заказа = p_id_заказа;
END;
$$;


CREATE OR REPLACE PROCEDURE sp_взять_задачу_в_работу(p_id_плана INTEGER, p_id_сборщика INTEGER)
LANGUAGE plpgsql AS $$
DECLARE
    rec RECORD;
    v_id_заготовки INTEGER;
    v_plan_qty INTEGER;
    v_status VARCHAR;
BEGIN

    SELECT id_заготовки, плановое_количество, статус INTO v_id_заготовки, v_plan_qty, v_status
    FROM план_заготовок WHERE id_плана = p_id_плана;

    IF v_status != 'принято' THEN
        RAISE EXCEPTION 'Задача уже в работе или выполнена/отменена';
    END IF;


    FOR rec IN SELECT id_материала, количество_материала FROM расход_материалов WHERE id_заготовки = v_id_заготовки
    LOOP
        IF (SELECT количество_на_складе FROM материалы WHERE id_материала = rec.id_материала) < (rec.количество_материала * v_plan_qty) THEN
            RAISE EXCEPTION 'Недостаточно материала ID % на складе!', rec.id_материала;
        END IF;
    END LOOP;


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


CREATE OR REPLACE FUNCTION sp_добавить_изделие_в_заказ(
    p_id_заказа INTEGER, 
    p_id_изделия INTEGER, 
    p_количество INTEGER
) RETURNS VARCHAR LANGUAGE plpgsql AS $$
DECLARE
    v_stock INTEGER;
    v_price NUMERIC;
    v_missing INTEGER;
    rec RECORD;
    v_msg VARCHAR := '';
BEGIN

    SELECT стоимость, количество_на_складе INTO v_price, v_stock 
    FROM изделия WHERE id_изделия = p_id_изделия;
    

    INSERT INTO состав_заказа (id_заказа, id_изделия, количество_изделий, цена_фиксированная)
    VALUES (p_id_заказа, p_id_изделия, p_количество, v_price);

]
    IF v_stock >= p_количество THEN
        
        UPDATE изделия SET количество_на_складе = количество_на_складе - p_количество 
        WHERE id_изделия = p_id_изделия;
        RETURN 'OK: Изделия зарезервированы со склада.';
    ELSE
        v_missing := p_количество - v_stock;
        
        IF v_stock > 0 THEN
            UPDATE изделия SET количество_на_складе = 0 WHERE id_изделия = p_id_изделия;
        END IF;

        FOR rec IN SELECT id_заготовки, количество_заготовок 
                   FROM состав_изделия WHERE id_изделия = p_id_изделия
        LOOP
            INSERT INTO план_заготовок (id_заказа, id_заготовки, плановое_количество, дата_план, статус)
            VALUES (
                p_id_заказа, 
                rec.id_заготовки, 
                rec.количество_заготовок * v_missing, 
                (SELECT дата_готовности FROM заказы WHERE id_заказа = p_id_заказа) - INTERVAL '1 day',
                'принято'
            );
        END LOOP;
        
        RETURN 'WARNING: Недостаточно на складе. Созданы задания на производство ' || v_missing || ' ед.';
    END IF;
END;
$$;