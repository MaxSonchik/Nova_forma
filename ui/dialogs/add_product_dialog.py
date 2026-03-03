from PyQt6.QtWidgets import (
    QDialog, QVBoxLayout, QHBoxLayout, QLabel, 
    QComboBox, QSpinBox, QDateEdit, QPushButton, 
    QRadioButton, QGroupBox, QWidget, QMessageBox
)
from PyQt6.QtCore import QDate
from db.database import Database
from ui.widgets.toast import Toast

class AddProductDialog(QDialog):
    def __init__(self, parent, user_id):
        super().__init__(parent)
        self.user_id = user_id
        self.setWindowTitle("Добавить изделие")
        self.setFixedSize(450, 400)
        
        layout = QVBoxLayout(self)
        
                        
        mode_group = QGroupBox("Режим")
        mode_layout = QHBoxLayout()
        self.radio_existing = QRadioButton("Существующий заказ")
        self.radio_new = QRadioButton("Новый заказ")
        self.radio_existing.setChecked(True)
        self.radio_existing.toggled.connect(self.toggle_mode)
        
        mode_layout.addWidget(self.radio_existing)
        mode_layout.addWidget(self.radio_new)
        mode_group.setLayout(mode_layout)
        layout.addWidget(mode_group)
        
                        
        self.existing_widget = QWidget()
        ex_layout = QVBoxLayout(self.existing_widget)
        ex_layout.setContentsMargins(0,0,0,0)
        ex_layout.addWidget(QLabel("ID Заказа:"))
        self.spin_order = QSpinBox()
        self.spin_order.setRange(1, 999999)
        ex_layout.addWidget(self.spin_order)
        layout.addWidget(self.existing_widget)
        
                   
        self.new_order_widget = QWidget()
        new_layout = QVBoxLayout(self.new_order_widget)
        new_layout.setContentsMargins(0,0,0,0)
        new_layout.addWidget(QLabel("Клиент:"))
        self.combo_client = QComboBox()
        self.load_clients()
        new_layout.addWidget(self.combo_client)
        layout.addWidget(self.new_order_widget)
        
        self.new_order_widget.setVisible(False)
        
                           
        layout.addWidget(QLabel("Изделие:"))
        self.combo_product = QComboBox()
        self.load_products()
        layout.addWidget(self.combo_product)
        
                  
        layout.addWidget(QLabel("Количество:"))
        self.spin_qty = QSpinBox()
        self.spin_qty.setRange(1, 1000)
        layout.addWidget(self.spin_qty)
        
                  
        layout.addWidget(QLabel("Дедлайн:"))
        self.date_deadline = QDateEdit()
        self.date_deadline.setDate(QDate.currentDate().addDays(3))
        self.date_deadline.setCalendarPopup(True)
        self.date_deadline.setDisplayFormat("dd.MM.yyyy")
        layout.addWidget(self.date_deadline)
        
                 
        btn_layout = QHBoxLayout()
        btn_cancel = QPushButton("Отмена")
        btn_cancel.clicked.connect(self.reject)
        btn_save = QPushButton("Добавить")
        btn_save.setObjectName("PrimaryButton")
        btn_save.clicked.connect(self.save)
        btn_layout.addStretch()
        btn_layout.addWidget(btn_cancel)
        btn_layout.addWidget(btn_save)
        layout.addLayout(btn_layout)

    def load_clients(self):
        clients = Database.fetch_all("SELECT * FROM sp_get_clients()")
        self.combo_client.clear()
        for c in clients:
            self.combo_client.addItem(str(c['фио']), c['id_клиента'])

    def load_products(self):
        products = Database.fetch_all("SELECT * FROM Изделие ORDER BY наименование")
        self.combo_product.clear()
        for p in products:
            self.combo_product.addItem(p['наименование'], p['id_изделия'])

    def toggle_mode(self):
        is_new = self.radio_new.isChecked()
        self.new_order_widget.setVisible(is_new)
        self.existing_widget.setVisible(not is_new)

    def save(self):
        product_idx = self.combo_product.currentIndex()
        if product_idx == -1:
            QMessageBox.warning(self, "Ошибка", "Выберите изделие")
            return
            
        product_id = self.combo_product.itemData(product_idx)
        qty = self.spin_qty.value()
        deadline = self.date_deadline.date().toString("yyyy-MM-dd")
        
        try:
            order_id = None
            if self.radio_new.isChecked():
                client_id = self.combo_client.currentData()
                if not client_id:
                     QMessageBox.warning(self, "Ошибка", "Выберите клиента")
                     return
                
                              
                res_order = Database.call_procedure(
                    "sp_create_order",
                    [client_id, self.user_id, deadline] 
                )
                if res_order.get("status") == "OK":
                    order_id = res_order.get("id_заказа")
                else:
                    Toast.error(self, "Ошибка", res_order.get("message", ""))
                    return
            else:
                order_id = self.spin_order.value()
            
                                  
            res = Database.call_procedure(
                "sp_add_product_to_order_smart",
                [order_id, product_id, qty, deadline]
            )
            
            if res.get("status") == "OK":
                Toast.success(self.parent(), "Успешно", res.get("message"))
                self.accept()
            else:
                Toast.error(self, "Ошибка", res.get("message", "Неизвестная ошибка"))
                
        except Exception as e:
            Toast.error(self, "Ошибка", str(e))
