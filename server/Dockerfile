FROM python:3.12-slim
WORKDIR /app
RUN pip install --no-cache-dir confluent-kafka==2.15.1
COPY store.py /app/store.py
COPY dashboard.py dashboard.html dashboard.js dashboard.css /app/
RUN useradd --uid 10001 --create-home archive && mkdir /data && chown archive /data
USER 10001:10001
CMD ["python", "-u", "/app/store.py"]
