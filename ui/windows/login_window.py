import os
import sys

import qtawesome as qta
from PyQt6.QtCore import Qt, pyqtSignal
from PyQt6.QtGui import QColor, QPixmap
from PyQt6.QtWidgets import (
    QFrame,
    QGraphicsDropShadowEffect,
    QLabel,
    QLineEdit,
    QPushButton,
    QVBoxLayout,
    QWidget,
)

# Добавляем путь для импорта config
sys.path.append(
    os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
)

from db.database import Database
from config import config


class LoginWindow(QWidget):
    # Сигнал успешного входа (передает ID сотрудника, Роль, ФИО)
    loginSuccess = pyqtSignal(int, str, str)

    def __init__(self):
        super().__init__()
        self.setObjectName("LoginWindow")
        self.setWindowTitle("Nova Forma CRM - Вход")
        self.setFixedSize(450, 600)

        # Настройка интерфейса
        self.setup_ui()

    def setup_ui(self):
        # Основной слой
        main_layout = QVBoxLayout(self)
        main_layout.setAlignment(Qt.AlignmentFlag.AlignCenter)

        # Карточка входа (Container)
        container = QFrame()
        container.setObjectName("LoginContainer")
        container.setFixedSize(380, 500)

        # Тень для красоты (объем)
        shadow = QGraphicsDropShadowEffect()
        shadow.setBlurRadius(20)
        shadow.setColor(QColor(0, 0, 0, 30))
        shadow.setOffset(0, 5)
        container.setGraphicsEffect(shadow)

        layout = QVBoxLayout(container)
        layout.setSpacing(15)
        layout.setContentsMargins(30, 40, 30, 40)

        # 1. Логотип
        logo_label = QLabel()
        logo_path = os.path.join("assets", "logo.png")
        if os.path.exists(logo_path):
            pixmap = QPixmap(logo_path)
            # Масштабируем логотип, сохраняя пропорции
            scaled_pixmap = pixmap.scaled(
                120,
                120,
                Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation,
            )
            logo_label.setPixmap(scaled_pixmap)
        else:
            logo_label.setText("NOVA FORMA")
            logo_label.setStyleSheet("font-weight: bold; font-size: 20px;")
        logo_label.setAlignment(Qt.AlignmentFlag.AlignCenter)

        # 2. Текст приветствия
        title = QLabel("Добро пожаловать")
        title.setObjectName("Header")
        title.setAlignment(Qt.AlignmentFlag.AlignCenter)

        subtitle = QLabel("Войдите в систему управления")
        subtitle.setObjectName("SubHeader")
        subtitle.setAlignment(Qt.AlignmentFlag.AlignCenter)

        # 3. Поля ввода
        self.login_input = QLineEdit()
        self.login_input.setPlaceholderText("Логин")
        # Добавляем иконку внутрь поля (Action)
        self.login_input.addAction(
            qta.icon("fa5s.user", color="#95A5A6"),
            QLineEdit.ActionPosition.LeadingPosition,
        )

        self.password_input = QLineEdit()
        self.password_input.setPlaceholderText("Пароль")
        self.password_input.setEchoMode(QLineEdit.EchoMode.Password)
        self.password_input.addAction(
            qta.icon("fa5s.lock", color="#95A5A6"),
            QLineEdit.ActionPosition.LeadingPosition,
        )
        # Обработка Enter
        self.password_input.returnPressed.connect(self.handle_login)

        # 4. Кнопка входа
        self.login_btn = QPushButton("ВОЙТИ")
        self.login_btn.setObjectName("PrimaryButton")
        self.login_btn.setCursor(Qt.CursorShape.PointingHandCursor)
        self.login_btn.clicked.connect(self.handle_login)

        # 5. Метка ошибки (скрыта по умолчанию)
        self.error_label = QLabel("")
        self.error_label.setObjectName("ErrorLabel")
        self.error_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.error_label.hide()

        # Добавляем всё в лайаут
        layout.addWidget(logo_label)
        layout.addSpacing(10)
        layout.addWidget(title)
        layout.addWidget(subtitle)
        layout.addSpacing(20)
        layout.addWidget(self.login_input)
        layout.addWidget(self.password_input)
        layout.addWidget(self.error_label)
        layout.addStretch()
        layout.addWidget(self.login_btn)

        main_layout.addWidget(container)

    def handle_login(self):
        login = self.login_input.text().strip()
        password = self.password_input.text().strip()

        if not login or not password:
            self.show_error("Введите логин и пароль")
            return

        # Используем вызов процедуры
        try:
            result = Database.call_procedure('sp_login', [login, password])
            
            if result.get('status') == 'OK':
                self.show_error("")
                user_id = result.get('user_id')
                role = result.get('role')
                fio = result.get('fio')
                
                self.loginSuccess.emit(user_id, role, fio)
            else:
                # Ошибка (Неверный пароль или пользователь не найден)
                msg = result.get('message', 'Ошибка входа')
                self.show_error(msg)

        except Exception as e:
            self.show_error(f"Системная ошибка: {str(e)}")

    def show_error(self, message):
        self.error_label.setText(message)
        self.error_label.show()
        # Эффект дрожания можно добавить позже
