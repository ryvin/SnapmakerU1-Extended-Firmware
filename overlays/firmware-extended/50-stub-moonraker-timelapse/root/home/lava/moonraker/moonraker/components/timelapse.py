from __future__ import annotations
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from confighelper import ConfigHelper

class Timelapse:

    def __init__(self, confighelper: ConfigHelper) -> None:
        self.confighelper = confighelper
        self.server = confighelper.get_server()

        # Default timelapse to ON so every print records a timelapse
        # without requiring manual enable via touchscreen each time.
        self.enabled = True

        # setup eventhandlers and endpoints
        file_manager = self.server.lookup_component("file_manager")
        camera_path = file_manager.datapath.joinpath("camera")
        file_manager.register_directory("timelapse",
                                        str(camera_path),
                                        full_access=True
                                        )

        # required by Mainsail API
        self.server.register_endpoint(
            "/machine/timelapse/settings",
            ["GET", "POST"],
            self._handle_settings
        )
        self.server.register_endpoint(
            "/machine/timelapse/lastframeinfo",
            ["GET"],
            self._handle_lastframeinfo
        )

    async def _handle_settings(self, web_request: WebRequest) -> Dict[str, Any]:
        """Handle timelapse settings - defaults to enabled."""
        if web_request.get_method() == "POST":
            self.enabled = web_request.get_boolean("enabled", self.enabled)
        return {
            "enabled": self.enabled
        }

    async def _handle_lastframeinfo(self, web_request: WebRequest) -> Dict[str, Any]:
        """Return stub last frame info."""
        return {
            "lastframefile": "",
            "count": 0
        }

def load_component(config: ConfigHelper) -> Timelapse:
    return Timelapse(config)
