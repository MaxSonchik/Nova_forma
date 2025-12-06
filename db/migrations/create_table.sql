-- СБРОС СТАРЫХ ТАБЛИЦ (чтобы пересоздать структуру начисто)
DROP TABLE IF EXISTS логи_операций CASCADE;
DROP TABLE IF EXISTS план_заготовок CASCADE;
DROP TABLE IF EXISTS состав_закупки CASCADE;
DROP TABLE IF EXISTS закупки_материалов CASCADE;
DROP TABLE IF EXISTS график_работы CASCADE;
DROP TABLE IF EXISTS состав_изделия CASCADE;
DROP TABLE IF EXISTS расход_материалов CASCADE;
DROP TABLE IF EXISTS состав_заказа CASCADE;
DROP TABLE IF EXISTS заказы CASCADE;
DROP TABLE IF EXISTS изделия CASCADE;
DROP TABLE IF EXISTS заготовки CASCADE;
DROP TABLE IF EXISTS материалы CASCADE;
DROP TABLE IF EXISTS клиенты CASCADE;
DROP TABLE IF EXISTS сотрудники CASCADE;

-- 1. Сотрудники (Теперь включают логин и пароль)
CREATE TABLE сотрудники (
    id_сотрудника SERIAL PRIMARY KEY,
    фио VARCHAR(100) NOT NULL,
    номер_телефона VARCHAR(20) UNIQUE NOT NULL,
    дата_рождения DATE CHECK (дата_рождения <= CURRENT_DATE - INTERVAL '18 years'),
    должность VARCHAR(50) CHECK (должность IN ('сборщик', 'менеджер', 'директор')),
    зарплата NUMERIC(10, 2) CHECK (зарплата > 0),
    дата_найма DATE DEFAULT CURRENT_DATE,
    дата_увольнения DATE,
    -- Поля авторизации
    login VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL
);

-- 2. Клиенты
CREATE TABLE клиенты (
    id_клиента SERIAL PRIMARY KEY,
    фио VARCHAR(100) NOT NULL,
    инн VARCHAR(12),
    номер_телефона VARCHAR(20) NOT NULL,
    адрес TEXT,
    дата_регистрации DATE DEFAULT CURRENT_DATE
);

-- 3. Материалы (Справочник)
CREATE TABLE материалы (
    id_материала SERIAL PRIMARY KEY,
    артикул_материала VARCHAR(50) UNIQUE NOT NULL,
    наименование VARCHAR(100) NOT NULL,
    количество_на_складе INTEGER DEFAULT 0 CHECK (количество_на_складе >= 0),
    единица_измерения VARCHAR(10) DEFAULT 'шт',
    минимальный_остаток INTEGER DEFAULT 10,
    цена_за_единицу NUMERIC(10, 2) CHECK (цена_за_единицу >= 0)
);

-- 4. Заготовки (Полуфабрикаты)
CREATE TABLE заготовки (
    id_заготовки SERIAL PRIMARY KEY,
    артикул_заготовки VARCHAR(50) UNIQUE NOT NULL,
    наименование VARCHAR(100) NOT NULL,
    количество_готовых INTEGER DEFAULT 0 CHECK (количество_готовых >= 0),
    описание TEXT
);

-- 5. Изделия (Готовая продукция)
CREATE TABLE изделия (
    id_изделия SERIAL PRIMARY KEY,
    артикул_изделия VARCHAR(50) UNIQUE NOT NULL,
    наименование VARCHAR(100) NOT NULL,
    тип VARCHAR(50),
    размеры VARCHAR(50),
    стоимость NUMERIC(10, 2) CHECK (стоимость >= 0)
);

-- 6. Расход материалов (Заготовка состоит из материалов)
CREATE TABLE расход_материалов (
    id_расход SERIAL PRIMARY KEY,
    id_заготовки INTEGER REFERENCES заготовки(id_заготовки) ON DELETE CASCADE,
    id_материала INTEGER REFERENCES материалы(id_материала) ON DELETE RESTRICT,
    количество_материала INTEGER CHECK (количество_материала > 0),
    UNIQUE(id_заготовки, id_материала) -- защита от дублей
);

