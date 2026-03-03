import qtawesome as qta
from PyQt6.QtCore import Qt
from PyQt6.QtGui import QColor
from PyQt6.QtWidgets import (
    QComboBox,
    QFileDialog,
    QHBoxLayout,
    QHeaderView,
    QInputDialog,
    QLabel,
    QMessageBox,
    QPushButton,
    QTableWidget,
    QTableWidgetItem,
    QVBoxLayout,
    QWidget,
)

from business_logic.pdf_generator import PDFGenerator
from db.database import Database
from ui.widgets.toast import Toast


class ProductionTab(QWidget):
    def __init__(self, user_id, role="сборщик"):
        super().__init__()
        self.user_id = user_id
        self.role = role
        self.setup_ui()
        self.load_data()

    def setup_ui(self):
        layout = QVBoxLayout(self)

                         
        top_layout = QHBoxLayout()

        self.filter_combo = QComboBox()
        self.filter_combo.addItems(
            ["Актуальные (Новые + Мои)", "Все задачи", "История (Выполнено)"]
        )
                                                                               

        self.btn_print = QPushButton()                                           
        self.btn_print.setIcon(qta.icon("fa5s.print"))
        self.btn_print.setToolTip("Печать сменного задания")
        self.btn_print.clicked.connect(self.print_tasks)

        btn_refresh = QPushButton("Обновить")
        btn_refresh.setIcon(qta.icon("fa5s.sync-alt"))
        btn_refresh.clicked.connect(self.load_data)
        
        if self.role == "сборщик":
                                                         
             self.filter_combo.hide()
                                                                               

        top_layout.addWidget(QLabel("Фильтр:"))
        top_layout.addWidget(self.filter_combo)
        top_layout.addStretch()
        top_layout.addWidget(self.btn_print)
        top_layout.addWidget(btn_refresh)

        layout.addLayout(top_layout)

                         
        self.table = QTableWidget()
        self.table.setColumnCount(8)
        self.table.setHorizontalHeaderLabels(
            ["ID", "Заготовка", "Заказ", "План", "Факт", "Дедлайн", "Статус", "Сборщик"]
        )
        header = self.table.horizontalHeader()
        header.setSectionResizeMode(QHeaderView.ResizeMode.Interactive)
        header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch) # Task name stretch
        header.setStretchLastSection(True)
        self.table.setSelectionBehavior(QTableWidget.SelectionBehavior.SelectRows)
        self.table.setEditTriggers(QTableWidget.EditTrigger.NoEditTriggers)

        layout.addWidget(self.table)

                                 
        action_layout = QHBoxLayout()

        self.btn_take = QPushButton("Взять в работу")
        self.btn_take.setIcon(qta.icon("fa5s.hand-holding"))
        self.btn_take.clicked.connect(self.take_task)
        action_layout.addWidget(self.btn_take)

        self.btn_report = QPushButton("Сдать работу")
        self.btn_report.setIcon(qta.icon("fa5s.check"))
        self.btn_report.clicked.connect(self.report_progress)
        action_layout.addWidget(self.btn_report)

        self.btn_release = QPushButton("Снять задачу")
        self.btn_release.setIcon(qta.icon("fa5s.undo", color="#E67E22"))
        self.btn_release.clicked.connect(self.release_task)
        action_layout.addWidget(self.btn_release)

        layout.addLayout(action_layout)

                                                           
        self.filter_combo.currentTextChanged.connect(self.load_data)

    def load_data(self):
        filter_mode = self.filter_combo.currentText()

                                                                   
        query = "SELECT * FROM sp_get_assembler_tasks()"
        params = []
                                                                       
                                                                  
        query = "SELECT * FROM sp_get_assembler_tasks() WHERE 1=1"
        
        if self.role == "сборщик":
                                                   
                                                                 
                                                                                                                             
             query += " AND id_сборщика = %s AND статус IN ('назначено', 'в_работе', 'выполнено')"
             params.append(self.user_id)
        else:
                                                      
            if filter_mode == "Актуальные (Новые + Мои)":
                query += " AND (статус != 'выполнено' AND (id_сборщика IS NULL OR id_сборщика = %s))"
                params.append(self.user_id)
            elif filter_mode == "Актуальные": 
                query += " AND (статус != 'выполнено' AND (id_сборщика IS NULL OR id_сборщика = %s))"
                params.append(self.user_id)
            elif filter_mode == "Мои задачи":
                query += " AND id_сборщика = %s"
                params.append(self.user_id)
            elif filter_mode == "Свободные":
                query += " AND id_сборщика IS NULL AND статус != 'выполнено'"
            elif filter_mode == "История (Выполнено)":
                query += " AND статус = 'выполнено' AND id_сборщика = %s"
                params.append(self.user_id)
            
                                                                        
                                                                    

        try:
            tasks = Database.fetch_all(query, tuple(params))
            
            self.table.setRowCount(0)
            self.table.setHorizontalHeaderLabels(
                ["ID", "Задача", "Заказ", "План", "Факт", "Дедлайн", "Статус", "Сборщик"]
            )
                                                         
            self.table.setColumnCount(8)
            header = self.table.horizontalHeader()
            header.setSectionResizeMode(1, QHeaderView.ResizeMode.Stretch) # Re-apply stretch after load
            
            for i, task in enumerate(tasks):
                self.table.insertRow(i)
                
                                        
                row_color = None
                status = task.get("статус")
                if status == "принято":
                    row_color = QColor("#E3F2FD")
                elif status == "в_работе":
                    row_color = QColor("#FFF9C4")
                elif status == "выполнено":
                    row_color = QColor("#C8E6C9")
                elif status == "просрочено":
                    row_color = QColor("#FFCDD2")

                              
                                                                
                t_id = str(task.get("id_объекта", ""))
                t_name = str(task.get("наименование_задачи", ""))
                t_order = str(task.get("id_заказа", ""))
                t_plan = str(task.get("плановое_количество", 0))
                t_fact = str(task.get("фактическое_количество", 0))
                t_dead = str(task.get("дедлайн", ""))
                t_status = str(task.get("статус", ""))
                
                assignee_id = task.get("id_сборщика")
                t_assignee = str(assignee_id) if assignee_id else "—"

                items = [t_id, t_name, t_order, t_plan, t_fact, t_dead, t_status, t_assignee]

                for col, text in enumerate(items):
                    item = QTableWidgetItem(text)
                    if row_color:
                        item.setBackground(row_color)
                    self.table.setItem(i, col, item)

                                 
                self.table.item(i, 0).setData(Qt.ItemDataRole.UserRole, task)
            
            if self.role == "сборщик":
                 self.table.setColumnHidden(7, True)                        

        except Exception as e:
            print("Ошибка загрузки задач:", e)
            Toast.error(self, "Ошибка загрузки", str(e))

    def get_selected_task(self):
        row = self.table.currentRow()
        if row == -1:
            return None
        return self.table.item(row, 0).data(Qt.ItemDataRole.UserRole)

    def take_task(self):
        task = self.get_selected_task()
        if not task:
            Toast.warning(self, "Внимание", "Выберите задачу")
            return

        current_status = task["статус"]
        assigned_to = task["id_сборщика"]
        task_type = task.get("тип_задачи")

        if current_status == "выполнено":
            Toast.warning(self, "Ошибка", "Эта задача уже выполнена!")
            return

        if current_status == "в_работе":
            if assigned_to == self.user_id:
                Toast.warning(self, "Инфо", "Вы уже работаете над задачей.")
            else:
                Toast.error(self, "Ошибка", "Задача занята другим сотрудником!")
            return

        if assigned_to is not None and assigned_to != self.user_id:
            Toast.error(self, "Ошибка", "Задача назначена другому!")
            return

        try:
            proc_name = ""
            args = []
            
            if task_type == 'сборка':
                proc_name = "sp_take_assembly_task"
            else:
                proc_name = "sp_take_component_task"
                
            args = [task["id_объекта"], task["id_заказа"], self.user_id]
            
            result = Database.call_procedure(proc_name, args)
            
            if result and result.get("status") == "ERROR":
                Toast.error(self, "Ошибка", result.get("message", "Неизвестная ошибка"))
                return
            
            Toast.success(self, "В работе", result.get("message", "Задача взята в работу."))
            self.load_data()

        except Exception as e:
            Toast.error(self, "Ошибка", str(e))

    def release_task(self):
        """Снять задачу — возвращает материалы на склад"""
        task = self.get_selected_task()
        if not task:
            Toast.warning(self, "Внимание", "Выберите задачу")
            return

        current_status = task["статус"]
        assigned_to = task.get("id_сборщика")

        if current_status == "выполнено":
            Toast.warning(self, "Ошибка", "Нельзя снять выполненную задачу")
            return

        if current_status not in ("в_работе", "назначено"):
            Toast.warning(self, "Ошибка", "Задача не в работе")
            return

        if assigned_to is not None and assigned_to != self.user_id:
            Toast.error(self, "Ошибка", "Это не ваша задача!")
            return

        confirm = QMessageBox.question(
            self, "Подтверждение",
            "Снять задачу? Материалы будут возвращены на склад.",
            QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No
        )
        if confirm != QMessageBox.StandardButton.Yes:
            return

        try:
            result = Database.call_procedure("sp_release_task", [
                task["id_объекта"], task["id_заказа"]
            ])

            if result and result.get("status") == "ERROR":
                Toast.error(self, "Ошибка", result.get("message", "Неизвестная ошибка"))
                return

            Toast.success(self, "Успешно", result.get("message", "Задача освобождена"))
            self.load_data()
        except Exception as e:
            Toast.error(self, "Ошибка", str(e))

    def report_progress(self):
        task = self.get_selected_task()
        if not task:
            Toast.warning(self, "Внимание", "Выберите задачу для сдачи")
            return

        order_id = task["id_заказа"]
        task_type = task.get("тип_задачи")
        object_id = task.get("id_объекта")
        task_name = task.get("наименование_задачи", "")
        plan = task["плановое_количество"]
        fact = task["фактическое_количество"]
        
        start_qty = 1
        max_qty = plan - fact
        if max_qty < 1:
            Toast.warning(self, "Внимание", "План по этой задаче выполнен!")
            return

        qty, ok = QInputDialog.getInt(
            self, "Сдать работу", 
            f"Сколько единиц '{task_name}' вы сделали? (Тип: {task_type})", 
            start_qty, 1, 1000000
        )
        if ok:
            try:
                assigned_to = task.get("id_сборщика")
                if str(assigned_to) != str(self.user_id):
                     Toast.error(self, "Ошибка", "Вы не исполнитель этой задачи!")
                     return

                proc_name = ""
                                                                                           
                                                                                       
                                        
                if task_type == 'сборка':
                     proc_name = "sp_submit_assembly_work"
                else:
                    proc_name = "sp_submit_component_work"
                    
                                                              
                res = Database.call_procedure(proc_name, [object_id, order_id, qty, self.user_id])
                
                if res and res.get("status") == "ERROR":
                    Toast.error(self, "Ошибка", res.get("message", "Неизвестная ошибка"))
                    return

                Toast.success(self, "Успешно", "Работа принята!")
                self.load_data()
            except Exception as e:
                Toast.error(self, "Ошибка", str(e))

    def print_tasks(self):
        file_path, _ = QFileDialog.getSaveFileName(
            self, "Сохранить задание", "Tasks.pdf", "PDF (*.pdf)"
        )
        if not file_path:
            return

        try:
            gen = PDFGenerator(file_path)
            success, msg = gen.generate_assembler_tasks(self.user_id)
            if success:
                Toast.success(self, "Успешно", f"Файл сохранен:\n{file_path}")
            else:
                Toast.error(self, "Ошибка", msg)
        except Exception as e:
            Toast.error(self, "Ошибка", str(e))
