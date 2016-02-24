from notebook.services.config import ConfigManager
c = get_config()
cm = ConfigManager()
c.NotebookApp.oauth_client_id = "df01cf317b5ea36f741f"
c.NotebookApp.oauth_client_secret = "365d8a71924c0597fbfc8c08a3c04d8590aeee6b"
cm.update('notebook', {"oauth_client_id": c.NotebookApp.oauth_client_id})
