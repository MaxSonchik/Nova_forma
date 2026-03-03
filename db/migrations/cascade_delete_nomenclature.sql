-- db/migrations/cascade_delete_nomenclature.sql
-- Function to safely delete a Product (Изделие)
CREATE OR REPLACE FUNCTION sp_delete_product(p_product_id INT) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN -- Check if the product is part of any active order
    IF EXISTS (
        SELECT 1
        FROM СоставЗаказа
        WHERE id_изделия = p_product_id
    ) THEN status := 'ERROR';
message := 'Невозможно удалить: Изделие участвует в оформленных заказах.';
RETURN NEXT;
RETURN;
END IF;
-- Check if there are active assembly plans
IF EXISTS (
    SELECT 1
    FROM "ПланСборки"
    WHERE id_изделия = p_product_id
) THEN status := 'ERROR';
message := 'Невозможно удалить: Изделие находится в плане сборки.';
RETURN NEXT;
RETURN;
END IF;
-- Safe to delete, cascade manually to maintain expected constraints
-- Remove from product composition
DELETE FROM СоставИзделия
WHERE id_изделия = p_product_id;
-- Delete the product itself
DELETE FROM Изделие
WHERE id_изделия = p_product_id;
status := 'OK';
message := 'Изделие и его состав успешно удалены.';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка при удалении изделия: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- Function to safely delete a Component (Заготовка)
CREATE OR REPLACE FUNCTION sp_delete_component(p_component_id INT) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN -- Check if component is in active production plan
    IF EXISTS (
        SELECT 1
        FROM ПланЗаготовок
        WHERE id_заготовки = p_component_id
    ) THEN status := 'ERROR';
message := 'Невозможно удалить: Заготовка находится в плане производства.';
RETURN NEXT;
RETURN;
END IF;
-- Check if component is part of an ordered product
IF EXISTS (
    SELECT 1
    FROM СоставИзделия si
        JOIN СоставЗаказа sz ON si.id_изделия = sz.id_изделия
    WHERE si.id_заготовки = p_component_id
) THEN status := 'ERROR';
message := 'Невозможно удалить: Заготовка входит в изделие, которое участвует в заказе.';
RETURN NEXT;
RETURN;
END IF;
-- Safe to delete
-- Remove material requirements
DELETE FROM РасходМатериалов
WHERE id_заготовки = p_component_id;
-- Remove from product composition
DELETE FROM СоставИзделия
WHERE id_заготовки = p_component_id;
-- Delete the component itself
DELETE FROM Заготовка
WHERE id_заготовки = p_component_id;
status := 'OK';
message := 'Заготовка успешно удалена из системы.';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка при удалении заготовки: ' || SQLERRM;
RETURN NEXT;
END;
$$;
-- Function to safely delete a Material (Материал)
CREATE OR REPLACE FUNCTION sp_delete_material(p_material_id INT) RETURNS TABLE (status VARCHAR, message VARCHAR) LANGUAGE plpgsql AS $$ BEGIN -- Check if material is actively used in production components that are being manufactured
    IF EXISTS (
        SELECT 1
        FROM РасходМатериалов rm
            JOIN ПланЗаготовок pz ON rm.id_заготовки = pz.id_заготовки
        WHERE rm.id_материала = p_material_id
    ) THEN status := 'ERROR';
message := 'Невозможно удалить: Материал используется в производимых заготовках.';
RETURN NEXT;
RETURN;
END IF;
-- Safe to delete
-- Remove from active purchases
DELETE FROM СоставЗакупки
WHERE id_материала = p_material_id;
-- Remove from material expenditure composition
DELETE FROM РасходМатериалов
WHERE id_материала = p_material_id;
-- Delete the material itself
DELETE FROM Материал
WHERE id_материала = p_material_id;
status := 'OK';
message := 'Материал и все сопутствующие данные удалены.';
RETURN NEXT;
EXCEPTION
WHEN OTHERS THEN status := 'ERROR';
message := 'Ошибка при удалении материала: ' || SQLERRM;
RETURN NEXT;
END;
$$;