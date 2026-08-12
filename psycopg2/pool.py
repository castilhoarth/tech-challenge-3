class SimpleConnectionPool:
    def __init__(self, minconn, maxconn, dsn=None):
        self.minconn = minconn
        self.maxconn = maxconn
        self.dsn = dsn
    def getconn(self):
        return None
    def putconn(self, conn):
        return None
