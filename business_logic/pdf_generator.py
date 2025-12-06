import os
from datetime import datetime, timedelta

from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.pdfgen import canvas

from db.database import Database


class PDFGenerator:
    def __init__(self, filename):
        self.filename = filename
        self.c = canvas.Canvas(filename, pagesize=A4)
        self.width, self.height = A4

        font_path = os.path.join("assets", "font.ttf")
        if os.path.exists(font_path):
            pdfmetrics.registerFont(TTFont("RusFont", font_path))
            self.font_name = "RusFont"
        else:
            print("⚠️ Шрифт не найден! Русские буквы могут не отображаться.")
            self.font_name = "Helvetica"  # Стандартный (не поддерживает кириллицу)

    def generate_order_blank(self, order_id):
        """Генерация бланка заказа"""

        # 1. Получение данных (Заголовок)
        order_info = Database.fetch_one(
            """
            SELECT z.id_заказа, z.дата_заказа, z.дата_готовности, z.сумма_заказа, 
                   k.фио, k.номер_телефона, k.адрес
            FROM заказы z
            JOIN клиенты k ON z.id_клиента = k.id_клиента
            WHERE z.id_заказа = %s
        """,
            (order_id,),
        )

        if not order_info:
            return False, "Заказ не найден"

        # 2. Получение состава заказа
        items = Database.fetch_all(
            """
            SELECT i.наименование, i.артикул_изделия, sz.количество_изделий, sz.цена_фиксированная
            FROM состав_заказа sz
            JOIN изделия i ON sz.id_изделия = i.id_изделия
            WHERE sz.id_заказа = %s
        """,
            (order_id,),
        )

        c = self.c
        margin = 50
        y = self.height - margin

        logo_path = os.path.join("assets", "logo.png")
        if os.path.exists(logo_path):
            c.drawImage(
                logo_path,
                margin,
                y - 60,
                width=60,
                height=60,
                preserveAspectRatio=True,
                mask="auto",
            )

        c.setFont(self.font_name, 18)
        c.drawString(margin + 70, y - 25, "NOVA FORMA")
        c.setFont(self.font_name, 10)
        c.drawString(margin + 70, y - 40, "Мебельное производство")

        y -= 80

        c.setFont(self.font_name, 16)
        c.drawCentredString(self.width / 2, y, f"ЗАКАЗ №{order_info['id_заказа']}")
        y -= 30

        c.setFont(self.font_name, 12)
        c.drawString(margin, y, f"Клиент: {order_info['фио']}")
        y -= 15
        c.drawString(margin, y, f"Телефон: {order_info['номер_телефона']}")
        y -= 15
        c.drawString(margin, y, f"Адрес: {order_info['адрес'] or 'Самовывоз'}")
        y -= 15
        c.drawString(margin, y, f"Дата заказа: {order_info['дата_заказа']}")
        y -= 15
        c.drawString(margin, y, f"Дата готовности: {order_info['дата_готовности']}")

        y -= 40

        c.setFillColor(colors.lightgrey)
        c.rect(margin, y - 5, self.width - 2 * margin, 20, fill=1)
        c.setFillColor(colors.black)
        c.setFont(self.font_name, 10)

        col_x = [margin, margin + 40, margin + 250, margin + 350, margin + 450]
        c.drawString(col_x[0] + 5, y, "№")
        c.drawString(col_x[1] + 5, y, "Наименование")
        c.drawString(col_x[2] + 5, y, "Кол-во")
        c.drawString(col_x[3] + 5, y, "Цена")
        c.drawString(col_x[4] + 5, y, "Сумма")

        y -= 25

        total_qty = 0
        for i, item in enumerate(items):
            name = item["наименование"]
            qty = item["количество_изделий"]
            price = item["цена_фиксированная"]
            summ = qty * price
            total_qty += qty

            c.drawString(col_x[0] + 5, y, str(i + 1))
            c.drawString(col_x[1] + 5, y, name[:35])  # Обрезаем если длинное
            c.drawString(col_x[2] + 5, y, f"{qty} шт")
            c.drawString(col_x[3] + 5, y, f"{price:,.0f}")
            c.drawString(col_x[4] + 5, y, f"{summ:,.0f}")

            c.line(margin, y - 2, self.width - margin, y - 2)  # Линия
            y -= 20

            if y < 50:  
                c.showPage()
                y = self.height - 50

        # Итого
        y -= 20
        c.setFont(self.font_name, 14)
        c.drawRightString(
            self.width - margin, y, f"ИТОГО: {order_info['сумма_заказа']:,.2f} ₽"
        )

        # Подписи
        y -= 60
        c.setFont(self.font_name, 10)
        c.line(margin, y, margin + 150, y)
        c.drawString(margin, y - 15, "Менеджер")

        c.line(self.width - margin - 150, y, self.width - margin, y)
        c.drawString(self.width - margin - 150, y - 15, "Клиент")

        c.save()
        return True, "Отчет сформирован"

    def generate_assembler_tasks(self, user_id):
        """Генерация сменного задания (Чек-лист)"""
        # 1. Получаем имя сотрудника
        user_info = Database.fetch_one(
            "SELECT фио FROM сотрудники WHERE id_сотрудника = %s", (user_id,)
        )
        fio = user_info["фио"] if user_info else "Неизвестный"

        # 2. Получаем задачи (В работе + Принятые, назначенные мне)
        query = """
            SELECT z.наименование as заготовка, pz.плановое_количество, pz.фактическое_количество, 
                   m.наименование as изделие, o.id_заказа
            FROM план_заготовок pz
            JOIN заготовки z ON pz.id_заготовки = z.id_заготовки
            JOIN заказы o ON pz.id_заказа = o.id_заказа
            JOIN состав_заказа sz ON o.id_заказа = sz.id_заказа -- Приблизительная связь для инфо
            JOIN изделия m ON sz.id_изделия = m.id_изделия
            WHERE pz.id_сборщика = %s AND pz.статус IN ('в_работе', 'принято')
            GROUP BY pz.id_плана, z.наименование, pz.плановое_количество, pz.фактическое_количество, m.наименование, o.id_заказа
        """
        # Упростим запрос, чтобы не дублировать строки из-за join'ов (взять просто задачи)
        query = """
            SELECT pz.id_плана, z.наименование, pz.плановое_количество, pz.фактическое_количество
            FROM план_заготовок pz
            JOIN заготовки z ON pz.id_заготовки = z.id_заготовки
            WHERE pz.id_сборщика = %s AND pz.статус IN ('в_работе')
        """
        tasks = Database.fetch_all(query, (user_id,))

        # --- РИСОВАНИЕ ---
        c = self.c
        margin = 50
        y = self.height - margin

        # Логотип
        logo_path = os.path.join("assets", "logo.png")
        if os.path.exists(logo_path):
            c.drawImage(
                logo_path,
                margin,
                y - 50,
                width=50,
                height=50,
                preserveAspectRatio=True,
                mask="auto",
            )

        # Заголовок
        c.setFont(self.font_name, 16)
        c.drawString(margin + 60, y - 20, "СМЕННОЕ ЗАДАНИЕ")
        c.setFont(self.font_name, 12)
        c.drawString(margin + 60, y - 40, f"Сотрудник: {fio}")
        c.drawString(
            margin + 60, y - 55, f"Дата выдачи: {datetime.now().strftime('%d.%m.%Y')}"
        )

        y -= 80

        # Таблица
        c.setFillColor(colors.lightgrey)
        c.rect(margin, y - 5, self.width - 2 * margin, 20, fill=1)
        c.setFillColor(colors.black)
        c.setFont(self.font_name, 10)

        c.drawString(margin + 5, y, "ID")
        c.drawString(margin + 40, y, "Заготовка (Деталь)")
        c.drawString(margin + 300, y, "План")
        c.drawString(margin + 350, y, "Сделано")
        c.drawString(margin + 420, y, "Отметка")

        y -= 25

        if not tasks:
            c.drawString(margin, y, "Нет активных задач.")

        for task in tasks:
            plan = task["плановое_количество"]
            fact = task["фактическое_количество"]

            c.drawString(margin + 5, y, str(task["id_плана"]))
            c.drawString(margin + 40, y, task["наименование"][:45])
            c.drawString(margin + 300, y, str(plan))
            c.drawString(margin + 350, y, str(fact))

            # Чекбокс (квадратик)
            c.rect(margin + 420, y - 2, 12, 12, fill=0)

            c.line(margin, y - 5, self.width - margin, y - 5)
            y -= 20

            if y < 50:
                c.showPage()
                y = self.height - 50

        c.save()
        return True, "Сменное задание сформировано"

    def generate_assembler_schedule(self, user_id):
        """Генерация графика на текущий месяц"""
        # 1. Данные
        user_info = Database.fetch_one(
            "SELECT фио FROM сотрудники WHERE id_сотрудника = %s", (user_id,)
        )
        fio = user_info["фио"] if user_info else "Неизвестный"

        # Получаем график на текущий месяц
        now = datetime.now()
        start_date = now.replace(day=1).strftime("%Y-%m-%d")
        # Конец месяца (грубо +31 день)
        end_date = (now.replace(day=28) + timedelta(days=4)).replace(day=1) - timedelta(
            days=1
        )

        query = """
            SELECT дата, статус FROM график_работы 
            WHERE id_сотрудника = %s AND дата BETWEEN %s AND %s
            ORDER BY дата
        """
        schedule = Database.fetch_all(query, (user_id, start_date, end_date))

        # --- РИСОВАНИЕ ---
        c = self.c
        margin = 50
        y = self.height - margin

        # Логотип
        logo_path = os.path.join("assets", "logo.png")
        if os.path.exists(logo_path):
            c.drawImage(
                logo_path,
                margin,
                y - 50,
                width=50,
                height=50,
                preserveAspectRatio=True,
                mask="auto",
            )

        months_ru = [
            "",
            "Январь",
            "Февраль",
            "Март",
            "Апрель",
            "Май",
            "Июнь",
            "Июль",
            "Август",
            "Сентябрь",
            "Октябрь",
            "Ноябрь",
            "Декабрь",
        ]
        month_name = months_ru[now.month]

        c.setFont(self.font_name, 16)
        c.drawString(margin + 60, y - 20, f"ГРАФИК РАБОТЫ: {month_name} {now.year}")
        c.setFont(self.font_name, 12)
        c.drawString(margin + 60, y - 40, f"Сотрудник: {fio}")

        y -= 80

        # Таблица (Дата | День недели | Статус)
        c.setFont(self.font_name, 10)
        c.drawString(margin + 20, y, "Дата")
        c.drawString(margin + 120, y, "День недели")
        c.drawString(margin + 250, y, "Статус")
        c.line(margin, y - 5, margin + 400, y - 5)
        y -= 20

        days_ru = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

        for item in schedule:
            d = item["дата"]
            status = item["статус"]
            day_name = days_ru[d.weekday()]
            date_str = d.strftime("%d.%m.%Y")

            c.setFillColor(colors.black)
            c.drawString(margin + 20, y, date_str)
            c.drawString(margin + 120, y, day_name)

            # Цвет статуса
            if status == "рабочий":
                c.setFillColor(colors.green)
            elif status == "выходной":
                c.setFillColor(colors.red)
            elif status == "отпуск":
                c.setFillColor(colors.blue)
            elif status == "больничный":
                c.setFillColor(colors.orange)

            c.drawString(margin + 250, y, status.upper())

            y -= 15

            if y < 50:
                c.showPage()
                y = self.height - 50

        c.save()
        return True, "График сформирован"
