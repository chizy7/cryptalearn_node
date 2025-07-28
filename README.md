# CryptaLearn Node

**CryptaLearn Node** is a high-performance Elixir backend that orchestrates privacy-preserving federated learning across distributed OCaml clients. Built as the central coordination hub for the [CryptaLearn](https://github.com/chizy7/CryptaLearn) library, it provides secure model aggregation, differential privacy budget management, and fault-tolerant federated training coordination.


## Quick Start

### Prerequisites
- **Elixir 1.15+** and **Erlang/OTP 26+**
- **PostgreSQL 15+**

### Setup
```bash
# Install dependencies
mix deps.get

# Setup database
mix ecto.setup

# Set up environment variables (recommended for development)
# Create a .env file with the following variables:
# export DEV_DB_USERNAME=your_username
# export DEV_DB_PASSWORD=your_password
# export DEV_SECRET_KEY_BASE=$(mix phx.gen.secret)
# export TEST_DB_USERNAME=your_username
# export TEST_DB_PASSWORD=your_password
# export TEST_SECRET_KEY_BASE=$(mix phx.gen.secret)

# Start the server
mix phx.server
```

### Environment Setup

For security best practices, sensitive information such as database credentials and secret keys are loaded from environment variables. To set up your local environment:

1. Copy the example configuration files:
   ```bash
   cp config/dev.exs.example config/dev.exs
   cp config/test.exs.example config/test.exs
   ```

2. Create a `.env` file in the project root (this file is git-ignored):
   ```bash
   # Development environment
   export DEV_DB_USERNAME=postgres
   export DEV_DB_PASSWORD=your_password
   export DEV_SECRET_KEY_BASE=$(mix phx.gen.secret)
   
   # Test environment
   export TEST_DB_USERNAME=postgres
   export TEST_DB_PASSWORD=your_password
   export TEST_SECRET_KEY_BASE=$(mix phx.gen.secret)
   ```

3. Source the environment variables before starting the server:
   ```bash
   source .env
   mix phx.server
   ```

Visit [`localhost:4000/api/v1/health`](http://localhost:4000/api/v1/health) to verify installation.

## API Endpoints

### Node Management
```bash
# Register a node
curl -X POST http://localhost:4000/api/v1/nodes/register \
  -H "Content-Type: application/json" \
  -d '{"node_id": "test-node", "capabilities": ["fl", "dp"]}'

# List active nodes
curl http://localhost:4000/api/v1/nodes

# Send heartbeat
curl -X POST http://localhost:4000/api/v1/nodes/test-node/heartbeat

# Get node status
curl http://localhost:4000/api/v1/nodes/test-node/status

# Health check
curl http://localhost:4000/api/v1/health
```

## Testing

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover
```

## Monitoring

Visit [`localhost:4000/dev/dashboard`](http://localhost:4000/dev/dashboard) for real-time system metrics and monitoring.

## Current Features

- **Node Registration & Management** - Secure client session handling  
- **Session Tracking** - Heartbeat monitoring and automatic cleanup  
- **RESTful API** - Complete HTTP endpoints with error handling  
- **Database Foundation** - PostgreSQL schemas for nodes, rounds, models  
- **Health Monitoring** - System health checks and observability  
- **Process Supervision** - Fault-tolerant OTP architecture  
- **Testing Framework** - Unit and integration tests  

## TODO

- **JWT Authentication** - Secure API endpoints  
- **Training Rounds** - Federated learning coordination  
- **OCaml Integration** - Bridge to CryptaLearn library  
- **Privacy Management** - Differential privacy budget tracking  

## Development

```bash
# Database commands
mix ecto.create          # Create database
mix ecto.migrate         # Run migrations
mix ecto.reset           # Reset database

# Server commands
mix phx.server           # Start server
iex -S mix phx.server    # Start with interactive shell
mix format              # Format code
```

## Quick Start

To start your Phoenix server:

  * Run `mix setup` to install and setup dependencies
  * Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

  * Official website: https://www.phoenixframework.org/
  * Guides: https://hexdocs.pm/phoenix/overview.html
  * Docs: https://hexdocs.pm/phoenix
  * Forum: https://elixirforum.com/c/phoenix-forum
  * Source: https://github.com/phoenixframework/phoenix