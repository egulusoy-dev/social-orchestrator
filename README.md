# Social Orchestrator AI

An AI-driven multi-platform social media orchestrator, video repurposing engine, and analytics dashboard built for creators.

## Architecture

* **Backend**: FastAPI, Python, SQLite, async background workers, and automated OAuth management.
* **Frontend**: Native macOS SwiftUI application for local media file management, prompt engineering, and live analytics tracking.

## Quick Start

### 1. Run the FastAPI Backend
```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
uvicorn main:app --reload
