#!/bin/bash

# Получаем тип установки из аргумента командной строки
INSTALL_MODE="${1:-student}"  # По умолчанию - student

# Цвета для вывода
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Массив для хранения ошибок
declare -a FAILED_COMPONENTS=()
declare -a ERROR_MESSAGES=()
declare -a SUCCESS_COMPONENTS=()
declare -a SKIPPED_COMPONENTS=()

# Функция для добавления ошибки
add_error() {
    FAILED_COMPONENTS+=("$1")
    ERROR_MESSAGES+=("$2")
}

# Функция для добавления успешной установки
add_success() {
    SUCCESS_COMPONENTS+=("$1")
}

# Функция для добавления пропущенного компонента
add_skipped() {
    SKIPPED_COMPONENTS+=("$1")
}

# Функция для выполнения команды с проверкой ошибок
execute_step() {
    local step_name="$1"
    local command="$2"
    
    echo -ne "${YELLOW}[/]${NC} $step_name\033[K"
    
    # Выполняем команду и сохраняем вывод
    local error_output
    error_output=$(eval "$command" 2>&1)
    local exit_code=$?
    
    if [ $exit_code -eq 0 ]; then
        echo -e "\r${GREEN}[+]${NC} $step_name - ${GREEN}УСПЕШНО${NC}\033[K"
        add_success "$step_name"
    else
        echo -e "\r${RED}[-]${NC} $step_name - ${RED}ОШИБКА${NC}\033[K"
        # Сохраняем последние 3 строки ошибки для краткости
        local error_summary
        error_summary=$(echo "$error_output" | tail -n 3 | sed 's/^/  /')
        add_error "$step_name" "Код ошибки: $exit_code\n$error_summary"
    fi
}

# Функция для создания пользователя
create_user() {
    local username="$1"
    local password_hash="$2"
    local groups="$3"  # необязательный параметр
    
    echo -ne "${YELLOW}[/]${NC} Создание пользователя $username\033[K"
    
    if id "$username" &>/dev/null; then
        echo -e "\r${YELLOW}[!]${NC} Создание пользователя $username - ${YELLOW}УЖЕ СУЩЕСТВУЕТ${NC}\033[K"
        add_success "Пользователь $username - уже существует"
    else
        local useradd_cmd="useradd -m $username"
        
        # Добавляем группы если указаны
        if [ -n "$groups" ]; then
            useradd_cmd="$useradd_cmd -G $groups"
        fi
        
        # Добавляем пароль
        useradd_cmd="$useradd_cmd -p '$password_hash'"
        
        if eval "$useradd_cmd" > /dev/null 2>&1; then
            echo -e "\r${GREEN}[+]${NC} Создание пользователя $username - ${GREEN}УСПЕШНО${NC}\033[K"
            add_success "Создание пользователя $username"
        else
            echo -e "\r${RED}[-]${NC} Создание пользователя $username - ${RED}ОШИБКА${NC}\033[K"
            add_error "Создание пользователя $username" "Не удалось создать пользователя"
        fi
    fi
}

# Функция для загрузки и установки .deb пакета
install_package() {
    local package_name="$1"
    local package_description="$2"
    local package_url="$3"
    local package_file="$4"
    local dependencies="$5"  # необязательный параметр
    
    echo -e "${YELLOW}[↓]${NC} Загрузка $package_description..."
    
    # Показываем только прогресс бар wget
    if wget -q --show-progress -O "$package_file" "$package_url" 2>&1; then
        echo -e "${GREEN}[+]${NC} Загрузка $package_description - ${GREEN}УСПЕШНО${NC}"
        add_success "$package_name - загружен"
        
        # Установка зависимостей если указаны
        if [ -n "$dependencies" ]; then
            execute_step "Установка зависимостей для $package_name" "apt install $dependencies -y"
        fi
        
        # Установка пакета
        execute_step "Установка $package_name" "dpkg --install $package_file"
    else
        local wget_exit=$?
        echo -e "${RED}[-]${NC} Загрузка $package_description - ${RED}ОШИБКА${NC}"
        local error_msg="Не удалось загрузить файл $package_file с $package_url\nКод ошибки: $wget_exit"
        add_error "$package_name" "$error_msg"
        
        if [ -n "$dependencies" ]; then
            add_skipped "Зависимости для $package_name - не установлены из-за ошибки загрузки"
        fi
        add_skipped "$package_name - не установлен из-за ошибки загрузки"
    fi
}

echo "======================================="
echo "   УСТАНОВКА ПРОГРАММНОГО ОБЕСПЕЧЕНИЯ"
echo "======================================="
echo ""

