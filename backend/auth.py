import httpx
import logging
from datetime import datetime, timedelta
from sqlmodel import Session
from models import SocialAccount, PlatformType

logger = logging.getLogger("AuthManager")

class TokenManager:
    @staticmethod
    async def get_valid_token(account: SocialAccount, session: Session) -> str:
        """Returns active access token or executes OAuth refresh flow if expired."""
        if account.token_expires_at and account.token_expires_at <= datetime.utcnow():
            logger.info(f"Token expired for {account.platform}. Initiating OAuth refresh...")
            
            if account.platform == PlatformType.TWITTER and account.refresh_token:
                new_token, expires_in = await TokenManager._refresh_twitter_token(account.refresh_token)
                if new_token:
                    account.access_token = new_token
                    account.token_expires_at = datetime.utcnow() + timedelta(seconds=expires_in)
                    session.add(account)
                    session.commit()
                    
        return account.access_token

    @staticmethod
    async def _refresh_twitter_token(refresh_token: str):
        url = "https://api.twitter.com/2/oauth2/token"
        data = {
            "grant_type": "refresh_token",
            "refresh_token": refresh_token,
            "client_id": "YOUR_TWITTER_CLIENT_ID"
        }
        async with httpx.AsyncClient() as client:
            res = await client.post(url, data=data)
            if res.status_code == 200:
                body = res.json()
                return body["access_token"], body.get("expires_in", 7200)
        return None, 0
