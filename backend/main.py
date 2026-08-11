import os
import shutil
import requests
from typing import List, Optional
from fastapi import FastAPI, HTTPException, UploadFile, File, Form, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import RedirectResponse, HTMLResponse
from pydantic import BaseModel
from sqlalchemy.orm import Session
from dotenv import load_dotenv

from database import engine, Base, get_db, Post, SocialAccount
from ai_engine import ContentAIComposer

load_dotenv()
Base.metadata.create_all(bind=engine)

app = FastAPI(title="Social Orchestrator Engine")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

class AIRepurposeRequest(BaseModel):
    prompt: str

class PostCreate(BaseModel):
    title: str
    content_text: str
    media_url: Optional[str] = None
    target_platforms: List[str]
    scheduled_time: str

@app.get("/health")
def health_check():
    return {"status": "ok"}

# --- Real Google OAuth 2.0 Flow for YouTube ---

@app.get("/auth/youtube")
def youtube_login():
    client_id = os.getenv("YOUTUBE_CLIENT_ID")
    redirect_uri = os.getenv("YOUTUBE_REDIRECT_URI", "http://localhost:8000/auth/youtube/callback")
    scope = "https://www.googleapis.com/auth/youtube.readonly"
    
    if not client_id or client_id == "your_google_client_id_here":
        raise HTTPException(status_code=400, detail="YOUTUBE_CLIENT_ID missing in .env file.")
        
    auth_url = (
        f"https://accounts.google.com/o/oauth2/v2/auth?"
        f"client_id={client_id}&redirect_uri={redirect_uri}&"
        f"response_type=code&scope={scope}&access_type=offline&prompt=consent"
    )
    return RedirectResponse(auth_url)

@app.get("/auth/youtube/callback", response_class=HTMLResponse)
def youtube_callback(code: str, db: Session = Depends(get_db)):
    client_id = os.getenv("YOUTUBE_CLIENT_ID")
    client_secret = os.getenv("YOUTUBE_CLIENT_SECRET")
    redirect_uri = os.getenv("YOUTUBE_REDIRECT_URI", "http://localhost:8000/auth/youtube/callback")

    # 1. Exchange OAuth code for Access Token
    token_url = "https://oauth2.googleapis.com/token"
    token_data = {
        "code": code,
        "client_id": client_id,
        "client_secret": client_secret,
        "redirect_uri": redirect_uri,
        "grant_type": "authorization_code"
    }
    token_res = requests.post(token_url, data=token_data).json()
    access_token = token_res.get("access_token")

    if not access_token:
        raise HTTPException(status_code=400, detail="Failed to retrieve access token from Google.")

    # 2. Query YouTube Data API for Channel Info & Stats
    yt_res = requests.get(
        "https://www.googleapis.com/youtube/v3/channels?mine=true&part=snippet,statistics",
        headers={"Authorization": f"Bearer {access_token}"}
    ).json()

    items = yt_res.get("items", [])
    if not items:
        raise HTTPException(status_code=404, detail="No YouTube channel found for this Google account.")

    channel_snippet = items[0]["snippet"]
    channel_stats = items[0]["statistics"]

    channel_name = channel_snippet["title"]
    views = int(channel_stats.get("viewCount", 0))
    likes = int(channel_stats.get("commentCount", 0)) * 2  # Estimate engagement
    comments = int(channel_stats.get("commentCount", 0))

    # 3. Store/Update in local Database
    acc = db.query(SocialAccount).filter(SocialAccount.platform == "youtube").first()
    if not acc:
        acc = SocialAccount(
            platform="youtube",
            account_name=channel_name,
            access_token=access_token,
            total_impressions=views,
            total_likes=likes,
            total_comments=comments
        )
        db.add(acc)
    else:
        acc.account_name = channel_name
        acc.access_token = access_token
        acc.total_impressions = views
        acc.total_likes = likes
        acc.total_comments = comments

    db.commit()

    return f"""
    <html>
        <body style="background:#090a0f; color:#00f2fe; font-family:sans-serif; text-align:center; padding-top:80px;">
            <h2>✅ YouTube Channel Connected: {channel_name}</h2>
            <p style="color:#aaa;">Views: {views:,} | Comments: {comments:,}</p>
            <p style="color:#666;">You can close this tab now and return to the Social Orchestrator App.</p>
        </body>
    </html>
    """

# --- Account Status & Analytics Endpoints ---

@app.get("/accounts/status")
def get_account_status(db: Session = Depends(get_db)):
    accounts = db.query(SocialAccount).all()
    connected = {acc.platform: acc.account_name for acc in accounts}
    return {
        "youtube": connected.get("youtube"),
        "twitter": connected.get("twitter"),
        "linkedin": connected.get("linkedin")
    }

@app.get("/analytics/summary")
def get_analytics_summary(db: Session = Depends(get_db)):
    accounts = db.query(SocialAccount).all()
    
    total_impressions = sum(acc.total_impressions for acc in accounts)
    total_likes = sum(acc.total_likes for acc in accounts)
    total_comments = sum(acc.total_comments for acc in accounts)
    
    avg_engagement = 0.0
    if total_impressions > 0:
        avg_engagement = round(((total_likes + total_comments) / total_impressions) * 100, 2)
        
    return {
        "total_impressions": total_impressions,
        "total_likes": total_likes,
        "total_comments": total_comments,
        "average_engagement_rate": avg_engagement
    }

# --- Multimodal AI Video & Post Management ---

@app.post("/ai/analyze-video")
async def analyze_video_and_generate(
    prompt: str = Form(...),
    video: UploadFile = File(...)
):
    upload_dir = "uploads"
    os.makedirs(upload_dir, exist_ok=True)
    file_path = os.path.join(upload_dir, video.filename)
    
    with open(file_path, "wb") as buffer:
        shutil.copyfileobj(video.file, buffer)
        
    try:
        result = ContentAIComposer.generate_from_video(file_path, prompt)
        return result
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))
    finally:
        if os.path.exists(file_path):
            os.remove(file_path)

@app.post("/ai/repurpose")
def generate_ai_variations(payload: AIRepurposeRequest):
    try:
        return ContentAIComposer.generate_variations(payload.prompt)
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))

@app.get("/posts")
def get_posts(db: Session = Depends(get_db)):
    posts = db.query(Post).order_by(Post.id.desc()).all()
    return [
        {
            "id": p.id,
            "title": p.title,
            "content_text": p.content_text,
            "media_url": p.media_url,
            "target_platforms": p.target_platforms.split(","),
            "scheduled_time": p.scheduled_time.isoformat(),
            "status": p.status
        } for p in posts
    ]

@app.post("/posts")
def create_post(payload: PostCreate, db: Session = Depends(get_db)):
    new_post = Post(
        title=payload.title,
        content_text=payload.content_text,
        media_url=payload.media_url,
        target_platforms=",".join(payload.target_platforms),
        scheduled_time=payload.scheduled_time,
        status="scheduled"
    )
    db.add(new_post)
    db.commit()
    db.refresh(new_post)
    return {"status": "created", "id": new_post.id}
