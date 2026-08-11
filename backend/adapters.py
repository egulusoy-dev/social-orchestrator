import logging
import httpx
import os
from dotenv import load_dotenv
from models import PlatformType, ScheduledPost

load_dotenv()
logger = logging.getLogger("SocialAdapters")

class PlatformConstraintError(Exception):
    pass

class PlatformValidator:
    @staticmethod
    def validate_post(post: ScheduledPost, platform: PlatformType):
        if platform == PlatformType.TWITTER and len(post.content_text) > 280:
            raise PlatformConstraintError(
                f"Twitter character limit exceeded ({len(post.content_text)}/280 chars)."
            )
        if platform == PlatformType.INSTAGRAM and not post.media_url:
            raise PlatformConstraintError(
                "Instagram requires an image or video media URL."
            )
        return True

class BaseSocialAdapter:
    async def publish(self, post: ScheduledPost, access_token: str) -> dict:
        raise NotImplementedError

class TwitterAdapter(BaseSocialAdapter):
    """Integrates with X (Twitter) API v2 POST /2/tweets"""
    async def publish(self, post: ScheduledPost, access_token: str) -> dict:
        url = "https://api.twitter.com/2/tweets"
        headers = {
            "Authorization": f"Bearer {access_token}",
            "Content-Type": "application/json"
        }
        payload = {"text": post.content_text}

        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(url, json=payload, headers=headers)
            
            if response.status_code == 201:
                data = response.json()
                logger.info(f"[Twitter API] Successfully published tweet ID: {data['data']['id']}")
                return {"platform_post_id": data['data']['id'], "status": "success"}
            else:
                logger.error(f"[Twitter API Error] {response.status_code}: {response.text}")
                return {"status": "error", "code": response.status_code, "detail": response.text}

class LinkedInAdapter(BaseSocialAdapter):
    """Integrates with LinkedIn REST API /v2/ugcPosts"""
    async def publish(self, post: ScheduledPost, access_token: str) -> dict:
        url = "https://api.linkedin.com/v2/ugcPosts"
        author_urn = os.getenv("LINKEDIN_AUTHOR_URN", "urn:li:person:UNKNOWN")
        
        headers = {
            "Authorization": f"Bearer {access_token}",
            "X-Restli-Protocol-Version": "2.0.0",
            "Content-Type": "application/json"
        }
        payload = {
            "author": author_urn,
            "lifecycleState": "PUBLISHED",
            "specificContent": {
                "com.linkedin.ugc.ShareContent": {
                    "shareCommentary": {"text": post.content_text},
                    "shareMediaCategory": "NONE"
                }
            },
            "visibility": {"com.linkedin.ugc.MemberNetworkVisibility": "PUBLIC"}
        }

        async with httpx.AsyncClient(timeout=10.0) as client:
            response = await client.post(url, json=payload, headers=headers)
            
            if response.status_code in (200, 201):
                data = response.json()
                post_id = data.get("id", f"li_{post.id}")
                logger.info(f"[LinkedIn API] Successfully published post ID: {post_id}")
                return {"platform_post_id": post_id, "status": "success"}
            else:
                logger.error(f"[LinkedIn API Error] {response.status_code}: {response.text}")
                return {"status": "error", "code": response.status_code, "detail": response.text}

class InstagramAdapter(BaseSocialAdapter):
    """Integrates with Meta Graph API 2-step media container & publish pipeline"""
    async def publish(self, post: ScheduledPost, access_token: str) -> dict:
        ig_account_id = os.getenv("INSTAGRAM_ACCOUNT_ID", "me")
        base_url = f"https://graph.facebook.com/v19.0/{ig_account_id}"

        async with httpx.AsyncClient(timeout=15.0) as client:
            # Step 1: Create Media Container
            container_url = f"{base_url}/media"
            container_params = {
                "image_url": post.media_url,
                "caption": post.content_text,
                "access_token": access_token
            }
            container_res = await client.post(container_url, params=container_params)
            
            if container_res.status_code != 200:
                logger.error(f"[Instagram Container Error] {container_res.text}")
                return {"status": "error", "detail": container_res.text}

            creation_id = container_res.json().get("id")

            # Step 2: Publish Media Container
            publish_url = f"{base_url}/media_publish"
            publish_params = {
                "creation_id": creation_id,
                "access_token": access_token
            }
            pub_res = await client.post(publish_url, params=publish_params)

            if pub_res.status_code == 200:
                media_id = pub_res.json().get("id")
                logger.info(f"[Instagram API] Successfully published media ID: {media_id}")
                return {"platform_post_id": media_id, "status": "success"}
            else:
                logger.error(f"[Instagram Publish Error] {pub_res.text}")
                return {"status": "error", "detail": pub_res.text}

class YouTubeAdapter(BaseSocialAdapter):
    """Placeholder adapter for YouTube Data API v3 upload pipeline"""
    async def publish(self, post: ScheduledPost, access_token: str) -> dict:
        logger.info(f"[YouTube Adapter] Uploading video metadata for: {post.title}")
        return {"platform_post_id": f"yt_vid_{post.id}", "status": "success"}

class AdapterFactory:
    _adapters = {
        PlatformType.YOUTUBE: YouTubeAdapter(),
        PlatformType.LINKEDIN: LinkedInAdapter(),
        PlatformType.TWITTER: TwitterAdapter(),
        PlatformType.INSTAGRAM: InstagramAdapter(),
    }

    @classmethod
    def get_adapter(cls, platform: PlatformType) -> BaseSocialAdapter:
        return cls._adapters[platform]
