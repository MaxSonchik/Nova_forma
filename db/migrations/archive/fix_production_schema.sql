
DO $$ BEGIN IF NOT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_name = 'ПланПроизводства'
        AND column_name = 'дата_фактическая'
) THEN
ALTER TABLE ПланПроизводства
ADD COLUMN дата_фактическая TIMESTAMP;
END IF;
END $$;

CREATE OR REPLACE FUNCTION sp_get_production_plan_full() RETURNS TABLE (
        id_плана INTEGER,
        id_заказа INTEGER,
        наименование VARCHAR,
        
        плановое_количество INTEGER,
        фактическое_количество INTEGER,
        дата_план DATE,
        дата_фактическая TIMESTAMP,
        
        статус VARCHAR,
        сборщик VARCHAR,
        id_сотрудника INTEGER,
        id_заготовки INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT pp.id_плана,
    pp.id_заказа,
    z.наименование,
    pp.плановое_количество,
    pp.фактическое_количество,
    pp.дата_план,
    pp.дата_фактическая,
    pp.статус,
    (s.фамилия || ' ' || s.имя)::VARCHAR as сборщик,
    pp.id_сотрудника,
    pp.id_заготовки
FROM ПланПроизводства pp
    JOIN Заготовка z ON pp.id_заготовки = z.id_заготовки
    LEFT JOIN Сотрудник s ON pp.id_сотрудника = s.id_сотрудника
ORDER BY pp.дата_план ASC;
END;
$$;

CREATE OR REPLACE FUNCTION sp_add_product_to_order_smart(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_qty INTEGER,
        p_deadline DATE
    ) RETURNS TABLE(status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE r RECORD;
v_needed_qty INTEGER;
v_stock_qty INTEGER;
v_missing_qty INTEGER;
v_components_added INTEGER := 0;
BEGIN 

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
INSERT INTO СоставЗаказа (id_заказа, id_изделия, количество_изделий)
VALUES (p_order_id, p_product_id, p_qty);
END IF;

FOR r IN (
    SELECT si.id_заготовки,
        si.количество_заготовки,
        z.наименование
    FROM СоставИзделия si
        JOIN Заготовка z ON si.id_заготовки = z.id_заготовки
    WHERE si.id_изделия = p_product_id
) LOOP v_needed_qty := r.количество_заготовки * p_qty;

SELECT количество_готовых INTO v_stock_qty
FROM Заготовка
WHERE id_заготовки = r.id_заготовки;
IF v_stock_qty >= v_needed_qty THEN 



NULL;
ELSE 
v_missing_qty := v_needed_qty - v_stock_qty;
INSERT INTO ПланПроизводства (
        id_заказа,
        id_заготовки,
        плановое_количество,
        фактическое_количество,
        дата_план,
        статус
    )
VALUES (
        p_order_id,
        r.id_заготовки,
        v_missing_qty,
        0,
        p_deadline,
        'принято'
    );
v_components_added := v_components_added + 1;
END IF;
END LOOP;
IF v_components_added = 0 THEN status := 'OK';
message := 'Изделие добавлено. Все заготовки в наличии.';

ELSE status := 'OK';
message := 'Изделие добавлено. Созданы задачи для ' || v_components_added || ' заготовок.';
END IF;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;