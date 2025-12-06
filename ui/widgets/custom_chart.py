from PyQt6.QtCore import QPointF, Qt
from PyQt6.QtGui import QColor, QFont, QLinearGradient, QPainter, QPainterPath, QPen
from PyQt6.QtWidgets import QWidget


class CustomChart(QWidget):
    def __init__(self, data_dict, title="Динамика"):
        super().__init__()
        self.data = data_dict  # {'2023-01-01': 100, ...}
        self.title = title
        self.setMinimumSize(600, 400)
        self.setStyleSheet("background-color: white; border-radius: 10px;")

    def paintEvent(self, event):
        if not self.data:
            return

        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # Размеры и отступы
        w = self.width()
        h = self.height()
        padding = 60

        # Данные
        dates = list(self.data.keys())
        values = list(self.data.values())
        max_val = max(values) if values else 100
        min_val = 0  # Всегда от 0

        # Масштабирование
        step_x = (w - 2 * padding) / (len(dates) - 1) if len(dates) > 1 else 0
        scale_y = (h - 2 * padding) / (max_val - min_val) if max_val > 0 else 1

        # --- 1. Сетка и Оси ---
        painter.setPen(QPen(QColor("#E0E0E0"), 1, Qt.PenStyle.DashLine))
        # Горизонтальные линии (5 штук)
        for i in range(6):
            y = h - padding - (i * (h - 2 * padding) / 5)
            painter.drawLine(padding, int(y), w - padding, int(y))
            # Подписи оси Y
            val = min_val + (i * (max_val - min_val) / 5)
            painter.drawText(
                5, int(y) + 5, 50, 20, Qt.AlignmentFlag.AlignRight, f"{val:,.0f}"
            )

        # --- 2. Линия графика ---
        path = QPainterPath()
        points = []

        for i, val in enumerate(values):
            x = padding + i * step_x
            y = h - padding - (val - min_val) * scale_y
            points.append(QPointF(x, y))

            if i == 0:
                path.moveTo(x, y)
            else:
                path.lineTo(x, y)

        # Рисуем линию
        pen = QPen(QColor("#3498DB"), 3)
        painter.setPen(pen)
        painter.drawPath(path)

        # --- 3. Градиент под графиком (Красота) ---
        fill_path = QPainterPath(path)
        fill_path.lineTo(points[-1].x(), h - padding)
        fill_path.lineTo(points[0].x(), h - padding)
        fill_path.closeSubpath()

        grad = QLinearGradient(0, 0, 0, h)
        grad.setColorAt(0, QColor(52, 152, 219, 100))  # Полупрозрачный синий
        grad.setColorAt(1, QColor(52, 152, 219, 0))
        painter.fillPath(fill_path, grad)

        # --- 4. Точки и Даты ---
        for i, pt in enumerate(points):
            # Точка
            painter.setBrush(QColor("white"))
            painter.setPen(QPen(QColor("#3498DB"), 2))
            painter.drawEllipse(pt, 4, 4)

            # Дата (рисуем каждую 3-ю или 5-ю, чтобы не накладывались)
            if len(dates) < 10 or i % (len(dates) // 10 + 1) == 0:
                painter.setPen(QPen(QColor("#7F8C8D"), 1))
                # Поворот текста даты
                painter.save()
                painter.translate(pt.x(), h - padding + 20)
                painter.rotate(-45)
                # Берем только день и месяц
                d_str = dates[i].strftime("%d.%m")
                painter.drawText(0, 0, d_str)
                painter.restore()

        # Заголовок
        painter.setPen(QColor("#2C3E50"))
        painter.setFont(QFont("Arial", 14, QFont.Weight.Bold))
        painter.drawText(0, 20, w, 30, Qt.AlignmentFlag.AlignCenter, self.title)
