from fastapi import FastAPI, Query, Request
from typing import Optional
import numpy as np
from dotenv import load_dotenv
load_dotenv()

app = FastAPI()

@app.post("/payload")
def receive_payload(payload: dict):
    print(payload)
    return {"status": "received", "payload": payload}



if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8888)