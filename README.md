### Application FastAPI - Exemple (FR)

Une petite application web en Python avec FastAPI, comprenant des endpoints CRUD pour gérer des `items` en mémoire, des tests unitaires, un Dockerfile, et un Makefile.

### Prérequis
- Python 3.13 (ou 3.11+ recommandé)
- Optionnel: Docker, Make

### Installation locale (sans Docker)
1) Créez un environnement virtuel et installez les dépendances:

```bash
python3 -m venv .venv || true
. .venv/bin/activate
python -m pip install --upgrade pip
pip install -r requirements.txt
```

2) Lancer les tests:

```bash
pytest -q
```

3) Démarrer le serveur:

```bash
uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload
```

- Documentation interactive: `http://localhost:8000/docs`
- Healthcheck: `GET http://localhost:8000/api/v1/health`
- Items CRUD: `/api/v1/items`

### Utilisation Docker
1) Build de l'image:

```bash
docker build -t fastapi-demo:latest .
```

2) Lancer le conteneur:

```bash
docker run --rm -p 8000:8000 fastapi-demo:latest
```

### Structure du projet
```
app/
  api/
    v1/
      __init__.py
      endpoints.py
    __init__.py
  db/
    memory.py
  models/
    __init__.py
    item.py
  __init__.py
  main.py

requirements.txt
pyproject.toml
Dockerfile
Makefile
tests/
  conftest.py
  test_api.py
README.md
```

### Endpoints principaux
- `GET /api/v1/health`: statut du service
- `GET /api/v1/items`: liste des items
- `POST /api/v1/items`: création d'un item
- `GET /api/v1/items/{id}`: détail d'un item
- `PUT /api/v1/items/{id}`: mise à jour partielle d'un item
- `DELETE /api/v1/items/{id}`: suppression d'un item

### Notes
- Le stockage est en mémoire (données perdues au redémarrage). Pour une BDD réelle (SQLite/PostgreSQL), on peut intégrer SQLModel/SQLAlchemy et des migrations.
