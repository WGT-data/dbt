#!/bin/bash
# Start Snowflake MCP server in HTTP mode for Cowork connectivity
# Usage: ./start_snowflake_mcp.sh

export SNOWFLAKE_ACCOUNT="A1542297460671-LOB24395"
export SNOWFLAKE_USER="RILEYSORENSON"
export SNOWFLAKE_ROLE="SYSADMIN"
export SNOWFLAKE_WAREHOUSE="COMPUTE_WH"
export SNOWFLAKE_PRIVATE_KEY_FILE="/Users/riley/Documents/rsa_key.p8"

/Users/riley/.local/bin/uvx snowflake-labs-mcp \
  --service-config-file /Users/riley/.mcp/snowflake_config.yaml \
  --transport streamable-http \
  --port 8811
