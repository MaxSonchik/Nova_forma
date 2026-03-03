


ALTER TABLE IF EXISTS сотрудники
    RENAME TO Сотрудник;
ALTER TABLE IF EXISTS клиенты
    RENAME TO Клиент;
ALTER TABLE IF EXISTS заказы
    RENAME TO Заказ;
ALTER TABLE IF EXISTS изделия
    RENAME TO Изделие;
ALTER TABLE IF EXISTS материалы
    RENAME TO Материал;
ALTER TABLE IF EXISTS закупки_материалов
    RENAME TO Закупка;
ALTER TABLE IF EXISTS заготовки
    RENAME TO Заготовка;
ALTER TABLE IF EXISTS график_работы
    RENAME TO График;

ALTER TABLE IF EXISTS состав_закупки
    RENAME TO СоставЗакупки;
ALTER TABLE IF EXISTS состав_заказа
    RENAME TO СоставЗаказа;
ALTER TABLE IF EXISTS состав_изделия
    RENAME TO СоставИзделия;
ALTER TABLE IF EXISTS состав_заготовки
    RENAME TO СоставЗаготовки;

ALTER TABLE IF EXISTS план_заготовок
    RENAME TO ПланЗаготовок;
ALTER TABLE IF EXISTS план_сборки
    RENAME TO ПланСборки;

ALTER TABLE IF EXISTS расход_материалов
    RENAME TO РасходМатериалов;

ALTER TABLE IF EXISTS debug_log
    RENAME TO DebugLog;




DROP VIEW IF EXISTS v_задачи_сборщика;
DROP VIEW IF EXISTS v_склад_общий;



