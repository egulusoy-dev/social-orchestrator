import os
import time
from google import genai
from google.genai import types
from pydantic import BaseModel
from dotenv import load_dotenv

load_dotenv()

class RepurposedContentResponse(BaseModel):
    twitter_text: str
    linkedin_text: str
    youtube_script: str
    twitter_hashtags: str
    linkedin_hashtags: str
    youtube_tags: str

class ContentAIComposer:
    @staticmethod
    def generate_from_video(video_path: str, prompt_text: str) -> RepurposedContentResponse:
        api_key = os.getenv("GEMINI_API_KEY")
        if not api_key:
            raise ValueError("GEMINI_API_KEY missing from environment.")

        client = genai.Client(api_key=api_key)

        uploaded_file = client.files.upload(file=video_path)
        
        file_ref = client.files.get(name=uploaded_file.name)
        while file_ref.state.name == "PROCESSING":
            time.sleep(2)
            file_ref = client.files.get(name=uploaded_file.name)

        if file_ref.state.name != "ACTIVE":
            raise ValueError(f"Gemini file processing failed with state: {file_ref.state.name}")

        prompt = f"""
You are an expert social media video strategist (like vidIQ).
Analyze this attached video clip along with user instructions: "{prompt_text}"

Generate:
1. YouTube Shorts: Click-worthy title suggestions, script/caption breakdown, and description.
2. Twitter/X: Post with a strong visual hook.
3. LinkedIn: Professional insight takeaway.
4. Hashtags: 3-5 target hashtags for YouTube, Twitter, and LinkedIn.
"""

        response = client.models.generate_content(
            model='gemini-2.5-flash',
            contents=[file_ref, prompt],
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=RepurposedContentResponse,
            ),
        )

        return RepurposedContentResponse.model_validate_json(response.text)

    @staticmethod
    def generate_variations(core_idea: str) -> RepurposedContentResponse:
        api_key = os.getenv("GEMINI_API_KEY")
        client = genai.Client(api_key=api_key)

        prompt = f"""
You are an expert social media strategist.
Adapt this content idea into platform-specific posts and hashtags:
"{core_idea}"
"""

        response = client.models.generate_content(
            model='gemini-2.5-flash',
            contents=prompt,
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=RepurposedContentResponse,
            ),
        )

        return RepurposedContentResponse.model_validate_json(response.text)
