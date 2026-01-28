# SSH Connection Troubleshooting Guide

## Problem Description

When connecting via WezTerm SSH to `shalii@10.14.0.131`, you may see this error:

```
fish: "case" builtin not inside of switch block
command -v perl > /dev/null && exec perl ...
Warning: Process RemoteSshDomain didn't exit cleanly
Exited with code 127.
```

## Root Cause

The error is caused by:

1. **Incompatible Shell Scripts**: `~/.cargo/env` is a bash script with `case` statements
2. **Fish Shell Loading**: Fish shell tries to execute bash-formatted environment files  
3. **WezTerm SSH Mode**: Uses shell detection but encounters incompatible initialization

## Solution

### Recommended Fix: Update Remote Fish Configuration

SSH into the remote host:

```bash
ssh shalii@10.14.0.131
```

Then run these Fish commands:

```fish
# Backup original config
cp ~/.config/fish/config.fish ~/.config/fish/config.fish.bak

# Create fixed configuration
cat > ~/.config/fish/config.fish << 'EOF'
if status is-interactive
end

# conda initialize
if test -f ~/miniconda3/bin/conda
    eval ~/miniconda3/bin/conda "shell.fish" "hook" $argv | source
else
    if test -f ~/miniconda3/etc/fish/conf.d/conda.fish
        . ~/miniconda3/etc/fish/conf.d/conda.fish
    else
        set -x PATH ~/miniconda3/bin $PATH
    end
end

# Cargo/Rust (avoid bash script)
if test -d ~/.cargo/bin
    if not contains ~/.cargo/bin $PATH
        fish_add_path ~/.cargo/bin
    end
end

# uv package manager
fish_add_path ~/.local/bin

# Jira API credentials (add your own token)
set -gx JIRA_EMAIL "your_email@domain.com"
set -gx JIRA_TOKEN "YOUR_JIRA_API_TOKEN"
set -gx JIRA_BASE_URL "https://your-domain.atlassian.net"

# OpenCode CLI
fish_add_path /home/shalii/.opencode/bin

# NVM (Node Version Manager)
if test -d ~/.nvm
    set -gx NVM_DIR ~/.nvm
    if status is-interactive
        [ -s ~/.nvm/nvm.sh ] && . ~/.nvm/nvm.sh
    end
end

set -gx FISH_SSH_INITIALIZED 1
EOF

# Exit and test
exit
```

### Step 2: Test Connection

From your local machine:

```bash
# Test SSH connection
ssh shalii@10.14.0.131 "echo 'Connection OK' && pwd && fish --version"
```

Expected output:
```
Connection OK
/home/shalii
fish, version 4.0.1
```

### Step 3: Connect via WezTerm

In WezTerm, press F3 to open the launcher and search for the SSH domain.

## Alternative: Use Bash Instead of Fish

If you don't want to modify remote config, the default `assume_shell = 'Posix'` will use `/bin/bash`.

## Key Files Involved

| File | Location | Purpose |
|------|----------|---------|
| `config.fish` | Remote: `~/.config/fish/` | Fish shell initialization |
| `~/.cargo/env` | Remote: `~/` | Rust/Cargo environment (bash format) |
| `domains.lua` | Local: `~/.config/wezterm/config/` | WezTerm SSH configuration |
| `~/.profile` | Remote: `~/` | Login shell initialization |

## Prevention Tips

1. **Keep shell configs separate**
   - Use fish-specific files for Fish initialization
   - Use bash-specific files for Bash initialization

2. **Check for compatibility**
   ```bash
   # Test if file is Fish-compatible
   fish /path/to/script.sh
   ```

3. **Conditional sourcing**
   ```fish
   # In ~/.config/fish/config.fish
   if not set -q SSH_CONNECTION
       # Only in interactive sessions
       source ~/.cargo/env
   end
   ```

## Debugging Commands

```bash
# Check remote shell
ssh shalii@10.14.0.131 'echo $SHELL'

# Check Fish version
ssh shalii@10.14.0.131 'fish --version'

# Test Fish config
ssh shalii@10.14.0.131 'fish -c "set | head"'

# View WezTerm debug overlay
# Press F12 in WezTerm
```

## References

- WezTerm SSH Domains: https://wezfurlong.org/wezterm/config/lua/SshDomain.html
- Fish Shell Documentation: https://fishshell.com/docs/current/
- Rust/Cargo: https://rustup.rs/
