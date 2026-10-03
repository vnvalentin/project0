ARG GODOT_IMAGE
FROM ${GODOT_IMAGE} AS validation

# Validation-only dependencies. The production Godot image remains unchanged.
USER root
RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 git \
    && rm -rf /var/lib/apt/lists/*
