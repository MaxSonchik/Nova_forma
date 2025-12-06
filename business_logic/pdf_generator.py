from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib import colors
import os
from datetime import datetime
from db.database import Database

class PDFGenerator:
    def __init__(self, filename):
        self.filename = filename
        self.c = canvas.Canvas(filename, pagesize=A4)
        self.width, self.height = A4
        
        # Регистрация шрифта (ОБЯЗАТЕЛЬНО для русского языка)
        font_path = os.path.join("assets", "font.ttf")
        if os.path.exists(font_path):
            pdfmetrics.registerFont(TTFont('RusFont', font_path))
            self.font_name = 'RusFont'
        else:
            print("⚠️ Шрифт не найден! Русские буквы могут не отображаться.")
            self.font_name = 'Helvetica' # Стандартный (не поддерживает кириллицу)

    def generate_order_blank(self, order_id):
        """Генерация бланка заказа"""
        
        # 1. Получение данных (Заголовок)
        order_info = Database.fetch_one("""
            SELECT z.id_заказа, z.дата_заказа, z.дата_готовности, z.сумма_заказа, 
                   k.фио, k.номер_телефона, k.адрес
            FROM заказы z
            JOIN клиенты k ON z.id_клиента = k.id_клиента
            WHERE z.id_заказа = %s
        """, (order_id,))
        
        if not order_info:
            return False, "Заказ не найден"

        # 2. Получение состава заказа
        items = Database.fetch_all("""
            SELECT i.наименование, i.артикул_изделия, sz.количество_изделий, sz.цена_фиксированная
            FROM состав_заказа sz
            JOIN изделия i ON sz.id_изделия = i.id_изделия
            WHERE sz.id_заказа = %s
        """, (order_id,))

        # --- РИСОВАНИЕ ---
        c = self.c
        margin = 50
        y = self.height - margin

        # Логотип
        logo_path = os.path.join("assets", "logo.png")
        if os.path.exists(logo_path):
            c.drawImage(logo_path, margin, y - 60, width=60, height=60, preserveAspectRatio=True, mask='auto')

        # Заголовок компании
        c.setFont(self.font_name, 18)
        c.drawString(margin + 70, y - 25, "NOVA FORMA")
        c.setFont(self.font_name, 10)
        c.drawString(margin + 70, y - 40, "Мебельное производство")
        
        y -= 80

        # Заголовок документа
        c.setFont(self.font_name, 16)
        c.drawCentredString(self.width / 2, y, f"ЗАКАЗ №{order_info['id_заказа']}")
        y -= 30

        # Инфо о клиенте
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

        # Таблица товаров (Шапка)
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

        # Строки таблицы
        total_qty = 0
        for i, item in enumerate(items):
            name = item['наименование']
            qty = item['количество_изделий']
            price = item['цена_фиксированная']
            summ = qty * price
            total_qty += qty
            
            c.drawString(col_x[0] + 5, y, str(i + 1))
            c.drawString(col_x[1] + 5, y, name[:35]) # Обрезаем если длинное
            c.drawString(col_x[2] + 5, y, f"{qty} шт")
            c.drawString(col_x[3] + 5, y, f"{price:,.0f}")
            c.drawString(col_x[4] + 5, y, f"{summ:,.0f}")
            
            c.line(margin, y - 2, self.width - margin, y - 2) # Линия
            y -= 20
            
            if y < 50: # Новая страница, если места нет
                c.showPage()
                y = self.height - 50

        # Итого
        y -= 20
        c.setFont(self.font_name, 14)
        c.drawRightString(self.width - margin, y, f"ИТОГО: {order_info['сумма_заказа']:,.2f} ₽")
        
        # Подписи
        y -= 60
        c.setFont(self.font_name, 10)
        c.line(margin, y, margin + 150, y)
        c.drawString(margin, y - 15, "Менеджер")
        
        c.line(self.width - margin - 150, y, self.width - margin, y)
        c.drawString(self.width - margin - 150, y - 15, "Клиент")

        c.save()
        return True, "Отчет сформирован"