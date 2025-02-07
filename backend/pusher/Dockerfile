FROM python:3.11 AS builder

ENV PATH="/opt/venv/bin:$PATH"
RUN python -m venv /opt/venv

# Update the COPY path, assuming pusher/requirements.txt is in the pusher folder
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

FROM python:3.11-slim

WORKDIR /app
ENV PATH="/opt/venv/bin:$PATH"

RUN apt-get update && apt-get -y install ffmpeg curl unzip && rm -rf /var/lib/apt/lists/*

COPY --from=builder /opt/venv /opt/venv
# Copy all files from the repository root (if needed)
COPY . /app

EXPOSE 80
CMD ["uvicorn", "pusher.main:app", "--host", "0.0.0.0", "--port", "80"]
