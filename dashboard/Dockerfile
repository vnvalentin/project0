FROM python:3.12-alpine
WORKDIR /app
COPY app.py /app/app.py
ENV PROJECT_ROOT=/repo PORT=8080
EXPOSE 8080
USER nobody
CMD ["python", "/app/app.py"]
