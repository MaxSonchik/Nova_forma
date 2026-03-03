-- Fix for sp_calculate_order_sum function
-- Updates the function to use correct column 'сумма_заказа' instead of 'сумма'
CREATE OR REPLACE FUNCTION sp_calculate_order_sum() RETURNS TRIGGER AS $$ BEGIN
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
$$ LANGUAGE plpgsql;