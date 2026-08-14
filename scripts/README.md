# Top-Level Scripts Directory

This directory contains **utility scripts** that may be useful for both local and remote setups, or for project-wide operations.

## Scripts

### `generate-topics.sh`
**Status**: ✅ Still useful  
**Purpose**: Generates Kafka topics list from database/table configuration  
**Usage**: Can be run from root directory to help configure topics  
**Note**: References root `.env` file - may need to be run from `local/` directory

### `setup-all.sh`
**Status**: ⚠️ Deprecated  
**Purpose**: Was designed for unified setup (old architecture)  
**Note**: This script references the old structure (root docker-compose.yml, root connectors/).  
**Recommendation**: Use setup scripts in `local/` and `remote/` directories instead.

### `setup-connectors.sh`
**Status**: ⚠️ Deprecated  
**Purpose**: Was designed to generate both source and sink connectors  
**Note**: This script references root connectors directory.  
**Recommendation**: Use `local/scripts/setup-connectors.sh` and `remote/scripts/setup-connectors.sh` instead.

### `unregister-connectors.sh`
**Status**: ⚠️ Needs update  
**Purpose**: Unregisters connectors from Kafka Connect  
**Note**: Generic script that could work, but doesn't account for MirrorMaker connector  
**Recommendation**: Update to handle MirrorMaker connector or use directory-specific scripts

## Recommendation

For new setups, use the scripts in:
- `local/scripts/` - For local machine setup
- `remote/scripts/` - For remote server setup

The top-level scripts directory may be removed in a future version as functionality has been moved to the local/remote directories.

