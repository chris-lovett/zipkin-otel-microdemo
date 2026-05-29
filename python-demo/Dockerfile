# syntax=docker/dockerfile:1
# BuildKit automatically sets BUILDPLATFORM (host machine) and TARGETPLATFORM
# (image being produced).  Declaring them here makes them available as build
# arguments and documents multi-architecture intent.
ARG BUILDPLATFORM
ARG TARGETPLATFORM

# python:3.11-slim is a multi-platform image; Docker pulls the correct variant
# for the requested TARGETPLATFORM automatically.
FROM python:3.11-slim

WORKDIR /app

# Install dependencies first so Docker can cache this layer.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy the shared tracing helper and all service entry-points.
COPY tracing.py .
COPY service_a.py .
COPY service_b.py .
COPY service_c.py .
