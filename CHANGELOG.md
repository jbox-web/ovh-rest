# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `#patch` and `#head` verbs.
- Per-request `headers:` argument on every verb (e.g. for OVH batch mode); merged in without overriding the signed authentication headers.
- `retries:` option to retry idempotent requests on `429`/`5xx` with exponential backoff (via `faraday-retry`), honoring `Retry-After`.
- `#request_consumer_key` to start the OVH credential flow (`POST /auth/credential`), with access-rules validation, and `#current_credential` (`GET /auth/currentCredential`).
- `#synchronize_time!` and the `auto_sync_time:` option to handle clock skew via OVH's `/auth/time` endpoint (thread-safe lazy sync).
- `timeout:` and `open_timeout:` options (defaults: 30s / 10s).
- `OvhRest::Error`, `OvhRest::ApiError` and the `OvhRest::ClientError` (4xx) / `OvhRest::ServerError` (5xx) subclasses, exposing `message`, `error_code`, `http_code`, `status`, `response`; the gem no longer leaks Faraday exceptions.
- Credential headers (`X-Ovh-Application`, `X-Ovh-Consumer`, `X-Ovh-Signature`) are now redacted from logger output.
- Full YARD documentation of the public API.
- `OvhRest.new` shortcut, `client:` constructor option to inject a Faraday connection, and `#api_url` / `#api_version` readers.

### Changed

- **Breaking:** `GET`/`DELETE` parameters are now sent as a URL query string instead of a JSON body, and empty parameters produce an empty body (instead of `{}`), matching the OVH signing convention.
- **Breaking:** removed the public `client=` writer; inject via the `client:` constructor option instead.
- Renamed the internal `OvhRest::Client::VERSION` constant to `API_VERSION` to avoid clashing with the gem version.
- Path segments are now percent-encoded (slashes and OVH batch sub-delimiters preserved) so the signed URL always matches the URL sent.
