from fastapi import FastAPI
from fastapi.responses import JSONResponse
import requests
import yaml
import os
import socket

app = FastAPI(title="sample-api", version="0.1.0")


@app.get("/")
def root():
    return {
        "service": "sample-api",
        "version": "0.1.0",
        "host": socket.gethostname(),
    }


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    return {"status": "ready"}


@app.get("/info")
def info():
    """Returns the runtime version of a couple of key dependencies.
    Useful for confirming which image variant is actually deployed."""
    return {
        "requests": requests.__version__,
        "pyyaml": yaml.__version__,
        "user_uid": os.getuid(),
    }


@app.get("/echo/{message}")
def echo(message: str):
    # Real code path that uses requests + yaml, so the CVEs in the vulnerable image
    # are not "purely theoretical" - the libraries are actually loaded.
    payload = yaml.safe_dump({"message": message})
    return JSONResponse(content={"yaml": payload})