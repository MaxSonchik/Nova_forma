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

                             
        self.shadow = QGraphicsDropShadowEffect(self)
        self.shadow.setBlurRadius(10)                      
        self.shadow.setXOffset(0)
        self.shadow.setYOffset(3)
        self.shadow.setColor(QColor(0, 0, 0, 30))                     
        self.setGraphicsEffect(self.shadow)

                                  
        self.anim_blur = QPropertyAnimation(self.shadow, b"blurRadius")
        self.anim_blur.setDuration(200)
        self.anim_blur.setEasingCurve(QEasingCurve.Type.OutCubic)

                
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
        self.shadow.setColor(QColor("#27AE60"))                
        self.anim_blur.setEndValue(30)                    
        self.anim_blur.start()
        super().enterEvent(event)

    def leaveEvent(self, event):
        """Уход: Тень возвращается в серый и уменьшается"""
        self.anim_blur.stop()
        self.shadow.setColor(QColor(0, 0, 0, 30))                     
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

               
        self.grid = QGridLayout()
        self.grid.setSpacing(20)                  

               
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

        try:
                                      
                                                                             
            res = Database.fetch_one(
                "SELECT * FROM sp_get_dashboard_summary(%s, %s)", 
                (d_start, d_end)
            )

            if not res:
                                                                             
                revenue = 0.0
                orders_count = 0
                expenses = 0.0
                cancels = 0
                staff = 0
            else:
                revenue = float(res.get("revenue") or 0)
                orders_count = int(res.get("orders_count") or 0)
                expenses = float(res.get("expenses") or 0)
                cancels = int(res.get("cancels") or 0)
                staff = int(res.get("staff_count") or 0)

                                                                                       
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
            
        except Exception as e:
            print(f"Error loading dashboard: {e}")
            Toast.error(self, "Ошибка", "Не удалось загрузить данные")

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
                                                   
        if metric_type == "revenue":
            return "SELECT * FROM sp_get_sales_chart_data(%s, %s)"
        elif metric_type == "expenses":
            return "SELECT * FROM sp_get_expenses_chart_data(%s, %s)"
        elif metric_type == "profit":
                                                                         
            return "SELECT * FROM sp_get_profit_chart_data(%s, %s)"
        elif metric_type == "orders_count":
            return "SELECT * FROM sp_get_orders_count_chart_data(%s, %s)"
        elif metric_type == "avg_check":
            return "SELECT * FROM sp_get_avg_check_chart_data(%s, %s)"
        elif metric_type == "cancel_rate":
            return "SELECT * FROM sp_get_cancel_rate_chart_data(%s, %s)"
        return None
