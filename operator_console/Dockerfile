FROM python:3.12-alpine
WORKDIR /app
COPY operator_console/app.py /app/app.py
COPY dashboard/ops_registry.py /app/dashboard/ops_registry.py
ENV PYTHONDONTWRITEBYTECODE=1 HOST=0.0.0.0 PORT=8090 SERVER_MANIFEST=/config/servers.json SNAPSHOT_ROOT=/snapshots
EXPOSE 8090
USER nobody
CMD ["python", "/app/app.py"]
