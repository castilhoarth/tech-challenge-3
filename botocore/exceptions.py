class ClientError(Exception):
    """Minimal ClientError stub used by tests."""
    def __init__(self, error_response, operation_name):
        self.response = error_response
        self.operation_name = operation_name
        super().__init__(f"ClientError: {operation_name}")


class NoCredentialsError(Exception):
    """Stub for NoCredentialsError"""
    pass
