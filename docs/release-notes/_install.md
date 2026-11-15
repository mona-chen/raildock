### Quick start (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/mona-chen/raildock/main/install.sh | bash
```

### Manual setup

```bash
# Pull the image
docker pull __IMAGE__:__VERSION__

# Run with required env vars
docker run -d -p 80:80 \
  -e DATABASE_URL="postgres://user:pass@host:5432/raildock" \
  -e RAILS_MASTER_KEY="..." \
  -e JWT_SECRET_KEY="..." \
  __IMAGE__:__VERSION__
```

Or use docker-compose:

```yaml
services:
  raildock:
    image: __IMAGE__:__VERSION__
    environment:
      DATABASE_URL: "postgres://user:pass@host:5432/raildock"
      RAILS_MASTER_KEY: "..."
      JWT_SECRET_KEY: "..."
```
