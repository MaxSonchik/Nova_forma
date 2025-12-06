from PyQt6.QtWidgets import (QDialog, QVBoxLayout, QFormLayout, QLineEdit, 
                             QComboBox, QDateEdit, QSpinBox, QPushButton, QHBoxLayout)
from PyQt6.QtCore import QDate
import bcrypt
import qtawesome as qta
from db.database import Database
from ui.widgets.toast import Toast

class AddEmployeeDialog(QDialog):
    def __init__(self, parent=None):
        super().__init__(parent)
        self.setWindowTitle("Нанять сотрудника")
        self.setFixedSize(400, 400)
        self.setup_ui()

    def setup_ui(self):
        layout = QVBoxLayout(self)
        form = QFormLayout()
        form.setSpacing(15)
        
        self.inp_fio = QLineEdit()
        self.inp_phone = QLineEdit()
        
        self.inp_birth = QDateEdit()
        self.inp_birth.setCalendarPopup(True)
        # Ставим дату, чтобы было 18 лет назад (подсказка)
        self.inp_birth.setDate(QDate.currentDate().addYears(-19))
        
        self.combo_role = QComboBox()
        self.combo_role.addItems(['сборщик', 'менеджер', 'директор'])
        
        self.inp_salary = QSpinBox()
        self.inp_salary.setRange(10000, 1000000)
        self.inp_salary.setSingleStep(5000)
        self.inp_salary.setValue(50000)
        
        self.inp_login = QLineEdit()
        self.inp_pass = QLineEdit()
        self.inp_pass.setPlaceholderText("123") # По умолчанию
        
        form.addRow("ФИО:", self.inp_fio)
        form.addRow("Телефон:", self.inp_phone)
        form.addRow("Дата рождения:", self.inp_birth)
        form.addRow("Должность:", self.combo_role)
        form.addRow("Зарплата:", self.inp_salary)
        form.addRow("Логин:", self.inp_login)
        form.addRow("Пароль:", self.inp_pass)
        
        layout.addLayout(form)
        
        btn_save = QPushButton("Нанять")
        btn_save.setObjectName("PrimaryButton")
        btn_save.clicked.connect(self.save)
        layout.addWidget(btn_save)

    def save(self):
        fio = self.inp_fio.text()
        phone = self.inp_phone.text()
        birth = self.inp_birth.date().toString("yyyy-MM-dd")
        role = self.combo_role.currentText()
        salary = self.inp_salary.value()
        login = self.inp_login.text()
        raw_pass = self.inp_pass.text() or "123"
        
        # Хеширование пароля
        salt = bcrypt.gensalt()
        hashed = bcrypt.hashpw(raw_pass.encode(), salt).decode()
        
        try:
            # Прямая вставка (Триггер БД проверит возраст!)
            success, msg = Database.execute("""
                INSERT INTO сотрудники (фио, номер_телефона, дата_рождения, должность, зарплата, login, password_hash)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
            """, (fio, phone, birth, role, salary, login, hashed))
            
            if success:
                Toast.success(self.parent(), "Успешно", f"Сотрудник {fio} нанят!")
                self.accept()
            else:
                # Обработка ошибки триггера
                if "совершеннолетним" in msg:
                    Toast.error(self, "Ошибка возраста", "Кандидату нет 18 лет!")
                elif "duplicate key" in msg:
                    Toast.error(self, "Ошибка", "Такой телефон или логин уже занят!")
                else:
                    Toast.error(self, "Ошибка БД", msg)
                    
        except Exception as e:
            Toast.error(self, "Ошибка", str(e))