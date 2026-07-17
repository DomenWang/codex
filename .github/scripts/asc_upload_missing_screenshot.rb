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
    post: Net::HTTP::Post,
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
version_string = ENV.fetch("ASC_VERSION")
file_path = ENV.fetch("ASC_SCREENSHOT_PATH")
file_name = File.basename(file_path)
file_size = File.size(file_path)

versions = asc_request(
  :get,
  "/v1/apps/#{app_id}/appStoreVersions",
  token,
  params: {
    "filter[versionString]" => version_string,
    "filter[platform]" => "IOS",
    "include" => "appStoreVersionLocalizations",
    "limit" => "10"
  }
)
localization = versions.fetch("included", []).find do |item|
  item["type"] == "appStoreVersionLocalizations" && item.dig("attributes", "locale") == "zh-Hans"
end
abort("Missing zh-Hans version localization") unless localization

sets = asc_request(
  :get,
  "/v1/appStoreVersionLocalizations/#{localization.fetch("id")}/appScreenshotSets",
  token,
  params: {
    "include" => "appScreenshots",
    "limit" => "50"
  }
)
ipad_set = sets.fetch("data", []).find do |item|
  item.dig("attributes", "screenshotDisplayType") == "APP_IPAD_PRO_3GEN_129"
end
abort("Missing 13-inch iPad screenshot set") unless ipad_set

existing_names = sets.fetch("included", []).filter_map do |item|
  item.dig("attributes", "fileName") if item["type"] == "appScreenshots"
end
if existing_names.include?(file_name)
  puts "#{file_name} already exists; no upload needed"
  exit 0
end

created = asc_request(
  :post,
  "/v1/appScreenshots",
  token,
  body: {
    data: {
      type: "appScreenshots",
      attributes: {
        fileName: file_name,
        fileSize: file_size
      },
      relationships: {
        appScreenshotSet: {
          data: {
            type: "appScreenshotSets",
            id: ipad_set.fetch("id")
          }
        }
      }
    }
  }
)
screenshot = created.fetch("data")
screenshot_id = screenshot.fetch("id")

File.open(file_path, "rb") do |file|
  screenshot.dig("attributes", "uploadOperations").each do |operation|
    uri = URI(operation.fetch("url"))
    request = Net::HTTPGenericRequest.new(
      operation.fetch("method"),
      true,
      true,
      uri.request_uri
    )
    operation.fetch("requestHeaders", []).each do |header|
      request[header.fetch("name")] = header.fetch("value")
    end
    file.seek(operation.fetch("offset"))
    request.body = file.read(operation.fetch("length"))
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(request)
    end
    unless response.is_a?(Net::HTTPSuccess)
      warn "Screenshot asset upload failed: #{response.code} #{response.message}"
      warn response.body
      exit 1
    end
  end
end

asc_request(
  :patch,
  "/v1/appScreenshots/#{screenshot_id}",
  token,
  body: {
    data: {
      type: "appScreenshots",
      id: screenshot_id,
      attributes: {
        uploaded: true
      }
    }
  }
)

30.times do
  state = asc_request(:get, "/v1/appScreenshots/#{screenshot_id}", token)
          .dig("data", "attributes", "assetDeliveryState", "state")
  if state == "COMPLETE"
    puts "Uploaded and processed #{file_name} (#{screenshot_id})"
    exit 0
  end
  abort("Screenshot processing failed with state #{state}") if state == "FAILED"
  sleep 2
end

abort("Timed out waiting for #{file_name} to finish processing")
