FROM python:3.11-alpine
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY formslogic.py forms_sync.py ./
ENV PYTHONUNBUFFERED=1
ENTRYPOINT ["python", "forms_sync.py"]
