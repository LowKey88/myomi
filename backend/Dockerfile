FROM python:3.11 

ENV PATH="/opt/venv/bin:$PATH"
RUN python -m venv /opt/venv

COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir --upgrade -r /tmp/requirements.txt
RUN apt-get update && apt-get install -y libportaudio2 libportaudiocpp0 portaudio19-dev



WORKDIR /app

RUN apt-get update && apt-get -y install ffmpeg curl unzip && rm -rf /var/lib/apt/lists/*

COPY . .
RUN git clone https://github.com/dimastatz/whisper-flow.git
RUN cd whisper-flow && pip install -e . && cd ..
RUN cp -r whisper-flow/whisperflow /app/whisperflow

EXPOSE 8080
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
