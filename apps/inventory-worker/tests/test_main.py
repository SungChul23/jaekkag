import unittest
from unittest.mock import patch

from app.main import main


class TestMain(unittest.TestCase):

    def run_main(self) -> None:
        with (
            patch("app.main.wait_for_database") as mock_wait_for_database,
            patch("app.main.consume_forever") as mock_consume_forever,
        ):
            main()

        mock_wait_for_database.assert_called_once_with()
        mock_consume_forever.assert_called_once_with()

    def test_metrics_server_starts_once_on_default_port(self) -> None:
        with (
            patch.dict("app.main.os.environ", {}, clear=True),
            patch("app.main.start_http_server") as mock_start_http_server,
        ):
            self.run_main()

        mock_start_http_server.assert_called_once_with(8002)

    def test_metrics_server_uses_configured_port(self) -> None:
        with (
            patch.dict("app.main.os.environ", {"METRICS_PORT": "9102"}, clear=True),
            patch("app.main.start_http_server") as mock_start_http_server,
        ):
            self.run_main()

        mock_start_http_server.assert_called_once_with(9102)


if __name__ == "__main__":
    unittest.main()
