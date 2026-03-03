


ALTER TABLE Закупка DROP CONSTRAINT IF EXISTS закупки_материалов_статус_check;
ALTER TABLE Закупка
ADD CONSTRAINT закупки_материалов_статус_check CHECK (
        статус IN (
            'ожидает_подтверждения',
            'выполнено',
            'отменено',
            'в_работе'
        )
    );

DROP FUNCTION IF EXISTS sp_report_defect(INTEGER, INTEGER, INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_report_defect(
        p_order_id INTEGER,
        p_product_id INTEGER,
        p_defect_qty INTEGER,
        p_reason VARCHAR
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$
DECLARE v_current_qty INTEGER;
v_old_status VARCHAR;
BEGIN 
SELECT количество_изделий INTO v_current_qty
FROM СоставЗаказа
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;
SELECT статус INTO v_old_status
FROM Заказ
WHERE id_заказа = p_order_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Позиция не найдена в заказе';
RETURN NEXT;
RETURN;
END IF;
IF p_defect_qty > v_current_qty THEN status := 'ERROR';
message := 'Количество брака превышает количество в заказе';
RETURN NEXT;
RETURN;
END IF;

UPDATE СоставЗаказа
SET количество_изделий = количество_изделий - p_defect_qty
WHERE id_заказа = p_order_id
    AND id_изделия = p_product_id;

IF v_old_status IN ('выполнен', 'готов_к_отгрузке') THEN
UPDATE Заказ
SET статус = 'в_работе'
WHERE id_заказа = p_order_id;
END IF;

INSERT INTO ПланЗаготовок (
        id_заказа,
        id_заготовки,
        плановое_количество,
        дата_план,
        статус
    )
SELECT p_order_id,
    si.id_заготовки,
    si.количество_заготовок * p_defect_qty,
    (
        SELECT дата_готовности
        FROM Заказ
        WHERE id_заказа = p_order_id
    ) - INTERVAL '1 day',
    'принято'
FROM СоставИзделия si
WHERE si.id_изделия = p_product_id;
status := 'WARNING';
message := 'Брак: ' || p_defect_qty || ' шт. Статус заказа изменен на "в_работе". Созданы задания. Причина: ' || p_reason;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_all_components();
CREATE OR REPLACE FUNCTION sp_get_all_components() RETURNS TABLE (
        id_заготовки INTEGER,
        наименование VARCHAR,
        количество_на_складе INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT z.id_заготовки,
    z.наименование,
    z.количество_на_складе
FROM Заготовка z;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_component_materials(INTEGER);
CREATE OR REPLACE FUNCTION sp_get_component_materials(p_component_id INTEGER) RETURNS TABLE (
        id_материала INTEGER,
        наименование VARCHAR,
        количество INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN 
    
    RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    sz.количество_материала
FROM СоставЗаготовки sz
    JOIN Материал m ON sz.id_материала = m.id_материала
WHERE sz.id_заготовки = p_component_id;
END;
$$;

CREATE TABLE IF NOT EXISTS СоставЗаготовки (
    id_заготовки INTEGER REFERENCES Заготовка(id_заготовки) ON DELETE CASCADE,
    id_материала INTEGER REFERENCES Материал(id_материала) ON DELETE CASCADE,
    количество_материала INTEGER NOT NULL DEFAULT 1,
    PRIMARY KEY (id_заготовки, id_материала)
);

DROP FUNCTION IF EXISTS sp_add_component_material(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_add_component_material(
        p_component_id INTEGER,
        p_material_id INTEGER,
        p_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN IF EXISTS (
        SELECT 1
        FROM СоставЗаготовки
        WHERE id_заготовки = p_component_id
            AND id_материала = p_material_id
    ) THEN status := 'ERROR';
message := 'Этот материал уже добавлен';
RETURN NEXT;
RETURN;
END IF;
INSERT INTO СоставЗаготовки (id_заготовки, id_материала, количество_материала)
VALUES (p_component_id, p_material_id, p_qty);
status := 'OK';
message := 'Материал добавлен';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_update_component_material(INTEGER, INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_update_component_material(
        p_component_id INTEGER,
        p_material_id INTEGER,
        p_new_qty INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE СоставЗаготовки
SET количество_материала = p_new_qty
WHERE id_заготовки = p_component_id
    AND id_материала = p_material_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Связь не найдена';
RETURN NEXT;
RETURN;
END IF;
status := 'OK';
message := 'Количество обновлено';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_delete_component_material(INTEGER, INTEGER);
CREATE OR REPLACE FUNCTION sp_delete_component_material(
        p_component_id INTEGER,
        p_material_id INTEGER
    ) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
DELETE FROM СоставЗаготовки
WHERE id_заготовки = p_component_id
    AND id_материала = p_material_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Связь не найдена';
RETURN NEXT;
RETURN;
END IF;
status := 'OK';
message := 'Материал удален';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_get_all_materials();
CREATE OR REPLACE FUNCTION sp_get_all_materials() RETURNS TABLE (
        id_материала INTEGER,
        наименование VARCHAR,
        количество_на_складе INTEGER
    ) LANGUAGE plpgsql AS $$ BEGIN RETURN QUERY
SELECT m.id_материала,
    m.наименование,
    m.количество_на_складе
FROM Материал m;
END;
$$;

DROP FUNCTION IF EXISTS sp_create_component(VARCHAR);
CREATE OR REPLACE FUNCTION sp_create_component(p_name VARCHAR) RETURNS TABLE (status VARCHAR, message VARCHAR, id INTEGER) LANGUAGE plpgsql AS $$
DECLARE v_new_id INTEGER;
BEGIN
INSERT INTO Заготовка (наименование, количество_на_складе)
VALUES (p_name, 0)
RETURNING id_заготовки INTO v_new_id;
status := 'OK';
message := 'Заготовка создана';
id := v_new_id;
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
id := NULL;
RETURN NEXT;
END;
$$;

DROP FUNCTION IF EXISTS sp_update_component(INTEGER, VARCHAR);
CREATE OR REPLACE FUNCTION sp_update_component(p_id INTEGER, p_name VARCHAR) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN
UPDATE Заготовка
SET наименование = p_name
WHERE id_заготовки = p_id;
IF NOT FOUND THEN status := 'ERROR';
message := 'Заготовка не найдена';
RETURN NEXT;
RETURN;
END IF;
status := 'OK';
message := 'Заготовка обновлена';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка: ' || SQLERRM;
RETURN NEXT;
END;
$$;