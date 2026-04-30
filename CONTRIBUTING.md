# Contributing to Manager MCP Server

## Getting Started

1. Fork the repository
2. Clone your fork
3. Create a feature branch: `git checkout -b feature/your-feature`
4. Make your changes
5. Run the doctor script to verify: `.\doctor.ps1`
6. Commit with a clear message
7. Push and open a pull request

## Development

Manager is a Rust MCP server. Build with:

```bash
cargo build --release
```

Cross-compile targets:

- **x64**: `x86_64-pc-windows-msvc`
- **ARM64**: `aarch64-pc-windows-msvc`

## Pull Requests

- One logical change per PR
- Include a description of what changed and why
- Update CHANGELOG.md if adding user-visible changes
- Update skill files if tool signatures change

## Reporting Issues

Open an issue on GitHub with:

- Manager version (`manager.exe --version`)
- Backend(s) involved
- Steps to reproduce
- Expected vs actual behavior

## Code of Conduct

Be respectful. Be constructive. Focus on the work.

## License

By contributing, you agree that your contributions will be licensed
under the Apache License 2.0.
