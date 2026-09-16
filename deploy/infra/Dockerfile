# Shared image for the Python control-plane services (Slice 105).
#
# One image, two containers: the enrollment service and the operator service
# are the same dependency set (identical requirements.txt) differing only by
# the uvicorn target, exactly as the Godot image serves the game and login
# servers from one build. Compose selects the target per container.
#
# Trust-boundary note: enrollment is public-facing and operator is an internal
# control plane. Sharing an image couples those boundaries, which is the same
# liability recorded for the login server in DT-012. Revisit both together.
FROM python:3.12-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# curl backs the container healthcheck; tini gives correct PID 1 signal
# forwarding so uvicorn shuts down gracefully instead of being killed.
RUN apt-get update \
    && apt-get install -y --no-install-recommends curl tini \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Requirements are installed before the source copy so dependency layers stay
# cached when only application code changes. Both services pin the same set.
COPY infra/enrollment/requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt && rm -f /tmp/requirements.txt

COPY infra/ /app/infra/

# Non-root runtime; the services own no on-disk state inside the image.
RUN useradd --system --create-home --uid 10001 project0 \
    && chown -R project0:project0 /app
USER project0

EXPOSE 8095 8099

ENTRYPOINT ["/usr/bin/tini", "--"]
# Overridden per service in compose; enrollment is the default target.
CMD ["uvicorn", "infra.enrollment.asgi:app", "--host", "0.0.0.0", "--port", "8095", "--workers", "1"]
