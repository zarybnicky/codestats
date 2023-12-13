FROM python:buster

EXPOSE 8501

RUN apt-get update && apt-get install -y git libpq-dev && rm -rf /var/lib/apt/lists/*

RUN pip install poetry==1.4.2

ENV POETRY_NO_INTERACTION=1 \
    POETRY_VIRTUALENVS_IN_PROJECT=1 \
    POETRY_VIRTUALENVS_CREATE=1 \
    POETRY_CACHE_DIR=/tmp/poetry_cache

WORKDIR /
COPY pyproject.toml poetry.lock ./
RUN poetry install --without dev && rm -rf $POETRY_CACHE_DIR
ENV VIRTUAL_ENV=/.venv \
    PATH="/.venv/bin:$PATH"


RUN useradd -ms /bin/bash inuits
USER inuits
WORKDIR /app

COPY . .

CMD python -m streamlit run Recent.py
