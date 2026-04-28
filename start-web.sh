#!/bin/bash

cd "$(dirname "$0")"

if [ ! -d "venv" ]; then
    echo "Criando virtual environment..."
    python3 -m venv venv
    source venv/bin/activate
    echo "Instalando dependências..."
    pip install -r requirements.txt
else
    source venv/bin/activate
fi

echo "Iniciando servidor web em http://localhost:8080"
python3 web.py
