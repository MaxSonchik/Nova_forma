from PyQt6.QtWidgets import (QWidget, QVBoxLayout, QHBoxLayout, QTableWidget, 
                             QTableWidgetItem, QPushButton, QLineEdit, QHeaderView, QMessageBox)
from PyQt6.QtCore import Qt
import qtawesome as qta
from db.database import Database
from ui.widgets.toast import Toast
from ui.dialogs.add_client_dialog import AddClientDialog

class ClientsTab(QWidget):
    def __init__(self):
        super().__init__()
        self.setup_ui()
        self.load_data()

    def setup_ui(self):
        layout = QVBoxLayout(self)
        
        # --- ПАНЕЛЬ ИНСТРУМЕНТОВ ---
        toolbar = QHBoxLayout()
        
        self.search_input = QLineEdit()
        self.search_input.setPlaceholderText("🔍 Поиск по ФИО или телефону...")
        self.search_input.textChanged.connect(self.load_data)
        
        self.btn_add = QPushButton("Добавить")
        self.btn_add.setIcon(qta.icon('fa5s.user-plus', color='white'))
        self.btn_add.setObjectName("PrimaryButton")
        self.btn_add.clicked.connect(self.add_client)
        
        self.btn_edit = QPushButton("Редактировать")
        self.btn_edit.setIcon(qta.icon('fa5s.edit'))
        self.btn_edit.clicked.connect(self.edit_client)
        
        self.btn_delete = QPushButton("Удалить")
        self.btn_delete.setIcon(qta.icon('fa5s.trash-alt', color='#E74C3C'))
        self.btn_delete.clicked.connect(self.delete_client)
        
        btn_refresh = QPushButton()
        btn_refresh.setIcon(qta.icon('fa5s.sync-alt'))
        btn_refresh.setFixedWidth(40)
        btn_refresh.clicked.connect(self.load_data)

        toolbar.addWidget(self.search_input, 1)
        toolbar.addWidget(self.btn_add)
        toolbar.addWidget(self.btn_edit)
        toolbar.addWidget(self.btn_delete)
        toolbar.addWidget(btn_refresh)
        
        layout.addLayout(toolbar)

        # --- ТАБЛИЦА ---
        self.table = QTableWidget()
        self.table.setColumnCount(5)
        self.table.setHorizontalHeaderLabels(["ID", "ФИО", "Телефон", "ИНН", "Адрес"])
        
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch) # ФИО тянется
        header.setSectionResizeMode(4, QHeaderView.ResizeMode.Stretch) # Адрес тянется
        
        self.table.verticalHeader().setVisible(False)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setSelectionMode(QTableWidget.SelectionMode.SingleSelection) # Только одна строка
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)
        
        layout.addWidget(self.table)

    def load_data(self):
        search_text = self.search_input.text().strip().lower()
        
        query = "SELECT * FROM клиенты WHERE 1=1"
        params = []
        
        if search_text:
            query += " AND (LOWER(фио) LIKE %s OR номер_телефона LIKE %s)"
            like_str = f"%{search_text}%"
            params.append(like_str)
            params.append(like_str)
            
        query += " ORDER BY id_клиента DESC"
        
        clients = Database.fetch_all(query, params)
        self.populate_table(clients)

    def populate_table(self, clients):
        self.table.setRowCount(0)
        # Сохраняем полные данные о клиентах, чтобы потом брать их для редактирования
        self.current_clients_data = clients 
        
        for row_idx, client in enumerate(clients):
            self.table.insertRow(row_idx)
            
            # ID
            self.table.setItem(row_idx, 0, QTableWidgetItem(str(client['id_клиента'])))
            # ФИО
            self.table.setItem(row_idx, 1, QTableWidgetItem(client['фио']))
            # Телефон
            self.table.setItem(row_idx, 2, QTableWidgetItem(client['номер_телефона']))
            # ИНН
            self.table.setItem(row_idx, 3, QTableWidgetItem(client['инн'] or "—"))
            # Адрес
            self.table.setItem(row_idx, 4, QTableWidgetItem(client['адрес'] or "—"))
            
            # Сохраняем ID строки в UserRole элемента (для надежности)
            self.table.item(row_idx, 0).setData(Qt.ItemDataRole.UserRole, client)

    def get_selected_client(self):
        """Возвращает словарь данных выбранного клиента или None"""
        row = self.table.currentRow()
        if row == -1:
            return None
        # Данные спрятаны в первой ячейке
        return self.table.item(row, 0).data(Qt.ItemDataRole.UserRole)

    def add_client(self):
        dialog = AddClientDialog(self)
        if dialog.exec():
            self.load_data()

    def edit_client(self):
        client = self.get_selected_client()
        if not client:
            Toast.warning(self, "Внимание", "Выберите клиента для редактирования")
            return
            
        dialog = AddClientDialog(self, client_data=client)
        if dialog.exec():
            self.load_data()

    def delete_client(self):
        client = self.get_selected_client()
        if not client:
            Toast.warning(self, "Внимание", "Выберите клиента для удаления")
            return

        # Подтверждение (здесь можно использовать QMessageBox для критического вопроса)
        # Но по ТЗ "тосты". Однако удаление без подтверждения опасно.
        # Сделаем стандартный вопрос, а результат покажем Тостом.
        reply = QMessageBox.question(self, 'Удаление', 
                                     f"Вы уверены, что хотите удалить клиента:\n{client['фио']}?",
                                     QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No)
        
        if reply == QMessageBox.StandardButton.Yes:
            query = "DELETE FROM клиенты WHERE id_клиента = %s"
            success, error = Database.execute(query, (client['id_клиента'],))
            
            if success:
                Toast.success(self, "Удалено", "Клиент успешно удален")
                self.load_data()
            else:
                # Скорее всего Foreign Key Violation
                if "update or delete on table" in error.lower():
                    Toast.error(self, "Невозможно удалить", 
                                "У этого клиента есть заказы!\nСначала удалите заказы.")
                else:
                    Toast.error(self, "Ошибка БД", error)