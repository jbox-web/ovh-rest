# OVH Rest client

[![GitHub license](https://img.shields.io/github/license/jbox-web/ovh-rest.svg)](https://github.com/jbox-web/ovh-rest/blob/master/LICENSE)
[![GitHub release](https://img.shields.io/github/release/jbox-web/ovh-rest.svg)](https://github.com/jbox-web/ovh-rest/releases/latest)
[![CI](https://github.com/jbox-web/ovh-rest/workflows/CI/badge.svg)](https://github.com/jbox-web/ovh-rest/actions)
[![Maintainability](https://qlty.sh/gh/jbox-web/projects/ovh-rest/maintainability.svg)](https://qlty.sh/gh/jbox-web/projects/ovh-rest)
[![Code Coverage](https://qlty.sh/gh/jbox-web/projects/ovh-rest/coverage.svg)](https://qlty.sh/gh/jbox-web/projects/ovh-rest)

OVH Rest client is a tiny helper library based on [faraday](https://github.com/lostisland/faraday), wrapping the authentication parts and simplifying interaction with OVH API in Ruby programs.

## Installation

Put this in your `Gemfile` :

```ruby
git_source(:github){ |repo_name| "https://github.com/#{repo_name}.git" }

gem 'ovh-rest', github: 'jbox-web/ovh-rest', tag: '1.0.0'
```

then run `bundle install`.

## Usage

```ruby
require 'ovh-rest'

ovh = OvhRest.new( # shortcut for OvhRest::Client.new
  application_key: <application_key>,
  application_secret: <application_secret>,
  consumer_key: <consumer_key>
)

# Get sms account status
result = ovh.get("/sms/sms-xx12345-1")

puts YAML.dump(result)
=>
{
  "status": "enable",
  "creditsLeft": 42,
  "name": "sms-xx12345-1",
  "userQuantityWithQuota": 0,
  "description": "",
[...]
}

# Send sms
result = ovh.post("/sms/sms-xx12345-1/jobs", {
  "charset" => "UTF-8",
  "class" => "phoneDisplay",
  "coding" => "7bit",
  "priority" => "high",
  "validityPeriod" => 2880,
  "message" => "Dude! Disk is CRITICAL!",
  "receivers" => ["+12345678900", "+12009876543"],
  "sender" => "+12424242424",
})

puts YAML.dump(result)
=>
{
  "totalCreditsRemoved": 2,
  "ids": [
    12345,
    12346
  ]
}
```

`GET` and `DELETE` parameters are sent as a query string, while `POST`, `PUT`
and `PATCH` parameters are sent as a JSON body:

```ruby
# => GET /1.0/me/bill?date=2024-01
ovh.get("/me/bill", { "date" => "2024-01" })
```

The supported verbs are `get`, `head`, `post`, `put`, `patch` and `delete`.

You can pass extra request headers (for example to use the OVH batch mode);
they are merged in but never override the signed authentication headers:

```ruby
ovh.get("/dedicated/server/ns1,ns2", {}, headers: { "X-Ovh-Batch" => "," })
```

## Obtaining a consumer key

If you don't have a consumer key yet, start the OVH credential flow. The call is
unsigned and only needs the application key; the response carries a
`consumerKey` and a `validationUrl` the end user must visit to activate it:

```ruby
ovh = OvhRest::Client.new(
  application_key:    <application_key>,
  application_secret: <application_secret>,
  consumer_key:       nil,
)

ovh.request_consumer_key(
  [{ "method" => "GET", "path" => "/*" }],
  redirection: "https://example.com/callback", # optional
)
# =>
# {
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
ovh = OvhRest::Client.new(
  application_key:    <application_key>,
  application_secret: <application_secret>,
  consumer_key:       <consumer_key>,
  api_url:            "https://eu.api.ovh.com", # endpoint (eu/ca/us)
  api_version:        "1.0",
  timeout:            30,  # request timeout in seconds
  open_timeout:       10,  # connection-open timeout in seconds
  time_delta:         0,     # offset added to the local clock when signing
  auto_sync_time:     false, # sync the clock once before the first request
  retries:            0,     # retry idempotent requests on 429/5xx (0 = off)
  logger:             nil    # a Faraday-compatible logger
)
```

When `retries` is greater than zero, idempotent requests (never `POST`) are
retried on rate limiting (`429`) and transient server errors (`5xx`) with
exponential backoff, honoring the `Retry-After` header.

Credential headers (`X-Ovh-Application`, `X-Ovh-Consumer`, `X-Ovh-Signature`)
are automatically redacted from the logger output.

### Clock skew

OVH rejects requests whose signature timestamp drifts too far from its own
clock. On a host with an unreliable clock, sync once against OVH's time
endpoint; the computed offset is reused for every subsequent request:

```ruby
ovh.synchronize_time!
```

Or let the client sync lazily before the first signed request by passing
`auto_sync_time: true` to the constructor.

## Error handling

A `4xx` response raises `OvhRest::ClientError`, a `5xx` raises
`OvhRest::ServerError` (both subclasses of `OvhRest::ApiError`), and transport
failures (timeouts, connection errors) raise `OvhRest::Error`. Everything
descends from `OvhRest::Error`, so you never need to rescue Faraday classes
directly:

```ruby
begin
  ovh.get("/me")
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

The public API is documented with [YARD](https://yardoc.org/). Generate and
browse it locally with:

```bash
bin/yard doc   # outputs to doc/
bin/yard server
```
