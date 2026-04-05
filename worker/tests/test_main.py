import importlib.util
import unittest
from pathlib import Path


MODULE_PATH = Path(__file__).resolve().parents[1] / "main.py"
SPEC = importlib.util.spec_from_file_location("worker_main", MODULE_PATH)
worker_main = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(worker_main)


class FakeResponse:
    def __init__(self, data):
        self.data = data


class FakeQuery:
    def __init__(self, supabase, table_name, operation):
        self.supabase = supabase
        self.table_name = table_name
        self.operation = operation
        self.filters = {}

    def select(self, columns):
        self.columns = columns
        return self

    def update(self, payload):
        self.payload = payload
        return self

    def insert(self, payload):
        self.payload = payload
        return self

    def eq(self, column, value):
        self.filters[column] = value
        return self

    def single(self):
        return self

    def execute(self):
        self.supabase.calls.append(
            {
                "table": self.table_name,
                "operation": self.operation,
                "filters": dict(self.filters),
                "payload": getattr(self, "payload", None),
            }
        )
        if self.table_name == "recognition_requests" and self.operation == "select":
            return FakeResponse({"status": self.supabase.current_status})
        return FakeResponse(None)


class FakeSupabase:
    def __init__(self, current_status):
        self.current_status = current_status
        self.calls = []

    def table(self, table_name):
        return FakeTable(self, table_name)


class FakeTable:
    def __init__(self, supabase, table_name):
        self.supabase = supabase
        self.table_name = table_name

    def select(self, columns):
        return FakeQuery(self.supabase, self.table_name, "select").select(columns)

    def update(self, payload):
        return FakeQuery(self.supabase, self.table_name, "update").update(payload)

    def insert(self, payload):
        return FakeQuery(self.supabase, self.table_name, "insert").insert(payload)


class WorkerMainTests(unittest.TestCase):
    def test_is_terminal_request_status_recognizes_terminal_values(self):
        self.assertTrue(worker_main.is_terminal_request_status("completed"))
        self.assertTrue(worker_main.is_terminal_request_status("no_match"))
        self.assertTrue(worker_main.is_terminal_request_status("failed"))
        self.assertFalse(worker_main.is_terminal_request_status("pending"))
        self.assertFalse(worker_main.is_terminal_request_status("processing"))
        self.assertFalse(worker_main.is_terminal_request_status(None))

    def test_process_message_skips_stale_terminal_request_before_updates(self):
        supabase = FakeSupabase(current_status="completed")

        worker_main.process_message(
            supabase,
            {
                "request_id": "request-123",
                "station_id": "station-456",
                "stream_url": "https://example.com/stream",
            },
        )

        self.assertEqual(len(supabase.calls), 1)
        self.assertEqual(supabase.calls[0]["table"], "recognition_requests")
        self.assertEqual(supabase.calls[0]["operation"], "select")


if __name__ == "__main__":
    unittest.main()
