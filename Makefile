.PHONY: install test run dev docker-build docker-run

PYTHON := python3
PIP := pip3

install:
	$(PYTHON) -m venv .venv || true
	. .venv/bin/activate && $(PYTHON) -m pip install --upgrade pip && pip install -r requirements.txt

test:
	. .venv/bin/activate && pytest -q

run:
	. .venv/bin/activate && uvicorn app.main:app --host 0.0.0.0 --port 8000

dev:
	. .venv/bin/activate && uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload

docker-build:
	docker build -t fastapi-demo:latest .

docker-run:
	docker run --rm -p 8000:8000 fastapi-demo:latest

