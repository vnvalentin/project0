FROM python:3.12-alpine
WORKDIR /app
RUN apk add --no-cache git github-cli && mkdir -p /cache && chown nobody:nobody /cache
COPY app.py /app/app.py
COPY tracker.py tracker_schema.json github_cache.py /app/
ENV PROJECT_ROOT=/repo PORT=8080 HOME=/tmp GIT_OPTIONAL_LOCKS=0 PYTHONDONTWRITEBYTECODE=1 APP_FILE=/repo/dashboard/app.py GH_PROMPT_DISABLED=1 GH_PAGER=cat GITHUB_CACHE_PATH=/cache/github-feed.json
EXPOSE 8080
USER nobody
# Prefer the live /repo copy (reflects host edits) so hot-reload survives atomic saves.
CMD ["sh", "-c", "if [ -f \"$APP_FILE\" ]; then exec python \"$APP_FILE\"; else exec python /app/app.py; fi"]
