# Troubleshooting

## Plugin not found

Apply the plugin declaration and check its installation:
```bash
mise bootstrap plugins apply
mise bootstrap plugins status
```

## Skills CLI not found

Ensure you've installed the Vercel skills CLI via mise:
```toml
[tools]
node = "22.20.0"
"npm:skills" = "1.7.6"
```

Then run:
```bash
mise install
```

## Unsupported CLI version or permission denied

Check which command your configuration selects and reinstall the declared tool
if its executable is damaged. Do not repair paths guessed from mise's data layout.

```bash
mise exec -- skills --version
mise which skills
```

The expected version is a stable `x.y.z` release at or above `1.7.6`. If an older
or prerelease executable shadows it on `PATH`, correct the tool configuration or
shell environment before applying. A newer version that fails JSON or lock
validation needs a contract review; pin a previously verified release while
investigating.
