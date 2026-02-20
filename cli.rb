#!/usr/bin/env ruby
# frozen_string_literal: true

# Calendly CLI — manage event types, scheduled events, availability, and webhooks.
#
# Usage:
#   ruby cli.rb <command> [args] [options]
#
# Event Types:
#   ruby cli.rb types [--active] [-v]              List event types
#   ruby cli.rb types get <uuid> [-v]              Get a single event type
#   ruby cli.rb types create <name> [options]       Create a new event type
#   ruby cli.rb types update <uuid> [options]       Update an event type
#   ruby cli.rb types activate <uuid>               Activate an event type
#   ruby cli.rb types deactivate <uuid>             Deactivate (soft-delete)
#   ruby cli.rb types link <uuid>                   Generate a single-use scheduling link
#
# Scheduled Events:
#   ruby cli.rb events [--status active|canceled]   List scheduled events
#   ruby cli.rb events get <uuid>                   Get event details + invitees
#   ruby cli.rb events cancel <uuid> [--reason "…"] Cancel a scheduled event
#
# Invitees:
#   ruby cli.rb invitees <event_uuid>               List invitees for an event
#
# Availability:
#   ruby cli.rb availability                        Show availability schedules
#   ruby cli.rb availability get <uuid>             Show a specific schedule
#
# Webhooks:
#   ruby cli.rb webhooks                            List webhook subscriptions
#   ruby cli.rb webhooks create <url> [--events e1,e2,…]  Create a webhook
#   ruby cli.rb webhooks delete <uuid>              Delete a webhook
#
# Account:
#   ruby cli.rb me                                  Show current user info
#
# Requires CALENDLY_ACCESS_TOKEN in .env or environment.

require "bundler/setup"
require "dotenv/load"
require "net/http"
require "json"
require "uri"
require "time"

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

TOKEN = ENV.fetch("CALENDLY_ACCESS_TOKEN") {
  abort "Error: CALENDLY_ACCESS_TOKEN not set. Copy .env.example to .env and add your token."
}
BASE_URL = "https://api.calendly.com"

# ---------------------------------------------------------------------------
# HTTP helpers
# ---------------------------------------------------------------------------

def api_request(method, path, body: nil, params: {})
  uri = URI("#{BASE_URL}#{path}")
  uri.query = URI.encode_www_form(params) unless params.empty?

  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true

  request = case method
            when :get    then Net::HTTP::Get.new(uri)
            when :post   then Net::HTTP::Post.new(uri)
            when :patch  then Net::HTTP::Patch.new(uri)
            when :delete then Net::HTTP::Delete.new(uri)
            end

  request["Authorization"] = "Bearer #{TOKEN}"
  request["Content-Type"] = "application/json"
  request.body = body.to_json if body

  response = http.request(request)
  parsed = JSON.parse(response.body) rescue nil

  unless response.is_a?(Net::HTTPSuccess) || response.code == "204"
    msg = parsed ? JSON.pretty_generate(parsed) : response.body
    abort "API error (#{response.code}):\n#{msg}"
  end

  parsed
end

def get(path, params: {})   = api_request(:get, path, params: params)
def post(path, body)         = api_request(:post, path, body: body)
def patch(path, body)        = api_request(:patch, path, body: body)
def delete(path)             = api_request(:delete, path)

def uuid_from_uri(uri)
  uri.split("/").last
end

# ---------------------------------------------------------------------------
# API: User
# ---------------------------------------------------------------------------

def current_user
  get("/users/me")["resource"]
end

def user_uri
  @user_uri ||= current_user["uri"]
end

def org_uri
  @org_uri ||= current_user["current_organization"]
end

# ---------------------------------------------------------------------------
# API: Event Types
# ---------------------------------------------------------------------------

def list_event_types(active_only: false)
  data = get("/event_types", params: { user: user_uri })
  types = data["collection"]
  types = types.select { |et| et["active"] } if active_only
  types
end

