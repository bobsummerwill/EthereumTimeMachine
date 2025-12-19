FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py ./

EXPOSE 9100

ENV PORT=9100
ENV POLL_INTERVAL_SECONDS=10

CMD ["python", "-u", "app.py"]

