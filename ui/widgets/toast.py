import qtawesome as qta
from PyQt6.QtCore import QEasingCurve, QPropertyAnimation, Qt, QTimer
from PyQt6.QtGui import QBrush, QColor, QPainter
from PyQt6.QtWidgets import QGraphicsOpacityEffect, QHBoxLayout, QLabel, QWidget


class Toast(QWidget):
    # Настройка тем: (Цвет фона, Цвет иконки)
    # Используем нежные пастельные тона для фона и насыщенные для иконки
    THEMES = {
        "SUCCESS": {
            "bg": "#D4EDDA",  # Нежно-зеленый
            "icon_color": "#155724",  # Темно-зеленый
            "icon": "fa5s.check-circle",
        },
        "WARNING": {
            "bg": "#FFF3CD",  # Нежно-желтый/оранжевый
            "icon_color": "#856404",  # Темно-оранжевый
            "icon": "fa5s.exclamation-triangle",
        },
        "ERROR": {
            "bg": "#F8D7DA",  # Нежно-красный
            "icon_color": "#721C24",  # Темно-красный
            "icon": "fa5s.times-circle",
        },
        "INFO": {
            "bg": "#D1ECF1",  # Нежно-голубой
            "icon_color": "#0C5460",  # Темно-синий
            "icon": "fa5s.info-circle",
        },
    }

    def __init__(self, parent, title, message, theme_key):
        super().__init__(parent)
        self.setWindowFlags(Qt.WindowType.FramelessWindowHint | Qt.WindowType.SubWindow)
        self.setAttribute(Qt.WidgetAttribute.WA_TranslucentBackground)
        self.setAttribute(Qt.WidgetAttribute.WA_DeleteOnClose)

        # СБРОС ГЛОБАЛЬНЫХ СТИЛЕЙ (Убирает белые прямоугольники)
        self.setStyleSheet("background: transparent; border: none;")

        theme = self.THEMES.get(theme_key, self.THEMES["INFO"])
        self.bg_color = QColor(theme["bg"])

        # Настройка размеров
        self.setFixedWidth(350)
        self.setFixedHeight(85)

        # Layout
        layout = QHBoxLayout(self)
        layout.setContentsMargins(20, 10, 20, 10)
        layout.setSpacing(15)

        # Иконка
        icon_label = QLabel()
        # Иконка цветная, под цвет темы
        icon_label.setPixmap(
            qta.icon(theme["icon"], color=theme["icon_color"]).pixmap(32, 32)
        )
        icon_label.setStyleSheet("background: transparent; border: none;")  # Страховка
        layout.addWidget(icon_label)

        # Текст (Черный/Темный)
        msg_label = QLabel(
            f"<b style='font-size:14px; color:#2C3E50'>{title}</b><br><span style='font-size:13px; color:#404040'>{message}</span>"
        )
        msg_label.setWordWrap(True)
        msg_label.setStyleSheet("background: transparent; border: none;")  # Страховка
        layout.addWidget(msg_label, 1)

        # Анимация появления
        self.opacity_effect = QGraphicsOpacityEffect(self)
        self.setGraphicsEffect(self.opacity_effect)

        self.anim = QPropertyAnimation(self.opacity_effect, b"opacity")
        self.anim.setDuration(400)
        self.anim.setStartValue(0)
        self.anim.setEndValue(1)
        self.anim.setEasingCurve(QEasingCurve.Type.OutCubic)
        self.anim.start()

        # Таймер
        self.timer = QTimer()
        self.timer.timeout.connect(self.fade_out)
        self.timer.start(4000)

        self.adjust_position(parent)
        self.show()

    def adjust_position(self, parent):
        if not parent:
            return
        p_geo = parent.geometry()
        # Отступ 20px от правого нижнего края
        x = p_geo.width() - self.width() - 20
        y = p_geo.height() - self.height() - 20
        self.move(x, y)

    def fade_out(self):
        self.anim.setDirection(QPropertyAnimation.Direction.Backward)
        self.anim.setEndValue(0)
        self.anim.setDuration(400)
        self.anim.finished.connect(self.close)
        self.anim.start()

    def paintEvent(self, event):
        painter = QPainter(self)
        painter.setRenderHint(QPainter.RenderHint.Antialiasing)

        # Устанавливаем цвет фона с прозрачностью (Alpha = 230 из 255)
        color = QColor(self.bg_color)
        color.setAlpha(235)

        brush = QBrush(color)
        painter.setBrush(brush)
        painter.setPen(Qt.PenStyle.NoPen)

        rect = self.rect()
        painter.drawRoundedRect(rect, 10, 10)

    # --- Статические методы ---
    @staticmethod
    def notify(parent, title, message, theme_key):
        top_widget = parent.window()
        Toast(top_widget, title, message, theme_key)

    @staticmethod
    def success(parent, title, message):
        Toast.notify(parent, title, message, "SUCCESS")

    @staticmethod
    def warning(parent, title, message):
        Toast.notify(parent, title, message, "WARNING")

    @staticmethod
    def error(parent, title, message):
        Toast.notify(parent, title, message, "ERROR")
