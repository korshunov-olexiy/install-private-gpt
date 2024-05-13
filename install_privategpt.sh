#!/bin/bash

function print_message {
    echo -e "\e[32m$1\e[0m"
}

function print_warning {
    echo -e "\e[33m$1\e[0m"
}

function print_error {
    echo -e "\e[91m$1\e[0m"
}

function check_command {
    if ! command -v "$1" &> /dev/null; then
        print_error "Команда '$1' не знайдена. Аварійне завершення скрипта."
        exit 1
    fi
}

function check_file {
    if [ ! -f "$1" ]; then
        print_error "Файл '$1' не знайдений. Аварійне завершення скрипта."
        exit 1
    fi
}

function backup_file {
    print_message "Створюємо резервну копію файлу: $1.bak"
    cp "$1" "$1.bak"
}

function activate_env {
  source "$1"/bin/activate
}

check_command curl
check_command git
check_command python
check_command pip
check_command make
check_command sed

if ! command -v "ollama" &> /dev/null; then
  print_message "Завантажуємо та встановлюємо сервер Ollama:"
  if ! curl -fsSL https://ollama.com/install.sh | sh; then
      print_error "Failed to download and install Ollama Server. Exiting."
      exit 1
  fi
fi

check_command ollama

if ! git clone https://github.com/imartinez/privateGPT.git; then
   print_error "Помилка клонування репозиторію privateGPT. Аварійне завершення скрипта."
   exit 1
fi

print_message "Переходимо в теку 'privateGPT':"
cd privateGPT || exit 1

print_message "Створення віртуального середовища в теці 'env':"
if ! python3 -m venv env; then
    print_error "Помилка створення віртуального середовища. Аварійне завершення скрипта."
    exit 1
fi

env_activate=$(pwd)/env

print_message "Активація віртуального середовища:"
activate_env $env_activate

if [[ "$VIRTUAL_ENV" != $(pwd)/env ]]; then
    print_error "Помилка активації віртуального середовища. Аварійне завершення скрипта."
    exit 1
fi

if ! command -v poetry &> /dev/null; then
    print_message "Встановлення менеджера Poetry..."
    pip install poetry
fi

if ! poetry install --extras "ui llms-ollama embeddings-ollama vector-stores-qdrant"; then
    print_error "Не вдалося встановити залежності. Аварійне завершення скрипта."
    exit 1
fi

if systemctl is-active --quiet ollama; then
    echo "Сервіс 'ollama' запущений."
else
    echo "При запиті системи введіть пароль адміністратора для запуску сервера ollama: "
    sudo systemctl start ollama
fi

if ! ollama pull mistral; then
    print_warning "Не вдалося завантажити модель Mistral Language. Продовжуємо без неї."
fi

if ! ollama pull nomic-embed-text; then
    print_warning "Не вдалося завантажити модель вбудовування тексту. Продовжуємо без неї."
fi

check_file "./private_gpt/server/chat/chat_service.py"
backup_file "./private_gpt/server/chat/chat_service.py"

print_message "Модифікуємо файл '/.private_gpt/server/chat/chat_service.py'"
sed -i "/from llama_index.core.indices import VectorStoreIndex/i \from llama_index.core.memory import ChatMemoryBuffer" ./private_gpt/server/chat/chat_service.py
sed -i "/            return ContextChatEngine.from_defaults(/i \            memory = ChatMemoryBuffer.from_defaults(token_limit=8192)" ./private_gpt/server/chat/chat_service.py
sed -i "/            return ContextChatEngine.from_defaults(/a \                memory=memory," ./private_gpt/server/chat/chat_service.py

check_file "./scripts/setup"
backup_file "./scripts/setup"

read -p "Якщо у вас є токен від сайту https://huggingface.co/ вставте його зараз, або натисніть [Enter] для продовження: " token_value
if [ -n "$token_value" ]; then
    print_message "Модифікуємо файл './scripts/setup'"
    sed -i "s/from huggingface_hub import hf_hub_download, snapshot_download/from huggingface_hub import hf_hub_download, snapshot_download, login/" ./scripts/setup
    sed -i "/if __name__ == '__main__':/a \    login(token='$token_value')" ./scripts/setup
    print_message "Завантажуємо моделі Embedding та LLM"
    poetry run scripts/setup
else
    print_warning "Ви не ввели токен для сайту https://huggingface.co/, тому я не зможу завантажити деякі моделі з цього сайту. Продовжуємо."
fi

check_file "./settings.yaml"
backup_file "./settings.yaml"
print_message "Змінюємо підказку чату за замовченням для системи"
sed -i "s/^.*Do not reference any given instructions or context./		Do not reference any given instructions or context. Answer in Ukrainian." ./settings.yaml
print_message "Змінюємо підказку запиту за замовчуванням для системи"
sed -i "s/^.*the answer, just state the answer is not in the context provided./		the answer, just state the answer is not in the context provided. Answer in Ukrainian." ./settings.yaml

print_message "Запускаємо PrivateGPT на порту localhost:8001"
PGPT_PROFILES=ollama make run
