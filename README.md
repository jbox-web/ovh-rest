# OVH Rest client

[![GitHub license](https://img.shields.io/github/license/jbox-web/ovh-rest.svg)](https://github.com/jbox-web/ovh-rest/blob/master/LICENSE)
[![GitHub release](https://img.shields.io/github/release/jbox-web/ovh-rest.svg)](https://github.com/jbox-web/ovh-rest/releases/latest)
[![CI](https://github.com/jbox-web/ovh-rest/workflows/CI/badge.svg)](https://github.com/jbox-web/ovh-rest/actions)
[![Maintainability](https://qlty.sh/gh/jbox-web/projects/ovh-rest/maintainability.svg)](https://qlty.sh/gh/jbox-web/projects/ovh-rest)
[![Code Coverage](https://qlty.sh/gh/jbox-web/projects/ovh-rest/coverage.svg)](https://qlty.sh/gh/jbox-web/projects/ovh-rest)

A tiny Ruby client for the [OVH REST API](https://api.ovh.com/), built on
[Faraday](https://github.com/lostisland/faraday). It handles OVH's
request-signing authentication and gives you a thin, predictable HTTP client —
nothing more.

- **One method per HTTP verb** — `get`, `head`, `post`, `put`, `patch`, `delete`.
- **Automatic request signing** with the OVH application/consumer keys.
- **Consumer-key flow** and **clock-skew** handling built in.
- **Typed errors** (`OvhRest::ClientError` / `ServerError`) instead of leaking Faraday.
- **Optional retries** on rate limiting and transient server errors.
- **Credential redaction** in logs.

## Table of contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Quick start](#quick-start)
- [Making requests](#making-requests)
- [Obtaining a consumer key](#obtaining-a-consumer-key)
- [Configuration](#configuration)
- [Clock skew](#clock-skew)
- [Retries](#retries)
- [Logging](#logging)
- [Error handling](#error-handling)
- [Documentation](#documentation)
- [Development](#development)
- [License](#license)

## Requirements

- Ruby >= 3.2 (also tested on JRuby and TruffleRuby).

## Installation

Add the gem to your `Gemfile`:

```ruby
git_source(:github) { |repo_name| "https://github.com/#{repo_name}.git" }

gem 'ovh-rest', github: 'jbox-web/ovh-rest', tag: '1.0.0'
```

then run `bundle install`.

You will need an `application_key`, an `application_secret` and a `consumer_key`.
Create an application at the OVH API console for your region
([EU](https://eu.api.ovh.com/createApp/), [CA](https://ca.api.ovh.com/createApp/),
[US](https://api.us.ovhcloud.com/createApp/)); see
[Obtaining a consumer key](#obtaining-a-consumer-key) to mint the consumer key.

## Quick start

```ruby
require 'ovh-rest'

ovh = OvhRest.new( # shortcut for OvhRest::Client.new
  application_key:    '<application_key>',
  application_secret: '<application_secret>',
  consumer_key:       '<consumer_key>',
)

# GET an SMS account status — the parsed JSON body is returned as a Ruby Hash
ovh.get('/sms/sms-xx12345-1')
# => { "status" => "enable", "creditsLeft" => 42, "name" => "sms-xx12345-1", ... }

# POST to send an SMS
ovh.post('/sms/sms-xx12345-1/jobs', {
  'charset'        => 'UTF-8',
  'class'          => 'phoneDisplay',
  'coding'         => '7bit',
  'priority'       => 'high',
  'validityPeriod' => 2880,
  'message'        => 'Dude! Disk is CRITICAL!',
  'receivers'      => ['+12345678900', '+12009876543'],
  'sender'         => '+12424242424',
})
# => { "totalCreditsRemoved" => 2, "ids" => [12345, 12346] }
```

Every call returns the parsed JSON response body, or raises on error (see
[Error handling](#error-handling)).

## Making requests

`GET`, `HEAD` and `DELETE` send their parameters as a **query string**, while
`POST`, `PUT` and `PATCH` send them as a **JSON body**:

```ruby
ovh.get('/me/bill', { 'date' => '2024-01' })  # => GET /1.0/me/bill?date=2024-01
ovh.put('/me', { 'firstname' => 'Ada' })      # => PUT  /1.0/me  body: {"firstname":"Ada"}
```

You can pass extra request headers as a third argument — for example to use the
OVH [batch mode](https://help.ovhcloud.com/csm/en-api-getting-started-ovhcloud-api).
They are merged in but never override the signed authentication headers:

```ruby
ovh.get('/dedicated/server/ns1,ns2', {}, headers: { 'X-Ovh-Batch' => ',' })
```

For uncommon needs you can also reach the underlying call:

```ruby
ovh.query(method: 'GET', path: '/me')   # same as ovh.get('/me')
ovh.build_headers(method: 'GET', path: '/me')  # just the signed X-Ovh-* headers
```

## Obtaining a consumer key

If you don't have a consumer key yet, start the OVH credential flow. The call is
unsigned and only needs the application key; the response carries a
`consumerKey` and a `validationUrl` the end user must visit to activate it:

```ruby
ovh = OvhRest.new(
  application_key:    '<application_key>',
  application_secret: '<application_secret>',
  consumer_key:       nil,
)

ovh.request_consumer_key(
  [{ 'method' => 'GET', 'path' => '/*' }],
  redirection: 'https://example.com/callback', # optional
)
# => {
#   "consumerKey"   => "...",
#   "validationUrl" => "https://...",
#   "state"         => "pendingValidation"
# }
```

Inspect the credential currently in use (scope, status, expiration) with:

```ruby
ovh.current_credential
```

## Configuration

```ruby
ovh = OvhRest.new(
  application_key:    '<application_key>',
  application_secret: '<application_secret>',
  consumer_key:       '<consumer_key>',
  api_url:            'https://eu.api.ovh.com',
  api_version:        '1.0',
  timeout:            30,
  open_timeout:       10,
  time_delta:         0,
  auto_sync_time:     false,
  retries:            0,
  logger:             nil,
)
```

| Option               | Default                      | Description                                                        |
| -------------------- | ---------------------------- | ------------------------------------------------------------------ |
| `application_key`    | —                            | OVH application key.                                               |
| `application_secret` | —                            | OVH application secret (used to sign requests).                    |
| `consumer_key`       | —                            | OVH consumer key (may be `nil` when only calling `request_consumer_key`). |
| `api_url`            | `https://eu.api.ovh.com`     | API endpoint (EU/CA/US).                                           |
| `api_version`        | `1.0`                        | API version.                                                      |
| `timeout`            | `30`                         | Request timeout, in seconds.                                      |
| `open_timeout`       | `10`                         | Connection-open timeout, in seconds.                              |
| `time_delta`         | `0`                          | Offset added to the local clock when signing (see [Clock skew](#clock-skew)). |
| `auto_sync_time`     | `false`                      | Sync the clock against OVH once before the first signed request.  |
| `retries`            | `0`                          | Retry idempotent requests on `429`/`5xx` (see [Retries](#retries)). |
| `logger`             | `nil`                        | A Faraday-compatible logger (see [Logging](#logging)).            |

The configured endpoint is readable via `ovh.api_url`, `ovh.api_version` and the
combined `ovh.api_uri`.

## Clock skew

OVH rejects requests whose signature timestamp drifts too far from its own
clock. On a host with an unreliable clock, sync once against OVH's time
endpoint; the computed offset is reused for every subsequent request:

```ruby
ovh.synchronize_time!
```

Or let the client sync lazily before the first signed request by passing
`auto_sync_time: true` to the constructor.

## Retries

When `retries` is greater than zero, **idempotent** requests (never `POST`) are
retried on rate limiting (`429`) and transient server errors
(`500`, `502`, `503`, `504`) with exponential backoff, honoring the
`Retry-After` header:

```ruby
ovh = OvhRest.new(application_key: '...', application_secret: '...', consumer_key: '...', retries: 3)
```

## Logging

Pass any Faraday-compatible logger to trace requests and responses. The
credential headers (`X-Ovh-Application`, `X-Ovh-Consumer`, `X-Ovh-Signature`)
are automatically redacted from the output:

```ruby
require 'logger'

ovh = OvhRest.new(application_key: '...', application_secret: '...', consumer_key: '...', logger: Logger.new($stdout))
```

## Error handling

A `4xx` response raises `OvhRest::ClientError`, a `5xx` raises
`OvhRest::ServerError` (both subclasses of `OvhRest::ApiError`), and transport
failures (timeouts, connection errors) raise `OvhRest::Error`. Everything
descends from `OvhRest::Error`, so you never need to rescue Faraday classes
directly:

```ruby
begin
  ovh.get('/me')
rescue OvhRest::ClientError => e   # 4xx
  e.message     # OVH error message
  e.error_code  # OVH "errorCode", e.g. "INVALID_CREDENTIAL"
  e.http_code   # OVH "httpCode", e.g. "403 Forbidden"
  e.status      # HTTP status, e.g. 403
rescue OvhRest::ServerError => e   # 5xx
  e.status
rescue OvhRest::Error => e         # transport-level failure
  e.message
end
```

## Documentation

The public API is documented with [YARD](https://yardoc.org/):

```bash
bin/yard doc     # generate HTML docs into doc/
bin/yard server  # browse them at http://localhost:8808
```

## Development

After checking out the repo, run `bundle install`, then:

```bash
bin/rspec      # run the test suite
bin/rubocop    # lint
bin/guard      # auto-run specs on file change
bin/console    # IRB session with the gem loaded
```

Bug reports and pull requests are welcome on GitHub at
<https://github.com/jbox-web/ovh-rest>.

## License

Released under the [MIT License](LICENSE).
