FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY presets.yml eval_worker.py ./
CMD ["python", "-u", "eval_worker.py"]
