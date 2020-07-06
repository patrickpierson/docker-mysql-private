from typing import List, Dict
from flask import Flask
import requests
import json
from pprint import pprint
app = Flask(__name__)


@app.route('/app/B')
def index() -> str:
    res = requests.get('http://localhost:5000/app/A')
    return "letter_count: %s" % len(json.dumps(res.json().get('favorite_colors')))


if __name__ == '__main__':
    app.run(host='0.0.0.0',port=5001)
