# devcontainer

Personal Dev Container image with modern CLI tools, Node.js, Python, Rust, and Claude Code.

## Usage

```jsonc
// .devcontainer/devcontainer.json
{
  "image": "ghcr.io/publictheta/devcontainer:latest"
}
```

VS Code's Dev Containers extension forwards your local SSH agent, git credential helper, and `~/.gitconfig` automatically — no extra mounts needed for credentials.

## What's included

- **Base**: Debian stable-slim, sudo user `dev`, locales `en_US.UTF-8` / `ja_JP.UTF-8`
- **CLI tools**: bat, delta, eza, fd, fzf, gh, hyperfine, just, lazygit, neovim, ripgrep, shellcheck, shfmt, yazi, zoxide
- **Python**: uv + latest Python, ruff, ty
- **Node.js**: fnm + latest Node, corepack (pnpm)
- **Rust**: rustup + stable toolchain (rust-analyzer, rust-src, rustfmt, clippy); `SYS_PTRACE` + `seccomp=unconfined` for debuggers
- **Claude Code**
- **Shell**: zsh with autosuggestions, completions, git-aware prompt, integrations for fzf / fd / bat / zoxide / fnm

## Persistence recipes

Pick what you need.

### Cross-arch per-project workspace

Native binaries inside `node_modules`, `.venv`, `target/` are arch-specific (matters when host arch differs from container's). Use named volumes to keep them container-side:

```jsonc
{
  "image": "ghcr.io/publictheta/devcontainer:latest",
  "mounts": [
    "source=${localWorkspaceFolderBasename}-node-modules,target=${containerWorkspaceFolder}/node_modules,type=volume",
    "source=${localWorkspaceFolderBasename}-venv,target=${containerWorkspaceFolder}/.venv,type=volume",
    "source=${localWorkspaceFolderBasename}-target,target=${containerWorkspaceFolder}/target,type=volume"
  ]
}
```

These volumes get `chown`ed to `dev:dev` automatically on first mount.

### XDG state across rebuilds

For shell history, zoxide frecency, nvim plugins/shada, etc.:

```jsonc
{
  "mounts": [
    "source=dev-xdg-data,target=/home/dev/.local/share,type=volume",
    "source=dev-xdg-state,target=/home/dev/.local/state,type=volume"
  ]
}
```

### Build cache across rebuilds

```jsonc
{
  "mounts": [
    "source=dev-cargo-registry,target=/usr/local/cargo/registry,type=volume",
    "source=dev-cargo-git,target=/usr/local/cargo/git,type=volume",
    "source=dev-xdg-cache,target=/home/dev/.cache,type=volume"
  ]
}
```

### Host credentials (non-VS Code)

```jsonc
{
  "mounts": [
    "source=${localEnv:HOME}/.ssh,target=/home/dev/.ssh,type=bind,readonly",
    "source=${localEnv:HOME}/.gitconfig,target=/home/dev/.gitconfig,type=bind,readonly",
    "source=${localEnv:HOME}/.config/gh,target=/home/dev/.config/gh,type=bind"
  ]
}
```

### Don't persist these

These paths are populated at image build time. Mounting a named volume on them captures the image content at first mount, so future image rebuilds never propagate to your existing volume:

- `/usr/local/cargo/bin`
- `/usr/local/rustup/toolchains`
- `/usr/local/share/fnm/node-versions`
- `/usr/local/share/uv/python`

## Override pre-installed tools

`~/.local/bin` precedes `/usr/local/bin` on `PATH`, so `uv tool install ruff` puts ruff at `~/.local/bin/ruff` and shadows the bundled `/usr/local/bin/ruff` without touching it.

## Skip a tool

Set `"<toolName>Version": "none"` on the corresponding feature.

## License

Licensed under either of:

- Apache License, Version 2.0 ([LICENSE-APACHE](LICENSE-APACHE))
- MIT License ([LICENSE-MIT](LICENSE-MIT))

at your option.
