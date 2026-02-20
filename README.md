# Calendly CLI

Manage Calendly event types, scheduled events, availability, and webhooks from the command line.

## Setup

```bash
cd ~/tools/calendly
bundle install
```

Create `.env` with your Calendly personal access token:

```bash
CALENDLY_ACCESS_TOKEN=your_token_here
```

Get a token at [calendly.com/integrations/api_webhooks](https://calendly.com/integrations/api_webhooks).

## Usage

```bash
calendly <command> [subcommand] [args] [options]
```

### Account

```bash
calendly me                                    # Show current user info
```

### Event Types (booking link templates)

```bash
calendly types [--active] [-v]                 # List event types
calendly types get <uuid> [-v]                 # Get a single event type
calendly types create <name> [options]         # Create a new event type
calendly types update <uuid> [options]         # Update an event type
calendly types activate <uuid>                 # Activate an event type
calendly types deactivate <uuid>               # Deactivate (soft-delete)
calendly types link <uuid>                     # Generate a single-use scheduling link
```

#### Create/Update Options

| Option | Description |
|--------|-------------|
| `--name <name>` | Event type name |
| `--duration <min>` | Duration in minutes (default: 30) |
| `--slug <slug>` | URL slug *(create only, auto-generated from name)* |
| `--description <text>` | Plain-text description |
| `--color <hex>` | Color hex (e.g. `"#0099ff"`) |
| `--location <kind>` | `zoom_conference`, `google_conference`, `phone`, etc. |
| `--active / --inactive` | Set active status |
| `--secret / --no-secret` | Set secret (unlisted) status |
| `-v, --verbose` | Show full details |

### Scheduled Events (actual bookings)

```bash
calendly events [--status active|canceled] [--count N]  # List scheduled events
calendly events get <uuid>                               # Get event details + invitees
calendly events cancel <uuid> [--reason "…"]             # Cancel a scheduled event
```

### Invitees

```bash
calendly invitees <event_uuid>                 # List invitees for a scheduled event
```

### Availability

```bash
calendly availability                          # Show all availability schedules
calendly availability get <uuid>               # Show a specific schedule
```

### Webhooks

```bash
calendly webhooks                              # List webhook subscriptions
calendly webhooks create <url> [--events e1,e2,…]  # Create a webhook subscription
calendly webhooks delete <uuid>                # Delete a webhook subscription
```

Default webhook events: `invitee.created`, `invitee.canceled`.

## Examples

```bash
# Create a new booking link
calendly types create "Consultation" \
  --duration 45 --location zoom_conference --color "#0099ff" --active

# Update an event type
calendly types update <uuid> --description "New description" --duration 60

# Generate a single-use scheduling link
calendly types link <uuid>

# Soft-delete an event type
calendly types deactivate <uuid>

# List upcoming bookings
calendly events --status active --count 10

# Cancel a booking
calendly events cancel <uuid> --reason "Rescheduling"

# Set up a webhook
calendly webhooks create https://example.com/hook --events invitee.created,invitee.canceled
```

## API Limitations

- **slug**: Auto-generated from the event type name on create. Cannot be changed via API.
- **delete**: No DELETE endpoint for event types. Use `deactivate` to soft-delete.
- **availability**: Event types inherit your default availability schedule. Availability schedules can be viewed but not modified via the API (use the Calendly web UI).
