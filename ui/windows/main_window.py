
import qtawesome as qta
from PyQt6.QtCore import QSize, Qt, pyqtSignal
from PyQt6.QtWidgets import (
    QFrame,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QPushButton,
    QStackedWidget,
    QVBoxLayout,
    QWidget,
)

from ui.widgets.clients_tab import ClientsTab
from ui.widgets.components_tab import ComponentsTab
from ui.widgets.dashboard_tab import DashboardTab
from ui.widgets.employees_tab import EmployeesTab
from ui.widgets.manager_schedule_tab import ManagerScheduleTab
from ui.widgets.nomenclature_tab import NomenclatureTab
from ui.widgets.orders_tab import OrdersTab
from ui.widgets.production_planning_tab import ProductionPlanningTab
from ui.widgets.production_tab import ProductionTab
from ui.widgets.purchases_tab import PurchasesTab
from ui.widgets.schedule_tab import ScheduleTab
from ui.widgets.warehouse_tab import WarehouseTab


class MainWindow(QMainWindow):
                                         
    logoutSignal = pyqtSignal()

    def __init__(self, user_id, role, fio):
        super().__init__()
        self.user_id = user_id
        self.fio = fio

                                                  
                                                       
        self.role = str(role).lower().strip()

                                                                  
        print(f"DEBUG: Инициализация окна для роли: '{self.role}' (User ID: {user_id})")

                        
        self.setWindowTitle(f"Nova Forma CRM - {fio} ({self.role})")
        self.resize(1200, 800)

                                  
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        self.main_layout = QHBoxLayout(central_widget)
        self.main_layout.setContentsMargins(0, 0, 0, 0)
        self.main_layout.setSpacing(0)

                          
        self.setup_sidebar()
        self.setup_content_area()
        self.populate_menu_by_role()

    def setup_sidebar(self):
        """Создание левой боковой панели"""
        self.sidebar = QFrame()
        self.sidebar.setObjectName("Sidebar")

        self.sidebar_layout = QVBoxLayout(self.sidebar)
        self.sidebar_layout.setContentsMargins(0, 20, 0, 20)
        self.sidebar_layout.setSpacing(10)

                                             
        user_layout = QVBoxLayout()
        user_layout.setContentsMargins(15, 0, 15, 20)

                                
        icon_map = {
            "директор": "fa5s.user-tie",
            "менеджер": "fa5s.user-check",
            "сборщик": "fa5s.hard-hat",
        }
                                                         
        icon_name = icon_map.get(self.role, "fa5s.user")

        avatar_label = QLabel()
        avatar_label.setPixmap(qta.icon(icon_name, color="white").pixmap(QSize(40, 40)))

        name_label = QLabel(self.fio)
        name_label.setObjectName("UserName")
        name_label.setWordWrap(True)

        role_label = QLabel(self.role.upper())
        role_label.setObjectName("UserInfo")

        user_layout.addWidget(avatar_label)
        user_layout.addWidget(name_label)
        user_layout.addWidget(role_label)

        self.sidebar_layout.addLayout(user_layout)

                                                  
        self.menu_layout = QVBoxLayout()
        self.sidebar_layout.addLayout(self.menu_layout)
        self.sidebar_layout.addStretch()            

                         
        logout_btn = QPushButton("Выход")
        logout_btn.setObjectName("LogoutButton")
        logout_btn.setIcon(qta.icon("fa5s.sign-out-alt", color="#E74C3C"))
        logout_btn.clicked.connect(self.handle_logout)
        self.sidebar_layout.addWidget(logout_btn)

        self.main_layout.addWidget(self.sidebar)

    def setup_content_area(self):
        """Правая часть с контентом"""
        self.content_area = QFrame()
        self.content_area.setObjectName("ContentArea")

        self.stacked_widget = QStackedWidget()

        content_layout = QVBoxLayout(self.content_area)
        content_layout.setContentsMargins(20, 20, 20, 20)
        content_layout.addWidget(self.stacked_widget)

        self.main_layout.addWidget(self.content_area)

    def add_menu_item(self, title, icon_name, widget):
        """Добавляет кнопку в меню и страницу в стек"""
        btn = QPushButton(title)
        btn.setProperty("class", "NavButton")
        btn.setIcon(qta.icon(icon_name, color="#BDC3C7"))                            
        btn.setCheckable(True)
        btn.setAutoExclusive(True)

        index = self.stacked_widget.addWidget(widget)

        btn.clicked.connect(lambda: self.stacked_widget.setCurrentIndex(index))

        self.menu_layout.addWidget(btn)

        if self.stacked_widget.count() == 1:
            btn.setChecked(True)

    def create_placeholder(self, text):
        """Создает временную заглушку"""
        page = QLabel(f"Раздел: {text}\n(В разработке)")
        page.setAlignment(Qt.AlignmentFlag.AlignCenter)
        page.setStyleSheet("font-size: 24px; color: #95A5A6; font-weight: bold;")
        return page

    def populate_menu_by_role(self):
        """Заполняет меню в зависимости от роли"""

        if self.role == "директор":
            self.add_menu_item("Дашборд", "fa5s.chart-line", DashboardTab())
            self.add_menu_item("Номенклатура", "fa5s.boxes", NomenclatureTab())
            self.add_menu_item("Заготовки", "fa5s.puzzle-piece", ComponentsTab())
            self.add_menu_item("Закупки", "fa5s.shopping-cart", PurchasesTab())
            self.add_menu_item("Склад", "fa5s.warehouse", WarehouseTab(self.user_id))
            self.add_menu_item("Заказы", "fa5s.file-invoice", OrdersTab(self.user_id))
            self.add_menu_item("План работ", "fa5s.tasks", ProductionPlanningTab(self.user_id))
            self.add_menu_item("График", "fa5s.calendar-alt", ManagerScheduleTab())
            self.add_menu_item("Сотрудники", "fa5s.users-cog", EmployeesTab())

        elif self.role == "менеджер":
            self.add_menu_item("Заказы", "fa5s.file-invoice", OrdersTab(self.user_id))
            self.add_menu_item("План работ", "fa5s.tasks", ProductionPlanningTab(self.user_id))
            self.add_menu_item("Клиенты", "fa5s.users", ClientsTab())
            self.add_menu_item("Номенклатура", "fa5s.boxes", NomenclatureTab())
            self.add_menu_item("Склад", "fa5s.warehouse", WarehouseTab(self.user_id))

        elif self.role == "сборщик":
            self.add_menu_item("Производство", "fa5s.hammer", ProductionTab(self.user_id, self.role))
            self.add_menu_item("График", "fa5s.calendar-alt", ScheduleTab(self.user_id))

        else:
                                                            
            self.add_menu_item(
                "Ошибка доступа",
                "fa5s.exclamation-circle",
                self.create_placeholder(f"Роль '{self.role}' не найдена"),
            )

    def handle_logout(self):
        self.logoutSignal.emit()
        self.close()

    def switch_to_production_plan(self, order_id):
        """Переключение на вкладку План работ и фильтрация по заказу"""
                                          
        for i in range(self.stacked_widget.count()):
            widget = self.stacked_widget.widget(i)
            if isinstance(widget, ProductionPlanningTab):
                self.stacked_widget.setCurrentIndex(i)
                                                                 
                btn = self.menu_layout.itemAt(i).widget()
                if btn: btn.setChecked(True)
                
                              
                widget.filter_by_order(order_id)
                break
