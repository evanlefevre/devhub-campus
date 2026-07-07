import logging
import os
from fastapi import FastAPI

LOG_LEVEL = os.environ.get("LOG_LEVEL", "info").upper()
logging.basicConfig(level=getattr(logging, LOG_LEVEL, logging.INFO),
                    format='{"t":"%(asctime)s","level":"%(levelname)s","msg":"%(message)s"}')
log = logging.getLogger("planning")

app = FastAPI(title="planning-service")

SLOTS = [
    {"id": 1, "salle": "A-101", "jour": "lundi",    "creneau": "09:00-12:00"},
    {"id": 2, "salle": "B-203", "jour": "mardi",    "creneau": "14:00-17:00"},
    {"id": 3, "salle": "C-12",  "jour": "mercredi", "creneau": "09:00-12:00"},
]


@app.get("/healthz")
def healthz():
    return {"ok": True, "service": "planning"}


@app.get("/slots")
def slots():
    return SLOTS


log.debug("planning ready")
