from PyQt6.QtWidgets import (QDialog, QVBoxLayout, QHBoxLayout, QLabel, 
                             QLineEdit, QTextEdit, QPushButton, QFormLayout)
from PyQt6.QtCore import Qt
import qtawesome as qta
from db.database import Database
from ui.widgets.toast import Toast

class AddClientDialog(QDialog):
    def __init__(self, parent=None, client_data=None):
        super().__init__(parent)
        self.client_data = client_data # Если None -> Создание, иначе -> Редактирование
        
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
        btn_save.setIcon(qta.icon('fa5s.save', color='white'))
        btn_save.clicked.connect(self.save_client)
        
        btn_layout.addStretch()
        btn_layout.addWidget(btn_cancel)
        btn_layout.addWidget(btn_save)
        
        layout.addLayout(btn_layout)

    def fill_data(self):
        """Заполнение полей при редактировании"""
        c = self.client_data
        self.input_fio.setText(c['фио'])
        self.input_phone.setText(c['номер_телефона'])
        self.input_inn.setText(c['инн'] or "")
        self.input_address.setText(c['адрес'] or "")

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
            if self.client_data:
                # --- РЕДАКТИРОВАНИЕ (UPDATE) ---
                client_id = self.client_data['id_клиента']
                query = """
                    UPDATE клиенты 
                    SET фио=%s, номер_телефона=%s, инн=%s, адрес=%s
                    WHERE id_клиента=%s
                """
                params = (fio, phone, inn, address, client_id)
                success_msg = "Данные клиента обновлены!"
            else:
                # --- СОЗДАНИЕ (INSERT) ---
                query = """
                    INSERT INTO клиенты (фио, номер_телефона, инн, адрес)
                    VALUES (%s, %s, %s, %s)
                """
                params = (fio, phone, inn, address)
                success_msg = "Новый клиент создан!"

            # Отправка в БД
            success, error = Database.execute(query, params)
            
            if success:
                # Важно: показываем тост родителю (вкладке), т.к. диалог сейчас закроется
                Toast.success(self.parent(), "Успешно", success_msg)
                self.accept()
            else:
                # Обработка ошибок БД (например, дубль телефона)
                if "номер_телефона" in error and "unique" in error.lower():
                     Toast.error(self, "Ошибка", "Клиент с таким телефоном уже существует!")
                else:
                     Toast.error(self, "Ошибка БД", error)

        except Exception as e:
            Toast.error(self, "Критическая ошибка", str(e))