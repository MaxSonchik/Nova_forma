-- Fix constraint check on ПланЗаготовок
ALTER TABLE "ПланЗаготовок" DROP CONSTRAINT IF EXISTS план_заготовок_статус_check;
ALTER TABLE "ПланЗаготовок"
ADD CONSTRAINT план_заготовок_статус_check CHECK (
        статус IN (
            'ожидает',
            'принято',
            'назначено',
            'в_работе',
            'завершен',
            'отменено',
            'брак',
            'выполнено'
        )
    );