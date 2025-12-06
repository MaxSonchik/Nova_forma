import sys
from PyQt6.QtWidgets import (QMainWindow, QWidget, QVBoxLayout, QHBoxLayout, 
                             QPushButton, QLabel, QStackedWidget, QFrame)
from PyQt6.QtCore import Qt, QSize, pyqtSignal
import qtawesome as qta

from ui.widgets.orders_tab import OrdersTab

class MainWindow(QMainWindow):
    # Сигнал для выхода из учетной записи
    logoutSignal = pyqtSignal()

    def __init__(self, user_id, role, fio):
        super().__init__()
        self.user_id = user_id
        self.fio = fio
        
        # 1. НОРМАЛИЗАЦИЯ РОЛИ (Сразу при старте!)
        # Приводим к нижнему регистру и убираем пробелы
        self.role = str(role).lower().strip()
        
        # Отладка в консоль (чтобы видеть, что программа "поняла")
        print(f"DEBUG: Инициализация окна для роли: '{self.role}' (User ID: {user_id})")

        # Настройка окна
        self.setWindowTitle(f"Nova Forma CRM - {fio} ({self.role})")
        self.resize(1200, 800)
        
        # Основной виджет и layout
        central_widget = QWidget()
        self.setCentralWidget(central_widget)
        self.main_layout = QHBoxLayout(central_widget)
        self.main_layout.setContentsMargins(0, 0, 0, 0)
        self.main_layout.setSpacing(0)

        # Инициализация UI
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
        
        # 1. Блок пользователя (Аватар + Имя)
        user_layout = QVBoxLayout()
        user_layout.setContentsMargins(15, 0, 15, 20)
        
        # Иконка зависит от роли
        icon_map = {
            'директор': 'fa5s.user-tie',
            'менеджер': 'fa5s.user-check',
            'сборщик': 'fa5s.hard-hat'
        }
        # Используем get, по умолчанию ставим просто user
        icon_name = icon_map.get(self.role, 'fa5s.user')
        
        avatar_label = QLabel()
        avatar_label.setPixmap(qta.icon(icon_name, color='white').pixmap(QSize(40, 40)))
        
        name_label = QLabel(self.fio)
        name_label.setObjectName("UserName")
        name_label.setWordWrap(True)
        
        role_label = QLabel(self.role.upper())
        role_label.setObjectName("UserInfo")
        
        user_layout.addWidget(avatar_label)
        user_layout.addWidget(name_label)
        user_layout.addWidget(role_label)
        
        self.sidebar_layout.addLayout(user_layout)
        
        # 2. Меню навигации (контейнер для кнопок)
        self.menu_layout = QVBoxLayout()
        self.sidebar_layout.addLayout(self.menu_layout)
        self.sidebar_layout.addStretch() # Растяжка
        
        # 3. Кнопка Выход
        logout_btn = QPushButton("Выход")
        logout_btn.setObjectName("LogoutButton")
        logout_btn.setIcon(qta.icon('fa5s.sign-out-alt', color='#E74C3C'))
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
        btn.setIcon(qta.icon(icon_name, color='#BDC3C7')) # Цвет иконки по умолчанию
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
        
        # ВАЖНО: Роли должны быть написаны маленькими буквами (как в БД)
        if self.role == 'директор':
            self.add_menu_item("Дашборд", "fa5s.chart-line", self.create_placeholder("Дашборд Директора"))
            self.add_menu_item("Персонал", "fa5s.users", self.create_placeholder("Управление Персоналом"))
            self.add_menu_item("Закупки", "fa5s.shopping-cart", self.create_placeholder("Закупки Материалов"))
            self.add_menu_item("Заказы", "fa5s.file-invoice", OrdersTab()) 
            
        elif self.role == 'менеджер':
            self.add_menu_item("Заказы", "fa5s.clipboard-list", OrdersTab())
            self.add_menu_item("Клиенты", "fa5s.address-book", self.create_placeholder("База Клиентов"))
            self.add_menu_item("Склад", "fa5s.boxes", self.create_placeholder("Остатки Склада"))
            
        elif self.role == 'сборщик':
            self.add_menu_item("Мои Задачи", "fa5s.tools", self.create_placeholder("План работ"))
            self.add_menu_item("График", "fa5s.calendar-alt", self.create_placeholder("Мой График"))
            
        else:
            # Если роль не совпала, показываем ошибку в меню
            self.add_menu_item("Ошибка доступа", "fa5s.exclamation-circle", self.create_placeholder(f"Роль '{self.role}' не найдена"))

    def handle_logout(self):
        self.logoutSignal.emit()
        self.close()