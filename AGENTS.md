# calendly

Manage Calendly event types, scheduled events, availability, and webhooks.

## Commands

```bash
calendly me                                            # Current user info
calendly types [--active] [-v]                         # List event types
calendly types get <uuid> [-v]                         # Get event type details
calendly types create <name> [options]                 # Create event type
calendly types update <uuid> [options]                 # Update event type
calendly types activate <uuid>                         # Activate event type
calendly types deactivate <uuid>                       # Soft-delete event type
calendly types link <uuid>                             # Generate single-use scheduling link
calendly events [--status active|canceled] [--count N] # List scheduled events
calendly events get <uuid>                             # Event details + invitees
calendly events cancel <uuid> [--reason "…"]           # Cancel a booking
calendly invitees <event_uuid>                         # List invitees for an event
calendly availability                                  # Show availability schedules
calendly availability get <uuid>                       # Show a specific schedule
calendly webhooks                                      # List webhook subscriptions
calendly webhooks create <url> [--events e1,e2,…]      # Create webhook
calendly webhooks delete <uuid>                        # Delete webhook
```

## Create/Update Options

`--name`, `--duration <min>`, `--slug` (create only), `--description`, `--color "#hex"`, `--location <kind>` (zoom_conference, google_conference, phone), `--active`/`--inactive`, `--secret`/`--no-secret`

## Examples

```bash
calendly types create "Consultation" --duration 45 --location zoom_conference --active
calendly types update <uuid> --description "Updated" --duration 60
calendly types link <uuid>
calendly types deactivate <uuid>
calendly events --status active --count 10
calendly events cancel <uuid> --reason "Rescheduling"
calendly webhooks create https://example.com/hook --events invitee.created,invitee.canceled
```

## Notes

- **slug**: auto-generated from name on create, cannot be changed via API
- **delete**: no DELETE endpoint — use `deactivate` to soft-delete
- **availability**: view-only via API, edit in Calendly web UI
- Default webhook events: `invitee.created`, `invitee.canceled`

Requires `.env` with `CALENDLY_ACCESS_TOKEN`. See `.env.example`.
