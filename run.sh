#!/bin/bash

# ===================================
# УСТАНОВОЧНЫЙ СКРИПТ-ЗАГРУЗЧИК
# ===================================
# Этот файл клонирует репозиторий с Git и запускает установку
# с локальной конфигурацией.
# Отправляйте коллеге только этот файл + .env

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo "======================================="
echo "   ЗАГРУЗКА УСТАНОВОЧНОГО СКРИПТА"
echo "======================================="
echo ""

# Проверка прав администратора
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Этот скрипт должен запускаться с правами администратора!${NC}"
    echo "Используйте: sudo bash run.sh"
    exit 1
fi

echo "✅ Права администратора подтверждены"
echo ""

# Выбор типа установки
echo "Выберите тип установки:"
echo "1) ПК учителя (с дополнительным ПО)"
echo "2) ПК ученика (стандартная установка)"
echo ""
read -p "Введите номер (1 или 2): " INSTALL_TYPE

case $INSTALL_TYPE in
    1)
        INSTALL_MODE="teacher"
        echo -e "${GREEN}✓${NC} Выбрана установка для ПК учителя"
        ;;
    2)
        INSTALL_MODE="student"
        echo -e "${GREEN}✓${NC} Выбрана установка для ПК ученика"
        ;;
    *)
        echo -e "${RED}❌ Неверный выбор. Используется стандартная установка (ПК ученика)${NC}"
        INSTALL_MODE="student"
        ;;
esac
echo ""

# Определяем директорию где находится скрипт
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Установка dos2unix если не установлен (для преобразования окончаний строк)
if ! command -v dos2unix &> /dev/null; then
    echo -e "${YELLOW}📦 Установка dos2unix...${NC}"
    apt update > /dev/null 2>&1
    apt install dos2unix -y > /dev/null 2>&1
fi

# Проверка и преобразование .env из Windows в Unix формат (CRLF -> LF)
if [ -f "$SCRIPT_DIR/.env" ]; then
    # Проверяем наличие dos2unix
    if command -v dos2unix &> /dev/null; then
        dos2unix "$SCRIPT_DIR/.env" 2>/dev/null
    else
        # Используем sed для удаления \r
        sed -i 's/\r$//' "$SCRIPT_DIR/.env" 2>/dev/null
    fi
fi

# Загрузка конфигурации
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
else
    echo -e "${RED}❌ Файл .env не найден!${NC}"
    echo "Файл должен находиться в директории со скриптом: $SCRIPT_DIR"
    echo "Создайте файл .env с необходимыми настройками."
    exit 1
fi

# Проверка обязательных параметров
if [ -z "$GIT_USERNAME" ] || [ -z "$GIT_REPO" ]; then
    echo -e "${RED}❌ В файле .env отсутствуют GIT_USERNAME или GIT_REPO!${NC}"
    exit 1
fi

# Проверка подключения к интернету и доступности GitHub
echo -ne "${YELLOW}[/]${NC} Проверка подключения к GitHub...\033[K"
if ping -c 1 -W 2 github.com > /dev/null 2>&1 || ping -c 1 -W 2 8.8.8.8 > /dev/null 2>&1; then
    # Дополнительная проверка доступности GitHub через curl или wget
    if command -v curl &> /dev/null; then
        if curl -s --connect-timeout 5 https://github.com > /dev/null 2>&1; then
            echo -e "\r${GREEN}[+]${NC} Проверка подключения к GitHub - ${GREEN}УСПЕШНО${NC}\033[K"
        else
            echo -e "\r${RED}[-]${NC} Проверка подключения к GitHub - ${RED}НЕДОСТУПЕН${NC}\033[K"
            echo -e "${RED}GitHub недоступен. Проверьте подключение к интернету или настройки прокси.${NC}"
            exit 1
        fi
    elif command -v wget &> /dev/null; then
        if wget -q --timeout=5 --spider https://github.com 2>&1; then
            echo -e "\r${GREEN}[+]${NC} Проверка подключения к GitHub - ${GREEN}УСПЕШНО${NC}\033[K"
        else
            echo -e "\r${RED}[-]${NC} Проверка подключения к GitHub - ${RED}НЕДОСТУПЕН${NC}\033[K"
            echo -e "${RED}GitHub недоступен. Проверьте подключение к интернету или настройки прокси.${NC}"
            exit 1
        fi
    else
        echo -e "\r${GREEN}[+]${NC} Проверка подключения к GitHub - ${GREEN}ПРОПУЩЕНО${NC}\033[K"
    fi
else
    echo -e "\r${RED}[-]${NC} Проверка подключения к GitHub - ${RED}НЕТ ПОДКЛЮЧЕНИЯ${NC}\033[K"
    echo -e "${RED}Отсутствует подключение к интернету.${NC}"
    exit 1
fi

# Установка Git если не установлен
if ! command -v git &> /dev/null; then
    echo -e "${YELLOW}📦 Git не установлен. Установка Git...${NC}"
    apt update > /dev/null 2>&1
    if apt install git -y > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Git успешно установлен${NC}"
    else
        echo -e "${RED}❌ Не удалось установить Git${NC}"
        echo "Попробуйте установить вручную: apt install git"
        exit 1
    fi
else
    echo -e "${GREEN}✅ Git уже установлен${NC}"
fi

# URL Git репозитория
GIT_REPO_URL="https://github.com/${GIT_USERNAME}/${GIT_REPO}.git"

# Временная директория для клонирования
TEMP_DIR="/tmp/astra-setup"

echo -e "${YELLOW}📥 Клонирование репозитория из Git...${NC}"

# Удаляем старую временную папку если существует
if [ -d "$TEMP_DIR" ]; then
    rm -rf "$TEMP_DIR"
fi

# Клонирование репозитория
if git clone --depth 1 "$GIT_REPO_URL" "$TEMP_DIR" 2>&1 | grep -v "Cloning into"; then
    echo -e "${GREEN}✅ Репозиторий успешно клонирован${NC}"
    
    # Копируем .env в временную директорию
    cp "$SCRIPT_DIR/.env" "$TEMP_DIR/.env"
    
    # Переходим во временную директорию
    cd "$TEMP_DIR" || exit 1
    
    echo -e "${YELLOW}🚀 Запуск установки...${NC}"
    echo ""
    
    # Запуск основного скрипта с передачей типа установки
    bash ./setup-main.sh "$INSTALL_MODE"
    
    # Сохраняем код выхода
    EXIT_CODE=$?
    
    # Возвращаемся обратно
    cd ..
    
    # Удаляем временную директорию
    rm -rf "$TEMP_DIR"
    
    exit $EXIT_CODE
    
else
    echo -e "${RED}❌ Не удалось клонировать репозиторий${NC}"
    echo "Проверьте:"
    echo "1. Подключение к интернету"
    echo "2. Установлен ли git (apt install git)"
    echo "3. Правильность URL репозитория в скрипте"
    echo "4. Доступность репозитория"
    rm -rf "$TEMP_DIR"
    exit 1
fi
