import os
import re

                                        
TABLE_MAP = {
    "сотрудники": "Сотрудник",
    "клиенты": "Клиент",
    "заказы": "Заказ",
    "изделия": "Изделие",
    "материалы": "Материал",
    "закупки_материалов": "Закупка",
    "состав_закупки": "СоставЗакупки",
    "состав_заказа": "СоставЗаказа",
    "состав_изделия": "СоставИзделия",
    "заготовки": "Заготовка",
    "состав_заготовки": "СоставЗаготовки",
    "план_заготовок": "ПланЗаготовок",
    "план_сборки": "ПланСборки",
    "debug_log": "DebugLog",
    "график_работы": "График",
}

                                               
                                                                  
                                                                    
                                                             

EXTENSIONS = (".py", ".sql")
IGNORE_DIRS = ("venv", "__pycache__", ".git", ".gemini", "node_modules")

def refactor_file(filepath):
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()

    new_content = content
    changes_count = 0
    
    for old, new in TABLE_MAP.items():
                                                                              
                                       
                                                                                          
                                  
        
                                              
        pattern = r'\b' + re.escape(old) + r'\b'
        
                                                        
                                                                                             
                                                                                    
                                                          
        
        matches = re.findall(pattern, new_content)
        if matches:
            new_content = re.sub(pattern, new, new_content)
            changes_count += len(matches)

    if new_content != content:
        print(f"Refactoring {filepath}: {changes_count} changes")
        with open(filepath, "w", encoding="utf-8") as f:
            f.write(new_content)

def main():
    root_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    print(f"Refactoring in {root_dir}")
    
    for root, dirs, files in os.walk(root_dir):
                            
        dirs[:] = [d for d in dirs if d not in IGNORE_DIRS]
        
        for file in files:
            if file.endswith(EXTENSIONS):
                filepath = os.path.join(root, file)
                                                                                        
                if "rename_tables.sql" in filepath or "refactor_db_names.py" in filepath:
                    continue
                
                refactor_file(filepath)

if __name__ == "__main__":
    main()
