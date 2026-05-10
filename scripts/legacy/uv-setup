#!/bin/bash

if [ ! -d ".venv" ]; then
  echo "🚀 uv venv it's creating..."
  uv venv
fi

if [ -f "requirements.txt" ]; then
  echo "📦 Installing dependencies..."
  uv pip install -r requirements.txt
else
  echo "⚠️ requirements.txt not found, aborting..."
fi

# 3. Activar el entorno
# NOTA: Esto solo funcionará si llamas al script con 'source'
echo "✅ venv is ready."
source .venv/bin/activate