-- 7. Состав изделия (Изделие состоит из заготовок)
CREATE TABLE состав_изделия (
    id_состав_изделия SERIAL PRIMARY KEY,
    id_изделия INTEGER REFERENCES изделия(id_изделия) ON DELETE CASCADE,
    id_заготовки INTEGER REFERENCES заготовки(id_заготовки) ON DELETE RESTRICT,
    количество_заготовок INTEGER CHECK (количество_заготовок > 0),
    UNIQUE(id_изделия, id_заготовки)
);

-- 8. Заказы
CREATE TABLE заказы (
    id_заказа SERIAL PRIMARY KEY,
    id_клиента INTEGER REFERENCES клиенты(id_клиента) ON DELETE RESTRICT,
    id_менеджера INTEGER REFERENCES сотрудники(id_сотрудника) ON DELETE SET NULL,
    дата_заказа DATE DEFAULT CURRENT_DATE,
    дата_готовности DATE,
    -- ОБНОВЛЕННЫЙ СПИСОК СТАТУСОВ:
    статус VARCHAR(20) DEFAULT 'принят' CHECK (статус IN ('принят', 'в_работе', 'в_обработке', 'выполнен', 'отменен', 'отгружен', 'завершен')),
    сумма_заказа NUMERIC(12, 2) DEFAULT 0,
    примечания TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- 9. Состав заказа (Какие изделия заказал клиент)
CREATE TABLE состав_заказа (
    id_состав_заказа SERIAL PRIMARY KEY,
    id_заказа INTEGER REFERENCES заказы(id_заказа) ON DELETE CASCADE,
    id_изделия INTEGER REFERENCES изделия(id_изделия) ON DELETE RESTRICT,
    количество_изделий INTEGER CHECK (количество_изделий > 0),
    цена_фиксированная NUMERIC(10, 2)
);

-- 10. График работы
CREATE TABLE график_работы (
    id_графика SERIAL PRIMARY KEY,
    id_сотрудника INTEGER REFERENCES сотрудники(id_сотрудника) ON DELETE CASCADE,
    дата DATE NOT NULL,
    статус VARCHAR(20) CHECK (статус IN ('рабочий', 'выходной', 'отпуск', 'больничный')),
    UNIQUE(id_сотрудника, дата)
);

-- 11. Закупки материалов
CREATE TABLE закупки_материалов (
    id_закупки SERIAL PRIMARY KEY,
    дата_закупки DATE DEFAULT CURRENT_DATE,
    поставщик VARCHAR(100),
    статус VARCHAR(30) DEFAULT 'ожидает_подтверждения' CHECK (статус IN ('ожидает_подтверждения', 'подтверждено', 'выполнено'))
);

-- 12. Состав закупки
CREATE TABLE состав_закупки (
    id_состав_закупки SERIAL PRIMARY KEY,
    id_закупки INTEGER REFERENCES закупки_материалов(id_закупки) ON DELETE CASCADE,
    id_материала INTEGER REFERENCES материалы(id_материала) ON DELETE CASCADE,
    количество INTEGER CHECK (количество > 0),
    цена_закупки NUMERIC(10, 2)
);

-- 13. План заготовок (Задания на производство)
CREATE TABLE план_заготовок (
    id_плана SERIAL PRIMARY KEY,
    id_заказа INTEGER REFERENCES заказы(id_заказа) ON DELETE CASCADE,
    id_заготовки INTEGER REFERENCES заготовки(id_заготовки),
    id_сборщика INTEGER REFERENCES сотрудники(id_сотрудника),
    плановое_количество INTEGER NOT NULL,
    фактическое_количество INTEGER DEFAULT 0,
    дата_план DATE NOT NULL,
    дата_факт DATE,
    статус VARCHAR(20) DEFAULT 'принято' CHECK (статус IN ('принято', 'в_работе', 'выполнено', 'отменено', 'просрочено'))
);

-- 14. Логирование операций (обновлено id_user -> id_сотрудника)
CREATE TABLE логи_операций (
    id_лога SERIAL PRIMARY KEY,
    id_сотрудника INTEGER REFERENCES сотрудники(id_сотрудника) ON DELETE SET NULL,
    таблица VARCHAR(50),
    операция VARCHAR(10),
    данные_до JSONB,
    данные_после JSONB,
    дата_время TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);