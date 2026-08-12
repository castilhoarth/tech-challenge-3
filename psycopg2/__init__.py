class OperationalError(Exception):
    pass

class IntegrityError(Exception):
    pass

# Minimal placeholder to satisfy imports; real psycopg2 not required for unit tests
