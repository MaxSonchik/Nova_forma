import qtawesome as qta
from PyQt6.QtWidgets import (
    QDialog,
    QFormLayout,
    QHBoxLayout,
    QLineEdit,
    QPushButton,
    QTextEdit,
    QVBoxLayout,
)

from db.database import Database
from ui.widgets.toast import Toast


class AddClientDialog(QDialog):
    def __init__(self, parent=None, client_data=None):
        super().__init__(parent)
        self.client_data = client_data  # Если None -> Создание, иначе -> Редактирование

        mode_text = "Редактирование клиента" if client_data else "Новый клиент"
        self.setWindowTitle(mode_text)
        self.setFixedSize(500, 450)

        self.setup_ui()

        if client_data:
            self.fill_data()

    def setup_ui(self):
        layout = QVBoxLayout(self)

        # Форма ввода
        form_layout = QFormLayout()
        form_layout.setSpacing(15)

        self.input_fio = QLineEdit()
        self.input_fio.setPlaceholderText("Иванов Иван Иванович")

        self.input_phone = QLineEdit()
        self.input_phone.setPlaceholderText("+7...")

        self.input_inn = QLineEdit()
        self.input_inn.setPlaceholderText("Не обязательно")

        self.input_address = QTextEdit()
        self.input_address.setPlaceholderText("Город, улица, дом...")
        self.input_address.setFixedHeight(80)

        form_layout.addRow("ФИО: *", self.input_fio)
        form_layout.addRow("Телефон: *", self.input_phone)
        form_layout.addRow("ИНН:", self.input_inn)
        form_layout.addRow("Адрес:", self.input_address)

        layout.addLayout(form_layout)
        layout.addStretch()

        # Кнопки
        btn_layout = QHBoxLayout()

        btn_cancel = QPushButton("Отмена")
        btn_cancel.clicked.connect(self.reject)

        btn_save = QPushButton("Сохранить")
        btn_save.setObjectName("PrimaryButton")
        btn_save.setIcon(qta.icon("fa5s.save", color="white"))
        btn_save.clicked.connect(self.save_client)

        btn_layout.addStretch()
        btn_layout.addWidget(btn_cancel)
        btn_layout.addWidget(btn_save)

        layout.addLayout(btn_layout)

    def fill_data(self):
        """Заполнение полей при редактировании"""
        c = self.client_data
        self.input_fio.setText(c["фио"])
        self.input_phone.setText(c["номер_телефона"])
        self.input_inn.setText(c["инн"] or "")
        self.input_address.setText(c["адрес"] or "")

    def save_client(self):
        fio = self.input_fio.text().strip()
        phone = self.input_phone.text().strip()
        inn = self.input_inn.text().strip() or None
        address = self.input_address.toPlainText().strip()

        # 1. Валидация UI
        if not fio or not phone:
            Toast.warning(self, "Ошибка", "ФИО и Телефон обязательны!")
            return

        try:
            client_id = self.client_data["id_клиента"] if self.client_data else None
            
            # Вызываем процедуру сохранения (Create/Update)
            res = Database.call_procedure(
                'sp_save_client', 
                [client_id, fio, phone, inn, address]
            )

            if res.get('status') == 'OK':
                # Успех
                Toast.success(self.parent(), "Успешно", res.get('message'))
                self.accept()
            else:
                # Ошибка
                Toast.error(self, "Ошибка сохранения", res.get('message'))

        except Exception as e:
            Toast.error(self, "Критическая ошибка", str(e))
