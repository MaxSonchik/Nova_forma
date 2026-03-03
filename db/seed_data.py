import os
import random
import sys
from datetime import date, timedelta

import bcrypt
import psycopg2
from faker import Faker

                 
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import config

fake = Faker("ru_RU")


def hash_password_via_db(cur, password):
    """Использует pgcrypto для хеширования, чтобы быть совместимым с sp_login"""
    cur.execute("SELECT crypt(%s, gen_salt('bf'))", (password,))
    return cur.fetchone()[0]


def seed():
    conn = psycopg2.connect(config.DATABASE_URL)
    cur = conn.cursor()

    print("🧹 Очистка таблиц (TRUNCATE)...")
    tables = [
        "ПланЗаготовок",
        "СоставЗакупки",
        "Закупка",
        "График",
        "СоставЗаказа",
        "СоставИзделия",
        "расход_материалов",
        "Заказ",
        "Изделие",
        "Заготовка",
        "Материал",
        "Клиент",
        "Сотрудник",
    ]
    for table in tables:
        cur.execute(f"TRUNCATE TABLE {table} RESTART IDENTITY CASCADE;")

                                       
    print("🌱 1. Генерация материалов...")
    base_materials = [
        ("ДСП Белый", "лист", 1500),
        ("ДСП Дуб Сонома", "лист", 1800),
        ("ДСП Венге", "лист", 1900),
        ("ДСП Орех", "лист", 1750),
        ("МДФ Глянец", "лист", 3500),
        ("Фанера 10мм", "лист", 900),
        ("Брус сосновый 50х50", "м", 120),
        ("Кромка ПВХ 2мм", "м", 40),
        ("Кромка Меламин", "м", 15),
        ("Саморезы 3.5х16", "шт", 1),
        ("Саморезы 4х30", "шт", 2),
        ("Евровинт (Конфирмат)", "шт", 5),
        ("Эксцентриковая стяжка", "шт", 15),
        ("Шкант деревянный", "шт", 2),
        ("Клей ПВА Столяр", "л", 450),
        ("Лак Полиуретановый", "л", 1200),
        ("Краска Акриловая", "л", 900),
        ("Ручка Скоба хром", "шт", 150),
        ("Ручка Кнопка", "шт", 80),
        ("Петля накладная с доводчиком", "шт", 180),
        ("Петля вкладная", "шт", 120),
        ("Направляющие шариковые 450мм", "компл", 400),
        ("Опора колесная", "шт", 120),
        ("Труба Джокер 25мм", "м", 300),
    ]

    material_ids = []
    for name, unit, price in base_materials:
        cur.execute(
            """
            INSERT INTO Материал (артикул_материала, наименование, количество_на_складе, единица_измерения, цена_за_единицу)
            VALUES (%s, %s, %s, %s, %s) RETURNING id_материала
        """,
            (fake.unique.ean8(), name, random.randint(0, 1000), unit, price),
        )
        material_ids.append(cur.fetchone()[0])

                          
    print("🌱 2. Генерация заготовок и расхода материалов...")
    zagotovki_names = [
        "Боковина шкафа 2200х600",
        "Полка 568х500",
        "Дверь шкафа ЛДСП",
        "Цоколь 600х100",
        "Крышка стола 1200х700",
        "Ножка стола (брус)",
        "Царга стола",
        "Спинка стула",
        "Сиденье стула",
        "Фасад ящика МДФ",
        "Дно ящика ДВП",
        "Задняя стенка ДВП",
    ]
    zagotovki_ids = []

    for z_name in zagotovki_names:
        cur.execute(
            """
            INSERT INTO Заготовка (артикул_заготовки, наименование, количество_готовых, описание)
            VALUES (%s, %s, %s, %s) RETURNING id_заготовки
        """,
            (
                fake.unique.ean8(),
                z_name,
                random.randint(0, 50),
                fake.text(max_nb_chars=50),
            ),
        )
        z_id = cur.fetchone()[0]
        zagotovki_ids.append(z_id)

                                                
                                                              
        used_mats = random.sample(material_ids, k=random.randint(1, 3))
        for m_id in used_mats:
            cur.execute(
                """
                INSERT INTO расход_материалов (id_заготовки, id_материала, количество_материала)
                VALUES (%s, %s, %s)
            """,
                (z_id, m_id, random.randint(1, 5)),
            )

                        
    print("🌱 3. Генерация изделий и их состава...")
    products_base = [
        ("Шкаф-купе 'Лидер'", "шкаф"),
        ("Стол письменный 'Ученик'", "стол"),
        ("Стул 'Комфорт'", "стул"),
        ("Тумба прикроватная", "шкаф"),
        ("Комод на 4 ящика", "шкаф"),
        ("Стол обеденный раздвижной", "стол"),
        ("Полка навесная", "шкаф"),
        ("Стеллаж офисный", "шкаф"),
    ]
    product_ids = []

    for p_name, p_type in products_base:
        cur.execute(
            """
            INSERT INTO Изделие (артикул_изделия, наименование, тип, размеры, стоимость)
            VALUES (%s, %s, %s, %s, %s) RETURNING id_изделия
        """,
            (
                fake.unique.ean8(),
                p_name,
                p_type,
                f"{random.randint(500,2000)}x{random.randint(400,1000)}x{random.randint(400,2200)}",
                random.randint(3000, 45000),
            ),
        )
        p_id = cur.fetchone()[0]
        product_ids.append(p_id)

                                                      
                                                           
        used_zags = random.sample(zagotovki_ids, k=random.randint(2, 5))
        for z_id in used_zags:
            cur.execute(
                """
                INSERT INTO СоставИзделия (id_изделия, id_заготовки, количество_заготовки)
                VALUES (%s, %s, %s)
            """,
                (p_id, z_id, random.randint(1, 4)),
            )

                           
    print("🌱 4. Генерация сотрудников (Строго: 2 Дир, 8 Мен, 5 Сбор)...")
    employees_ids = []

                                      
    roles_distribution = ["директор"] * 2 + ["менеджер"] * 8 + ["сборщик"] * 5
                                                                       
                                                  

    for i, role in enumerate(roles_distribution):
        gender = random.choice(["M", "F"])
        if gender == "M":
            fio = fake.first_name_male() + " " + fake.last_name_male()
        else:
            fio = fake.first_name_female() + " " + fake.last_name_female()

                                                                 
        if i == 0:
            login = "director"
            fio = "Директор Иван"
        elif i == 2:
            login = "manager"
            fio = "Менеджер Анна"
        elif i == 10:
            login = "worker"
            fio = "Сборщик Петр"
        else:
            login = f"user_{i+1}"

        hashed = hash_password_via_db(cur, "123")

        cur.execute(
            """
            INSERT INTO Сотрудник (фио, номер_телефона, дата_рождения, должность, зарплата, дата_найма, login, password_hash)
            VALUES (%s, %s, %s, %s, %s, %s, %s, %s) RETURNING id_сотрудника
        """,
            (
                fio,
                fake.unique.phone_number(),
                fake.date_of_birth(minimum_age=18, maximum_age=60),
                role,                         
                random.randint(40000, 150000),
                fake.date_between(start_date="-5y", end_date="today"),
                login,
                hashed,
            ),
        )
        employees_ids.append(cur.fetchone()[0])

                                                 
    print("🌱 5. Заполнение графика (СБ/ВС - выходной)...")
    today = date.today()
                                                    
    start_date = today.replace(day=1)                                
    days_to_generate = 60

    for emp_id in employees_ids:
        for day_offset in range(days_to_generate):
            current_day = start_date + timedelta(days=day_offset)
            weekday = current_day.weekday()                    

                                 
            if weekday >= 5:
                status = "выходной"
            else:
                status = "рабочий"

            cur.execute(
                """
                INSERT INTO График (id_сотрудника, дата, статус)
                VALUES (%s, %s, %s)
            """,
                (emp_id, current_day, status),
            )

                                      
    print("🌱 6. Генерация клиентов (100+)...")
    client_ids = []
    for _ in range(110):             
        gender = random.choice(["M", "F"])
        if gender == "M":
            name = f"{fake.last_name_male()} {fake.first_name_male()} {fake.middle_name_male()}"
        else:
            name = f"{fake.last_name_female()} {fake.first_name_female()} {fake.middle_name_female()}"

        cur.execute(
            """
            INSERT INTO Клиент (фио, номер_телефона, адрес, дата_регистрации, инн)
            VALUES (%s, %s, %s, %s, %s) RETURNING id_клиента
        """,
            (
                name,
                fake.phone_number(),
                fake.address(),
                fake.date_between(start_date="-2y"),
                fake.unique.random_number(digits=12, fix_len=True),
            ),
        )
        client_ids.append(cur.fetchone()[0])

                                                     
    print("🌱 7. Генерация заказов (умные статусы)...")
    order_ids = []

                                                                       
    statuses = ["принят", "в_работе", "выполнен", "отгружен", "завершен", "отменен"]
    weights = [0.15, 0.25, 0.15, 0.10, 0.30, 0.05]

    for _ in range(120):
        client = random.choice(client_ids)
        manager = random.choice(employees_ids)

                                        
        status = random.choices(statuses, weights=weights, k=1)[0]

                                             
        if status in ["завершен", "отгружен", "выполнен", "отменен"]:
                                                   
            d_order = fake.date_between(start_date="-60d", end_date="-10d")
                                                          
            d_ready = d_order + timedelta(days=random.randint(5, 10))
        else:
                                              
            d_order = fake.date_between(start_date="-10d", end_date="today")

                                     
            if random.random() < 0.1:
                                               
                d_ready = d_order + timedelta(days=random.randint(1, 3))
            else:
                                             
                d_ready = date.today() + timedelta(days=random.randint(5, 20))

        cur.execute(
            """
            INSERT INTO Заказ (id_клиента, id_менеджера, дата_заказа, дата_готовности, статус, сумма_заказа)
            VALUES (%s, %s, %s, %s, %s, %s) RETURNING id_заказа
        """,
            (client, manager, d_order, d_ready, status, 0),
        )
        o_id = cur.fetchone()[0]
        order_ids.append(o_id)

                                    
        items_count = random.randint(1, 5)
        total_sum = 0
        used_products = random.sample(product_ids, k=items_count)

        for p_id in used_products:
            cur.execute("SELECT стоимость FROM Изделие WHERE id_изделия = %s", (p_id,))
            price = cur.fetchone()[0]
            qty = random.randint(1, 4)

            cur.execute(
                """
                INSERT INTO СоставЗаказа (id_заказа, id_изделия, количество_изделий, цена_фиксированная)
                VALUES (%s, %s, %s, %s)
            """,
                (o_id, p_id, qty, price),
            )
            total_sum += price * qty

        cur.execute(
            "UPDATE Заказ SET сумма_заказа = %s WHERE id_заказа = %s",
            (total_sum, o_id),
        )

                               
    print("🌱 8. Генерация плана производства...")
                          
    for o_id in order_ids[:50]:                                      
                                 
        cur.execute(
            "SELECT id_изделия, количество_изделий FROM СоставЗаказа WHERE id_заказа = %s",
            (o_id,),
        )
        order_items = cur.fetchall()

        for p_id, p_qty in order_items:
                                            
            cur.execute(
                "SELECT id_заготовки, количество_заготовки FROM СоставИзделия WHERE id_изделия = %s",
                (p_id,),
            )
            parts = cur.fetchall()

            for z_id, z_qty_per_item in parts:
                total_parts_needed = p_qty * z_qty_per_item
                assembler = random.choice(employees_ids)
                
                                                                                
                fact_qty = random.randint(0, total_parts_needed)
                if fact_qty >= total_parts_needed:
                    status = "выполнено"
                elif fact_qty > 0:
                    status = "в_работе"
                else:
                    status = "принято"

                cur.execute(
                    """
                    INSERT INTO ПланЗаготовок (id_заготовки, id_заказа, id_сотрудника, плановое_количество, фактическое_количество, дата_план, статус)
                    VALUES (%s, %s, %s, %s, %s, %s, %s)
                    ON CONFLICT (id_заготовки, id_заказа) DO UPDATE SET 
                        плановое_количество = ПланЗаготовок.плановое_количество + EXCLUDED.плановое_количество,
                        фактическое_количество = ПланЗаготовок.фактическое_количество + EXCLUDED.фактическое_количество,
                        статус = CASE 
                            WHEN (ПланЗаготовок.фактическое_количество + EXCLUDED.фактическое_количество) >= (ПланЗаготовок.плановое_количество + EXCLUDED.плановое_количество) THEN 'выполнено'
                            WHEN (ПланЗаготовок.фактическое_количество + EXCLUDED.фактическое_количество) > 0 THEN 'в_работе'
                            ELSE 'принято'
                        END
                """,
                    (
                        z_id,
                        o_id,
                        assembler,
                        total_parts_needed,
                        fact_qty,
                        fake.future_date(end_date="+14d"),
                        status,
                    ),
                )

                                 
    print("🌱 9. Генерация закупок...")
    suppliers = [
        "ООО 'ЛесСнаб'",
        "ИП Петров (Фурнитура)",
        "ЗАО 'ХимПродукт'",
        "МеталлКомплект",
    ]

    for _ in range(20):
        cur.execute(
            """
            INSERT INTO Закупка (поставщик, статус)
            VALUES (%s, %s) RETURNING id_закупки
        """,
            (random.choice(suppliers), random.choice(["выполнено", "подтверждено"])),
        )
        z_id = cur.fetchone()[0]

                          
        bought_mats = random.sample(material_ids, k=random.randint(3, 8))
        for m_id in bought_mats:
            cur.execute(
                "SELECT цена_за_единицу FROM Материал WHERE id_материала = %s", (m_id,)
            )
            base_price = cur.fetchone()[0]

            cur.execute(
                """
                INSERT INTO СоставЗакупки (id_закупки, id_материала, количество, цена_закупки)
                VALUES (%s, %s, %s, %s)
            """,
                (
                    z_id,
                    m_id,
                    random.randint(10, 100),
                    float(base_price) * 0.9,                                 
                ),
            )

    conn.commit()
    cur.close()
    conn.close()
    print("✅ Все таблицы успешно перезаполнены в соответствии с требованиями!")


if __name__ == "__main__":
    seed()
