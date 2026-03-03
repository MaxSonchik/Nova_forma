
BEGIN;

ALTER TABLE ПланЗаготовок DROP CONSTRAINT IF EXISTS план_заготовок_статус_check;

UPDATE ПланЗаготовок
SET статус = 'принято'
WHERE статус LIKE 'принято';
UPDATE ПланЗаготовок
SET статус = 'в_работе'
WHERE статус LIKE 'в_работе';
UPDATE ПланЗаготовок
SET статус = 'выполнено'
WHERE статус LIKE 'выполнено';

ALTER TABLE ПланЗаготовок
ADD CONSTRAINT план_заготовок_статус_check CHECK (
        статус IN (
            'принято',
            'в_работе',
            'выполнено',
            'отменено',
            'просрочено'
        )
    );
COMMIT;