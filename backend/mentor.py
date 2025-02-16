import wave
import struct
from fastapi import FastAPI, Request, Query
from dotenv import load_dotenv
load_dotenv()

app = FastAPI()

@app.post("/transcribe")
def receive_payload(payload: dict, uid: str = Query(default="default_uid")):
    print("Received payload:", payload)
    print("UID:", uid)
    return {"payload": payload, "uid": uid}

@app.post("/audio")
async def handle_audio_data(request: Request, sample_rate: int = Query(default=8000), uid: str = Query(default="default_uid")):
    try:
        data = await request.body()  # Read the raw bytes from the request body
        if len(data) < 4:
            return {"status": "error", "message": "Data too short to contain header"}

        # Extract header to determine audio format (assuming first 4 bytes are the header)
        header_type = struct.unpack('<I', data[:4])[0]
        audio_data = data[4:]

        # Define WAV file parameters (adjust as needed)
        num_channels = 1   # Example: Mono audio
        sample_width = 2   # Example: 2 bytes (16 bits)
        
        filename = f"received_audio_{uid}.wav"
        
        # Write audio data to a WAV file
        with wave.open(filename, 'wb') as wf:
            wf.setnchannels(num_channels)
            wf.setsampwidth(sample_width)
            wf.setframerate(sample_rate)
            wf.writeframes(audio_data)
        
        print(f"Saved raw audio data to {filename}")
        
        return {"status": "ok", "message": f"Audio saved to {filename}", "uid": uid, "sample_rate": sample_rate}
    
    except Exception as e:
        print(f"Error processing audio data: {e}")
        return {"status": "error", "message": str(e)}

@app.post("/memory")
def handle_memory_event(payload: dict):
    # payload example: {"uid": "...", "memory_id": "...", "segments": [...]}
    uid = payload.get("uid", "")
    memory_id = payload.get("memory_id", "")
    segments = payload.get("segments", [])
    print(f"Memory event for UID={uid}, memory_id={memory_id}:", segments)

    return {"status": "ok", "uid": uid}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8888)