import os
import uuid
import torch

from fastapi import UploadFile
from pyannote.audio import Pipeline

# Instantiate pretrained voice activity detection pipeline
device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
hf_token = os.getenv("HUGGINGFACE_TOKEN")
if not hf_token:
    raise EnvironmentError("HUGGINGFACE_TOKEN environment variable not set.")

vad = Pipeline.from_pretrained(
    "pyannote/voice-activity-detection",
    use_auth_token=hf_token
).to(device)

os.makedirs('_temp', exist_ok=True)


def vad_endpoint(file: UploadFile):
    upload_id = str(uuid.uuid4())
    file_path = f"_temp/{upload_id}_{file.filename}"
    with open(file_path, 'wb') as f:
        f.write(file.file.read())
    output = vad(file_path)
    segments = output.get_timeline().support()
    os.remove(file_path)
    data = []
    for segment in segments:
        data.append({
            'start': segment.start,
            'end': segment.end,
            'duration': segment.duration,
        })
    return data