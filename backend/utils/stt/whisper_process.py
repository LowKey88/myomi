import whisperflow.streaming as st
import whisperflow.transcriber as ts
from typing import Callable
import asyncio

class WhisperConnection:
    def __init__(self, stream_transcript: Callable[[dict], None], sample_rate: int, language: str):
        self.stream_transcript = stream_transcript
        self.model = ts.get_model()
        self.sample_rate = sample_rate
        self.language = language
        self.session = None
        self.initialized = False
        self._init_lock = asyncio.Lock()
        self._init_complete = asyncio.Event()
        self.last_text = ""  # Track the last complete text
        self.current_segment = None  # Track current segment being built

    async def start(self):
        async with self._init_lock:
            if self.initialized:
                return

            try:
                async def transcribe_async(chunks: list):
                    return await ts.transcribe_pcm_chunks_async(self.model, chunks)

                async def send_back_async(data: dict):
                    print("Received data:", data)
                    if not data.get('data', {}).get('segments'):
                        return
                        
                    current_text = data['data']['text']
                    is_partial = data.get('is_partial', True)
                    
                    # Only process if we have new content
                    if current_text == self.last_text:
                        return
                        
                    # Get the latest segment
                    latest_segment = data['data']['segments'][-1]
                    
                    if is_partial:
                        # For partial updates, only send if we have new words
                        new_text = current_text[len(self.last_text):].strip()
                        if new_text and self.current_segment:
                            self.current_segment['text'] += f" {new_text}"
                            self.current_segment['end'] = latest_segment['end']
                            self.stream_transcript([self.current_segment])
                    else:
                        # For final transcripts, create a new complete segment
                        self.current_segment = {
                            'speaker': 'SPEAKER_01',
                            'start': latest_segment['start'],
                            'end': latest_segment['end'],
                            'text': latest_segment['text'],
                            'is_user': True,
                            'person_id': None
                        }
                        self.stream_transcript([self.current_segment])
                        self.last_text = current_text

                self.session = st.TranscribeSession(transcribe_async, send_back_async)
                self.initialized = True
                self._init_complete.set()
                print("WhisperFlow session initialized successfully")
            except Exception as e:
                print(f"Error starting WhisperFlow session: {e}")
                self.session = None
                self.initialized = False
                self._init_complete.clear()
                await self.close()
                raise e

    async def send(self, data: bytes):
        if not self.initialized:
            await self.start()
            await self._init_complete.wait()
        
        if self.session:
            self.session.add_chunk(data)
        else:
            print("WhisperFlow session not initialized. Cannot send data.")

    async def finish(self):
        if self.session:
            await self.session.stop()
        await self.close()

    async def close(self):
        print("Closing WhisperConnection")

async def process_audio_whisper(
    stream_transcript: Callable[[dict], None], sample_rate: int, language: str, preseconds: int = 0
):
    print("process_audio_whisper", language, sample_rate, preseconds)
    connection = WhisperConnection(stream_transcript=stream_transcript, sample_rate=sample_rate, language=language)
    await connection.start()  # Initialize immediately
    await connection._init_complete.wait()  # Wait for initialization to complete
    return connection