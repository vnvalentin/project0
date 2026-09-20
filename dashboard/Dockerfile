FROM python:3.12-alpine
WORKDIR /app
RUN apk add --no-cache git
COPY app.py /app/app.py
ENV PROJECT_ROOT=/repo PORT=8080 HOME=/tmp GIT_OPTIONAL_LOCKS=0 PYTHONDONTWRITEBYTECODE=1 APP_FILE=/repo/dashboard/app.py
EXPOSE 8080
USER nobody
# Prefer the live /repo copy (reflects host edits) so hot-reload survives atomic saves.
CMD ["sh", "-c", "if [ -f \"$APP_FILE\" ]; then exec python \"$APP_FILE\"; else exec python /app/app.py; fi"]