# Вывод информации о типе установки
if [ "$INSTALL_MODE" = "teacher" ]; then
    echo -e "${YELLOW}📚 Режим установки: ПК учителя${NC}"
else
    echo -e "${YELLOW}👨‍🎓 Режим установки: ПК ученика${NC}"
fi
echo ""

# Проверка прав администратора
if [ "$EUID" -ne 0 ]; then
    echo "❌ Этот скрипт должен запускаться с правами администратора!"
    echo "Используйте: sudo bash setup-main.sh"
    exit 1
fi

echo "✅ Права администратора подтверждены"
echo ""

# Загрузка локальной конфигурации
if [ -f "./.env" ]; then
    echo "📋 Загрузка локальной конфигурации..."
    source ./.env
else
    echo "❌ Файл конфигурации .env не найден!"
    echo "Создайте файл .env с необходимыми настройками."
    exit 1
fi

# Проверка обязательных параметров
if [ -z "$SSH_PUBLIC_KEY" ] || [ -z "$TEACHER_PASSWORD_HASH" ]; then
    echo "❌ В файле конфигурации отсутствуют обязательные параметры!"
    echo "Убедитесь, что указаны SSH_PUBLIC_KEY и TEACHER_PASSWORD_HASH"
    exit 1
fi

# Настройка SSH для пользователя sysadm
echo -ne "${YELLOW}[/]${NC} Настройка SSH (безопасное подключение)\033[K"

# Создаём директорию если не существует
if ! mkdir -p /home/sysadm/.ssh; then
    echo -e "\r${RED}[-]${NC} Настройка SSH - ${RED}ОШИБКА${NC}\033[K"
    add_error "SSH" "Не удалось создать папку .ssh для пользователя sysadm"
else
    # Проверяем, не добавлен ли уже этот ключ
    if [ -f /home/sysadm/.ssh/authorized_keys ] && grep -qF "$SSH_PUBLIC_KEY" /home/sysadm/.ssh/authorized_keys; then
        echo -e "\r${YELLOW}[!]${NC} Настройка SSH - ${YELLOW}УЖЕ НАСТРОЕН${NC}\033[K"
        add_success "SSH - ключ уже существует для пользователя sysadm"
    else
        # Добавляем ключ
        if echo "$SSH_PUBLIC_KEY" >> /home/sysadm/.ssh/authorized_keys && chown -R sysadm:sysadm /home/sysadm/.ssh && chmod 700 /home/sysadm/.ssh && chmod 600 /home/sysadm/.ssh/authorized_keys; then
            echo -e "\r${GREEN}[+]${NC} Настройка SSH - ${GREEN}УСПЕШНО${NC}\033[K"
            add_success "SSH - настроен для пользователя sysadm"
        else
            echo -e "\r${RED}[-]${NC} Настройка SSH - ${RED}ОШИБКА${NC}\033[K"
            add_error "SSH" "Не удалось добавить ключ для пользователя sysadm"
        fi
    fi
fi

# Включение репозиториев
echo -ne "${YELLOW}[/]${NC} Включение репозиториев (источники программ)\033[K"
if sed 's/#deb/deb/g' /etc/apt/sources.list -i && sed 's/^deb cdrom/#deb cdrom/g' /etc/apt/sources.list -i > /dev/null 2>&1; then
    echo -e "\r${GREEN}[+]${NC} Включение репозиториев - ${GREEN}УСПЕШНО${NC}\033[K"
    add_success "Репозитории - источники программ включены"
else
    echo -e "\r${RED}[-]${NC} Включение репозиториев - ${RED}ОШИБКА${NC}\033[K"
    add_error "Репозитории" "Не удалось изменить файл sources.list"
fi

# Обновление списка пакетов
execute_step "Обновление списка пакетов" "apt update"
execute_step "Исправление зависимостей" "apt --fix-broken install -y"
execute_step "Установка необходимых пакетов" "apt install -y dnsutils git net-tools"

# Создание пользователей
create_user "student" "" "floppy"
create_user "teacher" "$TEACHER_PASSWORD_HASH" "sudo,floppy"

# Настройка SSH-сервера
execute_step "Настройка SSH-сервера (доступ только для sysadm)" "echo 'AllowUsers sysadm' >> /etc/ssh/sshd_config && systemctl restart sshd"

# Установка Pascal
install_package "Pascal" "Pascal (язык программирования)" "https://easyastra.ru/store/pascalABC.deb" "pascalABC.deb" "mono-complete"

# Обновление Python
execute_step "Установка Python (язык программирования)" "apt install python3 python3-pip -y"
execute_step "Установка IDLE3 (IDE для Python)" "apt install idle3 -y"

