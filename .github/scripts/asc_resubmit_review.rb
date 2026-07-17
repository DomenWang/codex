#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"
require "jwt"
require "net/http"
require "openssl"
require "uri"

key_id = ENV.fetch("APPLE_API_KEY_ID")
issuer_id = ENV.fetch("APPLE_API_ISSUER_ID")
private_key = OpenSSL::PKey.read(Base64.decode64(ENV.fetch("APPLE_API_KEY_BASE64")))
now = Time.now.to_i
token = JWT.encode(
  { iss: issuer_id, iat: now, exp: now + 1_200, aud: "appstoreconnect-v1" },
  private_key,
  "ES256",
  { kid: key_id, typ: "JWT" }
)

def asc_request(method, path, token, params: {}, body: nil)
  uri = URI("https://api.appstoreconnect.apple.com#{path}")
  uri.query = URI.encode_www_form(params) unless params.empty?
  request_class = {
    get: Net::HTTP::Get,
    patch: Net::HTTP::Patch
  }.fetch(method)
  request = request_class.new(uri)
  request["Authorization"] = "Bearer #{token}"
  if body
    request["Content-Type"] = "application/json"
    request.body = JSON.generate(body)
  end
  response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
    http.request(request)
  end
  unless response.is_a?(Net::HTTPSuccess)
    warn "ASC #{method.upcase} #{path} failed: #{response.code} #{response.message}"
    warn response.body
    exit 1
  end
  response.body.empty? ? {} : JSON.parse(response.body)
end

app_id = ENV.fetch("ASC_APP_ID")
submissions = asc_request(
  :get,
  "/v1/apps/#{app_id}/reviewSubmissions",
  token,
  params: { "limit" => "50" }
)
submission = submissions.fetch("data", []).find do |item|
  item.dig("attributes", "platform") == "IOS" &&
    item.dig("attributes", "state") == "UNRESOLVED_ISSUES"
end
abort("No unresolved iOS review submission found") unless submission

submission_id = submission.fetch("id")
asc_request(
  :patch,
  "/v1/reviewSubmissions/#{submission_id}",
  token,
  body: {
    data: {
      type: "reviewSubmissions",
      id: submission_id,
      attributes: {
        submitted: true
      }
    }
  }
)

20.times do
  current = asc_request(:get, "/v1/reviewSubmissions/#{submission_id}", token)
  state = current.dig("data", "attributes", "state")
  if %w[WAITING_FOR_REVIEW IN_REVIEW].include?(state)
    puts "Review submission #{submission_id} is now #{state}"
    exit 0
  end
  abort("Review submission entered unexpected state #{state}") if %w[CANCELING COMPLETE].include?(state)
  sleep 2
end

abort("Timed out waiting for review submission #{submission_id}")
