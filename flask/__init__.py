import json
from contextlib import contextmanager


class Response:
    def __init__(self, data='', status=200, content_type='application/json'):
        self.status_code = status
        if isinstance(data, (dict, list)):
            self.data = json.dumps(data).encode('utf-8')
        elif isinstance(data, str):
            self.data = data.encode('utf-8')
        else:
            self.data = data
        self.content_type = content_type


class Request:
    def __init__(self):
        self.headers = {}


class TestClient:
    def __init__(self, app):
        self._app = app

    def get(self, path):
        func = self._app._routes.get((path, 'GET'))
        if not func:
            return Response(json.dumps({'error': 'not found'}), status=404)
        result = func()
        if isinstance(result, Response):
            return result
        if isinstance(result, tuple):
            data, status = result[0], result[1]
            return Response(data, status=status)
        return Response(result)

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc, tb):
        return False


class Flask:
    def __init__(self, name):
        self.name = name
        self._routes = {}
        self.config = {}

    def route(self, path, methods=None):
        methods = methods or ['GET']
        def decorator(f):
            for m in methods:
                self._routes[(path, m)] = f
            return f
        return decorator

    def test_client(self):
        return TestClient(self)

def jsonify(obj):
    return Response(obj)

# Simple request object used by apps that access request.headers
request = Request()
