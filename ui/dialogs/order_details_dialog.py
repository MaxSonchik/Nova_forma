from PyQt6.QtWidgets import (
    QDialog, QVBoxLayout, QTableWidget, QTableWidgetItem, 
    QPushButton, QHeaderView, QLabel
)
from PyQt6.QtCore import Qt
from db.database import Database

class OrderDetailsDialog(QDialog):
    def __init__(self, parent, order_id):
        super().__init__(parent)
        self.order_id = order_id
        self.setWindowTitle(f"Состав заказа №{order_id}")
        self.resize(600, 400)
        
        layout = QVBoxLayout(self)
        
        # Title
        layout.addWidget(QLabel(f"<h2>Заказ №{order_id}</h2>"))
        
        # Table
        self.table = QTableWidget()
        self.table.setColumnCount(5)
        self.table.setHorizontalHeaderLabels([
            "ID Изделия", "Наименование", "Кол-во", "Цена (руб.)", "Сумма (руб.)"
        ])
        
        # Layout columns
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(0, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch)
        header.setSectionResizeMode(2, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(3, QHeaderView.ResizeMode.ResizeToContents)
        header.setSectionResizeMode(4, QHeaderView.ResizeMode.ResizeToContents)
        
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        
        layout.addWidget(self.table)
        
        # Close button
        btn_close = QPushButton("Закрыть")
        btn_close.clicked.connect(self.accept)
        layout.addWidget(btn_close)
        
        self.load_data()

    def load_data(self):
        try:
            items = Database.fetch_all(
                "SELECT * FROM sp_get_order_items(%s)", 
                (self.order_id,)
            )
            
            self.table.setRowCount(0)
            total_sum = 0
            
            for i, row in enumerate(items):
                self.table.insertRow(i)
                self.table.setItem(i, 0, QTableWidgetItem(str(row['id_изделия'])))
                self.table.setItem(i, 1, QTableWidgetItem(str(row['наименование'])))
                self.table.setItem(i, 2, QTableWidgetItem(str(row['количество'])))
                self.table.setItem(i, 3, QTableWidgetItem(f"{row['цена']:,.2f}"))
                self.table.setItem(i, 4, QTableWidgetItem(f"{row['сумма']:,.2f}"))
                
                total_sum += row['сумма']
                
            # Add Total row optional or just show in footer?
            # Let's add simple logic if needed, but simple table is enough for now per request.
            
        except Exception as e:
            # Fallback if SP missing (during dev) or error
            from ui.widgets.toast import Toast
            Toast.error(self, "Ошибка загрузки", str(e))