def get_event_type(uuid)
  get("/event_types/#{uuid}")["resource"]
end

def create_event_type(name:, duration: 30, slug: nil, description: nil, color: nil,
                      location: nil, active: false, secret: false)
  body = {
    name: name,
    owner: user_uri,
    duration: duration.to_i,
    active: active,
    secret: secret
  }
  body[:slug] = slug if slug
  body[:description] = description if description
  body[:color] = color if color
  body[:locations] = [{ kind: location }] if location

  post("/event_types", body)["resource"]
end

def update_event_type(uuid, **attrs)
  body = {}
  body[:name]        = attrs[:name]          if attrs.key?(:name)
  body[:duration]    = attrs[:duration].to_i if attrs.key?(:duration)
  body[:description] = attrs[:description]   if attrs.key?(:description)
  body[:color]       = attrs[:color]         if attrs.key?(:color)
  body[:active]      = attrs[:active]        if attrs.key?(:active)
  body[:secret]      = attrs[:secret]        if attrs.key?(:secret)
  body[:locations]   = [{ kind: attrs[:location] }] if attrs.key?(:location)
  body[:slug]        = attrs[:slug]          if attrs.key?(:slug)

  abort "Nothing to update. Pass options like --name, --duration, --description, etc." if body.empty?
  patch("/event_types/#{uuid}", body)["resource"]
end

def activate_event_type(uuid)
  patch("/event_types/#{uuid}", { active: true })["resource"]
end

def deactivate_event_type(uuid)
  patch("/event_types/#{uuid}", { active: false })["resource"]
end

def create_scheduling_link(event_type_uuid, max_event_count: 1)
  owner_uri = "#{BASE_URL}/event_types/#{event_type_uuid}"
  post("/scheduling_links", {
    max_event_count: max_event_count,
    owner: owner_uri,
    owner_type: "EventType"
  })["resource"]
end

# ---------------------------------------------------------------------------
# API: Scheduled Events
# ---------------------------------------------------------------------------

def list_scheduled_events(status: nil, count: 20)
  params = { user: user_uri, count: count, sort: "start_time:desc" }
  params[:status] = status if status
  get("/scheduled_events", params: params)["collection"]
end

def get_scheduled_event(uuid)
  get("/scheduled_events/#{uuid}")["resource"]
end

def cancel_scheduled_event(uuid, reason: nil)
  body = {}
  body[:reason] = reason if reason
  post("/scheduled_events/#{uuid}/cancellation", body)["resource"]
end

# ---------------------------------------------------------------------------
# API: Invitees
# ---------------------------------------------------------------------------

def list_invitees(event_uuid)
  get("/scheduled_events/#{event_uuid}/invitees")["collection"]
end

# ---------------------------------------------------------------------------
# API: Availability
# ---------------------------------------------------------------------------

def list_availability_schedules
  get("/user_availability_schedules", params: { user: user_uri })["collection"]
end

def get_availability_schedule(uuid)
  get("/user_availability_schedules/#{uuid}")["resource"]
end

# ---------------------------------------------------------------------------
# API: Webhooks
# ---------------------------------------------------------------------------

DEFAULT_WEBHOOK_EVENTS = %w[
  invitee.created
  invitee.canceled
].freeze

def list_webhooks
  params = { organization: org_uri, scope: "user", user: user_uri }
  get("/webhook_subscriptions", params: params)["collection"]
end

def create_webhook(url, events: nil)
  events ||= DEFAULT_WEBHOOK_EVENTS
  post("/webhook_subscriptions", {
    url: url,
    events: events,
    organization: org_uri,
    user: user_uri,
    scope: "user"
  })["resource"]
end

def delete_webhook(uuid)
  delete("/webhook_subscriptions/#{uuid}")
end

# ---------------------------------------------------------------------------
# Display helpers
# ---------------------------------------------------------------------------

