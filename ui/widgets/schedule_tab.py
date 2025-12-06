from PyQt6.QtWidgets import (QWidget, QVBoxLayout, QCalendarWidget, QLabel, 
                             QHBoxLayout, QFrame)
from PyQt6.QtCore import Qt, QDate
from PyQt6.QtGui import QColor, QTextCharFormat, QBrush
from db.database import Database
from PyQt6.QtWidgets import QPushButton, QFileDialog # Обнови
import qtawesome as qta # Обнови
from business_logic.pdf_generator import PDFGenerator
from ui.widgets.toast import Toast

class ScheduleTab(QWidget):
    def __init__(self, user_id):
        super().__init__()
        self.user_id = user_id
        self.setup_ui()
        self.load_schedule()

    def setup_ui(self):
        layout = QVBoxLayout(self)
        
        # Легенда (Описание цветов)
        legend_layout = QHBoxLayout()
        legend_layout.addWidget(self.create_legend_item("#27AE60", "Рабочий"))
        legend_layout.addWidget(self.create_legend_item("#E74C3C", "Выходной"))
        legend_layout.addWidget(self.create_legend_item("#3498DB", "Отпуск"))
        legend_layout.addWidget(self.create_legend_item("#F1C40F", "Больничный"))
        legend_layout.addStretch()

        btn_print = QPushButton("Печать")
        btn_print.setIcon(qta.icon('fa5s.print'))
        btn_print.clicked.connect(self.print_schedule)
        legend_layout.addWidget(btn_print)
            
        layout.addLayout(legend_layout)
        layout.addSpacing(10)

        # Календарь
        self.calendar = QCalendarWidget()
        self.calendar.setGridVisible(True)
        self.calendar.setVerticalHeaderFormat(QCalendarWidget.VerticalHeaderFormat.NoVerticalHeader)
        
        # Стилизация календаря
        self.calendar.setStyleSheet("""
            QCalendarWidget QWidget { background-color: white; }
            QCalendarWidget QToolButton { color: black; icon-size: 24px; }
            QCalendarWidget QMenu { background-color: white; }
            QCalendarWidget QSpinBox { background-color: white; color: black; }
            QCalendarWidget QAbstractItemView:enabled { font-size: 14px; color: black; }
        """)
        
        layout.addWidget(self.calendar)

    def create_legend_item(self, color, text):
        container = QFrame()
        l = QHBoxLayout(container)
        l.setContentsMargins(0,0,0,0)
        
        box = QLabel()
        box.setFixedSize(16, 16)
        box.setStyleSheet(f"background-color: {color}; border-radius: 3px;")
        
        lbl = QLabel(text)
        
        l.addWidget(box)
        l.addWidget(lbl)
        return container

    def load_schedule(self):
        # Получаем график сотрудника
        query = "SELECT дата, статус FROM график_работы WHERE id_сотрудника = %s"
        schedule = Database.fetch_all(query, (self.user_id,))
        
        for entry in schedule:
            date_obj = entry['дата'] # datetime.date
            status = entry['статус']
            
            # Преобразуем в QDate
            qdate = QDate(date_obj.year, date_obj.month, date_obj.day)
            
            # Определяем цвет
            fmt = QTextCharFormat()
            if status == 'рабочий':
                fmt.setBackground(QBrush(QColor("#27AE60"))) # Зеленый
                fmt.setForeground(QBrush(QColor("white")))
            elif status == 'выходной':
                fmt.setBackground(QBrush(QColor("#E74C3C"))) # Красный
                fmt.setForeground(QBrush(QColor("white")))
            elif status == 'отпуск':
                fmt.setBackground(QBrush(QColor("#3498DB"))) # Синий
                fmt.setForeground(QBrush(QColor("white")))
            elif status == 'больничный':
                fmt.setBackground(QBrush(QColor("#F1C40F"))) # Желтый
                fmt.setForeground(QBrush(QColor("black")))
            
            self.calendar.setDateTextFormat(qdate, fmt)
    def print_schedule(self):
        file_path, _ = QFileDialog.getSaveFileName(self, "Сохранить график", "Schedule.pdf", "PDF (*.pdf)")
        if not file_path: return
        
        try:
            gen = PDFGenerator(file_path)
            success, msg = gen.generate_assembler_schedule(self.user_id)
            if success:
                Toast.success(self, "Успешно", f"График сохранен:\n{file_path}")
            else:
                Toast.error(self, "Ошибка", msg)
        except Exception as e:
            Toast.error(self, "Ошибка", str(e))