FROM python:3.11 AS builder

ENV PATH="/opt/venv/bin:$PATH"
RUN python -m venv /opt/venv

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

FROM python:3.11

WORKDIR /app
ENV PATH="/opt/venv/bin:$PATH"

# ffmpeg still needed for audio processing
RUN apt-get update \
    && apt-get install -y ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/venv /opt/venv
COPY . .

EXPOSE 8080

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
