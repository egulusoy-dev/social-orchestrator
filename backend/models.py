from enum import Enum
from typing import Optional, List
from datetime import datetime
from sqlmodel import SQLModel, Field, JSON, Column

class PlatformType(str, Enum):
    YOUTUBE = "youtube"
    LINKEDIN = "linkedin"
    TWITTER = "twitter"
    INSTAGRAM = "instagram"

class PostStatus(str, Enum):
    DRAFT = "draft"
    SCHEDULED = "scheduled"
    PUBLISHED = "published"
    FAILED = "failed"

class SocialAccount(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    platform: PlatformType = Field(index=True)
    account_name: str
    access_token: str
    refresh_token: Optional[str] = None
    token_expires_at: Optional[datetime] = None
    is_active: bool = Field(default=True)

class ScheduledPost(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    title: str
    content_text: str
    media_url: Optional[str] = None
    target_platforms: List[str] = Field(default_factory=list, sa_column=Column(JSON))
    scheduled_time: datetime
    status: PostStatus = Field(default=PostStatus.SCHEDULED, index=True)
    published_metadata: Optional[str] = Field(default="{}", sa_column=Column(JSON))

class UnifiedMetric(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    platform: PlatformType = Field(index=True)
    post_id: str
    timestamp: datetime = Field(default_factory=datetime.utcnow)
    impressions: int = 0
    likes: int = 0
    comments: int = 0
    shares: int = 0
    engagement_rate: float = 0.0