def format_event_type(et, verbose: false)
  status = et["active"] ? "✅ active" : "⏸  inactive"
  secret = et["secret"] ? " 🔒" : ""
  lines = [
    "#{status}#{secret}  #{et['name']}",
    "    URL:      #{et['scheduling_url']}",
    "    UUID:     #{uuid_from_uri(et['uri'])}",
    "    Duration: #{et['duration']} min",
  ]
  if verbose
    lines << "    Slug:     #{et['slug']}"
    lines << "    Color:    #{et['color']}"
    lines << "    Desc:     #{et['description_plain'] || '(none)'}"
    locs = (et["locations"] || []).map { |l| l["kind"] }.join(", ")
    lines << "    Location: #{locs.empty? ? '(none)' : locs}"
    lines << "    Created:  #{et['created_at']}"
    lines << "    Updated:  #{et['updated_at']}"
  end
  lines.join("\n")
end

def format_time(iso)
  return "(none)" unless iso
  Time.parse(iso).localtime.strftime("%Y-%m-%d %I:%M %p %Z")
rescue
  iso
end

def format_scheduled_event(ev, verbose: false)
  status_icon = case ev["status"]
                when "active" then "📅"
                when "canceled" then "❌"
                else "❓"
                end
  lines = [
    "#{status_icon} #{ev['name']}  (#{ev['status']})",
    "    Start:    #{format_time(ev['start_time'])}",
    "    End:      #{format_time(ev['end_time'])}",
    "    UUID:     #{uuid_from_uri(ev['uri'])}",
  ]
  if verbose
    loc = ev["location"] || {}
    if loc["type"]
      loc_str = loc["join_url"] || loc["location"] || loc["type"]
      lines << "    Location: #{loc_str}"
    end
    lines << "    Event type: #{ev['event_type']}"
    lines << "    Created:  #{ev['created_at']}"
    lines << "    Updated:  #{ev['updated_at']}"
  end
  lines.join("\n")
end

def format_invitee(inv)
  lines = [
    "  👤 #{inv['name']} <#{inv['email']}>",
    "      Status:  #{inv['status']}",
    "      UUID:    #{uuid_from_uri(inv['uri'])}",
  ]
  if inv["questions_and_answers"] && !inv["questions_and_answers"].empty?
    inv["questions_and_answers"].each do |qa|
      lines << "      Q: #{qa['question']}"
      lines << "      A: #{qa['answer']}"
    end
  end
  lines.join("\n")
end

def format_availability(sched)
  lines = ["📅 #{sched['name']} (#{sched['timezone']})"]
  lines << "    UUID:    #{uuid_from_uri(sched['uri'])}"
  lines << "    Default: #{sched['default']}"
  (sched["rules"] || []).each do |rule|
    next if rule["intervals"].empty?
    intervals = rule["intervals"].map { |i| "#{i['from']}-#{i['to']}" }.join(", ")
    lines << "    #{rule['wday'].capitalize.ljust(10)} #{intervals}"
  end
  lines.join("\n")
end

def format_webhook(wh)
  events = (wh["events"] || []).join(", ")
  state = wh["state"] == "active" ? "✅" : "⏸ "
  lines = [
    "#{state} #{wh['callback_url']}",
    "    Events: #{events}",
    "    State:  #{wh['state']}",
    "    UUID:   #{uuid_from_uri(wh['uri'])}",
    "    Created: #{wh['created_at']}",
  ]
  lines.join("\n")
end

# ---------------------------------------------------------------------------
# CLI argument parsing
# ---------------------------------------------------------------------------

def parse_options(args)
  opts = {}
  i = 0
  while i < args.length
    case args[i]
    when "--duration"    then opts[:duration]    = args[i += 1]
    when "--slug"        then opts[:slug]        = args[i += 1]
    when "--description" then opts[:description] = args[i += 1]
    when "--color"       then opts[:color]       = args[i += 1]
    when "--location"    then opts[:location]    = args[i += 1]
    when "--name"        then opts[:name]        = args[i += 1]
    when "--status"      then opts[:status]      = args[i += 1]
    when "--reason"      then opts[:reason]      = args[i += 1]
    when "--events"      then opts[:events]      = args[i += 1]&.split(",")
    when "--count"       then opts[:count]       = args[i += 1].to_i
    when "--active"      then opts[:active]      = true
    when "--inactive"    then opts[:active]      = false
    when "--secret"      then opts[:secret]      = true
    when "--no-secret"   then opts[:secret]      = false
    when "-v", "--verbose" then opts[:verbose]   = true
    end
    i += 1
  end
  opts
