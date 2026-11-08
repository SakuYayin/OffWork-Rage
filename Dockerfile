FROM python:3.12-slim
WORKDIR /app
COPY . /app
ENV PORT=7860 WEB_ROOT=/app SCORE_DATA_DIR=/mnt/workspace PYTHONUNBUFFERED=1
EXPOSE 7860
CMD ["python", "server.py"]