# Установка Thonny
install_package "Thonny" "Thonny (редактор для Python)" "https://easyastra.ru/store/thonny.deb" "thonny.deb"

# Установка PyCharm
install_package "PyCharm" "PyCharm (редактор для Python)" "https://easyastra.ru/store/pycharm.deb" "pycharm.deb" "python3-tk"

# Установка VSCode
install_package "VSCode" "VSCode (универсальный редактор кода)" "https://easyastra.ru/store/code.deb" "code.deb"

# Установка Кумир
install_package "Кумир" "Кумир (учебная среда программирования)" "https://easyastra.ru/store/kumir2.deb" "kumir2.deb" "libqt5script5"

# Установка ЕСПД Прокси
install_package "ЕСПД Прокси" "ЕСПД Прокси (прокси-сервер)" "https://easyastra.ru/utils/espd-proxy.deb" "espd-proxy.deb"

# Установка Яндекс Браузер
install_package "Яндекс Браузер" "Яндекс Браузер (веб-браузер)" "https://easyastra.ru/store/yandex.deb" "yandex.deb" "binutils jq squashfs-tools"

# Установка VLC
install_package "VLC" "VLC (медиаплеер)" "https://easyastra.ru/store/vlc.deb" "vlc.deb"

# Установка Assistant (только для ПК учителя)
if [ "$INSTALL_MODE" = "teacher" ]; then
    install_package "Assistant" "Assistant (помощник учителя)" "https://easyastra.ru/store/assistant.deb" "assistant.deb"
fi

# Копирование файлов рабочего стола для пользователя student
echo -ne "${YELLOW}[/]${NC} Создание ярлыков рабочего стола для пользователя student\033[K"
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
if [ -d "$SCRIPT_DIR/Desktop_links" ] && [ "$(ls -A "$SCRIPT_DIR/Desktop_links" 2>/dev/null)" ]; then
    if mkdir -p /home/student/Desktops/Desktop1/ && cp -r "$SCRIPT_DIR/Desktop_links"/* /home/student/Desktops/Desktop1/ && chown -R student:student /home/student/Desktops/; then
        echo -e "\r${GREEN}[+]${NC} Копирование файлов рабочего стола - ${GREEN}УСПЕШНО${NC}\033[K"
        add_success "Файлы рабочего стола - скопированы для пользователя student"
    else
        echo -e "\r${RED}[-]${NC} Копирование файлов рабочего стола - ${RED}ОШИБКА${NC}\033[K"
        add_error "Копирование файлов" "Не удалось создать папку или скопировать файлы"
    fi
else
    echo -e "\r${YELLOW}[!]${NC} Копирование файлов рабочего стола - ${YELLOW}ПРОПУЩЕНО${NC}\033[K"
    add_success "Файлы рабочего стола - папка Desktop_links не найдена или пуста"
fi


echo ""
echo "======================================="
echo "           ИТОГОВЫЙ ОТЧЕТ"
echo "======================================="

if [ ${#FAILED_COMPONENTS[@]} -eq 0 ] && [ ${#SUCCESS_COMPONENTS[@]} -gt 0 ]; then
    echo "✅ ВСЕ КОМПОНЕНТЫ УСТАНОВЛЕНЫ УСПЕШНО!"
elif [ ${#SUCCESS_COMPONENTS[@]} -gt 0 ]; then
    echo "⚠️ УСТАНОВКА ЗАВЕРШЕНА С ОШИБКАМИ"
else
    echo "❌ УСТАНОВКА НЕ УДАЛАСЬ"
fi

if [ ${#SUCCESS_COMPONENTS[@]} -gt 0 ]; then
    echo ""
    echo "Успешно установленные компоненты:"
    for success in "${SUCCESS_COMPONENTS[@]}"; do
        echo "• $success"
    done
fi

if [ ${#FAILED_COMPONENTS[@]} -gt 0 ]; then
    echo ""
    echo "Компоненты с ошибками:"
    for i in "${!FAILED_COMPONENTS[@]}"; do
        echo "❌ ${FAILED_COMPONENTS[$i]}"
        echo -e "   Причина: ${ERROR_MESSAGES[$i]}"
        echo ""
    done
    
    if [ ${#SKIPPED_COMPONENTS[@]} -gt 0 ]; then
        echo "Компоненты не установленные из-за ошибок:"
        for skipped in "${SKIPPED_COMPONENTS[@]}"; do
            echo "⚠️ $skipped"
        done
        echo ""
    fi
    
    echo "РЕКОМЕНДАЦИИ:"
    echo "1. Проверьте подключение к интернету"
    echo "2. Убедитесь, что у вас есть права администратора"
    echo "3. Попробуйте запустить скрипт повторно"
fi

echo "======================================="