end

def usage
  puts <<~HELP
    Calendly CLI

    Usage:
      calendly <command> [subcommand] [args] [options]

    Event Types (booking link templates):
      calendly types [--active] [-v]                       List event types
      calendly types get <uuid> [-v]                       Get a single event type
      calendly types create <name> [options]               Create a new event type
      calendly types update <uuid> [options]               Update an event type
      calendly types activate <uuid>                       Activate an event type
      calendly types deactivate <uuid>                     Deactivate (soft-delete)
      calendly types link <uuid>                           Generate a single-use scheduling link

    Scheduled Events (actual bookings):
      calendly events [--status active|canceled] [--count N]  List scheduled events
      calendly events get <uuid>                              Get event details + invitees
      calendly events cancel <uuid> [--reason "…"]            Cancel a scheduled event

    Invitees:
      calendly invitees <event_uuid>                       List invitees for a scheduled event

    Availability:
      calendly availability                                Show all availability schedules
      calendly availability get <uuid>                     Show a specific schedule

    Webhooks:
      calendly webhooks                                    List webhook subscriptions
      calendly webhooks create <url> [--events e1,e2,…]    Create a webhook subscription
      calendly webhooks delete <uuid>                      Delete a webhook subscription

    Account:
      calendly me                                          Show current user info

    Options (for types create/update):
      --name <name>              Event type name
      --duration <minutes>       Duration (default: 30)
      --slug <slug>              URL slug (create only, auto-generated from name)
      --description <text>       Plain-text description
      --color <hex>              Color (e.g. "#0099ff")
      --location <kind>          zoom_conference, google_conference, phone, etc.
      --active / --inactive      Set active status
      --secret / --no-secret     Set secret (unlisted) status
      -v, --verbose              Show full details

    Examples:
      calendly types create "Consultation" --duration 45 --location zoom_conference --active
      calendly types update <uuid> --description "Updated description"
      calendly types link <uuid>
      calendly types deactivate <uuid>
      calendly events --status active --count 10
      calendly events cancel <uuid> --reason "Rescheduling"
      calendly webhooks create https://example.com/hook --events invitee.created,invitee.canceled
  HELP
end

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

command = ARGV[0]

case command

# --- Account ---
when "me"
  user = current_user
  puts "👤 #{user['name']} (#{user['email']})"
  puts "   Timezone:      #{user['timezone']}"
  puts "   Scheduling:    #{user['scheduling_url']}"
  puts "   Organization:  #{user['current_organization']}"
  puts "   URI:           #{user['uri']}"

