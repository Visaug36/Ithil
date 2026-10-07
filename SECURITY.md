# Security policy

Ithil is an offline app. It has no network access (the App Sandbox blocks it), no accounts and no servers.
Everything it stores lives in the folder you choose. Security issues are still possible, for example:

- writing, moving or deleting anything outside your Ithil folder
- losing or corrupting `events.json`, or recovering the wrong data
- following a symbolic link out of the folder
- a crafted `events.json`, folder name or dropped file that crashes Ithil or makes it misbehave

## Reporting a vulnerability

Please **don't open a public issue**. Report it privately through GitHub instead:

1. Go to the [Security tab](https://github.com/Visaug36/Ithil/security) of this repository.
2. Click **Report a vulnerability** and describe the problem, with steps to reproduce if you can.

You'll get a reply within a week. Once a fix is ready, it ships in a release and the advisory is published,
crediting you unless you'd rather stay anonymous.

## Supported versions

Only the latest release gets security fixes.
