DROP TABLE IF EXISTS логи_операций CASCADE;
DROP TABLE IF EXISTS ПланЗаготовок CASCADE;
DROP TABLE IF EXISTS СоставЗакупки CASCADE;
DROP TABLE IF EXISTS Закупка CASCADE;
DROP TABLE IF EXISTS График CASCADE;
DROP TABLE IF EXISTS СоставИзделия CASCADE;
DROP TABLE IF EXISTS расход_материалов CASCADE;
DROP TABLE IF EXISTS СоставЗаказа CASCADE;
DROP TABLE IF EXISTS Заказ CASCADE;
DROP TABLE IF EXISTS Изделие CASCADE;
DROP TABLE IF EXISTS Заготовка CASCADE;
DROP TABLE IF EXISTS Материал CASCADE;
DROP TABLE IF EXISTS Клиент CASCADE;
DROP TABLE IF EXISTS Сотрудник CASCADE;

CREATE TABLE Сотрудник (
    id_сотрудника SERIAL PRIMARY KEY,
    фио VARCHAR(100) NOT NULL,
    номер_телефона VARCHAR(20) UNIQUE NOT NULL,
    дата_рождения DATE CHECK (дата_рождения <= CURRENT_DATE - INTERVAL '18 years'),
    должность VARCHAR(50) CHECK (должность IN ('сборщик', 'менеджер', 'директор')),
    зарплата NUMERIC(10, 2) CHECK (зарплата > 0),
    дата_найма DATE DEFAULT CURRENT_DATE,
    дата_увольнения DATE,
    login VARCHAR(50) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL
);


CREATE TABLE Клиент (
    id_клиента SERIAL PRIMARY KEY,
    фио VARCHAR(100) NOT NULL,
    инн VARCHAR(12),
    номер_телефона VARCHAR(20) NOT NULL,
    адрес TEXT,
    дата_регистрации DATE DEFAULT CURRENT_DATE
);


CREATE TABLE Материал (
    id_материала SERIAL PRIMARY KEY,
    артикул_материала VARCHAR(50) UNIQUE NOT NULL,
    наименование VARCHAR(100) NOT NULL,
    количество_на_складе INTEGER DEFAULT 0 CHECK (количество_на_складе >= 0),
    единица_измерения VARCHAR(10) DEFAULT 'шт',
    минимальный_остаток INTEGER DEFAULT 10,
    цена_за_единицу NUMERIC(10, 2) CHECK (цена_за_единицу >= 0)
);


CREATE TABLE Заготовка (
    id_заготовки SERIAL PRIMARY KEY,
    артикул_заготовки VARCHAR(50) UNIQUE NOT NULL,
    наименование VARCHAR(100) NOT NULL,
    количество_готовых INTEGER DEFAULT 0 CHECK (количество_готовых >= 0),
    описание TEXT
);


CREATE TABLE Изделие (
    id_изделия SERIAL PRIMARY KEY,
    артикул_изделия VARCHAR(50) UNIQUE NOT NULL,
    наименование VARCHAR(100) NOT NULL,
    тип VARCHAR(50),
    размеры VARCHAR(50),
    стоимость NUMERIC(10, 2) CHECK (стоимость >= 0)
);


CREATE TABLE расход_материалов (
    id_расход SERIAL PRIMARY KEY,
    id_заготовки INTEGER REFERENCES Заготовка(id_заготовки) ON DELETE CASCADE,
    id_материала INTEGER REFERENCES Материал(id_материала) ON DELETE RESTRICT,
    количество_материала INTEGER CHECK (количество_материала > 0),
    UNIQUE(id_заготовки, id_материала) 
);


CREATE TABLE СоставИзделия (
    id_состав_изделия SERIAL PRIMARY KEY,
    id_изделия INTEGER REFERENCES Изделие(id_изделия) ON DELETE CASCADE,
    id_заготовки INTEGER REFERENCES Заготовка(id_заготовки) ON DELETE RESTRICT,
    количество_заготовок INTEGER CHECK (количество_заготовок > 0),
    UNIQUE(id_изделия, id_заготовки)
);


CREATE TABLE Заказ (
    id_заказа SERIAL PRIMARY KEY,
    id_клиента INTEGER REFERENCES Клиент(id_клиента) ON DELETE RESTRICT,
    id_менеджера INTEGER REFERENCES Сотрудник(id_сотрудника) ON DELETE SET NULL,
    дата_заказа DATE DEFAULT CURRENT_DATE,
    дата_готовности DATE,
    статус VARCHAR(20) DEFAULT 'принят' CHECK (статус IN ('принят', 'в_работе', 'в_обработке', 'выполнен', 'отменен', 'отгружен', 'завершен')),
    сумма_заказа NUMERIC(12, 2) DEFAULT 0,
    примечания TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);


CREATE TABLE СоставЗаказа (
    id_состав_заказа SERIAL PRIMARY KEY,
    id_заказа INTEGER REFERENCES Заказ(id_заказа) ON DELETE CASCADE,
    id_изделия INTEGER REFERENCES Изделие(id_изделия) ON DELETE RESTRICT,
    количество_изделий INTEGER CHECK (количество_изделий > 0),
    цена_фиксированная NUMERIC(10, 2)
);


CREATE TABLE График (
    id_графика SERIAL PRIMARY KEY,
    id_сотрудника INTEGER REFERENCES Сотрудник(id_сотрудника) ON DELETE CASCADE,
    дата DATE NOT NULL,
    статус VARCHAR(20) CHECK (статус IN ('рабочий', 'выходной', 'отпуск', 'больничный')),
    UNIQUE(id_сотрудника, дата)
);


CREATE TABLE Закупка (
    id_закупки SERIAL PRIMARY KEY,
    дата_закупки DATE DEFAULT CURRENT_DATE,
    поставщик VARCHAR(100),
    статус VARCHAR(30) DEFAULT 'ожидает_подтверждения' CHECK (статус IN ('ожидает_подтверждения', 'подтверждено', 'выполнено'))
);


CREATE TABLE СоставЗакупки (
    id_состав_закупки SERIAL PRIMARY KEY,
    id_закупки INTEGER REFERENCES Закупка(id_закупки) ON DELETE CASCADE,
    id_материала INTEGER REFERENCES Материал(id_материала) ON DELETE CASCADE,
    количество INTEGER CHECK (количество > 0),
    цена_закупки NUMERIC(10, 2)
);

CREATE TABLE ПланЗаготовок (
    id_плана SERIAL PRIMARY KEY,
    id_заказа INTEGER REFERENCES Заказ(id_заказа) ON DELETE CASCADE,
    id_заготовки INTEGER REFERENCES Заготовка(id_заготовки),
    id_сборщика INTEGER REFERENCES Сотрудник(id_сотрудника),
    плановое_количество INTEGER NOT NULL,
    фактическое_количество INTEGER DEFAULT 0,
    дата_план DATE NOT NULL,
    дата_факт DATE,
    статус VARCHAR(20) DEFAULT 'принято' CHECK (статус IN ('принято', 'в_работе', 'выполнено', 'отменено', 'просрочено'))
);

