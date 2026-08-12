class DummyClient:
    def __init__(self, *a, **k):
        pass
    def receive_message(self, *a, **k):
        return {}
    def delete_message(self, *a, **k):
        return {}
    def put_item(self, *a, **k):
        return {}

class Session:
    def __init__(self, region_name=None):
        self.region_name = region_name
    def client(self, service_name, **kwargs):
        return DummyClient()

def Session(region_name=None):
    return Session(region_name=region_name)
