import qtawesome as qta
from PyQt6.QtCore import (
    QDate,
    QEasingCurve,
    QPropertyAnimation,
    Qt,
    pyqtSignal,
)
from PyQt6.QtGui import QColor, QCursor
from PyQt6.QtWidgets import (
    QDateEdit,
    QFrame,
    QGraphicsDropShadowEffect,
    QGridLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

from db.database import Database
from ui.dialogs.detail_stats_dialog import DetailStatsDialog
from ui.widgets.toast import Toast


class ClickableCard(QFrame):
    """Карточка с плавной анимацией тени"""

    clicked = pyqtSignal()

    def __init__(self, title, value, icon_name, color_hex):
        super().__init__()
        self.setCursor(QCursor(Qt.CursorShape.PointingHandCursor))

        # Стиль статический, чтобы не было дерганий при ховере
        self.setStyleSheet(
            f"""
            QFrame {{
                background-color: white;
                border-radius: 12px;
                border-left: 6px solid {color_hex};
                border-right: 1px solid #ECF0F1; 
                border-bottom: 1px solid #ECF0F1;
                border-top: 1px solid #ECF0F1;
            }}
            QLabel {{ background: transparent; border: none; }}
        """
        )
        self.setFixedSize(240, 110)

        # --- Эффект Тени ---
        self.shadow = QGraphicsDropShadowEffect(self)
        self.shadow.setBlurRadius(10)  # Начальное размытие
        self.shadow.setXOffset(0)
        self.shadow.setYOffset(3)
        self.shadow.setColor(QColor(0, 0, 0, 30))  # Прозрачный черный
        self.setGraphicsEffect(self.shadow)

        # Анимация Размытия (Blur)
        self.anim_blur = QPropertyAnimation(self.shadow, b"blurRadius")
        self.anim_blur.setDuration(200)
        self.anim_blur.setEasingCurve(QEasingCurve.Type.OutCubic)

        # Layout
        layout = QVBoxLayout(self)
        top = QHBoxLayout()
        lbl_title = QLabel(title)
        lbl_title.setStyleSheet("color: #7F8C8D; font-weight: bold; font-size: 13px;")
        icon = QLabel()
        icon.setPixmap(qta.icon(icon_name, color=color_hex).pixmap(24, 24))
        top.addWidget(lbl_title)
        top.addStretch()
        top.addWidget(icon)

        self.lbl_value = QLabel(value)
        self.lbl_value.setStyleSheet(
            "color: #2C3E50; font-size: 22px; font-weight: bold;"
        )

        layout.addLayout(top)
        layout.addWidget(self.lbl_value)

    def set_value(self, value):
        self.lbl_value.setText(str(value))

    def mousePressEvent(self, event):
        if event.button() == Qt.MouseButton.LeftButton:
            self.clicked.emit()
        super().mousePressEvent(event)

    def enterEvent(self, event):
        """Наведение: Тень становится зеленой и большой"""
        self.anim_blur.stop()
        self.shadow.setColor(QColor("#27AE60"))  # Зеленая тень
        self.anim_blur.setEndValue(30)  # Большое размытие
        self.anim_blur.start()
        super().enterEvent(event)

    def leaveEvent(self, event):
        """Уход: Тень возвращается в серый и уменьшается"""
        self.anim_blur.stop()
        self.shadow.setColor(QColor(0, 0, 0, 30))  # Черная прозрачная
        self.anim_blur.setEndValue(10)
        self.anim_blur.start()
        super().leaveEvent(event)


class DashboardTab(QWidget):
    def __init__(self):
        super().__init__()
        self.setup_ui()
        self.date_from.setDate(QDate(QDate.currentDate().year(), 1, 1))
        self.date_to.setDate(QDate.currentDate())
        self.load_data()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        # Фильтры
        filter_group = QGroupBox("Период статистики")
        filter_layout = QHBoxLayout(filter_group)

        self.date_from = QDateEdit()
        self.date_from.setCalendarPopup(True)
        self.date_to = QDateEdit()
        self.date_to.setCalendarPopup(True)

        btn_apply = QPushButton("Применить")
        btn_apply.setIcon(qta.icon("fa5s.sync"))
        btn_apply.clicked.connect(self.load_data)

        filter_layout.addWidget(QLabel("С:"))
        filter_layout.addWidget(self.date_from)
        filter_layout.addWidget(QLabel("По:"))
        filter_layout.addWidget(self.date_to)
        filter_layout.addWidget(btn_apply)
        filter_layout.addStretch()

        layout.addWidget(filter_group)

        # Сетка
        self.grid = QGridLayout()
        self.grid.setSpacing(20)  # Больше воздуха

        # Ряд 1
        self.c_revenue = self.add_card(
            0, 0, "Выручка", "0 ₽", "fa5s.coins", "#27AE60", "revenue"
        )
        self.c_expense = self.add_card(
            0, 1, "Расходы", "0 ₽", "fa5s.shopping-cart", "#E74C3C", "expenses"
        )
        self.c_profit = self.add_card(
            0, 2, "Прибыль (расч.)", "0 ₽", "fa5s.chart-line", "#3498DB", "profit"
        )
        self.c_orders = self.add_card(
            0, 3, "Заказов закрыто", "0", "fa5s.check-double", "#F39C12", "orders_count"
        )

        # Ряд 2
        self.c_avg = self.add_card(
            1, 0, "Средний чек", "0 ₽", "fa5s.receipt", "#9B59B6", "avg_check"
        )
        self.c_margin = self.add_card(
            1, 1, "Рентабельность", "0 %", "fa5s.percent", "#1ABC9C", "profit"
        )
        self.c_cancel = self.add_card(
            1, 2, "Процент отмен", "0 %", "fa5s.ban", "#7F8C8D", "cancel_rate"
        )
        self.c_active = self.add_card(
            1, 3, "Активных сотрудн.", "0", "fa5s.users", "#34495E", None
        )

        layout.addLayout(self.grid)
        layout.addStretch()

    def add_card(self, row, col, title, val, icon, color, metric_key):
        card = ClickableCard(title, val, icon, color)
        self.grid.addWidget(card, row, col)
        if metric_key:
            card.clicked.connect(lambda: self.open_detail(title, metric_key))
        return card

    def load_data(self):
        d_start = self.date_from.date().toString("yyyy-MM-dd")
        d_end = self.date_to.date().toString("yyyy-MM-dd")

        # SQL с учетом ВСЕХ финальных статусов
        # 1. Выручка (выполнен + завершен + отгружен)
        rev_res = Database.fetch_one(
            """
            SELECT COALESCE(SUM(сумма_заказа), 0) as rev, COUNT(*) as cnt 
            FROM заказы 
            WHERE status IN ('выполнен', 'завершен', 'отгружен') 
              AND дата_заказа BETWEEN %s AND %s
        """.replace(
                "status", "статус"
            ),
            (d_start, d_end),
        )  # fix column name just in case

        revenue = float(rev_res["rev"])
        orders_count = int(rev_res["cnt"])

        # 2. Расходы
        exp_res = Database.fetch_one(
            """
            SELECT COALESCE(SUM(sz.количество * sz.цена_закупки), 0) as exp
            FROM закупки_материалов zm
            JOIN состав_закупки sz ON zm.id_закупки = sz.id_закупки
            WHERE zm.статус='выполнено' AND дата_закупки BETWEEN %s AND %s
        """,
            (d_start, d_end),
        )
        expenses = float(exp_res["exp"])

        # 3. Отмены
        cancel_res = Database.fetch_one(
            """
            SELECT COUNT(*) as cnt FROM заказы 
            WHERE статус='отменен' AND дата_заказа BETWEEN %s AND %s
        """,
            (d_start, d_end),
        )
        cancels = int(cancel_res["cnt"])

        # 4. Сотрудники
        staff_res = Database.fetch_one(
            "SELECT COUNT(*) as cnt FROM сотрудники WHERE дата_увольнения IS NULL"
        )
        staff = staff_res["cnt"]

        # Расчеты
        profit = revenue - expenses
        avg_check = revenue / orders_count if orders_count > 0 else 0
        margin = (profit / revenue * 100) if revenue > 0 else 0
        total_orders = orders_count + cancels
        cancel_rate = (cancels / total_orders * 100) if total_orders > 0 else 0

        self.c_revenue.set_value(f"{revenue:,.0f} ₽")
        self.c_expense.set_value(f"{expenses:,.0f} ₽")
        self.c_profit.set_value(f"{profit:,.0f} ₽")
        self.c_orders.set_value(str(orders_count))
        self.c_avg.set_value(f"{avg_check:,.0f} ₽")
        self.c_margin.set_value(f"{margin:.1f} %")
        self.c_cancel.set_value(f"{cancel_rate:.1f} %")
        self.c_active.set_value(str(staff))

    def open_detail(self, title, metric_type):
        d_start = self.date_from.date().toString("yyyy-MM-dd")
        d_end = self.date_to.date().toString("yyyy-MM-dd")

        query = self.get_metric_query(metric_type)
        if not query:
            return

        rows = Database.fetch_all(query, (d_start, d_end))

        data = {}
        for row in rows:
            if row["d"]:
                data[row["d"]] = float(row["val"])

        if not data:
            Toast.warning(
                self, "Нет данных", f"За период {d_start} - {d_end}\nнет статистики."
            )
            return

        dialog = DetailStatsDialog(
            self, title, metric_type, d_start, d_end, preloaded_data=data
        )
        dialog.exec()

    def get_metric_query(self, metric_type):
        # ВАЖНО: Используем кириллицу 'статус' для названий колонок в WHERE
        if metric_type == "revenue":
            return """
                SELECT дата_заказа as d, SUM(сумма_заказа) as val FROM заказы 
                WHERE статус IN ('выполнен', 'завершен', 'отгружен') 
                AND дата_заказа BETWEEN %s AND %s GROUP BY d ORDER BY d
            """
        elif metric_type == "expenses":
            return """
                SELECT дата_закупки as d, SUM(sz.количество * sz.цена_закупки) as val
                FROM закупки_материалов zm JOIN состав_закупки sz ON zm.id_закупки = sz.id_закупки
                WHERE zm.статус='выполнено' AND дата_закупки BETWEEN %s AND %s GROUP BY d ORDER BY d
            """
        elif metric_type == "profit":
            return """
                SELECT дата_заказа as d, SUM(сумма_заказа) * 0.3 as val FROM заказы 
                WHERE статус IN ('выполнен', 'завершен', 'отгружен') 
                AND дата_заказа BETWEEN %s AND %s GROUP BY d ORDER BY d
            """
        elif metric_type == "orders_count":
            return """
                SELECT дата_заказа as d, COUNT(*) as val FROM заказы 
                WHERE статус IN ('выполнен', 'завершен', 'отгружен') 
                AND дата_заказа BETWEEN %s AND %s GROUP BY d ORDER BY d
            """
        elif metric_type == "avg_check":
            return """
                SELECT дата_заказа as d, AVG(сумма_заказа) as val FROM заказы 
                WHERE статус IN ('выполнен', 'завершен', 'отгружен') 
                AND дата_заказа BETWEEN %s AND %s GROUP BY d ORDER BY d
            """
        elif metric_type == "cancel_rate":
            return """
                SELECT дата_заказа as d, (COUNT(*) FILTER (WHERE статус = 'отменен')::numeric / COUNT(*)) * 100 as val
                FROM заказы WHERE дата_заказа BETWEEN %s AND %s GROUP BY d ORDER BY d
            """
        return None
