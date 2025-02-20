from fastapi import APIRouter
from langchain_openai import ChatOpenAI
from transformers import pipeline
from models import Memory, EndpointResponse
from utils import num_tokens_from_string
from db import store_feedback

router = APIRouter()
chat = ChatOpenAI(model='gpt-4o', temperature=0)

# Load sentiment analysis model
sentiment_analyzer = pipeline("sentiment-analysis")

@router.post('/conversation-feedback', tags=['memory-enhanced'], response_model=EndpointResponse)
def conversation_feedback(memory: Memory):
    transcript = memory.get_transcript()
    # Use hash of transcript as unique identifier
    transcript_hash = str(hash(transcript))
    
    # Sentiment Analysis
    sentiment_result = sentiment_analyzer(transcript)
    sentiment = sentiment_result[0]["label"].lower()
    
    # Generate Summary
    summary_prompt = f"""
      Summarize this conversation in 2 concise sentences.
      
      Transcript:
      {transcript}
      
      Summary:
    """
    summary_response = chat.invoke(summary_prompt)
    summary = summary_response.content if len(summary_response.content) > 5 else "No summary available."
    
    # Generate Feedback
    feedback_prompt = f"""
      Based on the conversation summary below, determine if there's crucial feedback.
      If not, return an empty string. If important, output in 20 words or less.
      
      Summary:
      {summary}
      
      Feedback:
    """
    feedback_response = chat.invoke(feedback_prompt)
    feedback = feedback_response.content if len(feedback_response.content) > 5 else ""
    
    # Save to Redis using db utility function
    store_feedback(transcript_hash, feedback, sentiment, summary)
    
    # Only return message as per EndpointResponse model
    return {'message': feedback}