# --- Event Types ---
when "types"
  sub = ARGV[1]
  case sub
  when "get"
    uuid = ARGV[2] || abort("Usage: calendly types get <uuid>")
    opts = parse_options(ARGV[3..])
    et = get_event_type(uuid)
    puts format_event_type(et, verbose: true)

  when "create"
    name = ARGV[2] || abort("Usage: calendly types create <name> [options]")
    opts = parse_options(ARGV[3..])
    et = create_event_type(
      name: name,
      duration: opts[:duration] || 30,
      slug: opts[:slug],
      description: opts[:description],
      color: opts[:color],
      location: opts[:location],
      active: opts.fetch(:active, false),
      secret: opts.fetch(:secret, false)
    )
    puts "✅ Created event type!"
    puts format_event_type(et, verbose: true)

  when "update"
    uuid = ARGV[2] || abort("Usage: calendly types update <uuid> [options]")
    opts = parse_options(ARGV[3..])
    opts.delete(:verbose)
    et = update_event_type(uuid, **opts)
    puts "✅ Updated event type!"
    puts format_event_type(et, verbose: true)

  when "activate"
    uuid = ARGV[2] || abort("Usage: calendly types activate <uuid>")
    et = activate_event_type(uuid)
    puts "✅ Activated: #{et['name']}"
    puts "   URL: #{et['scheduling_url']}"

  when "deactivate"
    uuid = ARGV[2] || abort("Usage: calendly types deactivate <uuid>")
    et = deactivate_event_type(uuid)
    puts "⏸  Deactivated: #{et['name']}"

  when "link"
    uuid = ARGV[2] || abort("Usage: calendly types link <uuid>")
    link = create_scheduling_link(uuid)
    puts "🔗 Single-use scheduling link:"
    puts "   #{link['booking_url']}"

  else
    # "types" with no subcommand = list
    opts = parse_options(ARGV[1..])
    types = list_event_types(active_only: opts[:active])
    if types.empty?
      puts "No event types found."
    else
      types.each { |et| puts format_event_type(et, verbose: opts[:verbose]); puts }
    end
  end

# --- Scheduled Events ---
when "events"
  sub = ARGV[1]
  case sub
  when "get"
    uuid = ARGV[2] || abort("Usage: calendly events get <uuid>")
    ev = get_scheduled_event(uuid)
    puts format_scheduled_event(ev, verbose: true)
    puts
    invitees = list_invitees(uuid)
    if invitees.empty?
      puts "  No invitees."
    else
      puts "  Invitees:"
      invitees.each { |inv| puts format_invitee(inv); puts }
    end

  when "cancel"
    uuid = ARGV[2] || abort("Usage: calendly events cancel <uuid> [--reason \"…\"]")
    opts = parse_options(ARGV[3..])
    cancel_scheduled_event(uuid, reason: opts[:reason])
    puts "❌ Canceled event #{uuid}"

  else
    # "events" with no subcommand or with options = list
    opts = parse_options(ARGV[1..])
    events = list_scheduled_events(status: opts[:status], count: opts[:count] || 20)
    if events.empty?
      puts "No scheduled events found."
    else
      events.each { |ev| puts format_scheduled_event(ev, verbose: opts[:verbose]); puts }
    end
  end

# --- Invitees ---
when "invitees"
  event_uuid = ARGV[1] || abort("Usage: calendly invitees <event_uuid>")
  invitees = list_invitees(event_uuid)
  if invitees.empty?
    puts "No invitees found."
  else
    invitees.each { |inv| puts format_invitee(inv); puts }
  end

# --- Availability ---
when "availability"
  sub = ARGV[1]
  case sub
  when "get"
    uuid = ARGV[2] || abort("Usage: calendly availability get <uuid>")
    sched = get_availability_schedule(uuid)
    puts format_availability(sched)
  else
    schedules = list_availability_schedules
    schedules.each { |s| puts format_availability(s); puts }
  end

# --- Webhooks ---
when "webhooks"
  sub = ARGV[1]
  case sub
  when "create"
    url = ARGV[2] || abort("Usage: calendly webhooks create <url> [--events e1,e2,…]")
    opts = parse_options(ARGV[3..])
    wh = create_webhook(url, events: opts[:events])
    puts "✅ Created webhook!"
    puts format_webhook(wh)

  when "delete"
    uuid = ARGV[2] || abort("Usage: calendly webhooks delete <uuid>")
    delete_webhook(uuid)
    puts "🗑  Deleted webhook #{uuid}"

  else
    webhooks = list_webhooks
    if webhooks.empty?
      puts "No webhook subscriptions found."
    else
      webhooks.each { |wh| puts format_webhook(wh); puts }
    end
  end

# --- Help ---
when "help", "-h", "--help", nil
  usage

else
  abort "Unknown command: #{command}\nRun 'calendly help' for usage."
end
