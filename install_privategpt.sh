#!/bin/bash

function print_message {
    echo -e "\e[1;34m$1\e[0m"
}

function print_error {
    echo -e "\e[91m$1\e[0m"
}

function check_command {
    if ! command -v "$1" &> /dev/null; then
        print_error "Command '$1' not found. Exiting."
        exit 1
    fi
}

function check_file {
    if [ ! -f "$1" ]; then
        print_error "File '$1' not found. Exiting."
        exit 1
    fi
}

function backup_file {
    cp "$1" "$1.bak"
}

# Check necessary commands
check_command curl
check_command git
check_command python
check_command pip
check_command make
check_command sed

print_message "Download and install Ollama Server:"
if ! curl -fsSL https://ollama.com/install.sh | sh; then
    print_error "Failed to download and install Ollama Server. Exiting."
    exit 1
fi

check_command ollama

print_message "Clone repository:"
if ! git clone https://github.com/imartinez/privateGPT.git; then
    print_error "Failed to clone privateGPT repository. Exiting."
    exit 1
fi

print_message "Go to the 'privateGPT' directory:"
cd privateGPT/ || exit 1

print_message "Create virtual environment to 'env' directory:"
if ! python -m venv env; then
    print_error "Failed to create virtual environment. Exiting."
    exit 1
fi

print_message "Activate virtual environment:"
source env/bin/activate || exit 1

# echo "Install poetry if not exists:"
if ! command -v poetry &> /dev/null; then
    print_message "Installing Poetry..."
    pip install poetry
fi

# "Install dependencies:"
if ! poetry install --extras "ui llms-ollama embeddings-ollama vector-stores-qdrant"; then
    print_error "Failed to install dependencies. Exiting."
    exit 1
fi

# "Start Ollama Server:"
if ! ollama serve; then
    print_error "Failed to start Ollama Server. Exiting."
    exit 1
fi

# "Download Mistral Language model:"
if ! ollama pull mistral; then
    print_error "Failed to download Mistral Language model. Continuing without it."
fi

# "Download embedding text model:"
if ! ollama pull nomic-embed-text; then
    print_error "Failed to download embedding text model. Continuing without it."
fi

check_file "./private_gpt/server/chat/chat_service.py"
backup_file "./private_gpt/server/chat/chat_service.py"
# echo "Patching 'chat_service.py' in './private_gpt/server/chat/' directory:"
### Create a larger memory buffer for the chat engine (from ChatMemoryBuffer method)
### ### add import "from llama_index.core.memory import ChatMemoryBuffer" at the beginning of the file; insert line "memory = ChatMemoryBuffer.from_defaults(token_limit=8192)" before line: "return ContextChatEngine.from_defaults(" and insert line "memory=memory," before this line.
sed -i "/from llama_index.core.indices import VectorStoreIndex/i from llama_index.core.memory import ChatMemoryBuffer" ./private_gpt/server/chat/chat_service.py
sed -i "/            return ContextChatEngine.from_defaults(/i \            memory = ChatMemoryBuffer.from_defaults(token_limit=8192)" ./private_gpt/server/chat/chat_service.py
sed -i "/            return ContextChatEngine.from_defaults(/a \                memory=memory," ./private_gpt/server/chat/chat_service.py

check_file "./scripts/setup"
backup_file "./scripts/setup"
# echo "Patching 'setup' in './scripts/' directory:"
### Add a token hugging_face for accessing to limited repositories (replace 'my_token' to real token from https://huggingface.co/):
### ### add ", login" to line: "from huggingface_hub import hf_hub_download, snapshot_download" and use it after line "if __name__ == '__main__':" --> login(token="<my_token>")
sed -i "s/from huggingface_hub import hf_hub_download, snapshot_download/from huggingface_hub import hf_hub_download, snapshot_download, login/" ./scripts/setup
sed -i "/if __name__ == '__main__':/a \    login(token='my_token')" ./scripts/setup

# Download Embedding and LLM models
poetry run scripts/setup

print_message "Start PrivateGPT:"
PGPT_PROFILES=ollama make run
