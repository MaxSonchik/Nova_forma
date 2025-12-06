import os
import sys

from PyQt6.QtWidgets import QApplication

from ui.windows.login_window import LoginWindow
from ui.windows.main_window import MainWindow

STYLE_PATH = os.path.join(os.path.dirname(__file__), "ui", "resources", "styles.qss")


class AppController:
    """Контроллер для переключения между окнами"""

    def __init__(self):
        self.login_window = None
        self.main_window = None

    def show_login(self):
        """Показать окно входа"""
        self.login_window = LoginWindow()
        self.login_window.loginSuccess.connect(self.show_main)

        # Очистка старого главного окна, если было
        if self.main_window:
            self.main_window.close()
            self.main_window = None

        self.login_window.show()

    def show_main(self, user_id, role, fio):
        """Показать главное окно"""
        self.main_window = MainWindow(user_id, role, fio)
        self.main_window.logoutSignal.connect(
            self.show_login
        )  # При выходе -> снова логин

        # Закрываем логин
        if self.login_window:
            self.login_window.close()
            self.login_window = None

        self.main_window.show()


def main():
    app = QApplication(sys.argv)

    # Загрузка стилей
    if os.path.exists(STYLE_PATH):
        with open(STYLE_PATH, "r") as f:
            app.setStyleSheet(f.read())

    # Запуск контроллера
    controller = AppController()
    controller.show_login()

    sys.exit(app.exec())


if __name__ == "__main__":
    main()
