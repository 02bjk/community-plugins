# SearXNG Search

Privately search the web using SearXNG directly from the Noctalia launcher.

## Plugin

| Field | Value |
| --- | --- |
| ID | `02bjk/searxng` |
| Entries | Launcher provider: `search` |
| Launcher Prefix | `/sx` |

## Requirements

Install `xdg-open` on `PATH`.

## Usage

Open the Noctalia launcher and type `/sx` followed by your search query:

```sh
/sx linux kernel
```

- Results appear dynamically as you type.
- Press **Enter** on any result to open the link in your default web browser via `xdg-open`.
- If an instant calculation or answer is returned, press **Enter** to copy it directly to your clipboard.

## Settings

| Setting | Type | Default | Description |
| --- | --- | --- | --- |
| `instance_url` | `string` | `https://search.lumy.live` | The base URL of the SearXNG instance to query. |
| `categories` | `string` | `general` | Comma-separated list of search categories (e.g., `general`, `it`, `science`). |
| `max_results` | `int` | `8` | Maximum number of web results displayed in the launcher. |
| `safesearch` | `select` | `0` | SafeSearch filter level: None (`0`), Moderate (`1`), or Strict (`2`). |

## Notes

- All search requests are made over HTTP directly to the configured SearXNG instance.
- No telemetry or tracking data is collected by this plugin.
- URLs are strictly validated to `http://` or `https://` schemes before being dispatched to `xdg-open`.
